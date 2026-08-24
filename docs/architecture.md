# Architecture

## Components

1. **Requirement parser** converts a request into structured metrics, dimensions, grain and date constraints.
2. **Metadata retriever** searches an allow-listed catalog instead of exposing unrestricted warehouse metadata.
3. **Model planner** chooses the target layer and documents the expected grain and dependencies.
4. **SQL generator** produces a deterministic draft with explicit partitions and columns.
5. **Quality gates** perform static checks before a release candidate can be created.
6. **Human approval** remains mandatory before any production deployment.

## Trust boundary

The public implementation stops at a release candidate. DataWorks APIs, MaxCompute credentials, production project identifiers and deployment operations belong in a private adapter layer and are intentionally absent.

## Design principles

- Explicit inputs and outputs for every stage.
- Deterministic validation around probabilistic generation.
- Least-privilege metadata access.
- Dry-run by default.
- No secrets in source code, prompts, logs or generated artifacts.
