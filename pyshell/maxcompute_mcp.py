import os
import re
from mcp.server.fastmcp import FastMCP
from odps import ODPS

mcp = FastMCP("MaxCompute Server")

ENDPOINT = os.getenv("ODPS_ENDPOINT")
PROJECT = os.getenv("ODPS_PROJECT")
ACCESS_ID = os.getenv("ODPS_ACCESS_ID")
ACCESS_KEY = os.getenv("ODPS_ACCESS_KEY")

_ODPS_CLIENT = None


def _mask(value: str | None) -> str:
    if not value:
        return "未配置"
    if len(value) <= 8:
        return "****"
    return f"{value[:4]}****{value[-4:]}"


def _missing_env_names() -> list[str]:
    required = {
        "ODPS_ENDPOINT": ENDPOINT,
        "ODPS_PROJECT": PROJECT,
        "ODPS_ACCESS_ID": ACCESS_ID,
        "ODPS_ACCESS_KEY": ACCESS_KEY,
    }
    return [name for name, value in required.items() if not value]


def _get_odps() -> ODPS:
    global _ODPS_CLIENT
    missing = _missing_env_names()
    if missing:
        raise RuntimeError(
            "ODPS 环境变量未配置完整: "
            + ", ".join(missing)
            + "。请检查 opencode.json 的 mcp.maxcompute.environment 或启动 opencode 的 shell 环境。"
        )
    if _ODPS_CLIENT is None:
        _ODPS_CLIENT = ODPS(ACCESS_ID, ACCESS_KEY, PROJECT, endpoint=ENDPOINT)
    return _ODPS_CLIENT


def _strip_trailing_semicolon(sql_query: str) -> str:
    return sql_query.strip().rstrip(";").strip()


def _first_keyword(sql_query: str) -> str:
    sql = sql_query.strip()
    while True:
        if sql.startswith("--"):
            newline_pos = sql.find("\n")
            if newline_pos == -1:
                return ""
            sql = sql[newline_pos + 1 :].lstrip()
            continue
        if sql.startswith("/*"):
            end_pos = sql.find("*/")
            if end_pos == -1:
                return ""
            sql = sql[end_pos + 2 :].lstrip()
            continue
        break
    match = re.match(r"([A-Za-z]+)", sql)
    return match.group(1).lower() if match else ""


def _validate_select_sql(sql_query: str) -> str | None:
    first_keyword = _first_keyword(sql_query)
    if first_keyword not in {"select", "with"}:
        return "预览工具只允许 SELECT/WITH 查询，不执行 DDL/DML。"

    blocked = re.search(
        r"\b(insert|create|drop|alter|truncate|delete|update|merge|grant|revoke)\b",
        sql_query,
        re.IGNORECASE,
    )
    if blocked:
        return f"预览工具拒绝执行包含 {blocked.group(1).upper()} 的 SQL。"
    return None


def _apply_preview_limit(sql_query: str, limit: int) -> str:
    sql = _strip_trailing_semicolon(sql_query)
    safe_limit = min(max(int(limit), 1), 200)
    if re.search(r"\blimit\s+\d+\s*$", sql, re.IGNORECASE):
        return sql
    return f"{sql}\nLIMIT {safe_limit}"


@mcp.tool()
def diagnose_connection() -> str:
    """诊断 MaxCompute MCP 的环境变量和基础连接状态。"""
    lines = [
        "MaxCompute MCP 诊断",
        f"ODPS_ENDPOINT: {ENDPOINT or '未配置'}",
        f"ODPS_PROJECT: {PROJECT or '未配置'}",
        f"ODPS_ACCESS_ID: {_mask(ACCESS_ID)}",
        f"ODPS_ACCESS_KEY: {_mask(ACCESS_KEY)}",
    ]
    missing = _missing_env_names()
    if missing:
        lines.append("状态: 配置不完整，缺少 " + ", ".join(missing))
        return "\n".join(lines)

    try:
        odps_client = _get_odps()
        next(odps_client.list_tables(), None)
        lines.append("状态: 已连接，基础 list_tables 测试通过")
    except Exception as e:
        lines.append(f"状态: 连接失败，{type(e).__name__}: {str(e)}")
    return "\n".join(lines)

@mcp.tool()
def list_tables(prefix: str = "", limit: int = 50) -> str:
    """列出 MaxCompute 中的表。如果提供 prefix，则只列出前缀匹配的表。"""
    try:
        odps_client = _get_odps()
        safe_limit = min(max(int(limit), 1), 200)
        table_names = []
        for table in odps_client.list_tables(prefix=prefix):
            table_names.append(table.name)
            if len(table_names) >= safe_limit:
                break
        if not table_names:
            return "未找到匹配表。"
        return f"找到表 (最多显示{safe_limit}张):\n" + "\n".join(table_names)
    except Exception as e:
        return f"列出表失败: {type(e).__name__}: {str(e)}"

@mcp.tool()
def get_table_schema(table_name: str) -> str:
    """获取指定 MaxCompute 表的字段规范(Schema)及注释，用于数仓梳理。"""
    try:
        odps_client = _get_odps()
        t = odps_client.get_table(table_name)
        schema_info = []
        for col in t.table_schema.columns:
            schema_info.append(f"字段名: {col.name}, 类型: {col.type}, 注释: {col.comment}")

        partition_info = []
        if t.table_schema.partitions:
            for p in t.table_schema.partitions:
                partition_info.append(f"分区字段: {p.name}, 类型: {p.type}, 注释: {p.comment}")

        result = f"表名: {table_name}\n"
        result += f"备注: {t.comment}\n\n[字段列表]\n" + "\n".join(schema_info)
        if partition_info:
            result += "\n\n[分区信息]\n" + "\n".join(partition_info)
        return result
    except Exception as e:
        return f"获取表结构失败: {type(e).__name__}: {str(e)}"

@mcp.tool()
def execute_sql_preview(sql_query: str, limit: int = 100) -> str:
    """执行 SELECT/WITH 型 MaxCompute SQL 并返回预览数据，默认最多100行。"""
    try:
        error = _validate_select_sql(sql_query)
        if error:
            return error

        odps_client = _get_odps()
        preview_sql = _apply_preview_limit(sql_query, limit)
        instance = odps_client.execute_sql(preview_sql)
        instance.wait_for_success()

        with instance.open_reader() as reader:
            df = reader.to_pandas()
            if df.empty:
                return "查询成功，无返回行。"
            return df.to_string(index=False, max_rows=200, max_cols=80)
    except Exception as e:
        return f"SQL执行失败: {type(e).__name__}: {str(e)}"

if __name__ == "__main__":
    mcp.run()
