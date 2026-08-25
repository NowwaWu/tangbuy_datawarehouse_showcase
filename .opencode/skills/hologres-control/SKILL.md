# Skill: hologres-control

# Hologres Data Operations via PostgreSQL Protocol

Execute queries and manage data in the Demo Cross-border Commerce Hologres instance. Uses psycopg2 with AK/SK as PostgreSQL credentials.

## Instance Info

| Config | Value |
|--------|-------|
| Instance ID | `hgprecn-cn-rp63viyr9002` |
| Instance Name | `prod-tangbuy-us-hologres` |
| Host (Internet) | `your-instance.hologres.aliyuncs.com` |
| Port | `3560` |
| Database | `tang_data_warehouse` |
| SSL | Disabled |
| Version | `r2.2.24` |
| Auth | AK/SK via environment variables |

## Publishing Policy

- **Read operations** (SELECT, DESCRIBE, COUNT, list-tables, list-schemas): always safe, execute immediately.
- **Write operations** (INSERT, UPDATE, DELETE, DDL): require explicit `--yes` flag or verbal confirmation from the user.
- Default row limit for queries: 100 rows (configurable via `--limit`).

## Core Script

```
pyshell/hologres_control.py
```

### CLI Usage

```bash
# List all schemas
python3 pyshell/hologres_control.py list-schemas

# List tables in a schema
python3 pyshell/hologres_control.py list-tables --schema dwd

# Describe a table's columns
python3 pyshell/hologres_control.py describe --table dwd.td_ds_order_stream

# Count rows
python3 pyshell/hologres_control.py count --table dwd.td_ds_order_stream

# Execute SELECT query
python3 pyshell/hologres_control.py query "SELECT * FROM dwd.td_ds_order_stream" --limit 10

# Execute write SQL (requires --yes)
python3 pyshell/hologres_control.py exec "INSERT INTO tmp.test VALUES (1)" --yes
python3 pyshell/hologres_control.py exec "DELETE FROM tmp.test WHERE id=1" --yes
```

### Programmatic Usage

```python
from pyshell.hologres_control import HologresClient, HologresConfig, load_credentials

cfg = load_credentials()
client = HologresClient(cfg)

# Schema exploration
schemas = client.list_schemas()
tables = client.list_tables('dwd')
columns = client.get_table_schema('dwd.td_ds_order_stream')
count = client.get_row_count('dwd', 'td_ds_order_stream')

# Read query
result = client.execute_query("SELECT * FROM dwd.td_ds_order_stream", limit=10)
print(result['columns'], result['rows'])

# Write operations
client.execute_write("INSERT INTO tmp.test (id, name) VALUES (1, 'test')")
client.execute_write("UPDATE tmp.test SET name = 'updated' WHERE id = 1")
client.execute_write("DELETE FROM tmp.test WHERE id = 1")

# Convenience methods
client.select_all('dwd.td_ds_order_stream', columns='id, status', limit=10)
client.insert_row('tmp.test', {'id': 1, 'name': 'test'})
client.delete_rows('tmp.test', 'id = 1')
client.update_rows('tmp.test', {'name': 'new'}, 'id = 1')
```

## HologresClient API Reference

| Method | Description |
|--------|-------------|
| `list_schemas()` | List all schemas |
| `list_tables(schema)` | List tables in a schema |
| `get_table_schema(schema_table)` | Get column definitions |
| `get_row_count(schema, table)` | Get row count |
| `execute_query(sql, limit, params)` | Execute SELECT with row limit |
| `execute_write(sql)` | Execute DDL/DML (INSERT/UPDATE/DELETE) |
| `select_all(schema_table, columns, limit)` | Convenience SELECT * |
| `insert_row(schema_table, data)` | INSERT single row |
| `delete_rows(schema_table, condition)` | DELETE with WHERE |
| `update_rows(schema_table, updates, condition)` | UPDATE with SET/WHERE |

## Table Types

Hologres tables in this instance are either:
- **BASE TABLE** — Local Hologres storage, written by Flink streaming tasks
- **FOREIGN** — Foreign tables mapped from MaxCompute/ODPS

Flink tasks in the `prod-tangbuy-us-flink-01-default` namespace write to base tables (e.g., `dwd.td_ds_order_stream`, `dwd.ful_package_send_detail_stream`).

## Common Schemas

| Schema | Description |
|--------|-------------|
| `ods` | Raw operational data (foreign tables from MaxCompute) |
| `dwd` | Detail warehouse layer (Flink-written base tables + foreign tables) |
| `dws` | Summary warehouse layer |
| `ads` | Application data service layer |
| `dim` | Dimension tables |
| `mid` | Middle layer / intermediate calculations |
| `tmp` | Temporary tables |
| `public` | Default schema |

## Notes

- Hologres is PostgreSQL 11 compatible. Standard PostgreSQL SQL syntax applies.
- Foreign tables (MaxCompute-mapped) are read-only; writes only affect BASE TABLE types.
- The instance is PrePaid (subscription), region us-west-1.
- No SSL required for connection.
