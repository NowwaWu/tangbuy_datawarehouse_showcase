import json

src = json.load(open("/Users/wuyanjun/TangBuyDataWarehouseShowcase/table/tang_user_table.json"))

tables_to_check = [
    "ods_mysql_tang_user_user_info_ext_ri",
    "ods_mysql_tang_user_user_watermark_info_ri",
    "ods_mysql_tang_user_user_device_ri",
    "ods_mysql_tang_user_user_tags_ri",
    "ods_mysql_tang_user_user_address_ri",
    "ods_mysql_tang_user_member_config_ri",
]

for tname in tables_to_check:
    t = src.get(tname)
    if not t:
        print(f"{tname}: NOT FOUND")
        continue
    print(f"\n--- {tname} ({len(t['columns'])}col) ---")
    for c in t['columns']:
        print(f"  {c['name']:30s} {c['type']:15s} {c['comment']}")
