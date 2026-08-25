from odps import ODPS
import json
import os

o = ODPS(os.getenv('ODPS_ACCESS_ID'), os.getenv('ODPS_ACCESS_KEY'), os.getenv('ODPS_PROJECT', 'demo_dw'),
         endpoint=os.getenv('ODPS_ENDPOINT', 'https://maxcompute.example.invalid'))

groups = [
    ('ods_mysql_tang_product', 'tang_product_table.json'),
    ('ods_mysql_tang_storage', 'tang_storage_table.json'),
    ('ods_mysql_tang_pay',     'tang_pay_table.json'),
    ('ods_mysql_tang_cps',     'tang_cps_table.json'),
]

base_path = "/Users/wuyanjun/TangBuyDataWarehouseShowcase/table"

for prefix, filename in groups:
    print(f"\n{'='*60}")
    print(f"正在处理: {prefix}")
    print(f"{'='*60}")

    all_tables = list(o.list_tables(prefix=prefix))
    target_tables = [t.name for t in all_tables if t.name.endswith('_ri')]

    print(f'符合条件的表共 {len(target_tables)} 张，开始获取Schema...')

    table_schemas = {}
    for i, table_name in enumerate(target_tables):
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

            table_schemas[table_name] = schema_info
            print(f"  [{i+1}/{len(target_tables)}] {table_name} - 字段数: {len(schema_info['columns'])}")
        except Exception as e:
            print(f"  [{i+1}/{len(target_tables)}] {table_name} - 失败: {e}")

    output_path = f"{base_path}/{filename}"
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(table_schemas, f, ensure_ascii=False, indent=2)

    print(f"✅ 已保存: {output_path}  ({len(table_schemas)} 张表)")

print(f"\n{'='*60}")
print("全部完成！")
print(f"{'='*60}")
