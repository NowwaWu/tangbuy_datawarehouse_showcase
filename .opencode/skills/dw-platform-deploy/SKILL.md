---
name: dw-platform-deploy
description: Update local ETL SQL files to DataWorks node drafts and create/recreate tables in MaxCompute (ODPS). Use whenever the user mentions syncing ETL to DataWorks drafts, creating MaxCompute tables, executing DDL on ODPS, updating DataWorks node content, listing DataWorks nodes, getting node specs, or syncing local files to the Tang_Data_Warehouse project. Do not submit or publish DataWorks nodes unless the user explicitly asks for submit/publish/deploy.
env:
  - name: ALIBABA_CLOUD_ACCESS_KEY_ID
    description: Alibaba Cloud Access Key ID for DataWorks API
    required: true
  - name: ALIBABA_CLOUD_ACCESS_KEY_SECRET
    description: Alibaba Cloud Access Key Secret for DataWorks API
    required: true
  - name: ODPS_ACCESS_ID
    description: MaxCompute Access ID (falls back to ALIBABA_CLOUD_ACCESS_KEY_ID)
    required: false
  - name: ODPS_ACCESS_KEY
    description: MaxCompute Access Key (falls back to ALIBABA_CLOUD_ACCESS_KEY_SECRET)
    required: false
---

# DataWorks & MaxCompute Platform Draft Updates

Update local ETL SQL and DDL files to the Tang_Data_Warehouse project on Alibaba Cloud.

## Publishing Policy

Default behavior for DataWorks node operations is **draft only**:

- Use `CreateNode` / `UpdateNode` to create or update the DataWorks development draft.
- Do **not** call `SubmitFile`, `DeployFile`, `CreatePipelineRun`, or any publish/deploy API by default.
- Do **not** attempt publish as a follow-up after a successful draft update.
- If the user asks to "部署到 DataWorks", "同步到 DataWorks", "更新节点", or "帮我配置节点", interpret this as draft update only unless they explicitly say "提交", "发布", "submit", "publish", or "deploy to production".
- If explicit publish is requested, summarize affected node IDs/names first and ask for confirmation before calling publish APIs.
- In this project, the user normally publishes manually in the DataWorks console.

## Environment Constants (hardcoded, do not guess)

| Config | Value |
|--------|-------|
| DataWorks Region | `us-west-1` |
| DataWorks Endpoint | `dataworks.us-west-1.aliyuncs.com` |
| DataWorks ProjectId | `68155` |
| DataWorks ProjectName | `Tang_Data_Warehouse` |
| DataWorks SDK | `alibabacloud_dataworks_public20240518` |
| DataWorks Datasource | `tang_data_warehouse` (type: odps) |
| MaxCompute Project | `prod` |
| MaxCompute Endpoint | `http://service.us-west-1.maxcompute.aliyun.com/api` |
| MaxCompute SDK | `pyodps` |

## DataWorks Node Operations (Draft Update)

### Connect

```python
from alibabacloud_dataworks_public20240518.client import Client
from alibabacloud_dataworks_public20240518 import models
from alibabacloud_tea_openapi.models import Config

config = Config(
    access_key_id=os.environ['ALIBABA_CLOUD_ACCESS_KEY_ID'],
    access_key_secret=os.environ['ALIBABA_CLOUD_ACCESS_KEY_SECRET'],
    endpoint='dataworks.us-west-1.aliyuncs.com',
)
client = Client(config)
```

### List Nodes

```python
# ListNodes — PageSize must be ≤ 50
req = models.ListNodesRequest(project_id=68155, page_number=1, page_size=10)
resp = client.list_nodes(req)
paging = resp.body.paging_info.to_map()
nodes = paging.get('Nodes', [])  # each node has Id, Name fields
```

### Get Node Content

```python
req = models.GetNodeRequest(project_id=68155, id=node_id)
resp = client.get_node(req)
spec = resp.body.node.to_map().get('Spec')  # dict
# Node name: spec['spec']['name']
# SQL script: spec['spec']['nodes'][0]['script']['content']
# Script path: spec['spec']['nodes'][0]['script']['path']
# Datasource: spec['spec']['flow'][0]['metadata']['datasource']['name']
```

### Update Node Content

DataWorks nodes have a fixed SQL header that must be preserved. Only replace the SQL body.

Header format (example):
```sql
--MaxCompute SQL
--********************************************************************--
--author: 吴延俊
--create time: 2026-05-08 16:13:39
-- 数据域:   ...
...
--********************************************************************--
USE prod
;
```

**Update steps:**
1. Use GetNode to fetch the current node's Spec dict
2. Preserve the header from the beginning through `USE prod;`
3. Extract the SQL body from the local ETL file (starting from `WITH` or the first substantive statement after comments)
4. Concatenate: `header + "\n\n" + sql_body`
5. Replace `spec['spec']['nodes'][0]['script']['content']`
6. Call UpdateNode

```python
update_req = models.UpdateNodeRequest(
    project_id=68155,
    id=node_id,
    spec=json.dumps(spec_obj, ensure_ascii=False)  # Spec must be a JSON string
)
update_resp = client.update_node(update_req)
```

### Publish Node (Explicit Request Only)

`UpdateNode` only saves a draft. This is the normal stopping point.

Only when the user explicitly asks to submit/publish/deploy, and after a separate confirmation, use:

```python
# SubmitFile
submit_req = models.SubmitFileRequest(project_id=68155, file_id=node_id)
client.submit_file(submit_req)

# DeployFile (wait ~10 seconds after submit)
import time; time.sleep(10)
deploy_req = models.DeployFileRequest(project_id=68155, file_id=node_id)
client.deploy_file(deploy_req)
```

**Permission note:** Sub-account `2ccb997c8acb6020b1` may lack SubmitFile/DeployFile permissions. If a 403 error occurs, stop and tell the user to publish manually in the DataWorks console or ask a RAM administrator for the required permissions. Do not retry with alternate publish APIs unless explicitly authorized.

## MaxCompute Table Operations (DDL Deployment)

### Connect

```python
from odps import ODPS

o = ODPS(
    access_id=os.environ.get('ODPS_ACCESS_ID', os.environ['ALIBABA_CLOUD_ACCESS_KEY_ID']),
    secret_access_key=os.environ.get('ODPS_ACCESS_KEY', os.environ['ALIBABA_CLOUD_ACCESS_KEY_SECRET']),
    project='prod',
    endpoint='http://service.us-west-1.maxcompute.aliyun.com/api'
)
```

### Drop + Create Table

```python
# Drop table if exists
o.delete_table('table_name', if_exists=True)

# Read local DDL file
with open('path/to/table.ddl.sql', 'r') as f:
    ddl = f.read()

# Extract pure CREATE TABLE statement (strip comment header)
lines = ddl.split('\n')
create_start = -1
for i, line in enumerate(lines):
    if line.strip().upper().startswith('CREATE TABLE'):
        create_start = i
        break
create_stmt = '\n'.join(lines[create_start:])

# Execute
o.execute_sql(create_stmt)

# Verify
if o.exist_table('table_name'):
    t = o.get_table('table_name')
    print(f"OK - {len(t.table_schema.columns)} columns")
```

### Important Notes

- **Never** use the `maxcompute_execute_sql_preview` tool for DDL — it appends `LIMIT 10`, breaking DDL syntax.
- Strip comment headers (`--` lines) from DDL files before execution. Only pass the `CREATE TABLE ...` statement.
- If the DDL file uses `CREATE TABLE IF NOT EXISTS`, drop first with `DROP TABLE IF EXISTS` before recreating.

## Path Mapping

| Local Path | DataWorks Path |
|------------|---------------|
| `ETL/trd/dwd_trd_ds_ord_line_df.etl.sql` | `tangbuy_dw/trd/DWD/dwd_trd_ds_ord_line_df` |

General rule: `ETL/{domain}/{table_name}.etl.sql` → `tangbuy_dw/{domain}/{layer}/{table_name}`

## Workflow

When asked to update DataWorks nodes or create tables in MaxCompute:

1. **Check existence:** ListNodes or exist_table to see if the target already exists
2. **Read local file:** Get the latest DDL/ETL content from the local filesystem
3. **Update:**
   - **DataWorks ETL:** GetNode → replace content → UpdateNode → stop at draft update
   - **MaxCompute DDL:** DROP + CREATE via pyodps
4. **Verify:** GetNode to read back content / exist_table + row count to confirm

If the user explicitly requests publishing, treat it as a separate operation after draft verification and confirmation.
