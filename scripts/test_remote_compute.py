import re
import subprocess
import sys
import unittest

import remote_compute


class RemoteComputeConfigTests(unittest.TestCase):
    def setUp(self) -> None:
        self.job = remote_compute.build_job_spec(
            project="example-project",
            region="us-central1",
            job_id="mahjong-four-tile-test-123",
            service_account="batch@example-project.iam.gserviceaccount.com",
            image_uri=(
                "us-central1-docker.pkg.dev/example-project/mahjong-compute/"
                "mahjong-compute@sha256:abc123"
            ),
            git_commit="a" * 40,
            output_uri="gs://example-bucket/jobs/mahjong-four-tile-test-123",
            workers=2,
        )

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
        job_id = remote_compute.new_job_id("a" * 40)
        self.assertRegex(job_id, re.compile(r"^[a-z][a-z0-9-]{0,62}$"))

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


if __name__ == "__main__":
    unittest.main()
