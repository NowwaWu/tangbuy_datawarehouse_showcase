from __future__ import annotations

import re

from .models import GateResult


def review_sql(sql: str) -> list[GateResult]:
    normalized = " ".join(sql.lower().split())
    source_tables = re.findall(r"\b(?:from|join)\s+([a-z0-9_.]+)", normalized)
    target_match = re.search(r"insert\s+overwrite\s+table\s+([a-z0-9_.]+)", normalized)
    target = target_match.group(1) if target_match else ""

    return [
        GateResult(
            "explicit-columns",
            "select *" not in normalized,
            "SELECT * is forbidden; generated SQL must name every output column.",
        ),
        GateResult(
            "idempotent-write",
            "insert overwrite table" in normalized,
            "Partition writes must be idempotent.",
        ),
        GateResult(
            "partition-filter",
            "\${bizdate}" in sql,
            "The business-date partition must be explicit.",
        ),
        GateResult(
            "layer-boundary",
            not (
                target.startswith("dws_")
                and any(table.split(".")[-1].startswith("ods_") for table in source_tables)
            ),
            "DWS models must not read ODS directly.",
        ),
    ]
