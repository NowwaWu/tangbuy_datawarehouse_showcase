'''PyODPS 3
请确保不要使用从 MaxCompute下载数据来处理。下载数据操作常包括Table/Instance的open_reader以及 DataFrame的to_pandas方法。
推荐使用 MaxFrame DataFrame（从 MaxCompute 表创建）来处理数据，MaxFrame DataFrame数据计算发生在MaxCompute集群，无需拉数据至本地。
MaxFrame相关介绍及使用可参考：https://help.aliyun.com/zh/maxcompute/user-guide/maxframe
'''

import json
import sys
import os
import time
import base64
import urllib.request
import urllib.parse
import urllib.error

from odps import options
options.tunnel.use_instance_tunnel = True
options.tunnel.limit_instance_tunnel = False

# DataWorks PyODPS 3 节点中 o 是全局变量
bizdate = args.get('bizdate', '20260520')


# ============================================================
# 辅助函数
# ============================================================

def esc(v):
    """SQL 字符串转义，None → NULL"""
    if v is None:
        return 'NULL'
    s = str(v).replace('\\', '\\\\').replace("'", "\\'")
    return f"'{s}'"


def load_gcp_credentials():
    """从环境变量或外部文件读取 GCP 服务账号，不在代码中保存凭据。"""
    raw_json = os.getenv('GCP_SERVICE_ACCOUNT_JSON')
    credential_file = os.getenv('GOOGLE_APPLICATION_CREDENTIALS')
    if raw_json:
        return json.loads(raw_json)
    if credential_file:
        with open(credential_file, 'r', encoding='utf-8') as handle:
            return json.load(handle)
    raise RuntimeError(
        '请设置 GCP_SERVICE_ACCOUNT_JSON 或 GOOGLE_APPLICATION_CREDENTIALS'
    )

def fetch_bq_via_rest(project, sql):
    """
    使用 BigQuery REST API 执行查询。
    纯标准库实现 JWT RS256 签名，无需 cryptography。
    """
    import hashlib

    # SSL 兼容
    def _ssl_ctx():
        ctx = __import__('ssl').create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = __import__('ssl').CERT_NONE
        return ctx

    # ---------- RSA 私钥解析 (纯标准库 DER, 零依赖) ----------
    def _parse_private_key(pem_str):
        """从 PKCS#8 PEM 私钥提取 n(模数) 和 d(私钥指数)"""
        b64 = ''.join(
            pem_str.replace('<PRIVATE_KEY_FROM_SECRET_STORE>', '')
                   .replace('\n', '').replace('\r', '').split()
        )
        der = base64.b64decode(b64)

        def _read_tlv(data, pos):
            tag = data[pos]; pos += 1
            b = data[pos]; pos += 1
            if b & 0x80:
                nbytes = b & 0x7f
                length = int.from_bytes(data[pos:pos + nbytes], 'big')
                pos += nbytes
            else:
                length = b
            return tag, length, pos, pos + length

        def _read_int(data, pos):
            _, length, vstart, vnext = _read_tlv(data, pos)
            return int.from_bytes(data[vstart:vstart + length], 'big'), vnext

        def _skip(data, pos):
            _, _, _, vnext = _read_tlv(data, pos)
            return vnext

        # Walk PKCS#8: SEQUENCE → version → algorithm → OCTET STRING → RSAPrivateKey
        _, _, v0, _ = _read_tlv(der, 0)          # outer SEQUENCE
        _, pos = _read_int(der, v0)               # version=0
        pos = _skip(der, pos)                      # algorithm SEQUENCE
        _, _, rsa_start, _ = _read_tlv(der, pos)  # OCTET STRING (tag 0x04)
        _, _, v5, _ = _read_tlv(der, rsa_start)   # RSAPrivateKey SEQUENCE
        rpos = v5
        _, rpos = _read_int(der, rpos)             # version=0
        n, rpos = _read_int(der, rpos)             # modulus
        _, rpos = _read_int(der, rpos)             # public exponent e (ignore)
        d, rpos = _read_int(der, rpos)             # private exponent d
        return n, d

    # ---------- RSA PKCS#1 v1.5 SHA256 签名 (纯 Python) ----------
    def _rsa_sign_sha256(message, n, d):
        h = hashlib.sha256(message).digest()
        prefix = bytes([0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48,
            0x01, 0x65, 0x03, 0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20])
        di = prefix + h
        k = (n.bit_length() + 7) // 8
        pad = b'\x00\x01' + b'\xff' * (k - len(di) - 3) + b'\x00' + di
        return pow(int.from_bytes(pad, 'big'), d, n).to_bytes(k, 'big')

    # ---------- 获取 Access Token ----------
    def get_access_token():
        gcp_key = load_gcp_credentials()
        n, d = _parse_private_key(gcp_key["private_key"])

        now = int(time.time())
        _header = base64.urlsafe_b64encode(
            json.dumps({"alg": "RS256", "typ": "JWT"}).encode()
        ).rstrip(b'=')
        _claim = base64.urlsafe_b64encode(
            json.dumps({
                "iss": gcp_key["client_email"],
                "scope": "https://www.googleapis.com/auth/bigquery",
                "aud": "https://oauth2.googleapis.com/token",
                "exp": now + 3600,
                "iat": now,
            }).encode()
        ).rstrip(b'=')

        assertion = _header + b'.' + _claim
        sig = base64.urlsafe_b64encode(
            _rsa_sign_sha256(assertion, n, d)
        ).rstrip(b'=')
        signed_jwt = assertion + b'.' + sig

        token_url = 'https://oauth2.googleapis.com/token'
        token_data = urllib.parse.urlencode({
            'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
            'assertion': signed_jwt.decode(),
        }).encode()
        req = urllib.request.Request(token_url, data=token_data)
        resp = urllib.request.urlopen(req, timeout=30, context=_ssl_ctx())
        token_resp = json.loads(resp.read())
        return token_resp['access_token']

    access_token = get_access_token()
    print(f"[{bizdate}] Got BigQuery access token")

    ssl_ctx = _ssl_ctx()

    # 提交查询
    bq_url = f"https://bigquery.googleapis.com/bigquery/v2/projects/{project}/queries"
    headers = {
        'Authorization': f'Bearer {access_token}',
        'Content-Type': 'application/json',
    }
    body = json.dumps({
        'query': sql,
        'useLegacySql': False,
        'timeoutMs': 300000,
    }).encode()

    req = urllib.request.Request(bq_url, data=body, headers=headers)
    resp = urllib.request.urlopen(req, timeout=60, context=ssl_ctx)
    job = json.loads(resp.read())
    job_id = job.get('jobReference', {}).get('jobId', '')

    if not job.get('jobComplete'):
        print(f"[{bizdate}] Waiting for BigQuery job {job_id}...")
        for _ in range(60):
            time.sleep(5)
            status_url = f"https://bigquery.googleapis.com/bigquery/v2/projects/{project}/jobs/{job_id}"
            req = urllib.request.Request(status_url, headers={'Authorization': f'Bearer {access_token}'})
            resp = urllib.request.urlopen(req, timeout=30, context=ssl_ctx)
            job = json.loads(resp.read())
            if job.get('status', {}).get('state') == 'DONE':
                break

    if job.get('status', {}).get('errorResult'):
        error = job['status']['errorResult']
        if 'Not found' in str(error.get('message', '')):
            print(f"[{bizdate}] Table not found - no events for {bizdate}")
            return []
        raise Exception(f"BigQuery error: {error}")

    # 解析结果 (处理分页: BigQuery 默认每页 ~4k-5k 行)
    schema = [f['name'] for f in job.get('schema', {}).get('fields', [])]
    rows_data = []

    def _collect_rows(job_obj):
        for row in job_obj.get('rows', []):
            values = {}
            for i, field in enumerate(row.get('f', [])):
                col_name = schema[i] if i < len(schema) else f'col_{i}'
                values[col_name] = field.get('v')
            rows_data.append(values)

    _collect_rows(job)

    # 分页获取剩余结果
    page_token = job.get('pageToken')
    total_rows = job.get('totalRows', 'N/A')
    page = 1
    while page_token:
        page += 1
        fetch_url = (f"https://bigquery.googleapis.com/bigquery/v2/projects/{project}"
                     f"/queries/{job_id}?pageToken={page_token}&maxResults=100000")
        req = urllib.request.Request(fetch_url, headers={'Authorization': f'Bearer {access_token}'})
        resp = urllib.request.urlopen(req, timeout=60, context=ssl_ctx)
        job = json.loads(resp.read())
        _collect_rows(job)
        page_token = job.get('pageToken')
        if page % 5 == 0:
            print(f"[{bizdate}]   page {page}: {len(rows_data)} rows so far / {total_rows} total")

    print(f"[{bizdate}] BigQuery returned {len(rows_data)} rows")
    return rows_data


# ============================================================
# 主逻辑
# ============================================================

gcp_project = args.get('bq_project', 'tangbuy-master')
gcp_dataset = args.get('bq_dataset', 'analytics_471066976')
target_table = 'ods_google_firebase_events_di'

print(f"[{bizdate}] Syncing Firebase events from BigQuery")
print(f"[{bizdate}]   Project: {gcp_project}, Dataset: {gcp_dataset}")
print(f"[{bizdate}]   Date: {bizdate}")

# 确保目标表存在
if not o.exist_table(target_table):
    o.execute_sql("""
        CREATE TABLE IF NOT EXISTS ods_google_firebase_events_di (
            event_date              STRING  COMMENT '事件日期(yyyyMMdd)',
            event_timestamp         BIGINT  COMMENT '事件时间戳(微秒)',
            event_name              STRING  COMMENT '事件名称',
            user_pseudo_id          STRING  COMMENT '用户伪ID',
            user_id                 STRING  COMMENT '用户ID(登录后)',
            platform                STRING  COMMENT '平台',
            stream_id               BIGINT  COMMENT '数据流ID',
            event_value_in_usd      DOUBLE  COMMENT '事件价值(USD)',
            event_params_json       STRING  COMMENT '事件参数JSON',
            user_properties_json    STRING  COMMENT '用户属性JSON',
            user_ltv_json           STRING  COMMENT '用户LTV JSON',
            device_json             STRING  COMMENT '设备信息JSON',
            geo_json                STRING  COMMENT '地理位置JSON',
            app_info_json           STRING  COMMENT '应用信息JSON',
            traffic_source_json     STRING  COMMENT '流量来源JSON',
            ecommerce_json          STRING  COMMENT '电商数据JSON',
            items_json              STRING  COMMENT '商品列表JSON',
            privacy_info_json       STRING  COMMENT '隐私设置JSON',
            event_dimensions_json   STRING  COMMENT '事件维度JSON',
            raw_json                STRING  COMMENT '完整原始JSON',
            bq_sync_time            STRING  COMMENT '同步时间戳'
        )
        COMMENT 'Firebase Analytics 埋点事件-日增量'
        PARTITIONED BY (ds STRING COMMENT '分区日期 yyyyMMdd')
    """)
    print(f"[{bizdate}] Created {target_table}")

# BigQuery 查询
bq_table = f"{gcp_project}.{gcp_dataset}.events_{bizdate}"
sql_bq = f"""
SELECT
    event_date,
    event_timestamp,
    event_name,
    user_pseudo_id,
    CAST(user_id AS STRING) AS user_id,
    platform,
    stream_id,
    event_value_in_usd,
    TO_JSON_STRING(event_params) AS event_params_json,
    TO_JSON_STRING(user_properties) AS user_properties_json,
    TO_JSON_STRING(user_ltv) AS user_ltv_json,
    TO_JSON_STRING(device) AS device_json,
    TO_JSON_STRING(geo) AS geo_json,
    TO_JSON_STRING(app_info) AS app_info_json,
    TO_JSON_STRING(traffic_source) AS traffic_source_json,
    TO_JSON_STRING(ecommerce) AS ecommerce_json,
    TO_JSON_STRING(items) AS items_json,
    TO_JSON_STRING(privacy_info) AS privacy_info_json,
    TO_JSON_STRING(event_dimensions) AS event_dimensions_json,
    FORMAT_TIMESTAMP('%Y-%m-%d %H:%M:%E*S', CURRENT_TIMESTAMP()) AS bq_sync_time
FROM `{bq_table}`
"""

print(f"[{bizdate}] Querying: {bq_table}")

# 认证并执行查询
use_bq_lib = False
try:
    from google.cloud import bigquery
    from google.oauth2 import service_account
    use_bq_lib = True
except ImportError:
    pass

if use_bq_lib:
    print(f"[{bizdate}] Using google-cloud-bigquery library")
    credentials = service_account.Credentials.from_service_account_info(
        load_gcp_credentials(),
        scopes=['https://www.googleapis.com/auth/bigquery']
    )
    client = bigquery.Client(project=gcp_project, credentials=credentials)
    try:
        query_job = client.query(sql_bq)
        rows = [dict(row) for row in query_job.result()]
        print(f"[{bizdate}] BigQuery returned {len(rows)} rows")
    except Exception as e:
        error_msg = str(e)
        if 'Not found: Table' in error_msg or '404' in error_msg:
            print(f"[{bizdate}] Table {bq_table} not found - no events for {bizdate}")
            rows = []
        else:
            raise
else:
    print(f"[{bizdate}] Using BigQuery REST API fallback")
    rows = fetch_bq_via_rest(gcp_project, sql_bq)

# 写入 ODPS
if not rows:
    print(f"[{bizdate}] No data to write. Creating empty partition.")
    empty_sql = f"""
    INSERT OVERWRITE TABLE {target_table} PARTITION(ds='{bizdate}')
    SELECT
        '' AS event_date, CAST(0 AS BIGINT) AS event_timestamp, '' AS event_name,
        '' AS user_pseudo_id, '' AS user_id, '' AS platform,
        CAST(0 AS BIGINT) AS stream_id, CAST(NULL AS DOUBLE) AS event_value_in_usd,
        '' AS event_params_json, '' AS user_properties_json, '' AS user_ltv_json,
        '' AS device_json, '' AS geo_json, '' AS app_info_json,
        '' AS traffic_source_json, '' AS ecommerce_json, '' AS items_json,
        '' AS privacy_info_json, '' AS event_dimensions_json,
        '' AS raw_json, '' AS bq_sync_time
    WHERE 1=0
    """
    o.execute_sql(empty_sql)
else:
    t_write_start = time.time()
    print(f"[{bizdate}] Writing {len(rows)} rows to {target_table}...")

    tmp_table = f"tmp_firebase_sync_{bizdate}"
    if o.exist_table(tmp_table):
        o.delete_table(tmp_table)

    o.create_table(tmp_table,
        'event_date STRING, event_timestamp BIGINT, event_name STRING, '
        'user_pseudo_id STRING, user_id STRING, platform STRING, '
        'stream_id BIGINT, event_value_in_usd DOUBLE, '
        'event_params_json STRING, user_properties_json STRING, user_ltv_json STRING, '
        'device_json STRING, geo_json STRING, app_info_json STRING, '
        'traffic_source_json STRING, ecommerce_json STRING, items_json STRING, '
        'privacy_info_json STRING, event_dimensions_json STRING, '
        'raw_json STRING, bq_sync_time STRING',
        if_not_exists=True
    )

    # 使用 Tunnel 批量写入临时表（秒级，无 SQL 长度限制）
    from odps.tunnel import TableTunnel
    tunnel = TableTunnel(o)
    upload_session = tunnel.create_upload_session(tmp_table)
    print(f"  Tunnel session: {upload_session}")

    with upload_session.open_record_writer() as writer:
        for i, r in enumerate(rows):
            raw = json.dumps(r, ensure_ascii=False)
            record = upload_session.new_record()
            record[0]  = r.get('event_date') or ''
            record[1]  = r.get('event_timestamp') or 0
            record[2]  = r.get('event_name') or ''
            record[3]  = r.get('user_pseudo_id') or ''
            record[4]  = r.get('user_id') or ''
            record[5]  = r.get('platform') or ''
            record[6]  = r.get('stream_id') or 0
            record[7]  = r.get('event_value_in_usd')
            record[8]  = r.get('event_params_json') or ''
            record[9]  = r.get('user_properties_json') or ''
            record[10] = r.get('user_ltv_json') or ''
            record[11] = r.get('device_json') or ''
            record[12] = r.get('geo_json') or ''
            record[13] = r.get('app_info_json') or ''
            record[14] = r.get('traffic_source_json') or ''
            record[15] = r.get('ecommerce_json') or ''
            record[16] = r.get('items_json') or ''
            record[17] = r.get('privacy_info_json') or ''
            record[18] = r.get('event_dimensions_json') or ''
            record[19] = raw
            record[20] = r.get('bq_sync_time') or ''
            writer.write(record)
            if (i + 1) % 5000 == 0:
                print(f"  [{i+1:6d}/{len(rows)}] rows ({time.time() - t_write_start:.0f}s)")

    # 服务端内部分块（1个 writer → N个 block），必须获取全部 block_id 再 commit
    blocks = upload_session.get_block_list()
    upload_session.commit(blocks)
    print(f"  Tunnel committed {len(blocks)} block(s), {len(rows)} rows ({time.time() - t_write_start:.0f}s)")

    # INSERT OVERWRITE 到目标分区
    o.execute_sql(f"""
        INSERT OVERWRITE TABLE {target_table} PARTITION(ds='{bizdate}')
        SELECT * FROM {tmp_table}
    """)
    o.delete_table(tmp_table)

    # 验证写入行数
    verify_result = o.execute_sql(
        f"SELECT COUNT(*) FROM {target_table} WHERE ds='{bizdate}'"
    )
    with verify_result.open_reader() as rd:
        actual = int(list(rd)[0][0])
    t_total = time.time() - t_write_start
    if actual == len(rows):
        print(f"[{bizdate}] Done. {actual} rows written to ds={bizdate} in {t_total:.0f}s")
    else:
        raise Exception(
            f"Row count mismatch! Expected {len(rows)}, got {actual}. "
            f"Check tmp_table data or INSERT OVERWRITE."
        )
