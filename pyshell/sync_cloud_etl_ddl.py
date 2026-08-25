#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Sync local ETL / DDL files from DataWorks and MaxCompute.

Rules:
- Existing ETL files under ETL/** matching *.etl.sql or *.etl.py are replaced
  by DataWorks node content with the same node name.
- Existing DDL files under ETL/** matching *.ddl.sql are replaced by the
  MaxCompute table DDL with the same table name.
- Files without an exact cloud match are left untouched and reported.
"""

import argparse
import json
import os
import time
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Dict, Iterable, List, Optional

from alibabacloud_dataworks_public20240518.client import Client
from alibabacloud_dataworks_public20240518 import models
from alibabacloud_tea_openapi.models import Config
from odps import ODPS


DEFAULT_DATAWORKS_ENDPOINT = os.getenv('DATAWORKS_ENDPOINT', 'https://dataworks.example.invalid')
DEFAULT_DATAWORKS_PROJECT_ID = 68155
DEFAULT_ODPS_ENDPOINT = os.getenv('ODPS_ENDPOINT', 'https://maxcompute.example.invalid')
DEFAULT_ODPS_PROJECT = "prod"


@dataclass
class Settings:
    access_id: str
    access_key: str
    dataworks_endpoint: str
    dataworks_project_id: int
    odps_endpoint: str
    odps_project: str


def load_settings(root: Path, args: argparse.Namespace) -> Settings:
    opencode_cfg = root / "opencode.json"
    cfg_env = {}
    if opencode_cfg.exists():
        cfg = json.loads(opencode_cfg.read_text(encoding="utf-8"))
        cfg_env = (
            cfg.get("mcp", {})
            .get("maxcompute", {})
            .get("environment", {})
        )

    access_id = (
        os.getenv("ALIBABA_CLOUD_ACCESS_KEY_ID")
        or os.getenv("ODPS_ACCESS_ID")
        or cfg_env.get("ODPS_ACCESS_ID")
    )
    access_key = (
        os.getenv("ALIBABA_CLOUD_ACCESS_KEY_SECRET")
        or os.getenv("ODPS_ACCESS_KEY")
        or cfg_env.get("ODPS_ACCESS_KEY")
    )
    odps_endpoint = (
        args.odps_endpoint
        or os.getenv("ODPS_ENDPOINT")
        or cfg_env.get("ODPS_ENDPOINT")
        or DEFAULT_ODPS_ENDPOINT
    )
    odps_project = (
        args.odps_project
        or os.getenv("ODPS_PROJECT")
        or cfg_env.get("ODPS_PROJECT")
        or DEFAULT_ODPS_PROJECT
    )

    if not access_id or not access_key:
        raise RuntimeError(
            "Missing Alibaba Cloud credentials. Set ALIBABA_CLOUD_ACCESS_KEY_ID "
            "and ALIBABA_CLOUD_ACCESS_KEY_SECRET, or ODPS_ACCESS_ID / ODPS_ACCESS_KEY."
        )

    return Settings(
        access_id=access_id,
        access_key=access_key,
        dataworks_endpoint=args.dataworks_endpoint or DEFAULT_DATAWORKS_ENDPOINT,
        dataworks_project_id=args.dataworks_project_id,
        odps_endpoint=odps_endpoint,
        odps_project=odps_project,
    )


def local_etl_files(root: Path) -> List[Path]:
    files = []
    for path in (root / "ETL").glob("**/*"):
        if path.is_file() and (path.name.endswith(".etl.sql") or path.name.endswith(".etl.py")):
            files.append(path)
    return sorted(files)


def local_ddl_files(root: Path) -> List[Path]:
    return sorted((root / "ETL").glob("**/*.ddl.sql"))


def etl_base_name(path: Path) -> str:
    name = path.name
    if name.endswith(".etl.sql"):
        return name[:-len(".etl.sql")]
    if name.endswith(".etl.py"):
        return name[:-len(".etl.py")]
    raise ValueError(f"Unsupported ETL file: {path}")


def ddl_base_name(path: Path) -> str:
    return path.name[:-len(".ddl.sql")]


def write_text(path: Path, content: str, dry_run: bool) -> bool:
    if not content.endswith("\n"):
        content += "\n"
    old = path.read_text(encoding="utf-8") if path.exists() else ""
    changed = old != content
    if changed and not dry_run:
        path.write_text(content, encoding="utf-8")
    return changed


def list_dataworks_nodes(client: Client, project_id: int) -> Dict[str, dict]:
    nodes_by_name: Dict[str, dict] = {}
    page_number = 1
    while True:
        req = models.ListNodesRequest(
            project_id=project_id,
            page_number=page_number,
            page_size=50,
        )
        resp = call_with_retry(lambda: client.list_nodes(req))
        paging = resp.body.paging_info.to_map()
        nodes = paging.get("Nodes", []) or []
        for node in nodes:
            name = node.get("Name")
            if name and name not in nodes_by_name:
                nodes_by_name[name] = node
        total = int(paging.get("TotalCount") or len(nodes_by_name))
        if len(nodes_by_name) >= total or not nodes:
            break
        page_number += 1
    return nodes_by_name


def get_dataworks_node_content(client: Client, project_id: int, node_id: str) -> str:
    resp = call_with_retry(
        lambda: client.get_node(models.GetNodeRequest(project_id=project_id, id=node_id))
    )
    node = resp.body.node.to_map()
    spec = node.get("Spec")
    spec_obj = json.loads(spec) if isinstance(spec, str) else spec
    flow_nodes = (((spec_obj or {}).get("spec") or {}).get("nodes") or [])
    if not flow_nodes:
        raise RuntimeError(f"Node {node_id} has no flow nodes in Spec")
    script = flow_nodes[0].get("script") or {}
    content = script.get("content")
    if content is None:
        raise RuntimeError(f"Node {node_id} has no script content")
    return content


def is_throttling_error(exc: Exception) -> bool:
    text = str(exc)
    return "Throttling" in text or "9990020002" in text


def call_with_retry(fn, max_attempts: int = 5):
    for attempt in range(1, max_attempts + 1):
        try:
            return fn()
        except Exception as exc:
            if attempt >= max_attempts or not is_throttling_error(exc):
                raise
            time.sleep(min(30, 2 ** attempt))


def get_odps_tables(odps: ODPS) -> set:
    return {table.name for table in odps.list_tables()}


def get_odps_ddl(odps: ODPS, table_name: str) -> str:
    ddl = odps.get_table(table_name).get_ddl()
    ddl = ddl.rstrip()
    if not ddl.endswith(";"):
        ddl += ";"
    return ddl + "\n"


def rel_list(root: Path, paths: Iterable[Path]) -> List[str]:
    return [str(path.relative_to(root)) for path in paths]


def render_report(
    *,
    started_at: datetime,
    dry_run: bool,
    root: Path,
    etl_changed: List[Path],
    etl_unchanged: List[Path],
    etl_missing: List[Path],
    etl_failed: Dict[Path, str],
    ddl_changed: List[Path],
    ddl_unchanged: List[Path],
    ddl_missing: List[Path],
    ddl_failed: Dict[Path, str],
) -> str:
    def section(title: str, lines: List[str]) -> List[str]:
        result = [f"## {title}", ""]
        if lines:
            result.extend(f"- `{line}`" for line in lines)
        else:
            result.append("- 无")
        result.append("")
        return result

    lines = [
        "# Cloud ETL / DDL Sync Report",
        "",
        f"- Time: {started_at.strftime('%Y-%m-%d %H:%M:%S')}",
        f"- Mode: {'dry-run' if dry_run else 'write'}",
        f"- ETL changed: {len(etl_changed)}",
        f"- ETL unchanged: {len(etl_unchanged)}",
        f"- ETL missing cloud node: {len(etl_missing)}",
        f"- ETL failed: {len(etl_failed)}",
        f"- DDL changed: {len(ddl_changed)}",
        f"- DDL unchanged: {len(ddl_unchanged)}",
        f"- DDL missing ODPS table: {len(ddl_missing)}",
        f"- DDL failed: {len(ddl_failed)}",
        "",
    ]
    lines += section("ETL Changed", rel_list(root, etl_changed))
    lines += section("ETL Missing DataWorks Node", rel_list(root, etl_missing))
    lines += section("DDL Changed", rel_list(root, ddl_changed))
    lines += section("DDL Missing ODPS Table", rel_list(root, ddl_missing))

    failed_lines = [
        f"{path.relative_to(root)}: {msg}" for path, msg in sorted(
            {**etl_failed, **ddl_failed}.items(), key=lambda item: str(item[0])
        )
    ]
    lines += section("Failures", failed_lines)
    return "\n".join(lines)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Replace local ETL / DDL files with DataWorks and ODPS sources of truth."
    )
    parser.add_argument("--root", default=".", help="Project root directory")
    parser.add_argument("--dry-run", action="store_true", help="Report only; do not write files")
    parser.add_argument("--report-dir", default="reports", help="Directory for sync report")
    parser.add_argument("--dataworks-endpoint", default=None)
    parser.add_argument("--dataworks-project-id", type=int, default=DEFAULT_DATAWORKS_PROJECT_ID)
    parser.add_argument("--odps-endpoint", default=None)
    parser.add_argument("--odps-project", default=None)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    root = Path(args.root).resolve()
    started_at = datetime.now()
    settings = load_settings(root, args)

    client = Client(
        Config(
            access_key_id=settings.access_id,
            access_key_secret=settings.access_key,
            endpoint=settings.dataworks_endpoint,
        )
    )
    odps = ODPS(
        settings.access_id,
        settings.access_key,
        settings.odps_project,
        endpoint=settings.odps_endpoint,
    )

    nodes_by_name = list_dataworks_nodes(client, settings.dataworks_project_id)
    odps_tables = get_odps_tables(odps)

    etl_changed: List[Path] = []
    etl_unchanged: List[Path] = []
    etl_missing: List[Path] = []
    etl_failed: Dict[Path, str] = {}
    for path in local_etl_files(root):
        base = etl_base_name(path)
        node = nodes_by_name.get(base)
        if not node:
            etl_missing.append(path)
            continue
        try:
            content = get_dataworks_node_content(
                client,
                settings.dataworks_project_id,
                str(node["Id"]),
            )
            changed = write_text(path, content, args.dry_run)
            (etl_changed if changed else etl_unchanged).append(path)
        except Exception as exc:
            etl_failed[path] = f"{type(exc).__name__}: {exc}"

    ddl_changed: List[Path] = []
    ddl_unchanged: List[Path] = []
    ddl_missing: List[Path] = []
    ddl_failed: Dict[Path, str] = {}
    for path in local_ddl_files(root):
        table_name = ddl_base_name(path)
        if table_name not in odps_tables:
            ddl_missing.append(path)
            continue
        try:
            ddl = get_odps_ddl(odps, table_name)
            changed = write_text(path, ddl, args.dry_run)
            (ddl_changed if changed else ddl_unchanged).append(path)
        except Exception as exc:
            ddl_failed[path] = f"{type(exc).__name__}: {exc}"

    report = render_report(
        started_at=started_at,
        dry_run=args.dry_run,
        root=root,
        etl_changed=etl_changed,
        etl_unchanged=etl_unchanged,
        etl_missing=etl_missing,
        etl_failed=etl_failed,
        ddl_changed=ddl_changed,
        ddl_unchanged=ddl_unchanged,
        ddl_missing=ddl_missing,
        ddl_failed=ddl_failed,
    )

    report_dir = root / args.report_dir
    if not args.dry_run:
        report_dir.mkdir(parents=True, exist_ok=True)
        stamp = started_at.strftime("%Y%m%d_%H%M%S")
        report_path = report_dir / f"sync_cloud_etl_ddl_{stamp}.md"
        report_path.write_text(report, encoding="utf-8")
        print(f"report={report_path.relative_to(root)}")

    print(report)

    if etl_failed or ddl_failed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
