# TangBuy Data Warehouse Showcase

这是 `tangbuy_datawarehouse` 在提交 `8c21491ddb09` 基础上生成的**等结构脱敏展示版**。

本仓库保留原项目的数据域目录、DDL/ETL 配对、Python 控制脚本、OneData 建模资料及数仓研发 skills；只对凭据、云资源标识、环境项目名、个人路径和可识别示例值做脱敏。

## 核心目录

```text
ETL/                 # 按数据域组织的 DDL、ETL SQL 与 PyODPS 节点
data_model/          # OneData 标准、数仓规划与指标体系
table/               # 匿名化后的 ODS Schema
pyshell/             # 本地分析、同步和平台控制脚本
.opencode/skills/    # 数仓研发专用 skills
reports/             # 已脱敏的项目过程记录
```

## 安全边界

- 不包含硬编码 AK/SK、Token、Webhook 或服务账号私钥。
- 云端项目、Workspace、Host 和数据库名通过环境变量传入。
- `demo_dw`、`example.invalid`、`example.com` 与 `203.0.113.0/24` 均为公开展示占位符。
- 本仓库不会复制原仓库 Git 历史，避免历史提交中的敏感值进入公开仓库。

脱敏范围与验证结果见 [docs/SANITIZATION_REPORT.md](docs/SANITIZATION_REPORT.md)。
