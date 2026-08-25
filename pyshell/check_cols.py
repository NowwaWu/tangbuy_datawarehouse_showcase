import json
BASE = "/Users/wuyanjun/TangBuyDataWarehouseShowcase/table"

def show_cols(fname, tname):
    with open(f"{BASE}/{fname}") as f:
        src = json.load(f)
    if tname in src:
        print(f"\n{tname}:")
        for c in src[tname]['columns']:
            print(f"  {c['name']:30s} {c['type']:15s} {c['comment']}")

show_cols('tang_storage_table.json', 'ods_mysql_tang_storage_storage_ri')
show_cols('tang_storage_table.json', 'ods_mysql_tang_storage_shop_ri')
show_cols('tang_pay_table.json', 'ods_mysql_tang_pay_pay_channel_ri')
show_cols('tang_pay_table.json', 'ods_mysql_tang_pay_pay_currency_config_ri')
show_cols('tang_pay_table.json', 'ods_mysql_tang_pay_pay_exchange_rate_ri')
show_cols('tang_cps_table.json', 'ods_mysql_tang_cps_proxy_level_cfg_ri')
