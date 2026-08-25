# -*- coding: utf-8 -*-
"""
使用 ip-api.com 批量接口解析 IP 地理位置。
输出 dim_comm_ip_geo_df 格式: register_ip, cntry_cd, prov, city
特征:
  - 每批 100 个 IP，约 15 分钟完成 67k
  - 增量写入 CSV，断点续传
  - 遇 429 自动退避重试，不降级为单条请求
"""
import json
import time
import urllib.request
import os

BATCH_SIZE = 100
INPUT_FILE = '/tmp/missing_ips.txt'
OUTPUT_FILE = '/tmp/ip_geo_result_v2.csv'
CHECKPOINT_FILE = '/tmp/ip_geo_checkpoint.txt'

# ---------- 1. 读取 IP，确定断点 ----------
with open(INPUT_FILE, 'r') as f:
    ips = [line.strip() for line in f if line.strip()]

total = len(ips)
total_batches = (total + BATCH_SIZE - 1) // BATCH_SIZE

# 断点续传
start_batch = 0
if os.path.exists(CHECKPOINT_FILE):
    with open(CHECKPOINT_FILE) as f:
        start_batch = int(f.read().strip())
    print(f"Resuming from batch {start_batch} (already done: {start_batch * BATCH_SIZE} IPs)")

print(f"Total: {total} IPs, {total_batches} batches, starting from batch {start_batch}")

# ---------- 2. 私有 IP 前缀 ----------
PRIVATE_PREFIXES = (
    '10.', '192.168.', '172.16.', '172.17.', '172.18.', '172.19.',
    '172.20.', '172.21.', '172.22.', '172.23.', '172.24.', '172.25.',
    '172.26.', '172.27.', '172.28.', '172.29.', '172.30.', '172.31.',
    '127.', '0.', '169.254.', '198.18.', '198.19.',
    '198.51.100.', '203.0.113.', '224.', '240.', '203.0.113.245'
)

def is_private(ip):
    return any(ip.startswith(p) for p in PRIVATE_PREFIXES) or ip == '::1'

# ---------- 3. 批量解析 ----------
# 打开输出文件 (append 模式用于续传)
write_header = (start_batch == 0)
mode = 'w' if start_batch == 0 else 'a'
out_f = open(OUTPUT_FILE, mode, encoding='utf-8')
if write_header:
    out_f.write('register_ip,cntry_cd,prov,city\n')
    out_f.flush()

failures = []
resolved = start_batch * BATCH_SIZE
t0 = time.time()

for batch_idx in range(start_batch, total_batches):
    batch_start = batch_idx * BATCH_SIZE
    batch_end = min(batch_start + BATCH_SIZE, total)
    batch = ips[batch_start:batch_end]

    private = [ip for ip in batch if is_private(ip)]
    public  = [ip for ip in batch if not is_private(ip)]

    # 写入私有 IP
    for ip in private:
        out_f.write(f'"{ip}","未知","未知","未知"\n')
        resolved += 1

    # 批量请求 ip-api.com
    if public:
        success = False
        retries = 0
        while not success and retries < 5:
            try:
                url = 'http://ip-api.com/batch'
                headers = {'Content-Type': 'application/json'}
                data = json.dumps(public).encode()
                req = urllib.request.Request(url, data=data, headers=headers)
                resp = urllib.request.urlopen(req, timeout=60)
                resp_data = json.loads(resp.read())

                for item in resp_data:
                    ip = item.get('query', '')
                    if item.get('status') == 'success':
                        cntry = item.get('countryCode', '') or '未知'
                        prov  = item.get('regionName', '') or '未知'
                        city  = item.get('city', '') or '未知'
                    else:
                        cntry, prov, city = '未知', '未知', '未知'
                        failures.append(ip)
                    # 转义
                    esc_ip    = ip.replace('"', '""')
                    esc_cntry = cntry.replace('"', '""')
                    esc_prov  = prov.replace('"', '""')
                    esc_city  = city.replace('"', '""')
                    out_f.write(f'"{esc_ip}","{esc_cntry}","{esc_prov}","{esc_city}"\n')
                    resolved += 1
                out_f.flush()
                success = True

            except urllib.error.HTTPError as e:
                if e.code == 429:
                    wait = min(5 * (2 ** retries), 120)
                    print(f"  Batch {batch_idx+1} 429, waiting {wait}s (retry {retries+1}/5)...", flush=True)
                    time.sleep(wait)
                    retries += 1
                else:
                    print(f"  Batch {batch_idx+1} HTTP {e.code}: {e}, marking as failed", flush=True)
                    for ip in public:
                        out_f.write(f'"{ip}","未知","未知","未知"\n')
                        resolved += 1
                        failures.append(ip)
                    out_f.flush()
                    success = True  # 不再重试
            except Exception as e:
                print(f"  Batch {batch_idx+1} error: {e}, retrying ({retries+1}/5)...", flush=True)
                time.sleep(3)
                retries += 1

            if not success and retries >= 5:
                print(f"  Batch {batch_idx+1} FAILED after 5 retries, marking as unknown", flush=True)
                for ip in public:
                    out_f.write(f'"{ip}","未知","未知","未知"\n')
                    resolved += 1
                    failures.append(ip)
                out_f.flush()

    # 进度 & 限速
    progress = (batch_idx + 1) / total_batches * 100
    elapsed = time.time() - t0
    speed = (resolved - start_batch * BATCH_SIZE) / elapsed if elapsed > 0 else 0
    eta = (total_batches - batch_idx - 1) * 2.0  # rough estimate
    print(f"  [{batch_idx+1:4d}/{total_batches}] {progress:5.1f}% | resolved:{resolved} | fail:{len(failures)} | {speed:.0f} IP/s | ETA {eta:.0f}s", flush=True)

    # 保存断点
    with open(CHECKPOINT_FILE, 'w') as f:
        f.write(str(batch_idx + 1))

    # 限速: 45次/分钟 → 每批 ~1.33s, 用 1.5s 留有余量
    if batch_idx < total_batches - 1:
        time.sleep(1.5)

out_f.close()

# ---------- 4. 收尾 ----------
elapsed = time.time() - t0
print(f"\nDone! {resolved} IPs in {elapsed:.0f}s ({resolved/elapsed:.0f} IP/s)")
print(f"Failures: {len(failures)}")
print(f"Output: {OUTPUT_FILE}")

# 清理断点
if os.path.exists(CHECKPOINT_FILE):
    os.remove(CHECKPOINT_FILE)

# 失败列表
if failures:
    with open('/tmp/ip_geo_failures_v2.txt', 'w') as f:
        for ip in failures:
            f.write(ip + '\n')
    print(f"Failed IPs: /tmp/ip_geo_failures_v2.txt")
