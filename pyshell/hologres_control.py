#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Hologres data operations via PostgreSQL wire protocol.

Hologres is PostgreSQL-compatible. Uses psycopg2 with AK/SK as credentials.
Default behavior: read-only (SELECT, DESCRIBE). Write operations require
explicit --yes confirmation.

Environment constants (hardcoded, do not guess):
    Hologres Host:  set via HOLOGRES_HOST
    Port:           3560
    Database:       tang_data_warehouse

Credentials: ALIBABA_CLOUD_ACCESS_KEY_ID / ALIBABA_CLOUD_ACCESS_KEY_SECRET
"""

import argparse
import json
import os
import sys
from contextlib import contextmanager
from dataclasses import dataclass
from typing import Any, Dict, List, Optional

import psycopg2
import psycopg2.extras


# ── Constants ──────────────────────────────────────────────────────────────

DEFAULT_HOST = os.getenv('HOLOGRES_HOST', '')
DEFAULT_PORT = 3560
DEFAULT_DATABASE = os.getenv('HOLOGRES_DATABASE', 'demo_dw')
WRITE_KEYWORDS = {"INSERT", "UPDATE", "DELETE", "CREATE", "DROP", "ALTER",
                   "TRUNCATE", "GRANT", "REVOKE", "COPY", "VACUUM"}
READ_ROW_LIMIT = 100


# ── Helpers ────────────────────────────────────────────────────────────────

def _print_table(columns: List[str], rows: List[tuple]) -> None:
    """Print results as a formatted table."""
    if not rows:
        print("(no rows)")
        return

    # Calculate column widths
    widths = [len(c) for c in columns]
    for row in rows:
        for i, val in enumerate(row):
            widths[i] = max(widths[i], len(str(val)))

    # Print header
    header = " | ".join(c.ljust(w) for c, w in zip(columns, widths))
    sep = "-+-".join("-" * w for w in widths)
    print(f"\n{header}")
    print(sep)

    # Print rows
    for row in rows:
        line = " | ".join(str(v).ljust(w) for v, w in zip(row, widths))
        print(line)

    print(f"\n({len(rows)} row(s))")


def _is_write_sql(sql: str) -> bool:
    """Check if a SQL statement is a write operation."""
    upper = sql.strip().upper()
    first_word = upper.split()[0] if upper.split() else ""
    return first_word in WRITE_KEYWORDS


# ── Client ─────────────────────────────────────────────────────────────────

@dataclass
class HologresConfig:
    access_id: str
    access_key: str
    host: str = DEFAULT_HOST
    port: int = DEFAULT_PORT
    database: str = DEFAULT_DATABASE


class HologresClient:
    """Hologres PostgreSQL client with AK/SK authentication."""

    def __init__(self, cfg: HologresConfig):
        self._cfg = cfg

    @contextmanager
    def _cursor(self, autocommit: bool = False):
        """Context manager for database connection + cursor."""
        conn = psycopg2.connect(
            host=self._cfg.host,
            port=self._cfg.port,
            database=self._cfg.database,
            user=self._cfg.access_id,
            password=self._cfg.access_key,
            connect_timeout=15,
        )
        conn.autocommit = autocommit
        try:
            cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
            try:
                yield cur
            finally:
                cur.close()
        finally:
            conn.close()

    # ── Schema exploration ────────────────────────────────────────────

    def list_schemas(self) -> List[str]:
        """List all schemas."""
        with self._cursor() as cur:
            cur.execute(
                "SELECT schema_name FROM information_schema.schemata "
                "ORDER BY schema_name"
            )
            return [r["schema_name"] for r in cur.fetchall()]

    def list_tables(self, schema: str = "public") -> List[Dict]:
        """List all tables in a schema."""
        with self._cursor() as cur:
            cur.execute(
                "SELECT table_name, table_type "
                "FROM information_schema.tables "
                "WHERE table_schema = %s "
                "ORDER BY table_name",
                (schema,),
            )
            return cur.fetchall()

    def describe_table(self, schema: str, table: str) -> List[Dict]:
        """Get column definitions for a table."""
        with self._cursor() as cur:
            cur.execute(
                "SELECT column_name, data_type, is_nullable, column_default "
                "FROM information_schema.columns "
                "WHERE table_schema = %s AND table_name = %s "
                "ORDER BY ordinal_position",
                (schema, table),
            )
            return cur.fetchall()

    def get_table_schema(self, schema_table: str) -> List[Dict]:
        """Get column definitions. Format: schema.table or table."""
        parts = schema_table.split(".", 1)
        if len(parts) == 2:
            return self.describe_table(parts[0], parts[1])
        return self.describe_table("public", parts[0])

    def get_row_count(self, schema: str, table: str) -> int:
        """Get approximate row count for a table."""
        with self._cursor() as cur:
            cur.execute(
                f"SELECT COUNT(*) AS cnt FROM {self._quote(schema, table)}"
            )
            return cur.fetchone()["cnt"]

    # ── Query execution ────────────────────────────────────────────────

    def execute_query(
        self,
        sql: str,
        limit: int = READ_ROW_LIMIT,
        params: Optional[tuple] = None,
    ) -> Dict:
        """Execute a read-only SQL query and return results.

        Returns dict with keys: columns, rows, row_count, truncated.
        Write SQL is rejected unless allow_write=True.
        """
        if _is_write_sql(sql):
            raise ValueError(
                f"Write SQL detected: '{sql[:60]}...'. "
                "Use execute_write() for DDL/DML operations."
            )

        with self._cursor() as cur:
            cur.execute(f"{sql.rstrip(';')} LIMIT {limit + 1}", params)
            columns = [desc[0] for desc in cur.description] if cur.description else []
            rows = [tuple(row) for row in cur.fetchall()]
            truncated = len(rows) > limit
            if truncated:
                rows = rows[:limit]

        return {
            "columns": columns,
            "rows": rows,
            "row_count": len(rows),
            "truncated": truncated,
        }

    def execute_write(self, sql: str) -> str:
        """Execute a write (DDL/DML) SQL statement.

        Returns a status message.
        """
        if not _is_write_sql(sql):
            raise ValueError(
                f"Not a write SQL: '{sql[:60]}...'. "
                "Use execute_query() for SELECT statements."
            )

        with self._cursor(autocommit=True) as cur:
            cur.execute(sql)
            status = cur.statusmessage
        return status

    # ── Convenience methods ────────────────────────────────────────────

    def select_all(self, schema_table: str, columns: str = "*", limit: int = READ_ROW_LIMIT) -> Dict:
        """SELECT * FROM schema.table."""
        sql = f"SELECT {columns} FROM {self._quote_identifier(schema_table)}"
        return self.execute_query(sql, limit=limit)

    def insert_row(self, schema_table: str, data: Dict[str, Any]) -> str:
        """INSERT INTO schema.table (cols) VALUES (vals)."""
        cols = list(data.keys())
        placeholders = ", ".join(["%s"] * len(cols))
        vals = tuple(data.values())
        sql = (
            f"INSERT INTO {self._quote_identifier(schema_table)} "
            f"({', '.join(self._quote_col(c) for c in cols)}) "
            f"VALUES ({placeholders})"
        )
        return self.execute_write(sql)

    def delete_rows(self, schema_table: str, condition: str) -> str:
        """DELETE FROM schema.table WHERE condition."""
        sql = f"DELETE FROM {self._quote_identifier(schema_table)} WHERE {condition}"
        return self.execute_write(sql)

    def update_rows(self, schema_table: str, updates: Dict[str, Any], condition: str) -> str:
        """UPDATE schema.table SET col=val, ... WHERE condition."""
        set_clause = ", ".join(
            f"{self._quote_col(k)} = %s" for k in updates
        )
        # Use parameterized query
        vals = list(updates.values())
        sql = (
            f"UPDATE {self._quote_identifier(schema_table)} "
            f"SET {set_clause} WHERE {condition}"
        )
        with self._cursor(autocommit=True) as cur:
            cur.execute(sql, vals)
            status = cur.statusmessage
        return status

    # ── Utils ──────────────────────────────────────────────────────────

    @staticmethod
    def _quote(schema: str, table: str) -> str:
        return f'"{schema}"."{table}"'

    @staticmethod
    def _quote_identifier(schema_table: str) -> str:
        parts = schema_table.split(".", 1)
        if len(parts) == 2:
            return f'"{parts[0]}"."{parts[1]}"'
        return f'"public"."{parts[0]}"'

    @staticmethod
    def _quote_col(col: str) -> str:
        return f'"{col}"'


# ── Credential loading ─────────────────────────────────────────────────────

def load_credentials() -> HologresConfig:
    """Load credentials from environment."""
    access_id = os.getenv("ALIBABA_CLOUD_ACCESS_KEY_ID") or os.getenv("ODPS_ACCESS_ID")
    access_key = os.getenv("ALIBABA_CLOUD_ACCESS_KEY_SECRET") or os.getenv("ODPS_ACCESS_KEY")

    if not access_id or not access_key:
        opencode_cfg_path = os.path.join(
            os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
            "opencode.json",
        )
        if os.path.exists(opencode_cfg_path):
            with open(opencode_cfg_path, "r") as f:
                cfg = json.load(f)
            mcp_env = cfg.get("mcp", {}).get("maxcompute", {}).get("environment", {})
            access_id = access_id or mcp_env.get("ODPS_ACCESS_ID")
            access_key = access_key or mcp_env.get("ODPS_ACCESS_KEY")

    if not access_id or not access_key:
        raise RuntimeError(
            "Missing Alibaba Cloud credentials. Set ALIBABA_CLOUD_ACCESS_KEY_ID "
            "and ALIBABA_CLOUD_ACCESS_KEY_SECRET environment variables."
        )

    return HologresConfig(access_id=access_id, access_key=access_key)


# ── CLI ────────────────────────────────────────────────────────────────────

def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        description="Hologres data operations (PostgreSQL protocol)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # List schemas
  python3 pyshell/hologres_control.py list-schemas

  # List tables in a schema
  python3 pyshell/hologres_control.py list-tables --schema dwd

  # Describe a table
  python3 pyshell/hologres_control.py describe --table dwd.dwd_trd_ds_ord_line_df

  # Count rows
  python3 pyshell/hologres_control.py count --table dwd.dwd_trd_ds_ord_line_df

  # SELECT query (read-only)
  python3 pyshell/hologres_control.py query "SELECT * FROM dwd.dwd_trd_ds_ord_line_df"

  # Execute write SQL (requires --yes)
  python3 pyshell/hologres_control.py exec "INSERT INTO tmp.test VALUES (1)" --yes

  # Delete rows (requires --yes)
  python3 pyshell/hologres_control.py exec "DELETE FROM tmp.test WHERE id = 1" --yes
        """,
    )

    sub = p.add_subparsers(dest="command", help="Action to perform")

    # list-schemas
    sub.add_parser("list-schemas", help="List all schemas")

    # list-tables
    sp = sub.add_parser("list-tables", help="List tables in a schema")
    sp.add_argument("--schema", default="public", help="Schema name")

    # describe
    sp = sub.add_parser("describe", help="Describe table columns")
    sp.add_argument("--table", required=True, help="Table name (schema.table)")

    # count
    sp = sub.add_parser("count", help="Count rows in a table")
    sp.add_argument("--table", required=True, help="Table name (schema.table)")

    # query (read-only SELECT)
    sp = sub.add_parser("query", help="Execute SELECT query (read-only)")
    sp.add_argument("sql", help="SQL SELECT statement")
    sp.add_argument("--limit", type=int, default=READ_ROW_LIMIT, help="Max rows")

    # exec (write SQL)
    sp = sub.add_parser("exec", help="Execute write SQL (requires --yes)")
    sp.add_argument("sql", help="SQL statement (INSERT/UPDATE/DELETE/DDL)")
    sp.add_argument("--yes", action="store_true", help="Confirm write operation")

    return p


def main():
    parser = _build_parser()
    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        return

    cfg = load_credentials()
    client = HologresClient(cfg)

    if args.command == "list-schemas":
        schemas = client.list_schemas()
        print(f"\nSchemas ({len(schemas)}):")
        for s in schemas:
            print(f"  {s}")

    elif args.command == "list-tables":
        tables = client.list_tables(args.schema)
        print(f"\nTables in '{args.schema}' ({len(tables)}):")
        _print_table(
            ["Table", "Type"],
            [(t["table_name"], t["table_type"]) for t in tables],
        )

    elif args.command == "describe":
        cols = client.get_table_schema(args.table)
        print(f"\nTable: {args.table}")
        _print_table(
            ["Column", "Type", "Nullable", "Default"],
            [(c["column_name"], c["data_type"], c["is_nullable"], c.get("column_default", "-"))
             for c in cols],
        )

    elif args.command == "count":
        parts = args.table.split(".", 1)
        schema, table = (parts[0], parts[1]) if len(parts) == 2 else ("public", parts[0])
        cnt = client.get_row_count(schema, table)
        print(f"\n{table}: {cnt} rows")

    elif args.command == "query":
        result = client.execute_query(args.sql, limit=args.limit)
        _print_table(result["columns"], result["rows"])
        if result["truncated"]:
            print(f"(truncated to {args.limit} rows)")

    elif args.command == "exec":
        if not args.yes:
            print(
                f"⚠️  Write SQL detected.\n"
                f"   SQL: {args.sql[:120]}{'...' if len(args.sql) > 120 else ''}\n"
                f"   Re-run with --yes to execute."
            )
            sys.exit(1)
        status = client.execute_write(args.sql)
        print(f"✓ {status}")


if __name__ == "__main__":
    main()
