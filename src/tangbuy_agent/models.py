from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum


class Stage(str, Enum):
    REQUIREMENT = "requirement"
    RETRIEVAL = "retrieval"
    MODELING = "modeling"
    GENERATION = "generation"
    REVIEW = "review"
    RELEASE_CANDIDATE = "release_candidate"


@dataclass(frozen=True)
class Requirement:
    title: str
    metric: str
    dimensions: tuple[str, ...]
    grain: str
    date_field: str


@dataclass(frozen=True)
class Asset:
    name: str
    layer: str
    grain: str
    columns: tuple[str, ...]


@dataclass(frozen=True)
class GateResult:
    name: str
    passed: bool
    message: str


@dataclass
class PipelineResult:
    stage: Stage
    sql: str
    assets: list[Asset] = field(default_factory=list)
    gates: list[GateResult] = field(default_factory=list)

    @property
    def releasable(self) -> bool:
        return bool(self.gates) and all(gate.passed for gate in self.gates)
