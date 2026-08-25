import json, os, re
from collections import defaultdict

base = "/Users/wuyanjun/TangBuyDataWarehouseShowcase/table"
files = sorted([f for f in os.listdir(base) if f.endswith('.json')])

# domain classification by prefix
domain_map = {
    'cps': 'dist', 'order': 'trd', 'pay': 'pay', 'product': 'itm',
    'plugin': 'mixed', 'storage': 'wh', 'user': 'usr',
}

# read all tables
all_tables = {}
for fname in files:
    path = os.path.join(base, fname)
    with open(path) as f:
        data = json.load(f)
    all_tables.update(data)

# classify each table to domain
domain_tables = defaultdict(list)
for tname, schema in all_tables.items():
    stripped = tname.replace("ods_mysql_tang_", "").replace("_ri", "")
    prefix = stripped.split("_")[0]
    # special handling for plugin tables
    if prefix == 'plugin':
        sub = stripped.replace("plugin_", "")
        if sub.startswith('t_draft_order') or sub.startswith('t_order_'):
            dom = 'trd'
        elif sub.startswith('draft_product') or sub.startswith('draft_sku') or sub.startswith('publish') or sub.startswith('search_product') or sub.startswith('product_') or sub.startswith('third_platform') or sub.startswith('price_template') or sub.startswith('third_part_product'):
            dom = 'itm'
        elif sub.startswith('shopify_store') or sub.startswith('tiktok_store') or sub.startswith('woocommerce_store') or sub.startswith('user_auth_shop') or sub.startswith('shopify_fulfillment') or sub.startswith('shop_fix') or sub.startswith('order_setting') or sub.startswith('order_message') or sub.startswith('plugin_logistic'):
            dom = 'store'
        elif sub.startswith('msg_') or sub.startswith('operate_log') or sub.startswith('admin_biz'):
            dom = 'comm'
        elif sub.startswith('station_letter'):
            dom = 'usr'
        else:
            dom = 'trd'  # fallback: order-related
    else:
        dom = domain_map.get(prefix, 'unknown')
    domain_tables[dom].append((tname, stripped, schema))

print("=== 各域表数 ===")
for dom in sorted(domain_tables.keys()):
    print(f"  {dom}: {len(domain_tables[dom])}")

# extract dimension candidates by domain
# A dimension table typically has: id, name/description fields, status, create_time, update_time
# Fact tables tend to have: metrics (amount, count, etc) + foreign keys to dimensions

for dom in ['store', 'itm', 'trd', 'wh', 'pay', 'usr', 'dist', 'comm']:
    tables = domain_tables.get(dom, [])
    print(f"\n{'='*70}")
    print(f"  数据域: {dom}  ({len(tables)} 张表)")
    print(f"{'='*70}")
    for tname, stripped, schema in tables:
        comment = schema.get('comment', '')
        ncols = len(schema.get('columns', []))
        cols_preview = [c['name'] for c in schema.get('columns', [])[:8]]
        print(f"  [{tname}]  {comment} ({ncols}col)")
        print(f"    首8字段: {', '.join(cols_preview)}")
