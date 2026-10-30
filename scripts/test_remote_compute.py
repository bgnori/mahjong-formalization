import os
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import remote_compute


def job_spec(job_type_name: str, workers: int, fresh: bool = False) -> dict:
    return remote_compute.build_job_spec(
        project="example-project",
        region="us-central1",
        job_id=f"mahjong-{job_type_name}-test-123",
        service_account="batch@example-project.iam.gserviceaccount.com",
        image_uri=(
            "us-central1-docker.pkg.dev/example-project/mahjong-compute/"
            "mahjong-compute@sha256:abc123"
        ),
        git_commit="a" * 40,
        output_uri=f"gs://example-bucket/jobs/mahjong-{job_type_name}-test-123",
        job_type=remote_compute.JOB_TYPES[job_type_name],
        workers=workers,
        fresh=fresh,
    )


class RemoteComputeConfigTests(unittest.TestCase):
    def setUp(self) -> None:
        self.job = job_spec("four-tile", 2)

    def test_batch_job_is_spot_only_and_bounded(self) -> None:
        allocation = self.job["allocationPolicy"]
        self.assertEqual(
            allocation["instances"][0]["policy"]["provisioningModel"], "SPOT"
        )
        self.assertEqual(
            self.job["taskGroups"][0]["taskSpec"]["maxRetryCount"],
            remote_compute.MAX_RETRIES,
        )
        self.assertEqual(
            self.job["taskGroups"][0]["taskSpec"]["maxRunDuration"],
            f"{remote_compute.MAX_RUNTIME_SECONDS}s",
        )
        self.assertNotIn("allow", allocation["instances"][0]["policy"])

    def test_worker_is_pinned_to_image_digest_and_result_prefix(self) -> None:
        task = self.job["taskGroups"][0]["taskSpec"]
        runnable = task["runnables"][0]
        self.assertIn("@sha256:", runnable["container"]["imageUri"])
        self.assertEqual(
            runnable["container"]["commands"][3],
            "gs://example-bucket/jobs/mahjong-four-tile-test-123",
        )
        self.assertEqual(task["computeResource"]["cpuMilli"], 2000)
        self.assertEqual(task["computeResource"]["memoryMib"], 6144)

    def test_job_id_is_unique_and_valid(self) -> None:
        for job_type in remote_compute.JOB_TYPES.values():
            job_id = remote_compute.new_job_id(job_type, "a" * 40)
            self.assertRegex(job_id, re.compile(r"^[a-z][a-z0-9-]{0,62}$"))
            self.assertIn(job_type.name, job_id)

    def test_bucket_and_gcs_uri_validation(self) -> None:
        self.assertEqual(remote_compute.normalized_bucket("gs://bucket-name/"), "bucket-name")
        with self.assertRaises(remote_compute.RemoteComputeError):
            remote_compute.normalized_bucket("bucket-name/path")
        self.assertEqual(
            remote_compute.parse_gs_uri("gs://bucket-name/jobs/job-1"),
            ("bucket-name", "jobs/job-1"),
        )
        with self.assertRaises(remote_compute.RemoteComputeError):
            remote_compute.parse_gs_uri("https://bucket-name/jobs/job-1")

    def test_missing_image_detection(self) -> None:
        self.assertTrue(
            remote_compute.is_image_missing(
                "ERROR: (gcloud.artifacts.docker.images.describe) Image not found.\n"
            )
        )
        self.assertTrue(remote_compute.is_image_missing("code: NOT_FOUND"))
        self.assertFalse(
            remote_compute.is_image_missing(
                "ERROR: (gcloud.artifacts.docker.images.describe) PERMISSION_DENIED"
            )
        )

    def test_time_v_metrics_are_parsed(self) -> None:
        metrics = remote_compute.parse_time_v(
            """
            User time (seconds): 123.50
            System time (seconds): 4.25
            Percent of CPU this job got: 656%
            Elapsed (wall clock) time (h:mm:ss or m:ss): 7:10:22
            Maximum resident set size (kbytes): 14260633
            """
        )
        self.assertEqual(
            metrics,
            {
                "user_time_seconds": 123.5,
                "system_time_seconds": 4.25,
                "cpu_percent": 656,
                "wall_time": "7:10:22",
                "maximum_rss_kib": 14260633,
            },
        )

    def test_cli_reports_invalid_worker_count_without_traceback(self) -> None:
        result = subprocess.run(
            [
                sys.executable,
                remote_compute.__file__,
                "run",
                "four-tile",
                "--workers=0",
            ],
            check=False,
            text=True,
            capture_output=True,
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("Error: --workers must be a positive integer.", result.stderr)
        self.assertNotIn("Traceback", result.stderr)


class ComputeImageTests(unittest.TestCase):
    project = "example-project"
    region = "us-central1"
    image = (
        "us-central1-docker.pkg.dev/example-project/mahjong-compute/"
        "mahjong-compute:" + "a" * 40
    )
    base_name = image.rsplit("/", 1)[0] + "/mahjong-compute-deps"
    base_digest = "sha256:" + "b" * 64
    compute_digest = "sha256:" + "c" * 64

    def test_dependency_hash_tracks_every_dependency_input(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for name in remote_compute.DEPENDENCY_INPUTS:
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes((remote_compute.ROOT / name).read_bytes())
            with patch.object(remote_compute, "ROOT", root):
                initial = remote_compute.dependency_hash()
                self.assertRegex(initial, r"^[0-9a-f]{64}$")
                self.assertEqual(initial, remote_compute.dependency_hash())
                for name in remote_compute.DEPENDENCY_INPUTS:
                    with self.subTest(name=name):
                        path = root / name
                        original = path.read_bytes()
                        path.write_bytes(original + b"\n")
                        self.assertNotEqual(initial, remote_compute.dependency_hash())
                        path.write_bytes(original)
                (root / "Mahjong").mkdir()
                (root / "Mahjong" / "Basic.lean").write_text("-- changed source\n")
                (root / "remote-compute.Dockerfile").write_text("# changed project recipe\n")
                self.assertEqual(initial, remote_compute.dependency_hash())

    def test_existing_commit_needs_no_base_lookup_or_build(self) -> None:
        with (
            patch.object(
                remote_compute, "existing_image_digest", return_value=self.compute_digest
            ) as lookup,
            patch.object(remote_compute, "dependency_hash") as dependencies,
            patch.object(remote_compute, "run_command") as run,
        ):
            self.assertEqual(
                remote_compute.image_digest(self.project, self.region, self.image),
                self.compute_digest,
            )
        lookup.assert_called_once_with(self.project, self.image)
        dependencies.assert_not_called()
        run.assert_not_called()

    def test_new_commit_reuses_base_by_digest(self) -> None:
        with (
            patch.object(
                remote_compute,
                "existing_image_digest",
                side_effect=[None, self.base_digest, self.compute_digest],
            ) as lookup,
            patch.object(remote_compute, "run_command") as run,
        ):
            dependencies = remote_compute.dependency_hash()
            result = remote_compute.image_digest(self.project, self.region, self.image)
        self.assertEqual(result, self.compute_digest)
        self.assertEqual(
            lookup.call_args_list[1].args,
            (self.project, f"{self.base_name}:{dependencies}"),
        )
        run.assert_called_once()
        command = run.call_args.args[0]
        self.assertIn(f"--config={remote_compute.ROOT / 'cloudbuild.yaml'}", command)
        self.assertIn(
            f"--substitutions=_IMAGE_URI={self.image},"
            f"_BASE_IMAGE={self.base_name}@{self.base_digest},"
            f"_DEPENDENCY_HASH={dependencies},_GIT_COMMIT={'a' * 40}",
            command,
        )
        self.assertEqual(command[-1], str(remote_compute.ROOT))

    def test_missing_base_is_built_before_compute_image(self) -> None:
        with (
            patch.object(
                remote_compute,
                "existing_image_digest",
                side_effect=[None, None, self.base_digest, self.compute_digest],
            ),
            patch.object(remote_compute, "run_command") as run,
        ):
            dependencies = remote_compute.dependency_hash()
            result = remote_compute.image_digest(self.project, self.region, self.image)
        self.assertEqual(result, self.compute_digest)
        self.assertEqual(run.call_count, 2)
        base_command = run.call_args_list[0].args[0]
        self.assertIn(
            f"--config={remote_compute.ROOT / 'cloudbuild-deps.yaml'}", base_command
        )
        self.assertIn(
            f"--substitutions=_IMAGE_URI={self.base_name}:{dependencies},"
            f"_DEPENDENCY_HASH={dependencies}",
            base_command,
        )
        self.assertIn(f"--project={self.project}", base_command)
        self.assertIn(f"--region={self.region}", base_command)
        self.assertIn(
            f"_BASE_IMAGE={self.base_name}@{self.base_digest}",
            run.call_args_list[1].args[0][-2],
        )

    def test_unpublished_images_fail_without_rebuilding_forever(self) -> None:
        for responses in ([None, None, None], [None, self.base_digest, None]):
            with (
                self.subTest(responses=responses),
                patch.object(
                    remote_compute, "existing_image_digest", side_effect=responses
                ),
                patch.object(remote_compute, "run_command") as run,
            ):
                with self.assertRaisesRegex(
                    remote_compute.RemoteComputeError, "did not publish"
                ):
                    remote_compute.image_digest(self.project, self.region, self.image)
                run.assert_called_once()

    def test_failed_base_build_does_not_build_compute_image(self) -> None:
        with (
            patch.object(
                remote_compute, "existing_image_digest", side_effect=[None, None]
            ),
            patch.object(
                remote_compute,
                "run_command",
                side_effect=remote_compute.RemoteComputeError("build failed"),
            ) as run,
        ):
            with self.assertRaisesRegex(remote_compute.RemoteComputeError, "build failed"):
                remote_compute.image_digest(self.project, self.region, self.image)
        run.assert_called_once()

    def test_registry_errors_are_not_treated_as_missing_images(self) -> None:
        with (
            patch.object(
                remote_compute.subprocess,
                "run",
                return_value=subprocess.CompletedProcess(
                    [], 1, stdout="", stderr="PERMISSION_DENIED"
                ),
            ),
            patch.object(remote_compute, "run_command") as run,
        ):
            with self.assertRaisesRegex(
                remote_compute.RemoteComputeError, "PERMISSION_DENIED"
            ):
                remote_compute.image_digest(self.project, self.region, self.image)
        run.assert_not_called()

    def test_registry_response_requires_a_digest(self) -> None:
        for payload in ('{}', '{"image_summary":{"digest":"sha256:abc"}}'):
            with (
                self.subTest(payload=payload),
                patch.object(
                    remote_compute.subprocess,
                    "run",
                    return_value=subprocess.CompletedProcess(
                        [], 0, stdout=payload, stderr=""
                    ),
                ),
            ):
                if payload == '{}':
                    with self.assertRaisesRegex(
                        remote_compute.RemoteComputeError, "did not return an image digest"
                    ):
                        remote_compute.existing_image_digest(self.project, self.image)
                else:
                    self.assertEqual(
                        remote_compute.existing_image_digest(self.project, self.image),
                        "sha256:abc",
                    )

    def test_missing_registry_image_returns_none(self) -> None:
        with patch.object(
            remote_compute.subprocess,
            "run",
            return_value=subprocess.CompletedProcess(
                [], 1, stdout="", stderr="Image not found."
            ),
        ):
            self.assertIsNone(
                remote_compute.existing_image_digest(self.project, self.image)
            )

    def test_build_files_keep_dependency_work_out_of_commit_builds(self) -> None:
        root = remote_compute.ROOT
        base = (root / "remote-compute-deps.Dockerfile").read_text()
        compute = (root / "remote-compute.Dockerfile").read_text()
        self.assertIn("lake exe cache get", base)
        self.assertIn("pip install", base)
        self.assertNotIn("COPY Mahjong", base)
        self.assertNotIn("lake build", base)
        self.assertIn("FROM ${BASE_IMAGE}", compute)
        self.assertIn("lake build", compute)
        self.assertNotIn("lake exe cache get", compute)
        self.assertNotIn("pip install", compute)
        self.assertNotIn("apt-get", compute)
        self.assertIn("USER worker", compute)
        self.assertIn("chmod -R a-w /opt/mahjong", base)
        self.assertIn("find /opt/mahjong -perm /222 -exec chmod a-w {} +", compute)
        self.assertNotIn("chmod -R", compute)
        for job in remote_compute.JOB_TYPES.values():
            self.assertIn(f"test -x .lake/build/bin/{job.executable}", compute)
        ignore = (root / ".gcloudignore").read_text().splitlines()
        for name in remote_compute.DEPENDENCY_INPUTS:
            self.assertIn(f"!{name}", ignore)
        build = (root / "cloudbuild.yaml").read_text()
        self.assertIn("BASE_IMAGE=${_BASE_IMAGE}", build)
        self.assertIn("DEPENDENCY_HASH=${_DEPENDENCY_HASH}", build)


class SevenTileJobTests(unittest.TestCase):
    def setUp(self) -> None:
        self.job_type = remote_compute.JOB_TYPES["seven-tile"]
        self.job = job_spec("seven-tile", self.job_type.default_workers)

    def test_seven_tile_requests_a_parallel_machine(self) -> None:
        task = self.job["taskGroups"][0]["taskSpec"]
        policy = self.job["allocationPolicy"]["instances"][0]["policy"]
        self.assertGreater(self.job_type.vcpu, 1)
        self.assertEqual(self.job_type.default_workers, self.job_type.vcpu)
        self.assertEqual(policy["machineType"], self.job_type.machine_type)
        self.assertEqual(policy["provisioningModel"], "SPOT")
        self.assertEqual(task["computeResource"]["cpuMilli"], self.job_type.vcpu * 1000)

    def test_seven_tile_worker_command_passes_job_type_and_workers(self) -> None:
        commands = self.job["taskGroups"][0]["taskSpec"]["runnables"][0]["container"][
            "commands"
        ]
        self.assertEqual(commands[1], "worker")
        self.assertEqual(commands[2], "seven-tile")
        self.assertEqual(commands[-1], str(self.job_type.default_workers))
        self.assertEqual(self.job["labels"]["job-type"], "seven-tile")

    def test_job_types_have_distinct_executables_and_reports(self) -> None:
        executables = {job.executable for job in remote_compute.JOB_TYPES.values()}
        reports = {job.report_name for job in remote_compute.JOB_TYPES.values()}
        self.assertEqual(len(executables), len(remote_compute.JOB_TYPES))
        self.assertEqual(len(reports), len(remote_compute.JOB_TYPES))
        self.assertEqual(self.job_type.executable, "seven-tile-report-gen")
        self.assertEqual(self.job_type.report_name, "seven-tile-report.json")


class TenTileJobTests(unittest.TestCase):
    def setUp(self) -> None:
        self.job_type = remote_compute.JOB_TYPES["ten-tile"]
        self.job = job_spec("ten-tile", self.job_type.default_workers)

    def test_ten_tile_uses_measured_parallel_shape(self) -> None:
        task = self.job["taskGroups"][0]["taskSpec"]
        policy = self.job["allocationPolicy"]["instances"][0]["policy"]
        self.assertEqual(policy["machineType"], "e2-standard-4")
        self.assertEqual(policy["provisioningModel"], "SPOT")
        self.assertEqual(task["computeResource"]["cpuMilli"], 4000)
        self.assertEqual(task["computeResource"]["memoryMib"], 12288)
        self.assertEqual(self.job_type.default_workers, 4)

    def test_ten_tile_worker_uses_report_generator(self) -> None:
        commands = self.job["taskGroups"][0]["taskSpec"]["runnables"][0][
            "container"
        ]["commands"]
        self.assertEqual(commands[1:3], ["worker", "ten-tile"])
        self.assertEqual(commands[-1], "4")
        self.assertEqual(self.job_type.executable, "ten-tile-report-gen")
        self.assertEqual(self.job_type.report_name, "ten-tile-report.json")


class ThirteenTileJobTests(unittest.TestCase):
    def setUp(self) -> None:
        self.job_type = remote_compute.JOB_TYPES["thirteen-tile"]
        self.job = job_spec("thirteen-tile", self.job_type.default_workers)

    def test_thirteen_tile_requests_a_large_long_running_machine(self) -> None:
        task = self.job["taskGroups"][0]["taskSpec"]
        policy = self.job["allocationPolicy"]["instances"][0]["policy"]
        self.assertEqual(policy["machineType"], "n2-standard-32")
        self.assertEqual(policy["provisioningModel"], "SPOT")
        self.assertEqual(task["computeResource"]["cpuMilli"], 32000)
        self.assertEqual(
            task["maxRunDuration"], f"{self.job_type.max_runtime_seconds}s"
        )
        self.assertGreater(
            self.job_type.max_runtime_seconds, remote_compute.MAX_RUNTIME_SECONDS
        )

    def test_thirteen_tile_splits_generation_and_classification_workers(self) -> None:
        arguments = self.job_type.report_arguments(32, Path("/work"))
        self.assertEqual(
            arguments,
            [
                "--generation-workers=32",
                "--classification-workers=16",
                "--buckets=256",
                "--work-dir=/work/thirteen-tile-buckets",
            ],
        )

    def test_reports_without_split_workers_keep_a_single_worker_flag(self) -> None:
        self.assertEqual(
            remote_compute.JOB_TYPES["ten-tile"].report_arguments(4, Path("/work")),
            ["--workers=4"],
        )


class CheckpointTests(unittest.TestCase):
    class FakeBlob:
        def __init__(self, store: dict, name: str) -> None:
            self.store = store
            self.name = name

        def upload_from_filename(self, path: str) -> None:
            self.store[self.name] = Path(path).read_bytes()

    class FakeBucket:
        def __init__(self) -> None:
            self.store: dict[str, bytes] = {}

        def blob(self, name: str):
            return CheckpointTests.FakeBlob(self.store, name)

    def setUp(self) -> None:
        self.bucket = self.FakeBucket()
        self.temp = tempfile.TemporaryDirectory()
        self.local = Path(self.temp.name)
        self.addCleanup(self.temp.cleanup)

    def write(self, name: str, text: str) -> None:
        (self.local / name).write_text(text, encoding="utf-8")

    def test_checkpoint_prefix_is_scoped_by_job_type_and_commit(self) -> None:
        self.assertEqual(
            remote_compute.checkpoint_prefix(
                remote_compute.JOB_TYPES["thirteen-tile"], "b" * 40
            ),
            f"checkpoints/thirteen-tile/{'b' * 40}",
        )

    def test_sync_uploads_members_and_skips_unchanged_and_partial_files(self) -> None:
        uploaded: dict[str, tuple[int, int]] = {}
        self.write("bucket-0.bin", "data")
        self.write("bucket-0.bin.part", "half")
        self.write(remote_compute.GENERATION_MARKER, "MJWC-GENERATION-1\n")
        remote_compute.sync_checkpoint(self.bucket, "cp", self.local, uploaded)
        self.assertEqual(
            sorted(self.bucket.store),
            ["cp/bucket-0.bin", f"cp/{remote_compute.GENERATION_MARKER}"],
        )
        self.bucket.store.clear()
        remote_compute.sync_checkpoint(self.bucket, "cp", self.local, uploaded)
        self.assertEqual(self.bucket.store, {})

    def test_sync_skips_buckets_that_generation_has_not_finished(self) -> None:
        uploaded: dict[str, tuple[int, int]] = {}
        self.write("bucket-0.bin", "partially written")
        remote_compute.sync_checkpoint(self.bucket, "cp", self.local, uploaded)
        self.assertEqual(self.bucket.store, {})
        self.assertEqual(uploaded, {})

    def test_generation_marker_is_published_after_its_buckets(self) -> None:
        uploaded: dict[str, tuple[int, int]] = {}
        self.write("bucket-0.bin", "data")
        self.write(remote_compute.GENERATION_MARKER, "MJWC-GENERATION-1\n")
        remote_compute.sync_checkpoint(self.bucket, "cp", self.local, uploaded)
        self.assertEqual(
            sorted(self.bucket.store),
            ["cp/bucket-0.bin", f"cp/{remote_compute.GENERATION_MARKER}"],
        )

    def test_generation_marker_waits_while_a_bucket_is_still_growing(self) -> None:
        uploaded: dict[str, tuple[int, int]] = {}
        growing = self.local / "bucket-0.bin"
        growing.write_text("data", encoding="utf-8")
        self.write(remote_compute.GENERATION_MARKER, "MJWC-GENERATION-1\n")
        original = remote_compute.upload_file

        def grow_during_upload(bucket, name, path):
            original(bucket, name, path)
            if path == growing:
                growing.write_text("data+more", encoding="utf-8")
                os.utime(growing, ns=(0, 0))

        remote_compute.upload_file = grow_during_upload
        self.addCleanup(setattr, remote_compute, "upload_file", original)
        remote_compute.sync_checkpoint(self.bucket, "cp", self.local, uploaded)
        self.assertNotIn(
            f"cp/{remote_compute.GENERATION_MARKER}", self.bucket.store
        )
        self.assertNotIn("bucket-0.bin", uploaded)


if __name__ == "__main__":
    unittest.main()
