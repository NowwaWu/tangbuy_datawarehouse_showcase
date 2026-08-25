import os, re

ETL = "/Users/wuyanjun/TangBuyDataWarehouseShowcase/ETL"

# (old_table, new_table, domain_dir) — tables to rename
renames = [
    # itm domain
    ("dim_plugin_third_product_df",  "dim_itm_third_product_df",   "itm"),
    ("dim_product_category_df",      "dim_itm_category_df",        "itm"),
    ("dim_product_item_df",          "dim_itm_item_df",            "itm"),
    ("dim_product_pallet_df",        "dim_itm_pallet_df",          "itm"),
    ("dim_product_price_template_df","dim_itm_price_template_df",  "itm"),
    ("dim_product_sku_df",           "dim_itm_sku_df",             "itm"),
    # store domain
    ("dim_plugin_store_df",          "dim_store_plugin_df",        "store"),
    # wh domain
    ("dim_storage_shop_df",          "dim_wh_shop_df",             "wh"),
    ("dim_storage_warehouse_df",     "dim_wh_warehouse_df",        "wh"),
    # usr domain
    ("dim_user_info_df",             "dim_usr_info_df",            "usr"),
    # dist domain
    ("dim_cps_proxy_level_df",       "dim_dist_proxy_level_df",    "dist"),
]

count = 0
for old_table, new_table, domain in renames:
    for suffix in [".ddl.sql", ".etl.sql"]:
        old_path = os.path.join(ETL, domain, f"{old_table}{suffix}")
        new_path = os.path.join(ETL, domain, f"{new_table}{suffix}")

        if not os.path.exists(old_path):
            print(f"  ⚠ SKIP: {old_path} 不存在")
            continue

        # Read content
        with open(old_path, 'r', encoding='utf-8') as f:
            content = f.read()

        # Replace all occurrences of old_table with new_table
        new_content = content.replace(old_table, new_table)

        # Write new file
        with open(new_path, 'w', encoding='utf-8') as f:
            f.write(new_content)

        # Remove old file
        os.remove(old_path)

        print(f"  ✅ {domain:6s} {old_table:42s} → {new_table}")
        count += 1

print(f"\n总计重命名: {count} 个文件")
