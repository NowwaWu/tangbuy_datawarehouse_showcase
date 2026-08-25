---
name: odps-query-sql-writer
description: 专门编写、改写和解释 ODPS/MaxCompute 查询 SQL 的 skill，只处理 SELECT/WITH 型取数、临时分析、指标查询和查询口径排查。凡是用户说“帮我取数”“查一下”“写个查询 SQL”“这个指标怎么算”“按天/按用户/按店铺统计”“改一下这段 SELECT”时都应优先使用本 skill。禁止用于 DDL、建表、INSERT OVERWRITE、DataWorks 调度 ETL、部署或数仓建模；这些写表相关任务应交给 dw-architect、dw-code-reviewer 或 dw-platform-deploy。
---

# ODPS Query SQL Writer

你负责产出可直接运行的 ODPS/MaxCompute 查询 SQL，不需要写到任何文件中，直接输出到用户对话框中。默认使用中文沟通，SQL 只写 `WITH ... SELECT ...` 或单条 `SELECT`，不生成建表、写表、调度或部署内容。

## 边界

使用本 skill 处理：

- 临时取数、运营分析、指标查询、排查口径。
- 改写已有 `SELECT` 查询，让它更清晰、更省资源、更符合项目命名。
- 解释查询口径、字段含义、分区选择和聚合粒度。

禁止用本 skill 处理：

- `CREATE TABLE`、DDL、表结构设计、字段注释设计。
- `INSERT OVERWRITE`、`INSERT INTO`、DataWorks 调度 ETL。
- DWD/DWS/ADS 新表建模、事实表类型判断、上线部署。
- DDL/ETL 生产代码审查。
- 创建、修改或保存本地 `.sql`、`.md` 等文件；查询 SQL 只直接输出到对话框。

遇到写表或建模需求时，停止生成查询 SQL，改用对应的数仓建模、代码审查或平台部署 skill。

## 查询前先定口径

写 SQL 前先明确四件事：

- 统计对象：用户、订单、子单、店铺、商品、包裹或推广者。
- 统计粒度：按天、按月、按用户、按店铺、按订单、还是总览单行。
- 时间范围：固定日期、最近 N 天、从某日起、当月、历史截至当天。
- 分区口径：指定 `ds`，还是读取最新分区。

如果用户没有给完整背景，按最简单、最可执行的查询口径写；只有口径选择会明显改变结果时，才按照当前已有的背景，根据设计树依次拷问用户，直到背景信息完整。不要额外加用户没要求的维度或指标。

## 资产与命名

需要判断字段别名、指标词根或数据域时，按需读取：

- `data_model/数据标准/命名词典.md`：字段词根与缩写来源。
- `data_model/数仓规划/数据域.md`：数据域和业务边界。
- `data_model/数据指标/时间周期.md`：时间周期含义。
- `data_model/数据指标/业务取数映射.md`：指标与业务取数的映射关系，保存之前业务查询的沉淀，需要查询的指标可以现在这里找。

查询输出字段也要遵守项目词根。

所有实体表引用都必须带项目名前缀 `demo_dw.`，包括 `FROM`、`JOIN` 和 `MAX_PT` 参数；CTE 临时名不加 `demo_dw.`。不带项目前缀会导致本项目环境读取不到表。

## WITH/CTE 写法

需要多个中间步骤时，把中间逻辑拆成独立 `WITH` 片段，不在 `FROM` 或 `JOIN` 中写内联子查询。CTE 的目标是让查询可读、可拆、可单独调试，但不要为了“显得规范”制造一次性源表提取 CTE；只被使用一次的表可以直接在聚合或业务 CTE 中 `FROM demo_dw.xxx` 后完成字段选择、过滤和聚合。单表查询不要为了统一格式硬写 `a` 这类无意义别名，也不要把所有字段都机械写成 `a.field`。
![alt text](image.png)
多个 CTE 属于不同业务分类时，才使用三行横线块注释，并且只写在这一组的第一个 CTE 上方。例如 A/B/C 都用于产出“注册用户口径”，D/E 用于产出“店铺绑定口径”，就在 A 和 D 前分别写组注释。多个 CTE 共同服务同一个目标时，只在最上方写一次块注释；中间每个 CTE 上方必须写一行职责注释，例如 `-- 统计注册用户数`、`-- 按店铺统计三方商品推荐与关联情况`。首个 CTE 的注释必须写在 `WITH` 关键字上方，不要写在 `WITH` 下一行，避免 ODPS 格式化后变成 `WITH -- 注释内容`。所有 CTE 名必须以 `with_` 开头，用来和实体表名区分；`with_` 后面继续表达职责，例如 `with_reg_usr`、`with_ord_pay`。

同一个表如果会被多个后续 CTE 使用，才先写源表提取 CTE：只选择后续需要的字段，先完成分区过滤、时间过滤、类型转换和基础清洗，再让后续 CTE 复用。这样方便排查字段与过滤条件，也减少重复读表和重复写过滤条件的风险。

每个 CTE 只做一件事：源表裁剪、去重、防膨胀聚合、业务过滤、指标计算、最终整形分开写。复杂或复用链路可以按 `with_source -> with_clean -> with_agg -> with_final` 组织；简单一次性查询允许直接 `WITH with_agg AS (...)` 或单条 `SELECT`，不要机械套多层 CTE。

注释要服务读者理解口径，不是装饰。凡是出现去重、防膨胀、状态枚举、日期窗口、指标口径、主从表关系时，都要写一行简短注释说明“为什么这么算”；不要给 `ds = '${bizdate}'`、`is_del = 0` 这类显而易见的过滤逐行注释。

开发和排错时，可以临时在任意 CTE 后插入：

```sql
SELECT  *
FROM    with_cte_name
LIMIT   100
;
```

只运行到该 CTE 检查中间结果，确认后删除临时 SELECT。

## 分区与日期

即席查询最新全量快照时，优先使用：

```sql
WHERE   ds = MAX_PT('demo_dw.table_name')
```

`MAX_PT` 返回有数据的一级最大分区，适合日分区全量快照的最新分区查询；多级分区、空分区表、或用户指定业务日期时不要滥用，改用明确分区条件。

用户指定业务日期时，使用明确日期或参数，不要混用最新分区：

```sql
WHERE   ds = '20260521'
```

即席查询里，用户给的是 `yyyymmdd` 日期或业务上按天比较时，日期过滤优先把日期字段转成 `yyyymmdd` 字符串后和字面量比较。这样更贴近业务人员阅读习惯，也避免把一个直观的 `20260401` 写成多层日期函数：

```sql
TO_CHAR(crt_time, 'yyyymmdd') >= '20260501'
TO_CHAR(crt_time, 'yyyymmdd') AS stat_date
```

只有在需要小时/分钟精度、半开区间防止边界重复、或需要用 `${bizdate}` 动态推算月初/次日/次月时，才使用 `TO_DATE`、`DATEADD` 等日期函数。

按天统计时，统一输出 `stat_date`，格式为 `yyyymmdd`。

## 条件表达式

简单二分条件优先使用 `IF(condition, true_value, false_value)`，不要写成 `CASE WHEN condition THEN true_value ELSE false_value END`。只有条件分支较多、需要多个 `WHEN`、或 `CASE WHEN` 明显更易读时，才使用 `CASE WHEN`。

## 聚合与 Join

一对多关系先聚合到目标粒度，再 join，避免重复计数。用户数、店铺数、订单数等去重指标使用 `COUNT(DISTINCT ...)`，去重对象必须与业务实体一致。

单表查询默认不写表别名，直接写字段名，让 SQL 更干净。只有出现 `JOIN`、自连接、同一张表重复引用、或字段名会歧义时才使用表别名。

凡出现 `JOIN`，表别名统一按连接顺序使用 `a`、`b`、`c`、`d`：主表是 `a`，第二张表是 `b`，第三张表是 `c`，依次类推。不要使用语义别名、拼音别名或 `t1`/`t2`。JOIN 查询中的字段必须带别名，避免同名字段歧义；没有 JOIN 的单表查询不要为了“看起来规范”给字段加 `a.` 前缀。

跨平台店铺去重时，用平台类型和店铺 ID 组成复合键：

```sql
COUNT(DISTINCT CONCAT(NVL(shop_type_cd, '未知'), '_', CAST(shop_id AS STRING))) AS plugin_bind_shop_cnt
```

多个独立指标按日期或实体合并时，可使用 `FULL OUTER JOIN` 补齐日期，并用 `COALESCE` 延续连接键：

```sql
FROM    with_metric_a a
FULL OUTER JOIN with_metric_b b
ON      a.stat_date = b.stat_date
FULL OUTER JOIN with_metric_c c
ON      COALESCE(a.stat_date, b.stat_date) = c.stat_date
```

如果存在一个清晰主口径，例如“注册用户及其下单情况”，优先以主口径 CTE 为主表 `LEFT JOIN` 其他指标，不要为了补齐无关实体滥用 `FULL OUTER JOIN`。

## 查询模板

```sql
-- 统计注册用户数
WITH
with_reg_usr AS
(
    SELECT  TO_CHAR(crt_time, 'yyyymmdd') AS stat_date
            ,COUNT(DISTINCT usr_id) AS reg_usr_cnt
    FROM    demo_dw.dim_usr_info_df
    WHERE   ds = MAX_PT('demo_dw.dim_usr_info_df')
    AND     usr_stat = 1
    AND     is_del = 0
    AND     TO_CHAR(crt_time, 'yyyymmdd') >= '20260501'
    GROUP BY TO_CHAR(crt_time, 'yyyymmdd')
)

SELECT  stat_date
        ,NVL(reg_usr_cnt, 0) AS reg_usr_cnt
FROM    with_reg_usr
ORDER BY stat_date
;
```

## 输出格式

用户要 SQL 时，直接在对话框输出可复制执行的 SQL，不要写入任何文件，也不要告诉用户已保存到文件。先给 SQL，再用一小段中文说明口径和关键假设。用户要改 SQL 时，先给修正版 SQL，再说明改了哪些口径或性能点。不要输出 DDL、`INSERT OVERWRITE` 或部署步骤。

## 自检

交付前检查：

- 是否只有查询语句，没有 DDL/DML 写表语句。
- 是否直接在对话框输出 SQL，没有创建、修改或保存任何文件。
- 是否有明确分区过滤，最新分区和指定日期没有混用。
- 是否避免 `SELECT *`，只选需要字段。
- 实体表是否都带 `demo_dw.` 前缀，尤其是 `FROM`、`JOIN` 和 `MAX_PT`。
- 单表查询是否避免无意义表别名和 `a.` 字段前缀。
- 是否只把重复使用的源表抽成源表 CTE，避免为单次使用表拆无意义提取 CTE。
- 是否避免内联子查询，中间逻辑可单独调试。
- 所有 CTE 名是否都以 `with_` 开头，避免和实体表名混淆。
- 首个 CTE 的注释是否写在 `WITH` 上方，避免 ODPS 格式化成 `WITH -- 注释内容`。
- 每个 CTE 是否至少有一行职责注释，复杂逻辑是否说明了去重、防膨胀、状态枚举、日期窗口或指标口径。
- 多 CTE 注释是否只在业务分组起点使用横线块注释，组内 CTE 只用一行职责注释。
- 日期字段按天比较时是否优先使用 `TO_CHAR(date_col, 'yyyymmdd')` 与 `yyyymmdd` 字符串比较；只有精度或边界需要时才使用日期函数。
- 简单二分条件是否优先使用 `IF`，只有多分支或更清晰时才使用 `CASE WHEN`。
- 聚合粒度是否清楚，JOIN 后是否会重复计数。
- JOIN 别名是否按 `a`/`b`/`c`/`d` 顺序使用，JOIN 字段是否带别名。
- 输出字段别名是否符合项目词根。
- 最终结果是否只包含用户请求的字段和指标。
