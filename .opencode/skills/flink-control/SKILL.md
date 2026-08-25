# Skill: flink-control

# Flink Realtime Compute Control via OpenAPI

Control Demo Cross-border Commerce Flink real-time compute tasks using the Alibaba Cloud Ververica OpenAPI SDK. This skill mirrors the approach of `dw-platform-deploy` for offline DataWorks/MaxCompute.

## Publishing Policy

Default behavior for Flink operations is **read-only**:

- `list-deployments`, `get-deployment`, `list-jobs`, `get-job`, `events`, `diagnosis`, `start-log`, `list-savepoints` are always safe to execute.
- Write operations (`start`, `stop`, `create-savepoint`) require explicit `--yes` confirmation.
- Do **not** execute write operations unless the user explicitly confirms.
- For the `prod-tangbuy-us-flink-01-default` namespace, extra caution: do not stop or restart jobs without explicit user confirmation.

## Environment Constants (hardcoded, do not guess)

| Config | Value |
|--------|-------|
| Flink Endpoint | `ververica.us-west-1.aliyuncs.com` |
| Workspace | `67053268783826` |
| Namespace | `prod-tangbuy-us-flink-01-default` |
| API Version | `2022-07-18` |
| SDK Package | `alibabacloud_ververica20220718` |

Credentials are loaded from environment variables: `ALIBABA_CLOUD_ACCESS_KEY_ID` / `ALIBABA_CLOUD_ACCESS_KEY_SECRET`.

## RAM Permission

The sub-account (`2ccb997c8acb6020b1`) needs Flink permissions. Grant one of:

- **Read-only**: `AliyunStreamReadOnlyAccess` (managed policy)
- **Read+Write**: `AliyunStreamFullAccess` (managed policy)

Or create a custom policy with specific actions like `stream:ListDeployments`, `stream:GetDeployment`, etc.

## Core Script

```
pyshell/flink_control.py
```

### Quick Test (CLI)

```bash
# List all deployments
python3 pyshell/flink_control.py list-deployments

# Filter by status
python3 pyshell/flink_control.py list-deployments --status RUNNING

# Get deployment detail
python3 pyshell/flink_control.py get-deployment --deployment-id <id>

# List jobs for a deployment
python3 pyshell/flink_control.py list-jobs --deployment-id <id>

# Get job detail
python3 pyshell/flink_control.py get-job --job-id <id>

# Job diagnosis
python3 pyshell/flink_control.py diagnosis --job-id <id>

# Latest start log
python3 pyshell/flink_control.py start-log --job-id <id>

# List savepoints
python3 pyshell/flink_control.py list-savepoints --deployment-id <id>
```

### Write Operations (require --yes)

```bash
# Start a job
python3 pyshell/flink_control.py start --deployment-id <id> --yes

# Stop a job
python3 pyshell/flink_control.py stop --job-id <id> --yes

# Create savepoint
python3 pyshell/flink_control.py create-savepoint --deployment-id <id> --yes
```

### Programmatic Usage

```python
from pyshell.flink_control import FlinkClient, FlinkConfig, load_credentials

cfg = load_credentials()
client = FlinkClient(cfg)

# Read operations
deployments = client.list_deployments(status='RUNNING')
detail = client.get_deployment('deployment-id')
jobs = client.list_jobs('deployment-id')
job = client.get_job('job-id')
events = client.get_events('deployment-id')
diag = client.get_job_diagnosis('job-id')
log = client.get_latest_job_start_log('job-id')
savepoints = client.list_savepoints('deployment-id')

# Write operations
client.start_job('deployment-id')
client.stop_job('job-id')
client.create_savepoint('deployment-id', description='pre-upgrade')
```

## FlinkClient API Reference

| Method | Description | Access |
|--------|-------------|--------|
| `list_deployments(page, page_size, name, status, execution_mode, sort_name)` | List all deployments | Read |
| `get_deployment(deployment_id)` | Get deployment detail | Read |
| `list_jobs(deployment_id, page, page_size)` | List job instances | Read |
| `get_job(job_id)` | Get job instance detail | Read |
| `get_events(deployment_id, page, page_size)` | Get deployment events | Read |
| `get_job_diagnosis(job_id)` | Get intelligent diagnosis | Read |
| `get_latest_job_start_log(job_id)` | Get latest start log | Read |
| `list_savepoints(deployment_id, page, page_size)` | List savepoints/checkpoints | Read |
| `start_job(deployment_id, resource_spec, restore_strategy)` | Start a job instance | Write |
| `stop_job(job_id, stop_strategy)` | Stop a job instance | Write |
| `create_savepoint(deployment_id, description, native_format)` | Create a savepoint | Write |

## Workflow

When asked to interact with Flink tasks:

1. **Check connectivity:** Run `list-deployments` to verify credentials and permissions work.
2. **Read status:** Use read operations to get current state of tasks.
3. **Diagnose issues:** Use `diagnosis` and `events` to investigate problems.
4. **Write operations:** Only when user explicitly confirms with `--yes` or verbally confirms.

For the `prod` namespace, always:
- Show the target deployment/job name and ID before any write operation.
- Warn if stopping a RUNNING job.
- Do not batch-stop or batch-start without explicit enumeration of each task.

## Error Handling

| Error | Cause | Solution |
|-------|-------|----------|
| `RAM_AUTH_DENY` (403) | Missing Flink permissions | Grant `AliyunStreamReadOnlyAccess` to the sub-account |
| `Missingworkspace` (400) | Workspace header not set | Ensure SDK wrapper injects workspace header |
| `SSLError` | Wrong endpoint format | Use plain `ververica.us-west-1.aliyuncs.com` |

## Available API Operations (Full List)

The Ververica SDK (`2022-07-18`) also supports these operations not yet wrapped in the script:

- **Deployment Drafts**: Create/Update/Delete/List/Deploy/Validate deployment drafts (SQL/YAML)
- **Deployment Targets**: CRUD for Session/Per-Job clusters
- **Session Clusters**: Full CRUD + Start/Stop
- **Scheduled Plans**: CRUD + Apply/Stop + Execution History
- **UDF Management**: Register/Delete/Get UDF artifacts and functions
- **Custom Connectors**: Register/Delete/List
- **Variables**: CRUD for project-level variables
- **Member Management**: CRUD for project members and permissions
- **Metadata**: GetDatabases, GetTables, GetCatalogs
- **SQL Execution**: ExecuteSqlStatement (DDL/DML only)
- **Flink REST API Proxy**: FlinkApiProxy for direct Flink REST access

Add these to `flink_control.py` as needed following the same pattern with workspace header injection.
