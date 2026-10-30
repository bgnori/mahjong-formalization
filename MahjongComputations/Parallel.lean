import MahjongComputations.Common
import Std.Sync.Mutex

/-!
# Parallel report computation support

This module provides a wait-core cache shared by concurrent report workers.
-/

namespace MahjongComputations

/-- Run at most `workers` fixed chunks concurrently and preserve chunk result order. -/
def parallelMapChunks {α β : Type} (workers : Nat) (items : List α)
    (f : List α → BaseIO β) : BaseIO (List β) := do
  let workerCount := Nat.max 1 workers
  let chunkSize := Nat.max 1 ((items.length + workerCount - 1) / workerCount)
  let tasks ← (items.toChunks chunkSize).mapM fun chunk =>
    BaseIO.asTask (f chunk) Task.Priority.dedicated
  tasks.mapM IO.wait

/-- IO-error-preserving variant of `parallelMapChunks`. -/
def parallelMapChunksIO {α β : Type} (workers : Nat) (items : List α)
    (f : List α → IO β) : IO (List β) := do
  let workerCount := Nat.max 1 workers
  let chunkSize := Nat.max 1 ((items.length + workerCount - 1) / workerCount)
  let tasks ← (items.toChunks chunkSize).mapM fun chunk =>
    IO.asTask (f chunk) Task.Priority.dedicated
  tasks.mapM fun task => do
    IO.ofExcept (← IO.wait task)

/-- Run at most `workers` tasks, dynamically taking the next item and preserving input order. -/
def parallelMapDynamicIO {α β : Type} (workers : Nat) (items : List α)
    (f : α → IO β) : IO (List β) := do
  let jobs := (items.zip (List.range items.length)).map fun (item, index) => (index, item)
  let queue ← Std.Mutex.new jobs
  let worker : IO (List (Nat × β)) := do
    let mut results := []
    let mut running := true
    while running do
      let next ← queue.atomically do
        let pending ← get
        match pending with
        | [] => return none
        | job :: rest =>
          set rest
          return some job
      match next with
      | none => running := false
      | some (index, item) =>
        results := (index, ← f item) :: results
    return results
  let workerCount := min (Nat.max 1 workers) items.length
  let tasks ← (List.range workerCount).mapM fun _ =>
    IO.asTask worker Task.Priority.dedicated
  let outcomes ← tasks.mapM fun task => do
    let outcome ← IO.wait task
    pure outcome
  let indexedResults ← outcomes.foldlM (init := []) fun results outcome => do
    match outcome with
    | Except.ok workerResults => pure (workerResults ++ results)
    | Except.error error => throw error
  let orderedResults := indexedResults.mergeSort fun first second =>
    decide (first.1 ≤ second.1)
  return orderedResults.map Prod.snd

/-- Number of processors available to this container, with a safe fallback. -/
def availableWorkerCount : IO Nat :=
  try
    let output ← IO.Process.run { cmd := "nproc" }
    match output.trimAscii.toString.toNat? with
    | some workers => pure (Nat.max 1 workers)
    | none => throw (IO.userError "nproc returned a non-numeric value")
  catch _ =>
    IO.eprintln "warning: could not detect processor count; using one worker"
    pure 1

/-- Parse `--workers=N` and an optional output path, defaulting to available processors. -/
def parseWorkerArgs (args : List String) (defaultOutputPath : String) : IO (Nat × String) := do
  let defaultWorkers ← availableWorkerCount
  let mut workers := defaultWorkers
  let mut outputPath := defaultOutputPath
  for arg in args do
    if arg.startsWith "--workers=" then
      match (arg.drop 10).toNat? with
      | some count =>
          if count == 0 then throw (IO.userError "--workers must be greater than zero")
          workers := count
      | none => throw (IO.userError s!"invalid worker count: {arg}")
    else if arg.startsWith "workers=" then
      throw (IO.userError s!"invalid worker option: {arg}; use --{arg}")
    else if arg.startsWith "--" then
      throw (IO.userError s!"unknown option: {arg}")
    else
      outputPath := arg
  return (workers, outputPath)

private abbrev CachedWaitCoreKeys := Option (List Nat)

private inductive SharedWaitCoreCacheEntry where
  | ready (cores : CachedWaitCoreKeys)
  | inFlight (promise : IO.Promise CachedWaitCoreKeys)

private structure SharedWaitCoreCacheState where
  values : Std.HashMap Nat SharedWaitCoreCacheEntry
  hits : Nat
  misses : Nat

/-- A wait-core cache whose entries and statistics are shared by all worker tasks. -/
structure SharedWaitCoreCache where
  private firstStripe : Std.Mutex SharedWaitCoreCacheState
  private remainingStripes : List (Std.Mutex SharedWaitCoreCacheState)

/-- Observable statistics for a shared wait-core cache. -/
structure SharedWaitCoreCacheStats where
  hits : Nat
  misses : Nat
  entries : Nat
deriving BEq, DecidableEq, Repr

private inductive SharedWaitCoreCacheLookup where
  | ready (cores : CachedWaitCoreKeys)
  | wait (promise : IO.Promise CachedWaitCoreKeys)
  | compute (promise : IO.Promise CachedWaitCoreKeys)

private def waitCoreCacheStripeCount : Nat := 64

private def newWaitCoreCacheStripe : BaseIO (Std.Mutex SharedWaitCoreCacheState) :=
  Std.Mutex.new { values := ∅, hits := 0, misses := 0 }

/-- Create an empty wait-core cache for concurrent workers. -/
def SharedWaitCoreCache.new : BaseIO SharedWaitCoreCache := do
  let firstStripe ← newWaitCoreCacheStripe
  let remainingStripes ← (List.range (waitCoreCacheStripeCount - 1)).mapM fun _ =>
    newWaitCoreCacheStripe
  return { firstStripe, remainingStripes }

private def SharedWaitCoreCache.stripeFor
    (cache : SharedWaitCoreCache) (key : Nat) : Std.Mutex SharedWaitCoreCacheState :=
  (cache.firstStripe :: cache.remainingStripes).getD
    (key % waitCoreCacheStripeCount) cache.firstStripe

private def computeWaitCoreKeys (tiles : List Tile) : CachedWaitCoreKeys :=
  let completions := WaitCompletionFinder.findWaitCompletions tiles
  if completions.isEmpty then none
  else some (WaitDecompositionCode.waitCoreKeys (WaitDecompositionCode.waitCores completions))

/--
Look up wait-core keys, ensuring that concurrent misses for the same hand share one computation.
-/
def SharedWaitCoreCache.lookup (cache : SharedWaitCoreCache)
    (tiles : List Tile) : BaseIO CachedWaitCoreKeys := do
  let key := tileMultisetKey tiles
  let stripe := cache.stripeFor key
  let lookup : SharedWaitCoreCacheLookup ← stripe.atomically do
    let state : SharedWaitCoreCacheState ← get
    match state.values.get? key with
    | some (.ready cores) =>
      set { state with hits := state.hits + 1 }
      return SharedWaitCoreCacheLookup.ready cores
    | some (.inFlight promise) =>
      set { state with hits := state.hits + 1 }
      return SharedWaitCoreCacheLookup.wait promise
    | none =>
      let promise ← IO.Promise.new
      set { state with
        values := state.values.insert key (.inFlight promise)
        misses := state.misses + 1 }
      return SharedWaitCoreCacheLookup.compute promise
  match lookup with
  | .ready cores => return cores
  | .wait promise =>
      return (← IO.wait promise.result?).get!
  | .compute promise =>
      let cores := computeWaitCoreKeys tiles
      stripe.atomically do
        modify fun state => { state with values := state.values.insert key (.ready cores) }
      promise.resolve cores
      return cores

/-- Read a consistent snapshot of cache statistics. -/
def SharedWaitCoreCache.stats (cache : SharedWaitCoreCache) : BaseIO SharedWaitCoreCacheStats := do
  let stripeStats ← (cache.firstStripe :: cache.remainingStripes).mapM fun stripe =>
    stripe.atomically do
      let state : SharedWaitCoreCacheState ← get
      return ({ hits := state.hits, misses := state.misses, entries := state.values.size } :
        SharedWaitCoreCacheStats)
  return stripeStats.foldl
    (fun (total stats : SharedWaitCoreCacheStats) => {
      hits := total.hits + stats.hits
      misses := total.misses + stats.misses
      entries := total.entries + stats.entries
    })
    { hits := 0, misses := 0, entries := 0 }

/-- Reducibility check backed by a wait-core cache shared across worker tasks. -/
def canReduceMentsuPreservingWaitCoresShared
    (tiles : List Tile) (completions : List WaitCompletion)
    (cache : SharedWaitCoreCache) : BaseIO Bool :=
  canReduceMentsuPreservingWaitCoreKeysWith tiles completions cache.lookup

def waitPathologyWitnessesShared
    (tiles : List Tile) (completions : List WaitCompletion)
    (cache : SharedWaitCoreCache) : BaseIO (List WaitDecompositionCode.WaitPathologyWitness) :=
  WaitDecompositionCode.waitPathologyWitnessesWith tiles completions cache.lookup

end MahjongComputations
