#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Flink Realtime Compute control via OpenAPI SDK.

Mirrors the dw-platform-deploy approach for offline DataWorks/MaxCompute.
Default behavior: read-only (list, get, status). Write operations require
explicit confirmation.

Environment constants (hardcoded, do not guess):
    Flink Endpoint:  set via FLINK_ENDPOINT
    Workspace:       set via FLINK_WORKSPACE
    Namespace:       prod-tangbuy-us-flink-01-default

Credentials: ALIBABA_CLOUD_ACCESS_KEY_ID / ALIBABA_CLOUD_ACCESS_KEY_SECRET

Required RAM permission:
    Grant AliyunStreamReadOnlyAccess (read) or AliyunStreamFullAccess (read+write)
    to the sub-account accessing this API.
"""

import argparse
import json
import os
import sys
from dataclasses import dataclass, field
from datetime import datetime
from typing import Any, Dict, List, Optional

from alibabacloud_ververica20220718.client import Client
from alibabacloud_ververica20220718 import models
from alibabacloud_tea_openapi.models import Config
from alibabacloud_tea_util.models import RuntimeOptions


# ── Constants ──────────────────────────────────────────────────────────────

DEFAULT_ENDPOINT = os.getenv('FLINK_ENDPOINT', '')
DEFAULT_WORKSPACE = os.getenv('FLINK_WORKSPACE', '')
DEFAULT_NAMESPACE = "prod-tangbuy-us-flink-01-default"

# Allowed write action keywords (user must explicitly pass)
WRITE_ACTIONS = {"start", "stop", "restart", "delete", "deploy", "hotupdate"}


# ── Helpers ────────────────────────────────────────────────────────────────

def _print_json(data: Any, title: Optional[str] = None) -> None:
    """Pretty-print JSON with optional title."""
    if title:
        print(f"\n{'='*60}")
        print(f"  {title}")
        print(f"{'='*60}")
    print(json.dumps(data, indent=2, ensure_ascii=False, default=str))


def _parse_bool(v: str) -> bool:
    return v.lower() in ("true", "1", "yes", "y")


# ── Client wrapper ─────────────────────────────────────────────────────────

@dataclass
class FlinkConfig:
    access_id: str
    access_key: str
    endpoint: str = DEFAULT_ENDPOINT
    workspace: str = DEFAULT_WORKSPACE
    namespace: str = DEFAULT_NAMESPACE


class FlinkClient:
    """Flink Ververica OpenAPI client with automatic workspace header injection."""

    def __init__(self, cfg: FlinkConfig):
        self._cfg = cfg
        api_cfg = Config(
            access_key_id=cfg.access_id,
            access_key_secret=cfg.access_key,
            endpoint=cfg.endpoint,
        )
        self._client = Client(api_cfg)
        self._runtime = RuntimeOptions()

    @property
    def workspace(self) -> str:
        return self._cfg.workspace

    @property
    def namespace(self) -> str:
        return self._cfg.namespace

    # ── Read operations ────────────────────────────────────────────────

    def list_deployments(
        self,
        page_index: int = 1,
        page_size: int = 20,
        name: Optional[str] = None,
        status: Optional[str] = None,
        execution_mode: Optional[str] = None,
        sort_name: Optional[str] = None,
    ) -> Dict:
        """List all deployed Flink jobs (deployments)."""
        req = models.ListDeploymentsRequest(
            page_index=page_index,
            page_size=min(page_size, 100),
            name=name,
            status=status,
            execution_mode=execution_mode,
            sort_name=sort_name,
        )
        headers = models.ListDeploymentsHeaders(workspace=self.workspace)
        resp = self._client.list_deployments_with_options(
            self.namespace, req, headers, self._runtime
        )
        return resp.body.to_map()

    def get_deployment(self, deployment_id: str) -> Dict:
        """Get details of a single deployment."""
        headers = models.GetDeploymentHeaders(workspace=self.workspace)
        resp = self._client.get_deployment_with_options(
            self.namespace, deployment_id, headers, self._runtime
        )
        return resp.body.to_map()

    def list_jobs(
        self,
        deployment_id: str,
        page_index: int = 1,
        page_size: int = 20,
        sort_name: Optional[str] = None,
    ) -> Dict:
        """List job instances for a deployment."""
        req = models.ListJobsRequest(
            deployment_id=deployment_id,
            page_index=page_index,
            page_size=min(page_size, 100),
            sort_name=sort_name,
        )
        headers = models.ListJobsHeaders(workspace=self.workspace)
        resp = self._client.list_jobs_with_options(
            self.namespace, req, headers, self._runtime
        )
        return resp.body.to_map()

    def get_job(self, job_id: str) -> Dict:
        """Get details of a single job instance."""
        headers = models.GetJobHeaders(workspace=self.workspace)
        resp = self._client.get_job_with_options(
            self.namespace, job_id, headers, self._runtime
        )
        return resp.body.to_map()

    def get_events(
        self,
        deployment_id: str,
        page_index: int = 1,
        page_size: int = 50,
    ) -> Dict:
        """Get events for a deployment."""
        req = models.GetEventsRequest(
            deployment_id=deployment_id,
            page_index=page_index,
            page_size=min(page_size, 100),
        )
        headers = models.GetEventsHeaders(workspace=self.workspace)
        resp = self._client.get_events_with_options(
            self.namespace, req, headers, self._runtime
        )
        return resp.body.to_map()

    def get_job_diagnosis(self, job_id: str) -> Dict:
        """Get intelligent diagnosis for a job."""
        headers = models.GetJobDiagnosisHeaders(workspace=self.workspace)
        resp = self._client.get_job_diagnosis_with_options(
            self.namespace, job_id, headers, self._runtime
        )
        return resp.body.to_map()

    def get_latest_job_start_log(self, job_id: str) -> Dict:
        """Get the latest start log for a job instance."""
        headers = models.GetLatestJobStartLogHeaders(workspace=self.workspace)
        resp = self._client.get_latest_job_start_log_with_options(
            self.namespace, job_id, headers, self._runtime
        )
        return resp.body.to_map()

    def list_savepoints(
        self,
        deployment_id: str,
        page_index: int = 1,
        page_size: int = 20,
    ) -> Dict:
        """List savepoints and checkpoints for a deployment."""
        req = models.ListSavepointsRequest(
            deployment_id=deployment_id,
            page_index=page_index,
            page_size=min(page_size, 100),
        )
        headers = models.ListSavepointsHeaders(workspace=self.workspace)
        resp = self._client.list_savepoints_with_options(
            self.namespace, req, headers, self._runtime
        )
        return resp.body.to_map()

    # ── Write operations (require confirmation) ────────────────────────

    def start_job(
        self,
        deployment_id: str,
        resource_setting_spec: Optional[Dict] = None,
        restore_strategy: Optional[str] = None,
    ) -> Dict:
        """Start a job instance for a deployment.

        Args:
            deployment_id: The deployment to start.
            resource_setting_spec: Optional resource override spec.
            restore_strategy: Optional savepoint restore strategy.
        """
        body = models.StartJobRequestBody(
            deployment_id=deployment_id,
            resource_setting_spec=resource_setting_spec,
            restore_strategy=restore_strategy,
        )
        req = models.StartJobWithParamsRequest(body=body)
        headers = models.StartJobWithParamsHeaders(workspace=self.workspace)
        resp = self._client.start_job_with_params_with_options(
            self.namespace, req, headers, self._runtime
        )
        return resp.body.to_map()

    def stop_job(self, job_id: str, stop_strategy: Optional[str] = None) -> Dict:
        """Stop a job instance.

        Args:
            job_id: The job instance to stop.
            stop_strategy: Optional stop strategy.
        """
        body = models.StopJobRequestBody(stop_strategy=stop_strategy)
        req = models.StopJobRequest(body=body)
        headers = models.StopJobHeaders(workspace=self.workspace)
        resp = self._client.stop_job_with_options(
            self.namespace, job_id, req, headers, self._runtime
        )
        return resp.body.to_map()

    def create_savepoint(
        self,
        deployment_id: str,
        description: Optional[str] = None,
        native_format: bool = True,
    ) -> Dict:
        """Create a savepoint for a deployment."""
        req = models.CreateSavepointRequest(
            deployment_id=deployment_id,
            description=description,
            native_format=native_format,
        )
        headers = models.CreateSavepointHeaders(workspace=self.workspace)
        resp = self._client.create_savepoint_with_options(
            self.namespace, req, headers, self._runtime
        )
        return resp.body.to_map()

    def delete_deployment(self, deployment_id: str) -> Dict:
        """Delete a deployment by ID."""
        headers = models.DeleteDeploymentHeaders(workspace=self.workspace)
        resp = self._client.delete_deployment_with_options(
            self.namespace, deployment_id, headers, self._runtime
        )
        return resp.body.to_map()


# ── Credential loading ─────────────────────────────────────────────────────

def load_credentials() -> FlinkConfig:
    """Load credentials from environment.

    Order: env vars → opencode.json mcp config
    """
    access_id = os.getenv("ALIBABA_CLOUD_ACCESS_KEY_ID") or os.getenv("ODPS_ACCESS_ID")
    access_key = os.getenv("ALIBABA_CLOUD_ACCESS_KEY_SECRET") or os.getenv("ODPS_ACCESS_KEY")

    if not access_id or not access_key:
        # Try opencode.json
        opencode_cfg_path = os.path.join(
            os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
            "opencode.json",
        )
        if os.path.exists(opencode_cfg_path):
            with open(opencode_cfg_path, "r") as f:
                cfg = json.load(f)
            mcp_env = cfg.get("mcp", {}).get("maxcompute", {}).get("environment", {})
            access_id = access_id or mcp_env.get("ODPS_ACCESS_ID")
            access_key = access_key or mcp_env.get("ODPS_ACCESS_KEY")

    if not access_id or not access_key:
        raise RuntimeError(
            "Missing Alibaba Cloud credentials. Set ALIBABA_CLOUD_ACCESS_KEY_ID "
            "and ALIBABA_CLOUD_ACCESS_KEY_SECRET environment variables."
        )

    return FlinkConfig(access_id=access_id, access_key=access_key)


# ── CLI ────────────────────────────────────────────────────────────────────

def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        description="Flink Realtime Compute control (OpenAPI SDK)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # List all deployments
  python3 pyshell/flink_control.py list-deployments

  # List deployments with status filter
  python3 pyshell/flink_control.py list-deployments --status RUNNING

  # List jobs for a deployment
  python3 pyshell/flink_control.py list-jobs --deployment-id <id>

  # Get deployment detail
  python3 pyshell/flink_control.py get-deployment --deployment-id <id>

  # Get job detail, diagnosis, or start log
  python3 pyshell/flink_control.py get-job --job-id <id>
  python3 pyshell/flink_control.py diagnosis --job-id <id>
  python3 pyshell/flink_control.py start-log --job-id <id>

  # List savepoints for a deployment
  python3 pyshell/flink_control.py list-savepoints --deployment-id <id>

  # Start a job (requires --yes)
  python3 pyshell/flink_control.py start --deployment-id <id> --yes

  # Stop a job (requires --yes)
  python3 pyshell/flink_control.py stop --job-id <id> --yes

  # Create savepoint (requires --yes)
  python3 pyshell/flink_control.py create-savepoint --deployment-id <id> --yes
        """,
    )

    sub = p.add_subparsers(dest="command", help="Action to perform")

    # list-deployments
    sp = sub.add_parser("list-deployments", help="List deployed Flink jobs")
    sp.add_argument("--page", type=int, default=1)
    sp.add_argument("--page-size", type=int, default=20)
    sp.add_argument("--name")
    sp.add_argument("--status", choices=["RUNNING", "FAILED", "CANCELLED", "FINISHED", "TRANSITIONING"])
    sp.add_argument("--execution-mode", choices=["STREAMING", "BATCH"])
    sp.add_argument("--sort-name", choices=["gmt_create", "gmt_modified"])

    # get-deployment
    sp = sub.add_parser("get-deployment", help="Get deployment detail")
    sp.add_argument("--deployment-id", required=True)

    # list-jobs
    sp = sub.add_parser("list-jobs", help="List job instances for a deployment")
    sp.add_argument("--deployment-id", required=True)
    sp.add_argument("--page", type=int, default=1)
    sp.add_argument("--page-size", type=int, default=20)

    # get-job
    sp = sub.add_parser("get-job", help="Get job instance detail")
    sp.add_argument("--job-id", required=True)

    # events
    sp = sub.add_parser("events", help="Get deployment events")
    sp.add_argument("--deployment-id", required=True)
    sp.add_argument("--page", type=int, default=1)
    sp.add_argument("--page-size", type=int, default=50)

    # diagnosis
    sp = sub.add_parser("diagnosis", help="Get job intelligent diagnosis")
    sp.add_argument("--job-id", required=True)

    # start-log
    sp = sub.add_parser("start-log", help="Get latest job start log")
    sp.add_argument("--job-id", required=True)

    # list-savepoints
    sp = sub.add_parser("list-savepoints", help="List savepoints for a deployment")
    sp.add_argument("--deployment-id", required=True)
    sp.add_argument("--page", type=int, default=1)
    sp.add_argument("--page-size", type=int, default=20)

    # start (write)
    sp = sub.add_parser("start", help="Start a job instance (requires --yes)")
    sp.add_argument("--deployment-id", required=True)
    sp.add_argument("--yes", action="store_true", help="Confirm write operation")

    # stop (write)
    sp = sub.add_parser("stop", help="Stop a job instance (requires --yes)")
    sp.add_argument("--job-id", required=True)
    sp.add_argument("--yes", action="store_true", help="Confirm write operation")

    # create-savepoint (write)
    sp = sub.add_parser("create-savepoint", help="Create a savepoint (requires --yes)")
    sp.add_argument("--deployment-id", required=True)
    sp.add_argument("--description")
    sp.add_argument("--yes", action="store_true", help="Confirm write operation")

    # delete-deployment (write)
    sp = sub.add_parser("delete-deployment", help="Delete a deployment (requires --yes)")
    sp.add_argument("--deployment-id", required=True)
    sp.add_argument("--yes", action="store_true", help="Confirm write operation")

    return p


def main():
    parser = _build_parser()
    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        return

    cfg = load_credentials()
    client = FlinkClient(cfg)

    # ── Read commands ──────────────────────────────────────────────────
    if args.command == "list-deployments":
        result = client.list_deployments(
            page_index=args.page,
            page_size=args.page_size,
            name=args.name,
            status=args.status,
            execution_mode=args.execution_mode,
            sort_name=args.sort_name,
        )
        _print_deployments_summary(result)

    elif args.command == "get-deployment":
        result = client.get_deployment(args.deployment_id)
        _print_json(result, f"Deployment: {args.deployment_id}")

    elif args.command == "list-jobs":
        result = client.list_jobs(
            deployment_id=args.deployment_id,
            page_index=args.page,
            page_size=args.page_size,
        )
        _print_jobs_summary(result)

    elif args.command == "get-job":
        result = client.get_job(args.job_id)
        _print_json(result, f"Job: {args.job_id}")

    elif args.command == "events":
        result = client.get_events(
            deployment_id=args.deployment_id,
            page_index=args.page,
            page_size=args.page_size,
        )
        _print_json(result, f"Events: {args.deployment_id}")

    elif args.command == "diagnosis":
        result = client.get_job_diagnosis(args.job_id)
        _print_json(result, f"Diagnosis: {args.job_id}")

    elif args.command == "start-log":
        result = client.get_latest_job_start_log(args.job_id)
        _print_json(result, f"Start Log: {args.job_id}")

    elif args.command == "list-savepoints":
        result = client.list_savepoints(
            deployment_id=args.deployment_id,
            page_index=args.page,
            page_size=args.page_size,
        )
        _print_json(result, f"Savepoints: {args.deployment_id}")

    # ── Write commands (require --yes) ─────────────────────────────────
    elif args.command == "start":
        if not args.yes:
            print(
                "⚠️  This will START a Flink job instance. "
                "Re-run with --yes to confirm."
            )
            sys.exit(1)
        result = client.start_job(deployment_id=args.deployment_id)
        _print_json(result, f"Start Result: {args.deployment_id}")

    elif args.command == "stop":
        if not args.yes:
            print(
                "⚠️  This will STOP a Flink job instance. "
                "Re-run with --yes to confirm."
            )
            sys.exit(1)
        result = client.stop_job(job_id=args.job_id)
        _print_json(result, f"Stop Result: {args.job_id}")

    elif args.command == "create-savepoint":
        if not args.yes:
            print(
                "⚠️  This will create a savepoint. "
                "Re-run with --yes to confirm."
            )
            sys.exit(1)
        result = client.create_savepoint(
            deployment_id=args.deployment_id,
            description=args.description,
        )
        _print_json(result, f"Savepoint Result: {args.deployment_id}")

    elif args.command == "delete-deployment":
        if not args.yes:
            print(
                "⚠️  This will DELETE a Flink deployment permanently. "
                "Re-run with --yes to confirm."
            )
            sys.exit(1)
        result = client.delete_deployment(deployment_id=args.deployment_id)
        _print_json(result, f"Delete Result: {args.deployment_id}")


# ── Display helpers ────────────────────────────────────────────────────────

def _print_deployments_summary(result: Dict) -> None:
    """Print a compact summary of deployments."""
    total = result.get("totalSize", 0)
    page = result.get("pageIndex", 1)
    page_size = result.get("pageSize", 20)
    data = result.get("data") or []

    print(f"\nDeployments: {total} total (page {page}, {page_size}/page)")
    print(f"{'─' * 90}")
    print(f"{'Name':<35} {'ID':<22} {'Status':<14} {'Mode'}")
    print(f"{'─' * 90}")

    for dep in data:
        did = dep.get("deploymentId", "-")
        name = dep.get("name", "-")[:33]
        status = _extract_status(dep)
        mode = dep.get("executionMode", "-")
        print(f"{name:<35} {did:<22} {status:<14} {mode}")

    if not data:
        print("  (no deployments found)")

    print(f"{'─' * 90}")

    # Show success/error info
    if not result.get("success", True):
        print(f"⚠️  Error: [{result.get('errorCode')}] {result.get('errorMessage')}")


def _print_jobs_summary(result: Dict) -> None:
    """Print a compact summary of job instances."""
    total = result.get("totalSize", 0)
    data = result.get("data") or []

    print(f"\nJob Instances: {total} total")
    print(f"{'─' * 100}")
    print(f"{'Job ID':<50} {'Status':<14} {'Started'}")
    print(f"{'─' * 100}")

    for job in data:
        jid = job.get("jobId", "-")
        status = job.get("status", {}).get("state", "-") if isinstance(job.get("status"), dict) else job.get("status", "-")
        started = job.get("startedAt", "-")
        print(f"{jid:<50} {status:<14} {started}")

    if not data:
        print("  (no job instances found)")

    print(f"{'─' * 100}")


def _extract_status(dep: Dict) -> str:
    """Extract status from deployment dict, handling nested structure."""
    # deployment-level status
    js = dep.get("jobSummary", {})
    if js:
        for state in ("running", "failed", "cancelled", "finished", "starting", "cancelling"):
            if js.get(state, 0) > 0:
                return f"{state.upper()} ({js[state]})"
    # direct status
    if dep.get("status"):
        return dep["status"]
    return "-"


if __name__ == "__main__":
    main()
