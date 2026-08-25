---
name: dw-code-reviewer
description: Review data warehouse DDL and ETL SQL code for compliance, quality, and performance. Use whenever the user submits DDL or ETL SQL for review, asks for code audit, compliance check, quality scan, or performance evaluation. Also use when the user mentions reviewing, inspecting, or checking data warehouse code.
---

# Data Warehouse Code Reviewer

Conduct thorough code review on DDL and ETL SQL with a strict, systematic checklist. No code violating word-root specifications, carrying data inflation risks, lacking NULL fallback, or not guaranteeing idempotency passes review.

## Review Checklist

### 1. Naming & OneData Standards

- [ ] **Table name format**:
  - DIM: `dim_<domain>_<entity>_df`
  - DWD: `dwd_<domain>_<entity>_di` (increment) or `_df` (cumulative snapshot)
  - DWS: `dws_<domain>_<entity>_<grain>_1d/nd/td`
  - ADS: `ads_{mart}_{topic}_{custom}_{period}`
- [ ] **Domain abbreviations**: DIM/DWD/DWS must use `trd`/`itm`/`wh`/`pay`/`usr`/`store`/`dist`/`comm`, never ODS source prefixes
- [ ] **Suffix matches ETL pattern**: `_df` must accompany FULL OUTER JOIN with yesterday snapshot; `_di` only today increment; `_1d` daily rebuild
- [ ] **Partition field**: Must be `ds STRING COMMENT '分区日期 yyyyMMdd'`
- [ ] **Word root correctness**:
  - Metric suffix: `{subject}_{modifier}_{measure}` structure
  - `amt` for amounts, `fee` for fees/costs — never mix
  - `cnt` for counts, `no`/`id` for identifiers, `pct`/`rate` for ratios
  - `_time` for datetime, `_date` for date
  - Boolean flags: `is_` prefix
- [ ] **High-frequency root violations**:
  - cancel → `cxl`, done → `cmpl`, wait → `pend`, content → `cnt`, record → `rcd`
  - paid → `payd`, refuse → `rjt`, freeze/lock → `frz`, token → `tkn`, region → `rgn`
  - title → `nm`, install → `inst`, exchange → `exch`, crash → `crsh`, extend → `xtn`
- [ ] **Enum format**: Codes use `_cd` suffix, state machines use `_stat` suffix
- [ ] **External isolation**: External entities use `out_` prefix
- [ ] **Cross-table consistency**: Same concept = same field name globally

### 2. Data Quality & Fallback (Zero-NULL)

- [ ] All numeric measures: `NVL(col, 0)`
- [ ] All join keys and output ID fields: `NVL(id, -99)` — NULL in join keys is a 🔴 Blocker
- [ ] String dimensions: `NVL(col, '未知')` or `'-99'` (never `''`)
- [ ] JSON/config: `NVL(col, '{}')`
- [ ] Boolean: `NVL(col, 0)` or `-1`
- [ ] Time types: can remain NULL
- [ ] ODS type casting: DECIMAL(38,18) → DECIMAL(18,4), TIMESTAMP → DATETIME. Missing CAST is 🔴 Blocker.

### 3. Architecture & Performance

- [ ] **Anti-Cartesian**: 1:N joins use `ROW_NUMBER() rn=1` or aggregate convergence
- [ ] **Role-playing dimensions**: Same dim table joined twice uses different aliases + role prefixes
- [ ] **Layer chain**: DWS reads DWD (not ODS). DWD single granularity. Cleaning logic only in DWD.
- [ ] **Fact table type**: Suffix matches ETL pattern

### 4. Metrics Governance

- [ ] All measure fields registered in `data_model/数据指标/原子指标.md`
- [ ] Same metric abbreviation = same logic, precision, unit, dedup flag across all tables
- [ ] Derived metrics registered in `data_model/数据指标/派生指标.md`

### 5. Production SQL

- [ ] Write uses `INSERT OVERWRITE TABLE ... PARTITION(ds='${bizdate}')`. `INSERT INTO` is 🔴 Blocker.
- [ ] Time filtering uses `TO_DATE` + `DATEADD`, not `SUBSTR` or `LIKE`
- [ ] DDL-ETL field alignment: every DDL field has matching AS alias in ETL
- [ ] `LIFECYCLE 365` (or 366) present

## Workflow

1. **Review Conclusion**: Pass / Modify / Reject with reason
2. **Code Health Report**, organized by severity:
   - 🔴 **Blocker**: Data skew, inflation, non-idempotency, syntax errors
   - 🟠 **Warning**: Missing NVL, wrong word roots, naming non-compliant
   - 🟡 **Suggestion**: Logic simplification, readability, comments
3. **Refactored Code**: Output modified, fully compliant production-level DDL or ETL with change comments

## Output Format

```markdown
### 📝 审查结论：[conclusion] - [reason]

### 🩺 代码健康度体检报告
#### 🔴 致命缺陷 (Blocker)
1. **Issue type**: Description.

#### 🟠 规范警告 (Warning)
1. **Issue type**: Description.

#### 🟡 优化建议 (Suggestion)
1. **Suggestion type**: Description.

### 🛠️ 重构后的标准代码 (Refactored)
```

Be extremely strict. Every checklist item must be verified systematically.
