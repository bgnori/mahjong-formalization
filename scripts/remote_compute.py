#!/usr/bin/env python3
"""Build, submit, inspect, download, and execute GCP Batch report jobs."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
import uuid
from datetime import datetime, timezone
from typing import Any
from urllib.parse import urlparse


ROOT = Path(__file__).resolve().parents[1]
REPORT_NAME = "four-tile-direct-report.txt"
DEFAULT_REGION = "us-central1"
MAX_RETRIES = 3
MAX_RUNTIME_SECONDS = 7200


class RemoteComputeError(RuntimeError):
    pass


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def run_command(
    args: list[str], *, capture_output: bool = False
) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        args,
        check=False,
        text=True,
        capture_output=capture_output,
    )
    if result.returncode:
        details = result.stderr.strip() if capture_output else ""
        raise RemoteComputeError(
            f"Command failed with exit code {result.returncode}: "
            f"{' '.join(args)}"
            + (f"\n{details}" if details else "")
        )
    return result


def required_setting(name: str, fallback: str | None = None) -> str:
    value = os.environ.get(name, fallback)
    if not value:
        raise RemoteComputeError(
            f"Set {name} in the environment before running this command."
        )
    return value


def normalized_bucket(value: str) -> str:
    bucket = value.removeprefix("gs://").strip("/")
    if not bucket or "/" in bucket:
        raise RemoteComputeError("GCP_BUCKET must be a bucket name or gs://bucket.")
    return bucket


def image_digest(project: str, region: str, image_uri: str) -> str:
    describe = subprocess.run(
        [
            "gcloud",
            "artifacts",
            "docker",
            "images",
            "describe",
            image_uri,
            f"--project={project}",
            "--format=json",
        ],
        check=False,
        text=True,
        capture_output=True,
    )
    if describe.returncode == 0:
        payload = json.loads(describe.stdout)
        digest = payload.get("image_summary", {}).get("digest")
        if not digest:
            raise RemoteComputeError(
                f"Artifact Registry did not return an image digest for {image_uri}."
            )
        return digest
    if "NOT_FOUND" not in describe.stderr:
        raise RemoteComputeError(
            "Could not check the compute image in Artifact Registry:\n"
            + describe.stderr.strip()
        )

    commit = image_uri.rsplit(":", 1)[1]
    run_command(
        [
            "gcloud",
            "builds",
            "submit",
            "--config=cloudbuild.yaml",
            f"--project={project}",
            f"--region={region}",
            f"--substitutions=_IMAGE_URI={image_uri},_GIT_COMMIT={commit}",
            ".",
        ]
    )
    return image_digest(project, region, image_uri)


def build_job_spec(
    *,
    project: str,
    region: str,
    job_id: str,
    service_account: str,
    image_uri: str,
    git_commit: str,
    output_uri: str,
    workers: int,
) -> dict[str, Any]:
    return {
        "taskGroups": [
            {
                "taskCount": 1,
                "parallelism": 1,
                "taskSpec": {
                    "runnables": [
                        {
                            "container": {
                                "imageUri": image_uri,
                                "entrypoint": "python3",
                                "commands": [
                                    "/opt/mahjong/scripts/remote_compute.py",
                                    "worker",
                                    "four-tile",
                                    output_uri,
                                    job_id,
                                    git_commit,
                                    image_uri,
                                    str(workers),
                                ],
                            },
                            "environment": {
                                "variables": {
                                    "GCP_PROJECT": project,
                                    "GCP_REGION": region,
                                    "BATCH_MACHINE_TYPE": "e2-standard-2",
                                    "BATCH_VCPU": "2",
                                    "BATCH_MEMORY_MIB": "8192",
                                }
                            },
                        }
                    ],
                    "computeResource": {
                        "cpuMilli": 2000,
                        "memoryMib": 6144,
                    },
                    "maxRetryCount": MAX_RETRIES,
                    "maxRunDuration": f"{MAX_RUNTIME_SECONDS}s",
                },
            }
        ],
        "allocationPolicy": {
            "instances": [
                {
                    "policy": {
                        "machineType": "e2-standard-2",
                        "provisioningModel": "SPOT",
                        "bootDisk": {"type": "pd-balanced", "sizeGb": 40},
                    }
                }
            ],
            "serviceAccount": {"email": service_account},
        },
        "logsPolicy": {"destination": "CLOUD_LOGGING"},
        "labels": {
            "app": "mahjong-compute",
            "job-type": "four-tile",
            "git-commit": git_commit[:12],
        },
    }


def verify_clean_checkout() -> str:
    commit = run_command(
        ["git", "-C", str(ROOT), "rev-parse", "--verify", "HEAD"],
        capture_output=True,
    ).stdout.strip()
    status = run_command(
        [
            "git",
            "-C",
            str(ROOT),
            "status",
            "--porcelain",
            "--untracked-files=all",
        ],
        capture_output=True,
    ).stdout.strip()
    if status:
        raise RemoteComputeError(
            "Refusing to build from a dirty worktree. Commit or stash changes so "
            "the image can be identified by its Git commit."
        )
    return commit


def get_project() -> str:
    project = os.environ.get("GCP_PROJECT")
    if project:
        return project
    value = run_command(
        ["gcloud", "config", "get-value", "project"], capture_output=True
    ).stdout.strip()
    return "" if value == "(unset)" else value


def new_job_id(commit: str) -> str:
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    suffix = uuid.uuid4().hex[:6]
    return f"mahjong-four-tile-{commit[:8]}-{timestamp}-{suffix}"


def batch_job_json(
    project: str,
    region: str,
    job_id: str,
) -> dict[str, Any]:
    result = run_command(
        [
            "gcloud",
            "batch",
            "jobs",
            "describe",
            job_id,
            f"--project={project}",
            f"--location={region}",
            "--format=json",
        ],
        capture_output=True,
    )
    return json.loads(result.stdout)


def output_uri(bucket: str, job_id: str) -> str:
    return f"gs://{bucket}/jobs/{job_id}"


def submit(args: argparse.Namespace) -> int:
    project = get_project()
    if not project:
        raise RemoteComputeError(
            "Set GCP_PROJECT or select a project with `gcloud config set project`."
        )
    region = args.region or os.environ.get("GCP_REGION", DEFAULT_REGION)
    repository = required_setting("GCP_ARTIFACT_REPOSITORY")
    bucket = normalized_bucket(required_setting("GCP_BUCKET"))
    service_account = required_setting("GCP_BATCH_SERVICE_ACCOUNT")
    commit = verify_clean_checkout()
    job_id = new_job_id(commit)
    image = (
        f"{region}-docker.pkg.dev/{project}/{repository}/mahjong-compute:{commit}"
    )
    print(
        "GCP Batch job configuration:\n"
        f"  job: {job_id}\n"
        f"  region: {region}\n"
        "  machine: e2-standard-2 (2 vCPU, 8 GiB)\n"
        "  provisioning: Spot only\n"
        f"  maximum retries: {MAX_RETRIES}\n"
        f"  maximum runtime: {MAX_RUNTIME_SECONDS // 60} minutes\n"
        f"  output: {output_uri(bucket, job_id)}",
        flush=True,
    )
    digest = image_digest(project, region, image)
    immutable_image = f"{region}-docker.pkg.dev/{project}/{repository}/mahjong-compute@{digest}"
    spec = build_job_spec(
        project=project,
        region=region,
        job_id=job_id,
        service_account=service_account,
        image_uri=immutable_image,
        git_commit=commit,
        output_uri=output_uri(bucket, job_id),
        workers=args.workers,
    )
    with tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", suffix=".json"
    ) as config:
        json.dump(spec, config, indent=2)
        config.flush()
        run_command(
            [
                "gcloud",
                "batch",
                "jobs",
                "submit",
                job_id,
                f"--project={project}",
                f"--location={region}",
                f"--config={config.name}",
            ]
        )

    if args.detach:
        print(f"Submitted job {job_id}. Check it with `gcloud batch jobs describe {job_id} --location={region} --project={project}`.")
        print(f"Download when complete: ./scripts/remote-compute download {job_id}")
        return 0

    print(f"Waiting for Batch job {job_id}...", flush=True)
    last_state: str | None = None
    while True:
        job = batch_job_json(project, region, job_id)
        state = job.get("status", {}).get("state", "UNKNOWN")
        if state != last_state:
            print(f"Batch job state: {state}", flush=True)
            last_state = state
        if state in {"SUCCEEDED", "FAILED"}:
            break
        time.sleep(20)
    if state != "SUCCEEDED":
        raise RemoteComputeError(
            f"Batch job {job_id} finished with state {state}; inspect it with "
            f"`gcloud batch jobs describe {job_id} --location={region} --project={project}`."
        )
    return download_report(bucket, job_id, args.output)


def download_report(bucket: str, job_id: str, output: str | None) -> int:
    destination = Path(output) if output else ROOT / "reports" / f"four-tile-batch-{job_id}.txt"
    if not destination.is_absolute():
        destination = ROOT / destination
    if destination.exists():
        raise RemoteComputeError(
            f"Refusing to overwrite existing output: {destination}"
        )
    try:
        tracked_path = destination.relative_to(ROOT)
    except ValueError:
        tracked_path = destination
    tracked = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "--error-unmatch", str(tracked_path)],
        check=False,
        text=True,
        capture_output=True,
    )
    if tracked.returncode == 0:
        raise RemoteComputeError(
            f"Refusing to overwrite tracked file: {destination}"
        )
    destination.parent.mkdir(parents=True, exist_ok=True)
    metadata_result = run_command(
        [
            "gcloud",
            "storage",
            "cat",
            f"{output_uri(bucket, job_id)}/metadata.json",
        ],
        capture_output=True,
    )
    metadata = json.loads(metadata_result.stdout)
    report_metadata = metadata.get("report", {})
    expected_checksum = report_metadata.get("sha256")
    if metadata.get("status") != "SUCCEEDED" or not expected_checksum:
        raise RemoteComputeError(
            f"Job {job_id} does not have a verified successful report."
        )
    with tempfile.TemporaryDirectory(
        prefix=".remote-compute-", dir=destination.parent
    ) as temp:
        temporary_report = Path(temp) / REPORT_NAME
        run_command(
            [
                "gcloud",
                "storage",
                "cp",
                f"{output_uri(bucket, job_id)}/results/{REPORT_NAME}",
                str(temporary_report),
            ]
        )
        digest = hashlib.sha256(temporary_report.read_bytes()).hexdigest()
        if digest != expected_checksum:
            raise RemoteComputeError(
                f"Checksum mismatch for report from Batch job {job_id}."
            )
        try:
            os.link(temporary_report, destination)
        except FileExistsError as error:
            raise RemoteComputeError(
                f"Refusing to overwrite existing output: {destination}"
            ) from error
    print(f"Downloaded report for {job_id} to {destination}")
    return 0


def inspect_job(args: argparse.Namespace) -> int:
    project = get_project()
    if not project:
        raise RemoteComputeError(
            "Set GCP_PROJECT or select a project with `gcloud config set project`."
        )
    region = args.region or os.environ.get("GCP_REGION", DEFAULT_REGION)
    job = batch_job_json(project, region, args.job_id)
    print(json.dumps(job.get("status", {}), indent=2))
    return 0


def download(args: argparse.Namespace) -> int:
    bucket = normalized_bucket(required_setting("GCP_BUCKET"))
    return download_report(bucket, args.job_id, args.output)


def parse_gs_uri(value: str) -> tuple[str, str]:
    parsed = urlparse(value)
    if parsed.scheme != "gs" or not parsed.netloc:
        raise RemoteComputeError("Worker output must be a gs://bucket/prefix URI.")
    return parsed.netloc, parsed.path.strip("/")


def upload_file(bucket: Any, name: str, path: Path) -> None:
    bucket.blob(name).upload_from_filename(str(path))


def run_worker(args: argparse.Namespace) -> int:
    from google.api_core.exceptions import GoogleAPIError
    from google.auth.exceptions import GoogleAuthError
    from google.cloud import storage

    bucket_name, prefix = parse_gs_uri(args.output_uri)
    project = required_setting("GCP_PROJECT")
    client = storage.Client(project=project)
    bucket = client.bucket(bucket_name)
    started = utc_now()
    started_at = datetime.now(timezone.utc)
    exit_code = 1
    upload_errors: list[str] = []
    metadata: dict[str, Any] = {
        "job_id": args.job_id,
        "job_type": "four-tile",
        "git_commit": args.git_commit,
        "container_image": args.image,
        "region": os.environ.get("GCP_REGION"),
        "machine_type": os.environ.get("BATCH_MACHINE_TYPE"),
        "vcpu": os.environ.get("BATCH_VCPU"),
        "memory_mib": os.environ.get("BATCH_MEMORY_MIB"),
        "retry_attempt": os.environ.get("BATCH_TASK_RETRY_ATTEMPT"),
        "workers": args.workers,
        "started_at": started,
        "output_uri": args.output_uri,
    }
    request = {
        "job_id": args.job_id,
        "job_type": "four-tile",
        "git_commit": args.git_commit,
        "container_image": args.image,
        "region": os.environ.get("GCP_REGION"),
        "machine_type": os.environ.get("BATCH_MACHINE_TYPE"),
        "vcpu": os.environ.get("BATCH_VCPU"),
        "memory_mib": os.environ.get("BATCH_MEMORY_MIB"),
        "max_retries": MAX_RETRIES,
        "max_run_duration_seconds": MAX_RUNTIME_SECONDS,
        "arguments": [f"--workers={args.workers}"],
    }
    request_path = Path(tempfile.gettempdir()) / f"{args.job_id}-request.json"
    request_path.write_text(json.dumps(request, indent=2) + "\n", encoding="utf-8")
    try:
        upload_file(bucket, f"{prefix}/request.json", request_path)
    except (GoogleAPIError, GoogleAuthError, OSError) as error:
        request_path.unlink(missing_ok=True)
        raise RemoteComputeError(f"Could not upload job request: {error}") from error
    request_path.unlink(missing_ok=True)
    with tempfile.TemporaryDirectory(prefix="mahjong-batch-") as temp:
        temp_dir = Path(temp)
        report = temp_dir / REPORT_NAME
        time_log = temp_dir / "time-v.txt"
        command = [
            "/usr/bin/time",
            "-v",
            "-o",
            str(time_log),
            str(ROOT / ".lake" / "build" / "bin" / "four-tile-report-gen"),
            f"--workers={args.workers}",
            str(report),
        ]
        metadata["command"] = command[4:]
        try:
            result = subprocess.run(command, cwd=ROOT, check=False)
            exit_code = result.returncode
            if exit_code == 0 and not report.is_file():
                raise RemoteComputeError(
                    "Report generator succeeded but did not create its output."
                )
        except (OSError, RemoteComputeError) as error:
            print(f"Computation failed: {error}", file=sys.stderr, flush=True)
            exit_code = 1

        ended = utc_now()
        metadata.update(
            {
                "ended_at": ended,
                "duration_seconds": (
                    datetime.now(timezone.utc) - started_at
                ).total_seconds(),
                "exit_code": exit_code,
                "status": "SUCCEEDED" if exit_code == 0 else "FAILED",
            }
        )
        if report.is_file():
            checksum = hashlib.sha256(report.read_bytes()).hexdigest()
            metadata["report"] = {
                "uri": f"{args.output_uri}/results/{REPORT_NAME}",
                "sha256": checksum,
                "size_bytes": report.stat().st_size,
            }
            if exit_code == 0:
                try:
                    upload_file(bucket, f"{prefix}/results/{REPORT_NAME}", report)
                except (GoogleAPIError, GoogleAuthError, OSError) as error:
                    upload_errors.append(f"report upload failed: {error}")
        if time_log.is_file():
            try:
                print(time_log.read_text(encoding="utf-8"), flush=True)
                upload_file(bucket, f"{prefix}/logs/time-v.txt", time_log)
            except (GoogleAPIError, GoogleAuthError, OSError) as error:
                upload_errors.append(f"time log upload failed: {error}")

        if upload_errors:
            metadata["status"] = "ARTIFACT_UPLOAD_FAILED"
            metadata["artifact_upload_errors"] = upload_errors
        metadata_path = temp_dir / "metadata.json"
        metadata_path.write_text(
            json.dumps(metadata, indent=2) + "\n", encoding="utf-8"
        )
        try:
            upload_file(bucket, f"{prefix}/metadata.json", metadata_path)
        except (GoogleAPIError, GoogleAuthError, OSError) as error:
            upload_errors.append(f"metadata upload failed: {error}")
            print(upload_errors[-1], file=sys.stderr, flush=True)

    if upload_errors:
        for error in upload_errors:
            print(error, file=sys.stderr, flush=True)
        return 1
    return exit_code


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    subparsers = result.add_subparsers(dest="command", required=True)

    run_parser = subparsers.add_parser("run", help="build and submit a report job")
    run_parser.add_argument("job_type", choices=["four-tile"])
    run_parser.add_argument("--region")
    run_parser.add_argument("--workers", type=int, default=2)
    run_parser.add_argument("--detach", action="store_true")
    run_parser.add_argument("--output")
    run_parser.set_defaults(func=submit)

    status_parser = subparsers.add_parser("status", help="show a Batch job status")
    status_parser.add_argument("job_id")
    status_parser.add_argument("--region")
    status_parser.set_defaults(func=inspect_job)

    download_parser = subparsers.add_parser("download", help="download a report")
    download_parser.add_argument("job_id")
    download_parser.add_argument("--output")
    download_parser.set_defaults(func=download)

    worker_parser = subparsers.add_parser("worker", help="internal worker mode")
    worker_parser.add_argument("job_type", choices=["four-tile"])
    worker_parser.add_argument("output_uri")
    worker_parser.add_argument("job_id")
    worker_parser.add_argument("git_commit")
    worker_parser.add_argument("image")
    worker_parser.add_argument("workers", type=int)
    worker_parser.set_defaults(func=run_worker)
    return result


def main() -> int:
    try:
        arguments = parser().parse_args()
        if hasattr(arguments, "workers") and arguments.workers < 1:
            raise RemoteComputeError("--workers must be a positive integer.")
        if hasattr(arguments, "job_id") and not re.fullmatch(
            r"[a-z][a-z0-9-]{0,62}", arguments.job_id
        ):
            raise RemoteComputeError("Invalid GCP Batch job ID.")
        return arguments.func(arguments)
    except RemoteComputeError as error:
        print(f"Error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
