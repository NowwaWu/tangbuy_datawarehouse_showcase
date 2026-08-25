# -*- coding: utf-8 -*-
"""
解析 ods 中缺失地理信息的 IP，批量调用 ip-api.com，
输出 dim_comm_ip_geo_df 格式数据。
"""
import json
import time
import urllib.request
import sys
import os

BATCH_SIZE = 100          # ip-api.com batch 最多 100 个 IP
RATE_LIMIT = 45           # 免费版 45 次/分钟
OUTPUT_FILE = '/tmp/ip_geo_result.csv'
INPUT_FILE = '/tmp/missing_ips.txt'

# ---------- 1. 读取 IP 列表 ----------
with open(INPUT_FILE, 'r') as f:
    ips = [line.strip() for line in f if line.strip()]

print(f"Total IPs to resolve: {len(ips)}")

# ---------- 2. 分批解析 ----------
results = []
failures = []
total_batches = (len(ips) + BATCH_SIZE - 1) // BATCH_SIZE

# 私有/内网 IP 前缀
private_prefixes = (
    '10.', '192.168.', '172.16.', '172.17.', '172.18.', '172.19.',
    '172.20.', '172.21.', '172.22.', '172.23.', '172.24.', '172.25.',
    '172.26.', '172.27.', '172.28.', '172.29.', '172.30.', '172.31.',
    '127.', '0.', '169.254.', '100.64.', '100.65.', '100.66.',
    '100.67.', '100.68.', '100.69.', '100.70.', '100.71.', '100.72.',
    '100.73.', '100.74.', '100.75.', '100.76.', '100.77.', '100.78.',
    '100.79.', '100.80.', '100.81.', '100.82.', '100.83.', '100.84.',
    '100.85.', '100.86.', '100.87.', '100.88.', '100.89.', '100.90.',
    '100.91.', '100.92.', '100.93.', '100.94.', '100.95.', '100.96.',
    '100.97.', '100.98.', '100.99.', '100.100.', '100.101.',
    '100.102.', '100.103.', '100.104.', '100.105.', '100.106.',
    '100.107.', '100.108.', '100.109.', '100.110.', '100.111.',
    '100.112.', '100.113.', '100.114.', '100.115.', '100.116.',
    '100.117.', '100.118.', '100.119.', '100.120.', '100.121.',
    '100.122.', '100.123.', '100.124.', '100.125.', '100.126.',
    '100.127.', '198.18.', '198.19.', '198.51.100.', '203.0.113.',
    '224.', '240.', '203.0.113.245'
)

def is_private(ip):
    return any(ip.startswith(p) for p in private_prefixes) or ip == '::1'

def process_ip(ip):
    """返回 (register_ip, cntry_cd, prov, city)"""
    if is_private(ip):
        return (ip, '未知', '未知', '未知')

    try:
        url = f"http://ip-api.com/json/{ip}?fields=countryCode,regionName,city"
        req = urllib.request.Request(url)
        resp = urllib.request.urlopen(req, timeout=10)
        data = json.loads(resp.read())
        cntry = data.get('countryCode', '') or '未知'
        prov = data.get('regionName', '') or '未知'
        city = data.get('city', '') or '未知'
        return (ip, cntry, prov, city)
    except Exception as e:
        return None  # 标记为失败

# 逐批调用 batch 接口
for batch_idx in range(total_batches):
    batch_start = batch_idx * BATCH_SIZE
    batch_end = min(batch_start + BATCH_SIZE, len(ips))
    batch = ips[batch_start:batch_end]

    # 先分离私有 IP
    private_ips = [ip for ip in batch if is_private(ip)]
    public_ips = [ip for ip in batch if not is_private(ip)]

    # 私有 IP 直接标记
    for ip in private_ips:
        results.append((ip, '未知', '未知', '未知'))

    if public_ips:
        try:
            url = 'http://ip-api.com/batch'
            headers = {'Content-Type': 'application/json'}
            data = json.dumps(public_ips).encode()
            req = urllib.request.Request(url, data=data, headers=headers)
            resp = urllib.request.urlopen(req, timeout=30)
            resp_data = json.loads(resp.read())

            for item in resp_data:
                ip = item.get('query', '')
                if item.get('status') == 'success':
                    cntry = item.get('countryCode', '') or '未知'
                    prov = item.get('regionName', '') or '未知'
                    city = item.get('city', '') or '未知'
                    results.append((ip, cntry, prov, city))
                else:
                    # 批量接口中失败的 IP，尝试单独请求
                    fail_ip = item.get('query', public_ips[0])
                    result = process_ip(fail_ip)
                    if result:
                        results.append(result)
                    else:
                        results.append((fail_ip, '未知', '未知', '未知'))
                        failures.append(fail_ip)
        except Exception as e:
            print(f"Batch {batch_idx+1} failed: {e}, retrying individually...")
            # 批量请求失败，逐个重试
            for ip in public_ips:
                result = process_ip(ip)
                if result:
                    results.append(result)
                else:
                    results.append((ip, '未知', '未知', '未知'))
                    failures.append(ip)
                time.sleep(0.1)  # 微调限速

    # 进度输出
    progress = (batch_idx + 1) / total_batches * 100
    print(f"[{batch_idx+1:4d}/{total_batches}] {progress:5.1f}% | resolved: {len(results)} | failures: {len(failures)}", flush=True)

    # 限速: 每个 batch 后等待 ~1.33s (45次/分钟)
    if batch_idx < total_batches - 1:
        time.sleep(1.4)

# ---------- 3. 写入结果 ----------
print(f"\nResolved: {len(results)}, Failed: {len(failures)}")

# 输出 CSV (dim_comm_ip_geo_df 格式)
with open(OUTPUT_FILE, 'w', encoding='utf-8') as f:
    f.write('register_ip,cntry_cd,prov,city\n')
    for ip, cntry, prov, city in results:
        # 转义逗号和引号
        esc_ip = ip.replace('"', '""')
        esc_cntry = cntry.replace('"', '""')
        esc_prov = prov.replace('"', '""')
        esc_city = city.replace('"', '""')
        f.write(f'"{esc_ip}","{esc_cntry}","{esc_prov}","{esc_city}"\n')

print(f"Output saved to {OUTPUT_FILE}")
print(f"Total rows: {len(results)}")

# 输出失败 IP 列表
if failures:
    fail_file = '/tmp/ip_failures.txt'
    with open(fail_file, 'w') as f:
        for ip in failures:
            f.write(ip + '\n')
    print(f"Failed IPs saved to {fail_file}")
