# TangBuyDataWarehouseShowcase 项目知识库

**生成时间:** 2026-05-26  
**当前分支:** master  
**当前提交:** 8396317

## 项目概览

本仓库服务于 Demo Cross-border Commerce 数仓建设，核心方法论采用 Alibaba OneData V3.2，运行环境以 MaxCompute/ODPS 与 DataWorks 为主。

本次 `init-deep` 只维护 `AGENTS.md` 体系。不要顺手修改无关 SQL、Python、opencode 配置或业务文件。

## 协作语言

除 SQL、MaxCompute/ODPS、DataWorks、ETL、OneData、字段名、表名、路径、命令等专业名词外，项目协作、解释和文档默认优先使用中文。

如果需求不清，先提出一个必要问题，不要扩大范围或代替用户决定业务口径。

## 目录结构

```text
TangBuyDataWarehouseShowcase/
├── ETL/                 # DDL、ETL SQL、PyODPS 节点，按数据域组织
├── data_model/          # OneData 标准、数仓规划、指标体系
├── table/               # ODS 源表 JSON schema
├── pyshell/             # 本地分析、同步、生成、MaxCompute 辅助脚本
└── .opencode/skills/    # 数仓研发专用 skills
```

## 去哪里看

| 任务 | 首选位置 | 备注 |
|------|----------|------|
| 建模、建表、ETL 设计 | `AGENTS.md`、`data_model/`、`ETL/` | 先查本文件和标准，再找同域同层案例 |
| 字段命名 | `data_model/数据标准/命名词典.md` | 字段词根唯一权威来源 |
| 数据域和业务过程 | `data_model/数仓规划/数据域.md`、`业务过程.md` | 决定表名域段和业务过程段 |
| 时间周期后缀 | `AGENTS.md`、`data_model/数据指标/时间周期.md` | `_di/_df/_td/_1d/_nd` 以本文件为准 |
| 指标口径 | `data_model/数据指标/` | 原子指标、修饰词、派生指标、复合指标 |
| 业务取数路径 | `data_model/数仓规划/业务取数映射.md` | 业务问题到表字段的速查入口 |
| DataWorks/部署 | `dw-platform-deploy` skill、`pyshell/sync_cloud_etl_ddl.py` | 部署有外部副作用，需明确授权 |
| SELECT 取数 | `odps-query-sql-writer` skill | 只处理 SELECT/WITH 查询 |

## 核心约定

数仓分层使用 DIM、DWD、DWS、ADS。所有分区字段统一为 `ds`，类型为 STRING，格式为 `yyyyMMdd`。

| 层级 | 表名格式 | 分区字段 |
|------|----------|----------|
| DIM | `dim_<数据域>_<实体>_{存储策略}` | `ds` STRING yyyyMMdd |
| DWD | `dwd_<数据域>_<业务过程>_<实体>_{存储策略}` | `ds` STRING yyyyMMdd |
| DWS | `dws_<数据域>_<实体和粒度>_{时间周期后缀}` | `ds` STRING yyyyMMdd |
| ADS | `ads_<数据集市>_<主题域>_<自定义内容>_{时间周期后缀}` | `ds` STRING yyyyMMdd |

数据域缩写只使用 `trd`、`itm`、`wh`、`pay`、`usr`、`store`、`dist`、`comm`。

表名只描述实体身份，不描述计算方法。DWD 保持单粒度，主单、子单、明细不要混在一张表。

写入分区必须使用 `INSERT OVERWRITE TABLE ... PARTITION(ds='${bizdate}')`，保持幂等。

日期过滤优先使用 `TO_DATE('${bizdate}', 'yyyymmdd')` 与 `DATEADD`，不要用字符串比较表达业务日期范围。

DWS 不直接读取 ODS，必须经过 DWD。清洗、状态映射、词根转换等基础处理优先收口在 DWD。

字段词根必须参照 `data_model/数据标准/命名词典.md`。常用强约束如下：

| 不使用 | 使用 | 说明 |
|--------|------|------|
| `amount` | `amt` | 主体资金金额 |
| 资产金额写成 `fee` | `amt` / `fee` 区分 | 主体资金用 `amt`，附加费用用 `fee` |
| `count`、`num` | `cnt` | 次数、数量、件数 |
| `status` | `stat` | 状态 |
| `type` 直接作枚举 | `_cd` 后缀 | code 类枚举，如 `shop_type_cd` |
| `name` | `nm` | 名称 |
| `create` | `crt` | 创建 |
| `update` | `upd` | 更新 |
| `delete` | `del` | 删除 |
| `goods` | `item` | 商品全仓统一使用 `item` |
| `store` | `shop` | 店铺统一使用 `shop` |
| `user` | `usr` | 用户、操作人统一使用 `usr` |
| `splt` 表达分摊 | `alloc` | `splt` 只用于拆分 split，不用于分摊 allocation |
| `splt_` 过程前缀 | 不加过程前缀 | 表名已表达语义，如 `tot_pre_amt` |

布尔字段使用 `is_` 前缀，1 表示是或开启，0 表示否或关闭。

订单类编号使用 `no`，如 `ord_no`、`ord_line_no`；其他标识使用 `id`。

度量字段遵循 `{主体}_{修饰词}_{度量}`，例如 `tot_pre_amt`，不要写成 `tot_amt_pre`。

STRING 类型的枚举字段，枚举值必须统一使用大写字母。例如 `'ACTIVE'`、`'PENDING'` 而非 `'active'`、`'Pending'`。

常用词根速查：`crt` 创建、`upd` 更新、`del` 删除、`xtra` 补款/额外、`cmsn` 佣金/返利、`srv_fee` 服务费、`dev` 设备、`acty` 活动、`last` 最后/上次、`asgn` 分配、`dflt` 默认、`alloc` 分摊、`rtn` 退货、`cxl` 取消、`exch` 换货、`frz` 冻结、`rjt` 拒绝、`tkn` 令牌、`inst` 安装、`rgn` 地区。

## 时间周期后缀

| 后缀 | 含义 | 适用场景 |
|------|------|----------|
| `_di` | 日增量，只追加不修改 | 事务事实表，当日新发生事件 |
| `_df` | 日全量/累积快照，包含全部历史最新状态 | 当日增量 FULL OUTER JOIN 昨日快照 |
| `_1d` | 最近 1 天增量 | 只算当日新数据，底层源表当日分区仅含当天 |
| `_td` | 历史截至当天，全量 | 底层 DWD 为 `_df`，DWS/ADS 每日从全量分区重算 |
| `_nd` | 最近 N 天 | 滑动窗口汇总 |

判断 `_1d` 还是 `_td` 时看底层源表分区：当日分区是全部历史用 `_td`，当日分区仅当天用 `_1d`。

## Zero-NULL

| 类型 | 默认值 |
|------|--------|
| 金额、费用、数量、次数、价格、重量、比例 | `0` |
| JSON 字段 | `'{}'` |
| 布尔标记 | `0` |
| 状态枚举 | `-1` |
| 时间字段 | 保留 NULL |

如果文件内已有更新后的 NULL 策略，以当前业务取数映射和表级实现为准，不要机械批量改写旧逻辑。

## 明确禁止

不要在表名中使用 `_splt`、`_calc`、`_sum` 等计算过程词根。

不要把 `_1d` 用于全量快照或历史截至当天口径；读取 `_df` 全量分区重算时应使用 `_td`。

不要在 DWD/DWS/DIM/ADS 表名中使用 ODS 源系统前缀，如 `product`、`plugin`、`storage`、`cps`。

不要绕过 `data_model/数据标准/命名词典.md` 自造字段词根。

不要在 DWS 或 ADS 重复写本应在 DWD 收口的清洗逻辑。

不要在代码、配置或文档中新增硬编码 AK/SK、token、private key。已有暴露凭据属于高风险遗留问题，处理前先确认授权和轮换方案。

## Skills 路由

建模、DDL、ETL 设计使用 `dw-architect`。

DDL/ETL 审查使用 `dw-code-reviewer`。

DataWorks 节点同步、MaxCompute 建表或部署使用 `dw-platform-deploy`。

数据质量规则使用 `dw-data-quality`。

业务指标需求拆解使用 `ba-requirement-router`。

QuickBI 看板规划使用 `bi-analyst`。

SELECT/WITH 查询写作使用 `odps-query-sql-writer`。

日报、周报和项目进展总结使用 `daily-report`。

Flink 实时计算任务控制使用 `flink-control`。

Hologres 数据读写操作使用 `hologres-control`。

## 验证方式

本仓库没有自动化测试、CI、SQL lint 或统一依赖管理。验证依赖人工和 skill gate。

SQL 变更至少检查：表名、字段词根、分区、层级链路、Zero-NULL、日期过滤、ODS 类型转换、JOIN 防膨胀。

ODS 类型转换至少检查：`DECIMAL(38,18)` 金额类字段进入仓内时转 `DECIMAL(18,4)`；ODS `TIMESTAMP` 字段进入仓内时转 `DATETIME`。

Python 脚本变更先确认是否会写文件、调用外部 API、访问 MaxCompute 或覆盖本地 ETL；能 dry-run 时先 dry-run。

部署或云端写入有外部副作用，必须获得明确授权后再执行。

## 脏工作区

仓库可能长期存在用户或其他 agent 的未提交改动。开始修改前确认目标文件当前内容，只改本任务范围内的文件。

不要回滚、覆盖、格式化或顺手修复与当前任务无关的 SQL、Python、`.opencode`、配置或文档。
