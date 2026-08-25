from odps import ODPS
import json, os

o = ODPS(os.getenv('ODPS_ACCESS_ID'), os.getenv('ODPS_ACCESS_KEY'), os.getenv('ODPS_PROJECT', 'demo_dw'),
        endpoint=os.getenv('ODPS_ENDPOINT', 'https://maxcompute.example.invalid'))

target_tables = [
    'ods_mysql_tang_cps_b_share_ri',
    'ods_mysql_tang_cps_b_share_detail_ri',
    'ods_mysql_tang_cps_b_share_order_detail_ri',
]

new_schemas = {}
for table_name in target_tables:
    try:
        t = o.get_table(table_name)
        schema_info = {
            "comment": t.comment or "",
            "columns": [],
            "partitions": []
        }
        for col in t.table_schema.columns:
            schema_info["columns"].append({
                "name": col.name,
                "type": str(col.type),
                "comment": col.comment or ""
            })
        if t.table_schema.partitions:
            for p in t.table_schema.partitions:
                schema_info["partitions"].append({
                    "name": p.name,
                    "type": str(p.type),
                    "comment": p.comment or ""
                })
        new_schemas[table_name] = schema_info
        print(f"✅ {table_name} — {len(schema_info['columns'])} 列")
        for c in schema_info['columns']:
            print(f"     {c['name']:30s} {c['type']:15s} {c['comment']}")
    except Exception as e:
        print(f"❌ {table_name} — 失败: {e}")

# 读取现有 tang_cps_table.json
cps_path = "/Users/wuyanjun/TangBuyDataWarehouseShowcase/table/tang_cps_table.json"
with open(cps_path, 'r', encoding='utf-8') as f:
    existing = json.load(f)

print(f"\n现有表数: {len(existing)}")

# 合并
existing.update(new_schemas)

# 写入
with open(cps_path, 'w', encoding='utf-8') as f:
    json.dump(existing, f, ensure_ascii=False, indent=2)

print(f"合并后表数: {len(existing)}")
print(f"新增: {len(new_schemas)} 张表")
