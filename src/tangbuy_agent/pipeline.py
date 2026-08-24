from __future__ import annotations

import json
from pathlib import Path

from .gates import review_sql
from .models import Asset, PipelineResult, Requirement, Stage


class DataAgentPipeline:
    """A deterministic public skeleton of a warehouse-development agent."""

    def __init__(self, catalog_path: str | Path):
        payload = json.loads(Path(catalog_path).read_text(encoding="utf-8"))
        self.assets = [
            Asset(
                name=item["name"],
                layer=item["layer"],
                grain=item["grain"],
                columns=tuple(item["columns"]),
            )
            for item in payload["assets"]
        ]

    def run(self, requirement: Requirement) -> PipelineResult:
        candidates = [asset for asset in self.assets if asset.grain == requirement.grain]
        if not candidates:
            return PipelineResult(stage=Stage.RETRIEVAL, sql="", assets=[])

        source = candidates[0]
        select_dimensions = ",\n    ".join(requirement.dimensions)
        group_by = ", ".join(str(index + 1) for index in range(len(requirement.dimensions)))
        sql = f"""INSERT OVERWRITE TABLE dws_demo_order_line_1d PARTITION(ds='\${bizdate}')
SELECT
    {select_dimensions},
    SUM({requirement.metric}) AS metric_value
FROM {source.name}
WHERE ds = '\${bizdate}'
GROUP BY {group_by};
"""
        gates = review_sql(sql)
        stage = Stage.RELEASE_CANDIDATE if all(gate.passed for gate in gates) else Stage.REVIEW
        return PipelineResult(stage=stage, sql=sql, assets=candidates, gates=gates)
