# DataWorks Open API Cookbook (API Version: 2024-05-18)
Verified patterns, pitfalls, and working code snippets collected from real-world usage.
## Project publishing policy
For Tang_Data_Warehouse work, node creation/update stops at DataWorks draft by default. Do not call `SubmitFile`, `DeployFile`, `CreatePipelineRun`, or other publish/deploy APIs unless the user explicitly asks to submit/publish/deploy and confirms the affected resources. The user normally publishes manually in the DataWorks console.

## Verified API quick reference
| Category   | API                          | Status   | Notes                                         |
| ---------- | ---------------------------- | -------- | --------------------------------------------- |
| Workspace  | ListProjects                 | Verified |                                               |
| Node       | CreateNode                   | Verified | Must use FlowSpec JSON in `spec` param        |
| Node       | GetNode                      | Verified | `spec` field is JSON string; parse to get SQL |
| Node       | UpdateNode                   | Verified | Send full spec back after modification        |
| Node       | ListNodes                    | Verified |                                               |
| File       | ListFiles                    | Verified | Response at `resp.body.data.files`            |
| File       | SubmitFile                   | Verified | `file_id` = node ID (same value)              |
| File       | DeployFile                   | Verified | Must wait ~10 s after SubmitFile              |
| Adhoc      | ExecuteAdhocWorkflowInstance | Verified | One-off DDL/DML/SELECT; `biz_date` = `YYYYMMDD` |
| Workflow   | GetWorkflowInstance          | Verified | Poll `status`; fields: `started_time`/`finished_time` (ms) |
| Schedule   | ListTaskInstances            | Verified | `bizdate` is **millisecond** timestamp        |
| Schedule   | GetTaskInstance              | Verified | Returns full instance attributes              |
| Schedule   | GetTaskInstanceLog           | Verified |                                               |
| Schedule   | RerunTaskInstances           | Verified | Accepts list of IDs                           |
| Resource   | ListResourceGroups           | Verified |                                               |
| DataSource | ListDataSources              | Verified |                                               |
| Quality    | CreateDataQualityRule        | Verified | Needs typed Request sub-objects               |
| Quality    | ListDataQualityRules         | Verified |                                               |
| Workflow   | CreateWorkflowDefinition     | Verified | Creates a workflow container for nodes         |
| Deploy     | GetDeployment                | Verified | Poll pipeline status after deploy              |
| Trigger    | CreateWorkflowInstances      | Verified | Smoke-test / manual trigger                    |
| Trigger    | GetCreateWorkflowInstancesResult | Verified | Poll for workflow creation completion      |
| Workflow   | ImportWorkflowDefinition     | Verified | Create workflow + nodes in one call (CycleWorkflow FlowSpec) |
| DataMap    | GetTable                     | Verified | Get table info by GUID from data map       |
| Quality    | CreateDataQualityScan        | Verified | Create a quality scan task                  |
| Quality    | CreateDataQualityScanRun     | Verified | Execute a quality scan                      |
| Quality    | GetDataQualityRule           | Verified | Get quality rule details                    |
| Quality    | CreateDataQualityEvaluationTask | Verified | Create a monitoring task for a table     |
| Quality    | GetDataQualityEvaluationTask | Verified | Query evaluation task details              |
| Quality    | AttachDataQualityRulesToEvaluationTask | Verified | Bind rules to an evaluation task |
| Quality    | DeleteDataQualityRule        | Verified | Delete a quality rule by ID                 |
| Quality    | DeleteDataQualityEvaluationTask | Verified | Delete an evaluation task by ID           |
| DI         | CreateDIJob                  | Verified | Create data integration job (batch/realtime) |
| DI         | GetDIJob                     | Verified | Get DI job details                          |
| DI         | ListDIJobs                   | Verified | List DI jobs                                |
| DI         | CreateNode (DI type)         | Verified | Create DI offline sync node via FlowSpec    |
## Pitfalls and key discoveries
### 1. Node ID = File ID
`CreateNode` returns a node ID that doubles as the file ID for `SubmitFile` / `DeployFile`. No separate file-creation step is needed.
### 2. SubmitFile → wait → DeployFile (explicit request only)
Do not run this sequence by default. Use it only after the user explicitly requests publish/deploy and confirms the affected resources.

After `SubmitFile`, the internal pipeline needs **~10 seconds** to prepare before `DeployFile` can succeed. Calling `DeployFile` too early returns a "pipeline not ready" error.
```python
submit_resp = client.submit_file(submit_request)
time.sleep(10)   # required wait
deploy_resp = client.deploy_file(deploy_request)
```
### 3. `bizdate` must be a millisecond timestamp string
`ListTaskInstances` expects `bizdate` as a **string of milliseconds since epoch**, not a date string.
```python
from datetime import datetime, timedelta
bizdate = str(int((datetime.now() - timedelta(days=1)).timestamp() * 1000))
```
### 4. `GetNode` spec is a JSON string
The `spec` field returned by `GetNode` is a JSON string (or an SDK object). Always parse before use:
```python
spec = node.spec
if isinstance(spec, str):
    spec_dict = json.loads(spec)
else:
    spec_dict = spec.to_map() if hasattr(spec, 'to_map') else spec
sql = spec_dict['spec']['nodes'][0]['script']['content']
```
### 5. Response parsing varies by API generation
- **New-generation APIs** (ListProjects, ListNodes, etc.): response at `resp.body.paging_info.*`
- **Old-generation APIs** (ListFiles): response at `resp.body.data.*`
Use `to_map()` when the response is an SDK object:
```python
paging = resp.body.paging_info
result = paging.to_map() if hasattr(paging, 'to_map') else paging
```
### 6. CreateDataQualityRule requires typed sub-objects
Do **not** pass dicts; use the SDK model classes:
```python
target = models.CreateDataQualityRuleRequestTarget(
    type="Table",
    database_type="maxcompute",
    table_guid="odps.<project>.<table>",
    partition_spec="dt=$[yyyymmdd-1]",
)
checking_config = models.CreateDataQualityRuleRequestCheckingConfig(type="Fixed")
request = models.CreateDataQualityRuleRequest(
    project_id=PROJECT_ID,
    name="rule_name",
    enabled=True,
    severity="High",
    target=target,
    template_code="SYSTEM:table:table_count:fixed:0",
    checking_config=checking_config,
)
```
### 7. Throttling (Throttling.Resource)
API calls can hit rate limits. Retry with exponential backoff or wait before retrying.
### 8. CreateNode spec: `inputs` and `outputs` are required
Omitting `inputs` or `outputs` from the FlowSpec causes silent failures or scheduling issues. Always include at least:
- `inputs.nodeOutputs`: `[{"data": "project_root", "artifactType": "NodeOutput"}]` (root dependency)
- `outputs.nodeOutputs`: `[{"data": "<name>_output", "artifactType": "NodeOutput", "refTableName": "<name>"}]`
### 9. CycleWorkflow FlowSpec: create workflow + nodes in one call
Besides `CreateNode` (kind: `Node`), you can use `ImportWorkflowDefinition` with kind `CycleWorkflow` to create a full workflow with embedded nodes in a single API call:
```json
{
    "version": "1.1.0",
    "kind": "CycleWorkflow",
    "spec": {
        "name": "<workflow-name>",
        "type": "CycleWorkflow",
        "workflows": [{
            "script": { "path": "root/<workflow-name>", "runtime": {"command": "WORKFLOW"} },
            "trigger": { "type": "Scheduler", "cron": "00 00 02 * * ?", ... },
            "strategy": { "timeout": 0, "instanceMode": "T+1", "rerunMode": "Allowed", "rerunTimes": 3, "rerunInterval": 180000, "failureStrategy": "Break" },
            "name": "<workflow-name>",
            "nodes": [{
                "recurrence": "Normal",
                "script": { "path": "root/<workflow-name>/<node-name>", "runtime": {"command": "ODPS_SQL"}, "content": "SELECT 1;" },
                "trigger": { "type": "Scheduler", "cron": "00 00 02 * * ?", ... },
                "name": "<node-name>",
                "outputs": { "nodeOutputs": [{"data": "<node-name>_output", "artifactType": "NodeOutput"}] }
            }],
            "dependencies": []
        }]
    }
}
```
Call via generalized SDK: `action="ImportWorkflowDefinition"`, body param `Spec` = the JSON above.
### 10. SmokeTest: `WorkflowId` is always 1 for periodic tasks
When triggering a smoke test via `CreateWorkflowInstances`, set `WorkflowId=1` for periodic (scheduled) tasks. This is a fixed convention.
### 11. DeployFile retry on "pipeline not ready"
If `DeployFile` fails with a message containing "流水线未准备好" or "pipeline", wait a few more seconds and retry:
```python
resp = deploy_file(...)
if "流水线未准备好" in error_msg or "pipeline" in error_msg.lower():
    time.sleep(5)
    resp = deploy_file(...)  # retry
```
### 12. SubmitFile: `SkipAllDeployFileExtensions` parameter
Pass `SkipAllDeployFileExtensions='true'` to skip extension checks during submit (e.g. in HTTP-style calls). SDK-style calls may not need this.
### 13. Data service APIs are on older API version
`ListDataServicePublishedApis` and other data-service-related APIs belong to the **old API version `2020-05-18`**, not the current `2024-05-18`. If you need data service capabilities, use the older version endpoint.
### 14. MaxCompute as DI source: use CreateNode, NOT CreateDIJob
**Critical**: `CreateDIJob` API's `SourceDataSourceType` enum does **not include MaxCompute**. To sync data **from** MaxCompute (e.g. MaxCompute → Hologres), you must use `CreateNode` with DI type instead:
| Method | MaxCompute as source | How |
|--------|---------------------|-----|
| `CreateDIJob` | Not supported | `SourceDataSourceType` has no MC option |
| `CreateNode` (DI type) | Supported | `stepType: "odps"` in the DI config |
### 15. DI node: `command` must be `"DI"` with `commandTypeId: 23`
When creating a DI node via `CreateNode`, the `script.runtime` must have:
- `command`: `"DI"` (not `"ODPS_SQL"`)
- `commandTypeId`: `23`
- `script.language`: `"json"` (the content is a JSON DI config, not SQL)
### 16. `biz_date` in ExecuteAdhocWorkflowInstance vs `bizdate` in ListTaskInstances
These two use **completely different formats** — easy to confuse:
| API | Param | Format | Example |
|-----|-------|--------|---------|
| `ExecuteAdhocWorkflowInstance` | `biz_date` | `YYYYMMDD` string | `"20260315"` |
| `ListTaskInstances` | `bizdate` | Millisecond timestamp string | `"1710460800000"` |
### 17. ExecuteAdhocWorkflowInstance: `owner` required at BOTH levels
`owner` must be set on both the task object AND the workflow request itself. Missing either causes an error.
### 18. ExecuteAdhocWorkflowInstance: `client_unique_code` is REQUIRED
Despite being marked optional in some docs, omitting `client_unique_code` causes `MissingClientUniqueCode` error. Always provide one:
```python
import uuid
client_unique_code = str(uuid.uuid4()).replace('-', '')[:20]
```
### 19. ExecuteAdhocWorkflowInstance: `type` must be ALL_CAPS with underscores
```python
# WRONG formats:
type="hologres_sql"    # lowercase
type="HologresSql"     # camelCase
type="holo"            # abbreviation
# CORRECT formats:
type="HOLOGRES_SQL"    # Hologres SQL
type="ODPS_SQL"        # MaxCompute SQL
```
Supported task `type` values:
| type | Engine | Data source example |
|------|--------|---------------------|
| `ODPS_SQL` | MaxCompute SQL | mc_datasource |
| `HOLOGRES_SQL` | Hologres SQL | holo_datasource |
| `MYSQL_SQL` | MySQL SQL | mysql_datasource |
| `POSTGRESQL_SQL` | PostgreSQL SQL | pg_datasource |
### 20. `CreatePipelineRun` is NOT for running nodes — it's for publishing
Common mistake: `CreatePipelineRun` is a **deployment** pipeline (build → check → publish to production), not an execution API. Use the right API for each intent:
| API | Purpose | Flow |
|-----|---------|------|
| `CreatePipelineRun` | Publish node to production | Build → Check → Deploy (slow) |
| `ExecuteAdhocWorkflowInstance` | Run SQL directly | Immediate execution |
| `RerunTaskInstances` | Re-run existing instance | Needs an existing instance |
### 21. Task instance status values
| Status | Meaning |
|--------|---------|
| `NotRun` | Not yet started |
| `WaitTime` | Waiting for scheduled time |
| `WaitResource` | Waiting for available resource slot |
| `Running` | Executing |
| `Success` | Completed successfully |
| `Failure` | Failed |
### 22. Deployment pipeline status values (GetDeployment)
| Status | Meaning |
|--------|---------|
| `Success` | Deploy succeeded |
| `Fail` | Deploy failed |
| `Termination` | Deploy terminated |
| `Cancel` | Deploy cancelled |
### 23. FileType codes (for old-generation CreateFile API)
| Code | Engine |
|------|--------|
| 10 | ODPS SQL |
| 20 | Shell |
| 30 | Python |
### 24. CycleWorkflow FlowSpec: `outputs.tables` for table lineage
In `ImportWorkflowDefinition`, a node's `outputs` can include a `tables` array to register output table lineage:
```json
"outputs": {
    "nodeOutputs": [{"data": "<name>_output", "artifactType": "NodeOutput"}],
    "tables": [{"guid": "odps.<project>.<table>"}]
}
```
### 25. DI sync: target table must exist before running
DI sync will fail with `can not found table "public"."<table>"` if the target table does not exist. Create it first, e.g. via `ExecuteAdhocWorkflowInstance` with `HOLOGRES_SQL`:
```python
sql = "CREATE TABLE IF NOT EXISTS public.<table> (id BIGINT, name TEXT, value DOUBLE PRECISION);"
# Execute via adhoc workflow (see Recipe 3)
```
### 26. DI sync: partition format requires single quotes
For partitioned source tables, the `partition` parameter requires single quotes around the value:
```python
# WRONG
step['parameter']['partition'] = ["dt=20260315"]        # no quotes → error
# CORRECT
step['parameter']['partition'] = ["dt='20260315'"]      # with single quotes
```
Error if missing: "分区信息没有配置.由于源头表:xxx 为分区表, 所以您需要配置其分区信息"
### 27. DI sync: `splitMode` must be `'record'` or `'partition'`
```python
# WRONG
step['parameter']['splitMode'] = False          # → error
# CORRECT
step['parameter']['splitMode'] = 'record'       # split by records
step['parameter']['splitMode'] = 'partition'     # split by partitions
```
### 28. Old API `UpdateFile`: use for direct SQL content updates
The old-generation `UpdateFile` API can update file content directly (without going through FlowSpec):
```python
call_api('UpdateFile', {
    'ProjectId': PROJECT_ID,
    'FileId': file_id,
    'Content': new_sql_content,
    'AutoParsing': 'false',
})
# Then stop at draft update unless the user explicitly requests SubmitFile → DeployFile
```
### 29. HTTP API signing: GET vs POST use different string-to-sign
- POST: `'POST&%2F&' + encoded_params`
- GET: `'GET&%2F&' + encoded_params`
Using the wrong HTTP method prefix causes signature verification failure.
### 30. Deleting DQ rules and evaluation tasks: rules first, then task
Deletion order: **delete rules first**, then delete the evaluation task. Rules can be deleted directly without detaching from the task first.
```python
# 1. Delete rules
call_api('DeleteDataQualityRule', {'ProjectId': PROJECT_ID, 'Id': rule_id})
# 2. Delete evaluation task (after all rules are removed)
call_api('DeleteDataQualityEvaluationTask', {'ProjectId': PROJECT_ID, 'Id': task_id})
```
Both APIs only require `ProjectId` + `Id`. No detach step needed.
### 31. DQ for Hologres tables: metadata collection required first (no API!)
Creating DQ rules for Hologres tables fails with "表（holo.xxx.public.xxx）不存在" because DQ monitoring depends on **data map metadata**. The table must first be registered via metadata collection.
**DataWorks API does NOT provide metadata collection APIs.** You must do this manually:
```
DataWorks Console → Data Map → Metadata Collection → Configure data source → Execute sync
```
Workaround: skip DQ rules entirely and use `ExecuteAdhocWorkflowInstance` with `HOLOGRES_SQL` to run `SELECT COUNT(*)` checks directly.
### 32. `CreateDataQualityEvaluationTask`: `DataSourceId` is mandatory
