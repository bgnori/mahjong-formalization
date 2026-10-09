import re
import subprocess
import sys
import unittest

import remote_compute


def job_spec(job_type_name: str, workers: int) -> dict:
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
        self.assertEqual(self.job_type.report_name, "seven-tile-report.txt")


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
        self.assertEqual(self.job_type.report_name, "ten-tile-report.txt")


if __name__ == "__main__":
    unittest.main()
