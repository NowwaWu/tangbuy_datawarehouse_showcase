'''PyODPS 3
请确保不要使用从 MaxCompute下载数据来处理。下载数据操作常包括Table/Instance的open_reader以及 DataFrame的to_pandas方法。
推荐使用 MaxFrame DataFrame（从 MaxCompute 表创建）来处理数据，MaxFrame DataFrame数据计算发生在MaxCompute集群，无需拉数据至本地。
MaxFrame相关介绍及使用可参考：https://help.aliyun.com/zh/maxcompute/user-guide/maxframe
'''

import json
import time
import urllib.request
import urllib.error

# DataWorks PyODPS 3 节点中 o 是全局变量，无需手动创建 ODPS 入口
from odps import options
options.tunnel.use_instance_tunnel = True
options.tunnel.limit_instance_tunnel = False

# 获取调度参数
bizdate = args.get('bizdate', '20260519')

# ---------- 配置 ----------
BATCH_API_SIZE = 100       # ip-api.com batch 单次最多 100 个
BATCH_RATE_WAIT = 1.5      # 每批次间隔秒数（留余量避免429）
PRIVATE_PREFIXES = (
    '10.', '192.168.', '172.16.', '172.17.', '172.18.', '172.19.',
    '172.20.', '172.21.', '172.22.', '172.23.', '172.24.', '172.25.',
    '172.26.', '172.27.', '172.28.', '172.29.', '172.30.', '172.31.',
    '127.', '0.', '169.254.', '198.18.', '198.19.',
    '198.51.100.', '203.0.113.', '224.', '240.', '203.0.113.245'
)


def is_private(ip):
    return any(ip.startswith(p) for p in PRIVATE_PREFIXES) or ip == '::1'


# ---------- 1. 查询缺失地理信息的 IP ----------
sql_find = f"""
SELECT DISTINCT o.register_ip
FROM demo_dw.ods_mysql_tang_user_user_info_ri o
LEFT JOIN demo_dw.dim_comm_ip_geo_df g ON o.register_ip = g.reg_ip
WHERE o.register_ip IS NOT NULL
  AND o.register_ip != ''
  AND g.reg_ip IS NULL
"""

print(f"[{bizdate}] Querying ODS for IPs missing geo...")
# 确保表存在
if not o.exist_table('demo_dw.dim_comm_ip_geo_df'):
    o.execute_sql("""
        CREATE TABLE IF NOT EXISTS demo_dw.dim_comm_ip_geo_df (
            reg_ip STRING COMMENT '注册IP地址(IPv4/IPv6)',
            cntry_cd    STRING COMMENT '国家代码',
            prov        STRING COMMENT '省份/地区',
            city        STRING COMMENT '城市'
        )
        COMMENT 'IP地址地理位置映射表-每日增量更新'
        PARTITIONED BY (
            ds STRING NOT NULL COMMENT '分区日期 yyyyMMdd'
        )
    """)
    print(f"[{bizdate}] Created demo_dw.dim_comm_ip_geo_df")

ips = []
try:
    instance = o.execute_sql(sql_find)
    with instance.open_reader(tunnel=True, limit=False) as reader:
        ips = [r[0] for r in reader]
except Exception as e:
    print(f"[{bizdate}] Query failed: {e}")
    ips = []

if not ips:
    print(f"[{bizdate}] No new IPs to resolve, done.")
else:
    total = len(ips)
    print(f"[{bizdate}] Found {total} IPs to resolve")

    # 分离私有IP和公网IP
    private_ips = [ip for ip in ips if is_private(ip)]
    public_ips = [ip for ip in ips if not is_private(ip)]
    print(f"[{bizdate}] Private: {len(private_ips)}, Public: {len(public_ips)}")

    # ---------- 2. 批量调用 ip-api.com 解析公网IP ----------
    geo_data = []

    # 私有 IP 直接标记
    for ip in private_ips:
        geo_data.append((ip, '未知', '未知', '未知'))

    total_batches = (len(public_ips) + BATCH_API_SIZE - 1) // BATCH_API_SIZE
    resolved = 0
    failures = 0
    t0 = time.time()

    for batch_idx in range(total_batches):
        batch_start = batch_idx * BATCH_API_SIZE
        batch_end = min(batch_start + BATCH_API_SIZE, len(public_ips))
        batch = public_ips[batch_start:batch_end]
        batch_num = batch_idx + 1

        success = False
        retries = 0
        while not success and retries < 5:
            try:
                url = 'http://ip-api.com/batch'
                headers = {'Content-Type': 'application/json'}
                data = json.dumps(batch).encode()
                req = urllib.request.Request(url, data=data, headers=headers)
                resp = urllib.request.urlopen(req, timeout=60)
                resp_data = json.loads(resp.read())

                for item in resp_data:
                    ip = item.get('query', '')
                    if item.get('status') == 'success':
                        cntry = item.get('countryCode', '') or '未知'
                        prov = item.get('regionName', '') or '未知'
                        city = item.get('city', '') or '未知'
                        geo_data.append((ip, cntry, prov, city))
                        resolved += 1
                    else:
                        geo_data.append((ip, '未知', '未知', '未知'))
                        failures += 1
                success = True

            except urllib.error.HTTPError as e:
                if e.code == 429:
                    wait = min(5 * (2 ** retries), 60)
                    print(f"  [{batch_num:3d}/{total_batches}] 429 rate limit, waiting {wait}s (retry {retries+1}/5)...")
                    time.sleep(wait)
                    retries += 1
                else:
                    print(f"  [{batch_num:3d}/{total_batches}] HTTP {e.code}, marking {len(batch)} as unknown")
                    for ip in batch:
                        geo_data.append((ip, '未知', '未知', '未知'))
                    success = True
            except Exception as e:
                wait = min(3 * (2 ** retries), 30)
                print(f"  [{batch_num:3d}/{total_batches}] Error: {e}, retrying in {wait}s ({retries+1}/5)...")
                time.sleep(wait)
                retries += 1

        if not success:
            print(f"  [{batch_num:3d}/{total_batches}] FAILED after 5 retries, marking {len(batch)} as unknown")
            for ip in batch:
                geo_data.append((ip, '未知', '未知', '未知'))
            failures += len(batch)

        # 进度打印
        elapsed = time.time() - t0
        speed = (batch_num * BATCH_API_SIZE) / elapsed if elapsed > 0 else 0
        print(f"  [{batch_num:3d}/{total_batches}] {batch_num*100//total_batches:3d}% | "
              f"OK:{resolved} fail:{failures} | {speed:.0f} IP/s", flush=True)

        # 限速
        if batch_idx < total_batches - 1:
            time.sleep(BATCH_RATE_WAIT)

    elapsed = time.time() - t0
    print(f"[{bizdate}] API done: {total} IPs in {elapsed:.0f}s ({total/elapsed:.0f} IP/s)")

    # ---------- 3. 写入 dim_comm_ip_geo_df ----------
    print(f"[{bizdate}] Writing {len(geo_data)} rows to demo_dw.dim_comm_ip_geo_df...")
    insert_batch_size = 50
    for b in range(0, len(geo_data), insert_batch_size):
        batch = geo_data[b:b + insert_batch_size]
        values = []
        for ip, cntry, prov, city in batch:
            esc_ip = ip.replace("'", "\\'")
            esc_cntry = cntry.replace("'", "\\'")
            esc_prov = prov.replace("'", "\\'")
            esc_city = city.replace("'", "\\'")
            values.append(f"('{esc_ip}', '{esc_cntry}', '{esc_prov}', '{esc_city}')")
        insert_sql = f"INSERT INTO TABLE demo_dw.dim_comm_ip_geo_df PARTITION (ds = '{bizdate}') VALUES {','.join(values)}"
        o.execute_sql(insert_sql)
        if (b // insert_batch_size + 1) % 20 == 0:
            print(f"  Written {min(b + insert_batch_size, len(geo_data))}/{len(geo_data)} rows")

    print(f"[{bizdate}] Done. demo_dw.dim_comm_ip_geo_df updated with {len(geo_data)} new IPs.")
