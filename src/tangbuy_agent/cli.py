from __future__ import annotations

import json
import sys
from pathlib import Path

from .models import Requirement
from .pipeline import DataAgentPipeline


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: python -m tangbuy_agent.cli REQUEST_JSON CATALOG_JSON")
        return 2

    request_payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    requirement = Requirement(
        title=request_payload["title"],
        metric=request_payload["metric"],
        dimensions=tuple(request_payload["dimensions"]),
        grain=request_payload["grain"],
        date_field=request_payload["date_field"],
    )
    result = DataAgentPipeline(sys.argv[2]).run(requirement)
    print(result.sql)
    for gate in result.gates:
        print(f"[{'PASS' if gate.passed else 'FAIL'}] {gate.name}: {gate.message}")
    return 0 if result.releasable else 1


if __name__ == "__main__":
    raise SystemExit(main())
