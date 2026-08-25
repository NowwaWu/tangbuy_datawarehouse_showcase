import json
import os
import re

base = "/Users/wuyanjun/TangBuyDataWarehouseShowcase/table"
files = [
    "tang_cps_table.json",
    "tang_order_table.json",
    "tang_pay_table.json",
    "tang_product_table.json",
    "tang_storage_table.json",
]

# ── 1. 提取所有字段名和注释 ──
all_column_names = set()
all_comments = set()
all_table_names = set()

for fname in files:
    path = os.path.join(base, fname)
    with open(path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    for tname, schema in data.items():
        all_table_names.add(tname)
        for col in schema.get("columns", []):
            name = col.get("name", "")
            comment = col.get("comment", "")
            if name:
                all_column_names.add(name)
            if comment:
                all_comments.add(comment)

# ── 2. 统计分析 ──
print(f"=== 表名总数: {len(all_table_names)}")
print(f"=== 字段名总数: {len(all_column_names)}")
print(f"=== 注释总数: {len(all_comments)}")

# ── 3. 提取表名中的词素（按 _ 拆分） ──
table_words = set()
for tn in all_table_names:
    stripped = tn.replace("ods_mysql_tang_", "").replace("_ri", "")
    parts = stripped.split("_")
    for p in parts:
        if len(p) >= 2 and not p.isdigit():
            table_words.add(p)
print(f"\n=== 表名词素（去除了 ods_mysql_tang_ 和 _ri）: {len(table_words)} ===")
for w in sorted(table_words):
    print(f"  {w}")

# ── 4. 提取字段名中的词素 ──
col_words = set()
for col in all_column_names:
    parts = col.split("_")
    for p in parts:
        if len(p) >= 2 and not p.isdigit():
            col_words.add(p)
print(f"\n=== 字段名独立词素: {len(col_words)} ===")
for w in sorted(col_words):
    print(f"  {w}")

# ── 5. 注释中出现的高频中文词 ──
cn_words = {}
cn_pattern = re.compile(r'[\u4e00-\u9fff]+')
for comment in all_comments:
    words = cn_pattern.findall(comment)
    for w in words:
        if len(w) >= 2:
            cn_words[w] = cn_words.get(w, 0) + 1

print(f"\n=== 注释中文词（按频率排序，Top 100） ===")
for w, c in sorted(cn_words.items(), key=lambda x: -x[1])[:100]:
    print(f"  {w}: {c}")
