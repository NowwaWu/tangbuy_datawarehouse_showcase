import csv

existing_cn = set()
existing_abbr = set()
with open("/Users/wuyanjun/TangBuyDataWarehouseShowcase/data_model/数据标准/命名词典.md", encoding='utf-8') as f:
    for row in csv.DictReader(f):
        existing_cn.add(row['中文名称'])
        existing_abbr.add(row['英文缩写'])

new_terms = [
    ('持有人/持有者', 'holder', 'hldr'),
    ('妥投/送达', 'delivery', 'dly'),
    ('实际', 'actual', 'actl'),
    ('补款/额外', 'extra', 'xtra'),
    ('主体', 'entity', 'ety'),
    ('短链接', 'short', 'short'),
]

print('=== 检查结果 ===')
add_list = []
for cn, en, abbr in new_terms:
    if abbr in existing_abbr:
        print(f'  ⏭ [{abbr}] {cn} — 缩写已存在')
    elif cn.split('/')[0] in {x.split('/')[0] for x in existing_cn}:
        print(f'  ⏭ [{abbr}] {cn} — 中文概念已存在')
    else:
        print(f'  ✅ 新增 [{abbr}] {cn} ({en})')
        add_list.append((cn, en, abbr))

print(f'\n待添加: {len(add_list)} 条')
for cn, en, abbr in add_list:
    print(f'  {cn},{en},{abbr}')
