// Browser/Node port of examples/irreducible_wait_classifier.py.
// Works as a classic <script> (global `WaitClassifier`) and via require().
// Tiles are counted per type: 0-8 = 1-9m, 9-17 = 1-9p, 18-26 = 1-9s, 27-33 = 1-7z.
(function (root, factory) {
  const table = typeof module === "object" && module.exports
    ? require("./classification-table.js")
    : root.WaitClassificationTable;
  const api = factory(table);
  if (typeof module === "object" && module.exports) module.exports = api;
  else root.WaitClassifier = api;
})(typeof self !== "undefined" ? self : this, function (TABLE) {
  "use strict";

  class WaitClassificationError extends Error {}
  class InvalidHandError extends WaitClassificationError {}
  class NotTenpaiError extends WaitClassificationError {}
  class UnknownIrreducibleClassificationError extends WaitClassificationError {}
  class AmbiguousReductionError extends WaitClassificationError {}

  const SIZES = [4, 7, 10, 13];
  const PAIR = 0, SEQUENCE = 1, TRIPLET = 2;
  const TANKI = 2, TOITSU = 3, RYANMEN = 5, KANCHAN = 7, PENCHAN = 11, SHUNTSU = 13, KOUTSU = 17;

  const lookup = {};
  for (const [size, lists] of Object.entries(TABLE.codeLists)) {
    lookup[size] = new Map(lists.map((codes, i) => [codes.join(","), i]));
  }

  function parseHand(text) {
    const counts = new Array(34).fill(0);
    const base = { m: 0, p: 9, s: 18, z: 27 };
    const normalized = text.replace(/\s+/g, "");
    if (!/^([0-9]+[mpsz])+$/.test(normalized)) {
      throw new InvalidHandError("牌姿は 1223m111z のように入力してください");
    }
    for (const [, digits, suit] of normalized.matchAll(/([0-9]+)([mpsz])/g)) {
      for (const d of digits) {
        const rank = d === "0" ? 5 : Number(d);
        if (rank < 1 || rank > (suit === "z" ? 7 : 9)) {
          throw new InvalidHandError(`存在しない牌です: ${d}${suit}`);
        }
        counts[base[suit] + rank - 1]++;
      }
    }
    return validate(counts);
  }

  function validate(counts) {
    const total = counts.reduce((a, b) => a + b, 0);
    if (!SIZES.includes(total)) {
      throw new InvalidHandError(`牌数は 4, 7, 10, 13 のいずれかにしてください (現在 ${total} 枚)`);
    }
    if (counts.some((c) => c > 4)) throw new InvalidHandError("同じ牌は 4 枚までです");
    return counts;
  }

  const key = (counts) => counts.join(",");
  const memo = (fn) => {
    const cache = new Map();
    return (counts) => {
      const k = key(counts);
      if (!cache.has(k)) cache.set(k, fn(counts));
      return cache.get(k);
    };
  };

  const meldPartitions = (() => {
    const cache = new Map();
    const go = (counts, melds) => {
      if (melds === 0) return counts.some((c) => c) ? [] : [[]];
      const k = key(counts) + "|" + melds;
      if (cache.has(k)) return cache.get(k);
      const tile = counts.findIndex((c) => c > 0);
      const results = [];
      if (tile >= 0) {
        if (counts[tile] >= 3) {
          const r = counts.slice();
          r[tile] -= 3;
          for (const rest of go(r, melds - 1)) results.push([[TRIPLET, tile], ...rest]);
        }
        if (tile < 27 && tile % 9 <= 6 && counts[tile + 1] && counts[tile + 2]) {
          const r = counts.slice();
          r[tile]--; r[tile + 1]--; r[tile + 2]--;
          for (const rest of go(r, melds - 1)) results.push([[SEQUENCE, tile], ...rest]);
        }
      }
      cache.set(k, results);
      return results;
    };
    return go;
  })();

  function winningPartitions(counts) {
    const melds = (counts.reduce((a, b) => a + b, 0) - 2) / 3;
    const out = [];
    counts.forEach((c, pairTile) => {
      if (c < 2) return;
      const r = counts.slice();
      r[pairTile] -= 2;
      for (const m of meldPartitions(r, melds)) out.push([[PAIR, pairTile], ...m]);
    });
    return out;
  }

  const contains = ([kind, v], tile) => (kind === SEQUENCE ? v <= tile && tile <= v + 2 : v === tile);

  function incomplete([kind, v], wait) {
    if (kind === PAIR) return [TANKI, [v]];
    if (kind === TRIPLET) return [TOITSU, [v, v]];
    const tiles = [v, v + 1, v + 2].filter((t) => t !== wait);
    const offset = wait - v;
    if (offset === 1) return [KANCHAN, tiles];
    if ((offset === 0 && v % 9 === 6) || (offset === 2 && v % 9 === 0)) return [PENCHAN, tiles];
    return [RYANMEN, tiles];
  }

  const completePrime = ([kind]) => (kind === PAIR ? TOITSU : kind === SEQUENCE ? SHUNTSU : KOUTSU);

  const compareCore = (a, b) => a[0] - b[0] || a[1][0] - b[1][0] || (a[1][1] ?? -1) - (b[1][1] ?? -1);

  // Returns { codes: sorted number[], cores: Set<string>, waits: Set<number> }.
  const analyze = memo((counts) => {
    const entries = new Set();
    const cores = new Set();
    const waits = new Set();
    for (let wait = 0; wait < 34; wait++) {
      if (counts[wait] === 4) continue;
      const completed = counts.slice();
      completed[wait]++;
      for (const partition of winningPartitions(completed)) {
        partition.forEach((component, selected) => {
          if (!contains(component, wait)) return;
          const [prime, tiles] = incomplete(component, wait);
          const coreParts = [[prime, tiles]];
          partition.forEach((c, i) => {
            if (i !== selected && c[0] === PAIR) coreParts.push([TOITSU, [c[1], c[1]]]);
          });
          coreParts.sort(compareCore);
          let product = 1;
          partition.forEach((c, i) => { product *= i === selected ? prime : completePrime(c); });
          entries.add(wait + ":" + product);
          cores.add(wait + "/" + coreParts.map(([p, t]) => p + "[" + t.join(".") + "]").join(";"));
          waits.add(wait);
        });
      }
    }
    const codes = [...entries].map((e) => Number(e.split(":")[1])).sort((a, b) => a - b);
    return { codes, cores, waits };
  });

  function reductions(counts) {
    const seen = new Map();
    for (let t = 0; t < 34; t++) {
      if (counts[t] >= 3) {
        const r = counts.slice();
        r[t] -= 3;
        seen.set(key(r), r);
      }
    }
    for (let s = 0; s < 27; s++) {
      if (s % 9 <= 6 && counts[s] && counts[s + 1] && counts[s + 2]) {
        const r = counts.slice();
        r[s]--; r[s + 1]--; r[s + 2]--;
        seen.set(key(r), r);
      }
    }
    return [...seen.values()];
  }

  const isSubset = (a, b) => a.size < b.size && [...a].every((x) => b.has(x));
  const setEq = (a, b) => a.size === b.size && [...a].every((x) => b.has(x));

  const pathologyProfile = memo((counts) => {
    const original = analyze(counts);
    let suppression = false;
    let ambiguity = false;
    for (const r of reductions(counts)) {
      const rem = analyze(r);
      if (!rem.codes.length) continue;
      if (isSubset(original.waits, rem.waits)) suppression = true;
      else if (setEq(rem.waits, original.waits) && isSubset(rem.cores, original.cores)) ambiguity = true;
    }
    if (suppression && ambiguity) return "both";
    if (suppression) return "suppressionOnly";
    if (ambiguity) return "ambiguityOnly";
    return "healthy";
  });

  function lookupId(size, codes) {
    const local = lookup[size] && lookup[size].get(codes.join(","));
    return local === undefined ? null : TABLE.idOffsets[size] + local;
  }

  // Map of irreducible classifications reachable by wait-core-preserving meld removal.
  const irreducible = memo((counts) => {
    const original = analyze(counts);
    const preserving = reductions(counts).filter((r) => {
      const a = analyze(r);
      return a.codes.length && setEq(a.cores, original.cores);
    });
    const out = new Map();
    if (preserving.length) {
      for (const r of preserving) for (const [k, v] of irreducible(r)) out.set(k, v);
      return out;
    }
    const size = counts.reduce((a, b) => a + b, 0);
    const id = lookupId(size, original.codes);
    if (id !== null) {
      const profile = pathologyProfile(counts);
      out.set(original.codes.join(",") + "|" + profile, {
        waitDecompositionCodes: original.codes,
        pathologyProfile: profile,
        classificationId: id,
      });
    }
    return out;
  });

  // `counts` is a 34-element array of tile counts.
  function classifyCounts(counts) {
    validate(counts);
    const { codes, waits } = analyze(counts);
    if (!codes.length) throw new NotTenpaiError("テンパイ形(標準形)ではありません");
    const found = irreducible(counts);
    if (!found.size) throw new UnknownIrreducibleClassificationError("固定の分類表に該当がありません");
    if (found.size !== 1) throw new AmbiguousReductionError("面子の取り除き方により分類が一意に定まりません");
    return { ...found.values().next().value, waits: [...waits].sort((a, b) => a - b) };
  }

  const classify = (text) => classifyCounts(parseHand(text));

  const TILE_NAMES = (() => {
    const names = [];
    for (const s of "mps") for (let r = 1; r <= 9; r++) names.push(r + s);
    for (let r = 1; r <= 7; r++) names.push(r + "z");
    return names;
  })();

  return {
    classify, classifyCounts, parseHand, TILE_NAMES,
    WaitClassificationError, InvalidHandError, NotTenpaiError,
    UnknownIrreducibleClassificationError, AmbiguousReductionError,
  };
});
