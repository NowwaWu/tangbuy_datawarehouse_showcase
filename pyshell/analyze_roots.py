import json
import os
import re
import csv
from io import StringIO

base = "/Users/wuyanjun/TangBuyDataWarehouseShowcase/table"
files = [
    "tang_cps_table.json",
    "tang_order_table.json",
    "tang_pay_table.json",
    "tang_product_table.json",
    "tang_storage_table.json",
]

# ── 1. 读取已有词典 ──
existing_abbr = set()
existing_cn = set()
with open("/Users/wuyanjun/TangBuyDataWarehouseShowcase/data_model/命名词典.md", 'r', encoding='utf-8') as f:
    reader = csv.DictReader(f)
    for row in reader:
        cn = row.get("中文名称", "").strip()
        abbr = row.get("英文缩写", "").strip()
        if cn:
            existing_cn.add(cn)
        if abbr:
            existing_abbr.add(abbr.lower())

# ── 2. 提取所有注释中文词 ──
cn_words = {}
cn_pattern = re.compile(r'[\u4e00-\u9fff]+')
comment_count = 0
for fname in files:
    path = os.path.join(base, fname)
    with open(path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    for tname, schema in data.items():
        for col in schema.get("columns", []):
            comment = col.get("comment", "")
            if comment:
                comment_count += 1
                words = cn_pattern.findall(comment)
                for w in words:
                    if len(w) >= 2:
                        cn_words[w] = cn_words.get(w, 0) + 1

# ── 3. 提取表名级词素 ──
table_words = {}
for fname in files:
    path = os.path.join(base, fname)
    with open(path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    for tname in data.keys():
        stripped = tname.replace("ods_mysql_tang_", "").replace("_ri", "")
        parts = stripped.split("_")
        for p in parts:
            if len(p) >= 2 and not p.isdigit():
                table_words[p] = table_words.get(p, 0) + 1

# ── 4. 提取字段名级词素 ──
col_words_cnt = {}
for fname in files:
    path = os.path.join(base, fname)
    with open(path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    for tname, schema in data.items():
        for col in schema.get("columns", []):
            name = col.get("name", "")
            parts = name.split("_")
            for p in parts:
                if len(p) >= 2 and not p.isdigit():
                    col_words_cnt[p] = col_words_cnt.get(p, 0) + 1

# ── 5. 统计注释中完整短语（用于识别业务概念） ──
all_raw_comments = []
for fname in files:
    path = os.path.join(base, fname)
    with open(path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    for tname, schema in data.items():
        for col in schema.get("columns", []):
            comment = col.get("comment", "").strip()
            if comment:
                all_raw_comments.append(comment)

# ── 6. 输出分析 ──
print(f"=== 已有词典条目: {len(existing_cn)} ===")
print(f"=== 已有缩写: {len(existing_abbr)} ===")
print(f"=== 总注释条数: {comment_count} ===")

# 高频表名词素（可能是领域词）
print(f"\n=== 表名词素（频率） ===")
for w, c in sorted(table_words.items(), key=lambda x: -x[1]):
    print(f"  {w}: {c}")

print(f"\n=== 高频字段词素（Top 60） ===")
for w, c in sorted(col_words_cnt.items(), key=lambda x: -x[1])[:60]:
    print(f"  {w}: {c}")

print(f"\n=== 注释中文词（Top 80） ===")
for w, c in sorted(cn_words.items(), key=lambda x: -x[1])[:80]:
    print(f"  {w}({c})", end="  ")
print()

# ── 7. 列出所有现有缩写用于参照 ──
print(f"\n=== 现有英文缩写列表 ===")
for a in sorted(existing_abbr):
    print(f"  {a}", end="")
print()
