# ETL 本地规范

本文件只补充 `ETL/` 目录内的 DDL、ETL SQL、PyODPS 节点约定。全仓通用命名、分层、Zero-NULL 和 skill 路由继承根 `AGENTS.md`。

## 目录组织

`ETL/` 按数据域组织，而不是按 DIM/DWD/DWS/ADS 层级组织。判断层级必须看文件名前缀。

| 目录 | 职责 |
|------|------|
| `trd/` | 交易、订单、订单行、生命周期、包裹费用分摊 |
| `wh/` | 仓库、包裹、备货、库存预警 |
| `itm/` | 商品、类目、外部商品、商品关系 |
| `usr/` | 用户、行为事件、注册转化 |
| `store/` | 店铺、授权关系 |
| `pay/` | 支付渠道、汇率 |
| `dist/` | 分销、代理、佣金 |
| `comm/` | 字典、IP 地理信息等公共维表 |
| `ods/` | 少量自定义 ODS 加工节点，如 Firebase events |

## 文件配对

生产表通常成对维护 `表名.ddl.sql` 与 `表名.etl.sql`。

外部 API、推送、复杂控制流可以使用 `表名.etl.py`，当前主要是 Firebase、IP 地理信息、钉钉预警。

一次性初始化或历史回刷脚本可使用 `.init.etl.sql`，不要混入日常调度脚本。

DDL 文件只放建表结构、字段注释、分区定义。ETL 文件只放调度写入逻辑。

## 表后缀

`_di` 表示日增量，只写当天新增事件。

`_df` 表示日全量或累积快照，保留截至当天最新状态。

`_1d` 表示最近 1 天口径。

`_td` 表示历史截至当天全量口径，常见于 DWS/ADS 每日全量重算。

`_nd` 表示最近 N 天滑动窗口口径。

选择 `_1d` 还是 `_td` 时看底层源表分区：当日分区只含当天数据用 `_1d`；当日分区是全部历史最新状态，且下游每日全量重算时用 `_td`。

## 写入与分区

调度写表统一使用 `INSERT OVERWRITE TABLE ... PARTITION(ds='${bizdate}')`。

分区字段统一为 `ds`，类型为 STRING，格式为 `yyyyMMdd`。

不要使用 `INSERT INTO` 写生产分区表。

现有文件可能混用 `demo_dw.` 前缀和裸表名；新增代码优先跟随同域同层最近文件，不要无关批量统一。

## 分层约束

DWD 负责清洗、类型转换、状态归一和明细事实沉淀。

ODS `DECIMAL(38,18)` 金额类字段进入 DWD/DIM 前通常转为 `DECIMAL(18,4)`；比例、汇率类字段按业务精度确认。

ODS `TIMESTAMP` 字段进入仓内前通常转为 `DATETIME`。

DWD 必须单粒度。订单主单、订单行、包裹、操作事件要拆分表达。

DWS 读取 DWD、DIM 或其他合规汇总层，不得直接读取 ODS。

ADS 面向应用场景输出，不承接底层清洗逻辑。

ODS 源字段可以保留原名，例如 `goods_id`，但仓内输出字段必须标准化为 `item_*`。

## SQL 模板

DIM `_df` 常见模式是从 ODS `_ri` 全量分区直出，按 `ds='${bizdate}'` 覆盖。

DWD `_df` 常见模式是 `today_delta` FULL OUTER JOIN `yesterday`，用 `COALESCE(t.col, y.col)` 保留历史状态。

DWD `_di` 常见模式是按创建时间或事件时间筛选当天数据后覆盖当天分区。

DWS/ADS `_td` 常见模式是读取当日 DWD/DIM 全量分区，多 CTE 汇总后覆盖当天分区。

1:N JOIN 必须先 `ROW_NUMBER() rn = 1` 或预聚合，避免口径膨胀。

日期过滤使用 `TO_DATE('${bizdate}', 'yyyymmdd')` 与 `DATEADD`；月份截取等展示字段可有例外，但不要用字符串比较替代日期区间。

## PyODPS 节点

DataWorks PyODPS 节点中通常由平台注入 `o` 和 `args`。

PyODPS 节点应优先在 MaxCompute 侧执行 SQL 写表，不要把大表分区下载到本地内存循环处理。

外部 API 调用、Webhook 推送、BigQuery 同步等逻辑必须限制输入分区、字段和行数。

新增凭据必须来自 DataWorks 参数或环境变量，不要写入源码。

## 本地反模式

不要让 DWS 直接读 ODS。

不要在一个 DWD 表混合多个业务粒度。

不要把 `_1d` 表写成全量快照。

不要把 DWD/DWS/ADS 表名写成源系统名，如 `product_*`、`plugin_*`。

不要新增 `amount`、`count`、`status`、`name`、`goods` 等非标准仓内字段词根。

不要运行会批量覆盖 ETL 的脚本，除非任务明确要求并已确认脏工作区风险。
