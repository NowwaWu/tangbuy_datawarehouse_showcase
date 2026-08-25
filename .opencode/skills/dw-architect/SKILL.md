---
name: dw-architect
description: Design data warehouse table structures (DDL) and write ETL SQL following Alibaba OneData methodology. Use whenever the user needs to design DDL, write ETL SQL, plan data domains and business processes, define naming conventions and root words, determine data warehouse layers, or classify fact table types (transaction/cumulative-snapshot/periodic-snapshot). Also use when the user mentions architecture design, modeling, or needs production-ready MaxCompute SQL.
---

# Data Warehouse Architect (Alibaba OneData V3.2)

Design enterprise-grade data warehouse tables and write production-ready ETL SQL with strict OneData compliance.

## Data Domain Abbreviations

`trd` / `itm` / `wh` / `pay` / `usr` / `store` / `dist` / `comm`

Never use ODS source table prefixes (product/plugin/storage/cps) inside the warehouse.
- **插件/代发 (plugin)**: 数仓内部统一用 **`ds`**（dropship）表示插件相关概念。
  例: `ds_ord_no` (插件订单号), `dwd_store_ds_auth_rel_df` (插件店铺授权关系表)。
  例外: `dim_store_plugin_df` 保持 `plugin` 用于维度表名中**店铺平台**的概念（店铺实体属性），
  但数据内容中与插件代发业务相关的实体/字段统一用 `ds`。

## Layer & Table Naming

| Layer | Format | Partition |
|-------|--------|-----------|
| DIM | `dim_<domain>_<entity>_df` | `ds` STRING yyyyMMdd |
| DWD | `dwd_{domain}_{business_process}_{entity}_{suffix}` | `ds` STRING yyyyMMdd |
| DWS | `dws_<domain>_<entity>_<grain>_{period_suffix}` | `ds` STRING yyyyMMdd |
| ADS | `ads_{mart}_{topic}_{custom}_{period_suffix}` | `ds` STRING yyyyMMdd |

**Suffix rules**: `_di` = daily increment (append-only), `_df` = daily full/cumulative snapshot, `_1d` = latest 1 day, `_td` = total-to-date, `_nd` = sliding N-day window.

## Fact Table Type Determination

Before designing any DWD table, classify the fact type:

| Type | Characteristics | Suffix | ETL Pattern |
|------|----------------|--------|-------------|
| Transaction | 1 row = 1 event, append-only | `_di` | INSERT OVERWRITE today partition only |
| Cumulative Snapshot | 1 row = 1 entity, updated in place, multiple milestone date columns | `_df` | Today delta FULL OUTER JOIN yesterday snapshot |
| Periodic Snapshot | 1 row = 1 entity × 1 period | `_1d` / `_nd` | Rebuild from full partition daily |

## Naming Semantics (Critical)

### Money
- **`amt` (Amount)**: Principal capital, settlement funds (e.g., `bal_amt`, `ord_amt`)
- **`fee` (Fee)**: Surcharges, costs (e.g., `post_fee`, `tax_fee`). Never mix amt/fee.

### Metric Suffix Position
Must follow `{subject}_{modifier}_{measure}`:
- ✅ `tot_pre_amt` — NOT `tot_amt_pre`
- ✅ `tech_srv_pre_fee` — NOT `tech_srv_fee_pre`

### Common Word Roots

| Concept | Root | Concept | Root |
|---------|------|---------|------|
| Amount | `amt` | Fee/Cost | `fee` |
| Count (times) | `cnt` | Order Number | `no` |
| ID | `id` | Percentage/Rate | `pct` / `rate` |
| Time (datetime) | `_time` | Date | `_date` |
| Create | `crt` | Update | `upd` |
| Delete | `del` | Cancel | `cxl` |
| Complete | `cmpl` | Pending | `pend` |
| Reject | `rjt` | Freeze/Lock | `frz` |
| Token | `tkn` | Region | `rgn` |
| Install | `inst` | Exchange | `exch` |
| Name | `nm` | Record | `rcd` |
| Content | `cnt` | Extend | `xtn` |
| Crash | `crsh` | Allocate | `alloc` |
| Goods/Item | `item` | Shop/Store | `shop` |
| User | `usr` | Default | `dflt` |
| Commission | `cmsn` | Service Fee | `srv_fee` |
| Extra | `xtra` | Activity | `acty` |
| Last | `last` | Assign | `asgn` |
| Return | `rtn` | Payment | `pay` |
| Paid | `payd` | Device | `dev` |

### Enum & Boolean

- Enum codes: `_cd` suffix (e.g., `shop_type_cd`)
- Status sequences: `_stat` suffix (e.g., `ord_stat`)
- Boolean flags: `is_` prefix, 1=Yes/On, 0=No/Off. If source is inverted, use CASE WHEN to normalize.

### External Isolation

Third-party platform entities: `out_` prefix (e.g., `out_shop_id`).

## Zero-NULL Policy

| Type | Fallback |
|------|----------|
| Numeric measures (amt/fee/cnt/prc/wt/rate) | `0` |
| JSON fields | `'{}'` |
| Boolean flags | `0` or `-1` |
| Status enums | `-1` |
| Time fields | Keep NULL (downstream `IS NOT NULL`) |

## ODS → DWD Type Casting

- DECIMAL(38,18) → CAST AS DECIMAL(18,4) for amounts, DECIMAL(18,6) for rates
- TIMESTAMP → CAST AS DATETIME
- Source table full-spelling field names → standard word root abbreviations in DWD

## Production SQL Standards

### Idempotency
Always use `INSERT OVERWRITE TABLE ... PARTITION(ds='${bizdate}')`. Never `INSERT INTO`.

### Date Filtering
Use `TO_DATE('${bizdate}', 'yyyymmdd')` + `DATEADD`, never `SUBSTR` string comparison:
```sql
WHERE create_time >= TO_DATE('${bizdate}', 'yyyymmdd')
  AND create_time <  DATEADD(TO_DATE('${bizdate}', 'yyyymmdd'), 1, 'dd')
```

### Cumulative Snapshot Pattern (Late-Arriving Changes)
```sql
INSERT OVERWRITE TABLE dwd_xxx_df PARTITION(ds='${bizdate}')
SELECT COALESCE(t.col, y.col) ...
FROM today_delta t FULL OUTER JOIN yesterday y ON t.pk = y.pk;
```

## Layer Chain Compliance

- **No layer skipping**: DWS must not read ODS directly. Must pass through DWD.
- **Single granularity**: One DWD table = one grain. Order header and line must be separate tables.
- **No metric redundancy across grains**: Header-level amounts must not be duplicated in line-level tables.
- **Cleaning logic consolidation**: `REGEXP_EXTRACT`, CASE WHEN status mapping only in DWD layer.

## Anti-Cartesian Product Strategies

- **Strategy A (Latest)**: `ROW_NUMBER() OVER(PARTITION BY id ORDER BY update_time DESC)` → take `rn=1`
- **Strategy B (Aggregate)**: `WM_CONCAT(',', col)` collapse multiple rows into one

## Role-Playing Dimensions

When a fact table joins the same dimension table twice for different purposes, use different aliases and add role prefixes to redundant fields (e.g., `pmt_nm` vs `usr_nm`).

## Metrics Governance

All warehouse metrics must be centrally managed under `data_model/数据指标/`:

| File | Content |
|------|---------|
| `原子指标.md` | Atomic metrics (smallest indivisible measurement units) |
| `派生指标.md` | Derived metrics (time period + modifier + atomic metric) |
| `复合指标.md` | Composite metrics (arithmetic combinations of derived metrics) |
| `修饰词.md` | Modifiers (business filter conditions) |
| `时间周期.md` | Time period definitions |

**Formula**: Derived Metric = Time Period + Modifier + Atomic Metric

## Workflow

1. **Assign data domain & business process**: Determine which domain and process the requirement belongs to
2. **Declare granularity**: What does one row represent?
3. **Classify fact table type**: Transaction / Cumulative Snapshot / Periodic Snapshot → decide `_di` or `_df`
4. **Extract and merge word roots**: Identify business concepts, filter redundancies, merge synonyms
5. **Split dimensions vs facts**: Mark dimension keys, degenerate dimensions, measures
6. **Architecture diagnosis**: Flag unreasonable designs (missing enum constraints, 1:N inflation risk, inverted 0/1 definitions)
7. **Output DDL**: Complete with word-root comments on every field
8. **Generate production ETL SQL**: With CTE/NVL/CASE WHEN, anti-inflation, Zero-NULL, ODS type casting
