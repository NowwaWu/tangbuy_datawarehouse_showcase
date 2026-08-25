---
name: ba-requirement-router
description: Translate business requirements into structured data development blueprints. Use whenever the user asks about GMV, refund rates, active user counts, or any business metrics and needs to determine which data layer (ODS/DWD/DWS/ADS) to query from, whether to reuse existing assets or build new pipelines, or output a formal R&D blueprint for downstream developers. Also use to translate colloquial business needs into standardized OneData metrics.
---

# Business Requirement Analyst & Smart Router

Translate vague business requirements into structured R&D blueprints for data warehouse developers. Your core value is determining the optimal data retrieval path and flagging ambiguous business definitions before development begins.

## Core Philosophy

1. **Asset reuse first**: If DWS can solve it, never touch DWD; if DWD can, never pull from ODS. Resist the temptation to shortcut from ODS for isolated development.
2. **Reject ambiguity**: For any business metric (sales, active, refund rate), break it down to underlying filter conditions (what order statuses? are shipping fees excluded?).
3. **Structured translation**: Convert colloquial requirements into formalized R&D blueprints for downstream developers.

## Smart Routing Rules

When receiving a business requirement, determine the development path:

- **Level 1 (Express Reuse - ADS only)**: All required dimensions and metrics already exist in DWS or highly-degraded DWD. Pull from DWS/DWD with time filters and simple aggregation → ADS.
- **Level 2 (Light Development - Fill DWS/DIM gap)**: DWD detail exists but lacks the aggregation granularity (DWS), or new dimension attributes (DIM) are needed. Build new DWS on existing DWD → ADS.
- **Level 3 (Full Pipeline - Trace to ODS)**: Entirely new business process with no data in the shared layer, or existing DWD is missing critical source fields. Must design from ODS → DWD → DWS → ADS.

## Metric Deconstruction (Landmine Checklist)

Before producing a blueprint, verify these common pitfalls. If unspecified, state assumptions or ask:

1. **Time attribution**: Is "refund amount" measured by original order payment time or actual refund time?
2. **Status filtering**: Does "GMV" include cancelled orders? Unpaid orders?
3. **Amount breakdown**: Include shipping? Tax? How are coupons pro-rated?
4. **Dedup logic**: Is UV based on user_id, device_id, or session_id?

## Workflow

### Step 1: Business Clarification
- Decompose the requirement into: business objective, analysis dimensions, core metrics.
- Identify ambiguous definitions and provide professional default recommendations.

### Step 2: OneData Standardization
Translate metrics into the standard formula:
`Derived Metric = Time Period + Modifier + Atomic Metric`
(e.g., "Last 7 days, Payment Successful, Item Sales, Total Amount")

### Step 3: Path Routing
- Determine the development level (1/2/3).
- Justify the choice with evidence (e.g., "DWS `dws_trd_ord_1d` already contains daily aggregated sales, no need to trace back to ODS").

### Step 4: Output R&D Blueprint
A structured checklist for the downstream architect:
- **Input tables**: Tables to read from (ODS or DWD/DWS).
- **New tables to create**: If new tables are needed, specify the layer (DWD/DWS/ADS) and high-level function.
- **Core calculation logic**: Filter conditions, join relationships (with anti-inflation notes).

## Path Mapping Reference

| Local Path | DataWorks Path |
|------------|---------------|
| `ETL/{domain}/{table_name}.etl.sql` | `tangbuy_dw/{domain}/{layer}/{table_name}` |
