import json, os

base = "/Users/wuyanjun/TangBuyDataWarehouseShowcase/table"
files = [f for f in os.listdir(base) if f.endswith('.json')]

for fname in sorted(files):
    path = os.path.join(base, fname)
    with open(path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    for tname, schema in data.items():
        stripped = tname.replace("ods_mysql_tang_", "").replace("_ri", "")
        comment = schema.get("comment", "")
        ncols = len(schema.get("columns", []))
        print(f"{stripped:55s} | {ncols:3d}col | {comment}")
