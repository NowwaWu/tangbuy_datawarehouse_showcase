import os, json

base_etl = "/Users/wuyanjun/TangBuyDataWarehouseShowcase/ETL"
base_table = "/Users/wuyanjun/TangBuyDataWarehouseShowcase/table"

# ===================== 维度定义 =====================
# Each dim: (domain, biz_process, table_name, comment, [source_table_keys], [(col_name, col_type, col_comment)], sql_override=None)

dimensions = [
    # ========== store 店铺域 ==========
    {
        'domain': 'store', 'biz_process': 'store_flfl',
        'table': 'dim_plugin_fulfillment_service_df',
        'comment': '店铺履约服务维度表-日全量快照',
        'source_tables': ['ods_mysql_tang_plugin_shopify_fulfillment_service_ri'],
        'cols': [
            ('flfl_service_id', 'STRING', '履约服务ID（自然键）'),
            ('shop_nm', 'STRING', '店铺名称'),
            ('location_id', 'STRING', '地址ID'),
            ('handle', 'STRING', '履约服务唯一标识'),
            ('callback_url', 'STRING', '回调URL'),
            ('service_nm', 'STRING', '服务名称'),
            ('flfl_stat', 'BIGINT', '履约服务状态: 0-失效, 1-有效'),
            ('crt_time', 'DATETIME', '创建时间'),
            ('upd_time', 'DATETIME', '更新时间'),
        ],
    },
    # ========== itm 商品域 ==========
    {
        'domain': 'itm', 'biz_process': 'prod_mgr',
        'table': 'dim_product_item_df',
        'comment': '商品SPU维度表-日全量快照',
        'source_tables': ['ods_mysql_tang_product_product_item_ri'],
        'cols': [
            ('item_id', 'BIGINT', '商品ID（自然键）'),
            ('item_nm', 'STRING', '商品名称'),
            ('item_nm_cn', 'STRING', '商品中文名称'),
            ('imgs', 'STRING', '商品图片'),
            ('detail', 'STRING', '商品详情'),
            ('origin_item_id', 'BIGINT', '原始商品ID'),
            ('data_src', 'STRING', '数据来源'),
            ('provider_key', 'STRING', '供应商标识'),
            ('item_stat', 'BIGINT', '商品状态'),
            ('sales_m', 'BIGINT', '30日销量'),
            ('invalid_time', 'DATETIME', '下架时间'),
            ('invalid_cd', 'STRING', '下架原因编码'),
            ('default_lang', 'STRING', '默认语言'),
            ('is_del', 'BIGINT', '是否删除: 0-否, 1-是'),
            ('crt_time', 'DATETIME', '创建时间'),
            ('upd_time', 'DATETIME', '更新时间'),
        ],
    },
    {
        'domain': 'itm', 'biz_process': 'sku_mgr',
        'table': 'dim_product_sku_df',
        'comment': '商品SKU维度表-日全量快照',
        'source_tables': ['ods_mysql_tang_product_product_sku_ri'],
        'cols': [
            ('sku_id', 'BIGINT', 'SKU ID（自然键）'),
            ('item_id', 'BIGINT', '关联商品ID'),
            ('sku_cd', 'STRING', 'SKU编码'),
            ('prc', 'DECIMAL(18,4)', '价格'),
            ('cost_prc', 'DECIMAL(18,4)', '成本价'),
            ('inv', 'BIGINT', '库存数量'),
            ('sales', 'BIGINT', '实际销量'),
            ('wt', 'DECIMAL(18,6)', '重量'),
            ('vol', 'DECIMAL(18,6)', '体积'),
            ('attr_json', 'STRING', '属性JSON'),
            ('img', 'STRING', 'SKU图片'),
            ('sku_stat', 'BIGINT', 'SKU状态: 0-禁用, 1-启用'),
            ('is_del', 'BIGINT', '是否删除: 0-否, 1-是'),
            ('crt_time', 'DATETIME', '创建时间'),
            ('upd_time', 'DATETIME', '更新时间'),
        ],
    },
    {
        'domain': 'itm', 'biz_process': 'ctgy_mgr',
        'table': 'dim_product_category_df',
        'comment': '商品类目维度表-日全量快照',
        'source_tables': ['ods_mysql_tang_product_product_category_ri'],
        'cols': [
            ('ctgy_id', 'BIGINT', '类目ID（自然键）'),
            ('ctgy_nm', 'STRING', '类目名称'),
            ('parent_id', 'BIGINT', '父类目ID'),
            ('ancestors', 'STRING', '祖先类目路径'),
            ('lvl', 'BIGINT', '类目层级'),
            ('is_leaf', 'BIGINT', '是否叶子节点: 0-否, 1-是'),
            ('logo', 'STRING', '类目图标'),
            ('sort_num', 'BIGINT', '排序号'),
            ('ctgy_stat', 'BIGINT', '类目状态'),
            ('is_del', 'BIGINT', '是否删除: 0-否, 1-是'),
            ('crt_time', 'DATETIME', '创建时间'),
            ('upd_time', 'DATETIME', '更新时间'),
        ],
    },
    {
        'domain': 'itm', 'biz_process': 'pallet',
        'table': 'dim_product_pallet_df',
        'comment': '货盘维度表-日全量快照',
        'source_tables': ['ods_mysql_tang_product_pallet_ri'],
        'cols': [
            ('plt_id', 'BIGINT', '货盘ID（自然键）'),
            ('plt_nm', 'STRING', '货盘名称'),
            ('pc_banner', 'STRING', 'PC端横幅图'),
            ('app_banner', 'STRING', 'APP端横幅图'),
            ('plt_stat', 'BIGINT', '货盘状态'),
            ('bg_color', 'STRING', '背景色'),
            ('is_del', 'BIGINT', '是否删除: 0-否, 1-是'),
            ('crt_time', 'DATETIME', '创建时间'),
            ('upd_time', 'DATETIME', '更新时间'),
        ],
    },
    {
        'domain': 'itm', 'biz_process': 'prod_price',
        'table': 'dim_product_price_template_df',
        'comment': '价格模板维度表-日全量快照',
        'source_tables': ['ods_mysql_tang_plugin_price_template_ri'],
        'cols': [
            ('tpl_id', 'BIGINT', '价格模板ID（自然键）'),
            ('tpl_nm', 'STRING', '模板名称'),
            ('platform', 'BIGINT', '平台: 1-Shopify'),
            ('costs_json', 'STRING', '成本配置JSON'),
            ('prft_rate', 'DECIMAL(18,4)', '利润率'),
            ('tpl_stat', 'BIGINT', '模板状态: 0-下架, 1-上架'),
            ('is_free_ship', 'BIGINT', '是否包邮: 0-否, 1-是'),
            ('ship_cfg_json', 'STRING', '配送配置JSON'),
            ('usr_id', 'BIGINT', '用户ID'),
            ('crt_time', 'DATETIME', '创建时间'),
            ('upd_time', 'DATETIME', '更新时间'),
        ],
    },
    # ========== wh 仓储履约域 ==========
    {
        'domain': 'wh', 'biz_process': 'wh_mgr',
        'table': 'dim_storage_warehouse_df',
        'comment': '仓库维度表-日全量快照',
        'source_tables': ['ods_mysql_tang_storage_storage_ri'],
        'cols': [
            ('wh_id', 'BIGINT', '仓库ID（自然键）'),
            ('wh_nm', 'STRING', '仓库名称'),
            ('wh_type_cd', 'STRING', '仓库类型枚举'),
            ('addr', 'STRING', '仓库地址'),
            ('contact_nm', 'STRING', '联系人'),
            ('contact_phn', 'STRING', '联系电话'),
            ('wh_stat', 'BIGINT', '仓库状态'),
            ('is_del', 'BIGINT', '是否删除: 0-否, 1-是'),
            ('crt_time', 'DATETIME', '创建时间'),
            ('upd_time', 'DATETIME', '更新时间'),
        ],
    },
    {
        'domain': 'wh', 'biz_process': 'wh_mgr',
        'table': 'dim_storage_shop_df',
        'comment': '仓储店铺维度表-日全量快照',
        'source_tables': ['ods_mysql_tang_storage_shop_ri'],
        'cols': [
            ('shop_id', 'BIGINT', '仓储店铺ID（自然键）'),
            ('shop_nm', 'STRING', '店铺名称'),
            ('shop_type_cd', 'STRING', '店铺类型枚举'),
            ('shop_domain', 'STRING', '店铺域名'),
            ('shop_stat', 'BIGINT', '店铺状态'),
            ('crt_time', 'DATETIME', '创建时间'),
            ('upd_time', 'DATETIME', '更新时间'),
        ],
    },
    # ========== pay 支付结算域 ==========
    {
        'domain': 'pay', 'biz_process': 'pay_channel',
        'table': 'dim_pay_channel_df',
        'comment': '支付渠道维度表-日全量快照',
        'source_tables': ['ods_mysql_tang_pay_pay_channel_ri'],
        'cols': [
            ('chnl_id', 'BIGINT', '支付渠道ID（自然键）'),
            ('chnl_nm', 'STRING', '渠道名称'),
            ('chnl_type_cd', 'STRING', '渠道类型枚举'),
            ('chnl_stat', 'BIGINT', '渠道状态'),
            ('is_del', 'BIGINT', '是否删除: 0-否, 1-是'),
            ('crt_time', 'DATETIME', '创建时间'),
            ('upd_time', 'DATETIME', '更新时间'),
        ],
    },
    {
        'domain': 'pay', 'biz_process': 'pay_channel',
        'table': 'dim_pay_currency_config_df',
        'comment': '支付渠道币种配置维度表-日全量快照',
        'source_tables': ['ods_mysql_tang_pay_pay_currency_config_ri'],
        'cols': [
            ('cfg_id', 'BIGINT', '配置ID（自然键）'),
            ('chnl_id', 'BIGINT', '支付渠道ID'),
            ('ccy', 'STRING', '币种代码'),
            ('ccy_nm', 'STRING', '币种名称'),
            ('cfg_stat', 'BIGINT', '配置状态'),
            ('crt_time', 'DATETIME', '创建时间'),
            ('upd_time', 'DATETIME', '更新时间'),
        ],
    },
    {
        'domain': 'pay', 'biz_process': 'exch_rate',
        'table': 'dim_pay_exchange_rate_df',
        'comment': '汇率配置维度表-日全量快照',
        'source_tables': ['ods_mysql_tang_pay_pay_exchange_rate_ri'],
        'cols': [
            ('rate_id', 'BIGINT', '汇率ID（自然键）'),
            ('from_ccy', 'STRING', '来源币种'),
            ('to_ccy', 'STRING', '目标币种'),
            ('exch_rate', 'DECIMAL(18,6)', '汇率值'),
            ('rate_stat', 'BIGINT', '汇率状态'),
            ('crt_time', 'DATETIME', '创建时间'),
            ('upd_time', 'DATETIME', '更新时间'),
        ],
    },
    # ========== usr 用户域 ==========
    {
        'domain': 'usr', 'biz_process': 'usr_reg',
        'table': 'dim_user_info_df',
        'comment': '用户维度表-日全量快照',
        'source_tables': ['ods_mysql_tang_user_user_info_ri'],
        'cols': [
            ('usr_id', 'BIGINT', '用户ID（自然键）'),
            ('usr_nm', 'STRING', '用户名'),
            ('nick', 'STRING', '昵称'),
            ('email', 'STRING', '邮箱'),
            ('phn', 'STRING', '手机号'),
            ('gndr', 'STRING', '性别'),
            ('dob', 'STRING', '生日'),
            ('lang', 'STRING', '语言偏好'),
            ('img', 'STRING', '头像'),
            ('cntry', 'STRING', '国家'),
            ('usr_stat', 'BIGINT', '用户状态: 0-禁用, 1-正常'),
            ('is_del', 'BIGINT', '是否删除: 0-否, 1-是'),
            ('crt_time', 'DATETIME', '注册时间'),
            ('upd_time', 'DATETIME', '更新时间'),
        ],
    },
    {
        'domain': 'usr', 'biz_process': 'usr_member',
        'table': 'dim_user_member_level_df',
        'comment': '会员等级维度表-日全量快照',
        'source_tables': ['ods_mysql_tang_user_member_config_ri'],
        'cols': [
            ('lvl_id', 'BIGINT', '等级ID（自然键）'),
            ('lvl_nm', 'STRING', '等级名称'),
            ('lvl', 'BIGINT', '等级值'),
            ('growth_low', 'BIGINT', '成长值下限'),
            ('growth_high', 'BIGINT', '成长值上限'),
            ('lvl_stat', 'BIGINT', '等级状态'),
            ('crt_time', 'DATETIME', '创建时间'),
            ('upd_time', 'DATETIME', '更新时间'),
        ],
    },
    # ========== dist 分销域 ==========
    {
        'domain': 'dist', 'biz_process': 'proxy',
        'table': 'dim_cps_proxy_level_df',
        'comment': '推广等级维度表-日全量快照',
        'source_tables': ['ods_mysql_tang_cps_proxy_level_cfg_ri'],
        'cols': [
            ('lvl_id', 'BIGINT', '等级ID（自然键）'),
            ('lvl_nm', 'STRING', '等级名称'),
            ('lvl', 'BIGINT', '等级值'),
            ('cmsn_rate', 'DECIMAL(18,4)', '佣金比例'),
            ('lvl_stat', 'BIGINT', '等级状态'),
            ('crt_time', 'DATETIME', '创建时间'),
            ('upd_time', 'DATETIME', '更新时间'),
        ],
    },
    # ========== comm 公共域 ==========
    {
        'domain': 'comm', 'biz_process': 'msg_cfg',
        'table': 'dim_comm_msg_config_df',
        'comment': '消息配置维度表-日全量快照',
        'source_tables': ['ods_mysql_tang_plugin_msg_config_ri'],
        'cols': [
            ('cfg_id', 'BIGINT', '配置ID（自然键）'),
            ('usr_id', 'BIGINT', '用户ID'),
            ('cfg_json', 'STRING', '配置内容JSON'),
            ('crt_time', 'DATETIME', '创建时间'),
            ('upd_time', 'DATETIME', '更新时间'),
        ],
    },
]

# ===================== 生成函数 =====================

def make_ddl(dim):
    lines = []
    lines.append("-- " + "=" * 60)
    lines.append(f"-- 数据域:   {dim['domain']} ({domain_names.get(dim['domain'], '')})")
    lines.append(f"-- 业务过程: {dim['biz_process']}")
    lines.append(f"-- 表名:     {dim['table']}")
    lines.append(f"-- 表类型:   维度表 (Dimension) - 日全量快照")
    lines.append(f"-- 描述:     {dim['comment']}")
    for i, s in enumerate(dim['source_tables']):
        lines.append(f"-- 来源{' (UNION)' if i>0 else '':}     {s}")
    lines.append("-- 调度周期: 日")
    lines.append("-- " + "=" * 60)
    lines.append("")
    lines.append(f"CREATE TABLE IF NOT EXISTS {dim['table']} (")

    max_name = max(len(c[0]) for c in dim['cols']) + 2
    max_type = max(len(c[1]) for c in dim['cols']) + 2
    for i, (col_name, col_type, col_comment) in enumerate(dim['cols']):
        suffix = ',' if i < len(dim['cols']) - 1 else ''
        lines.append(f"    {col_name:<{max_name}} {col_type:<{max_type}} COMMENT '{col_comment}'{suffix}")

    lines.append(")")
    lines.append(f"COMMENT '{dim['comment']}'")
    lines.append("PARTITIONED BY (dt STRING COMMENT '分区日期 yyyyMMdd')")
    lines.append("LIFECYCLE 365;")
    return '\n'.join(lines)

def make_etl(dim):
    lines = []
    lines.append("-- " + "=" * 60)
    lines.append(f"-- 数据域:   {dim['domain']} ({domain_names.get(dim['domain'], '')})")
    lines.append(f"-- 业务过程: {dim['biz_process']}")
    lines.append(f"-- 表名:     {dim['table']}")
    lines.append(f"-- 表类型:   维度表 (Dimension) - 日全量快照")
    lines.append(f"-- ETL方式:  INSERT OVERWRITE 按日分区全量覆盖")
    lines.append(f"-- 调度变量: ${{bizdate}} 格式 yyyyMMdd")
    lines.append("-- " + "=" * 60)
    lines.append(f"INSERT OVERWRITE TABLE {dim['table']} PARTITION (dt = '${{bizdate}}')")

    # generate the etl sql
    if len(dim['source_tables']) == 1:
        # single source
        src = dim['source_tables'][0]
        lines.append("SELECT")
        # get actual column names from source
        col_names = []
        nvl_map = build_nvl_map(dim)
        for col_name, col_type, _ in dim['cols']:
            src_col = nvl_map.get(col_name, col_name)
            col_names.append((col_name, src_col, col_type))
        max_alias = max(len(c[0]) for c in col_names) + 4
        for i, (dim_col, src_col, col_type) in enumerate(col_names):
            suffix = ',' if i < len(col_names) - 1 else ''
            if 'CAST' in src_col or 'NVL' in src_col:
                lines.append(f"    {src_col:<{max_alias}} AS {dim_col}{suffix}")
            elif src_col == dim_col:
                lines.append(f"    {src_col}{suffix}")
            else:
                lines.append(f"    {src_col:<{max_alias}} AS {dim_col}{suffix}")
        lines.append(f"FROM {src};")
    else:
        # union
        lines.append("SELECT")
        # apply NVL at outer layer
        for i, (col_name, col_type, _) in enumerate(dim['cols']):
            suffix = ',' if i < len(dim['cols']) - 1 else ''
            nvl_expr = get_nvl_expr(col_name, col_type)
            if nvl_expr:
                lines.append(f"    NVL({col_name}, {nvl_expr}){' ' * max(2, 45-len(col_name)-len(nvl_expr))} AS {col_name}{suffix}")
            else:
                lines.append(f"    {col_name}{suffix}")
        lines.append("FROM (")
        for si, src in enumerate(dim['source_tables']):
            if si > 0:
                lines.append("")
                lines.append("    UNION ALL")
                lines.append("")
            lines.append(f"    -- {src}")
            lines.append("    SELECT")
            src_cols = build_src_cols(dim, src, si)
            for i, (dim_col, expr, col_type) in enumerate(src_cols):
                suffix = ',' if i < len(src_cols) - 1 else ''
                if expr is None:
                    lines.append(f"        NULL{' ' * max(2, 50 - len(dim_col))} AS {dim_col}{suffix}")
                elif expr == dim_col:
                    lines.append(f"        {dim_col}{suffix}")
                else:
                    lines.append(f"        {expr:<50} AS {dim_col}{suffix}")
            lines.append(f"    FROM {src}")
        lines.append(") t;")
    return '\n'.join(lines)


domain_names = {
    'trd': '交易域', 'itm': '商品域', 'wh': '仓储履约域', 'pay': '支付结算域',
    'usr': '用户域', 'store': '店铺域', 'dist': '分销域', 'comm': '公共域'
}

def build_nvl_map(dim):
    mapping = {}
    for col_name, col_type, _ in dim['cols']:
        if 'CAST' in col_name or 'NVL' in col_name:
            mapping[col_name] = col_name
        else:
            mapping[col_name] = col_name
    return mapping

def get_nvl_expr(col_name, col_type):
    if 'DATETIME' in col_type.upper():
        return 'NULL'
    elif 'DECIMAL' in col_type.upper():
        return "0"
    elif 'BIGINT' in col_type.upper():
        if 'is_' in col_name:
            return '0'
        if 'stat' in col_name:
            return '-1'
        if '_id' in col_name or col_name.endswith('_num') or col_name in ('parent_id',):
            return '-99'
        return '0'
    elif 'STRING' in col_type.upper():
        if 'json' in col_name:
            return "'{}'"
        return "'未知'"
    return 'NULL'

def build_src_cols(dim, src, si):
    # simple: just map dim cols to src cols with same name, null for missing
    with open(f"{base_table}/tang_{dim['domain']}_table.json" if dim['domain'] not in ('store','comm') else (
        f"{base_table}/tang_plugin_table.json" if dim['domain'] in ('store','comm') else f"{base_table}/tang_{dim['domain']}_table.json"), 'r') as f:
        all_data = json.load(f)
    # try to find src table
    src_schema = None
    for tname in all_data:
        if src in tname or tname in src:
            src_schema = all_data[tname]
            break
    if not src_schema:
        for tname in all_data:
            if any(s in tname for s in [src.replace('ods_mysql_tang_','').replace('_ri','')]):
                src_schema = all_data[tname]
                break
    src_col_names = set()
    if src_schema:
        for c in src_schema['columns']:
            src_col_names.add(c['name'])

    result = []
    for col_name, col_type, _ in dim['cols']:
        if col_name in src_col_names:
            result.append((col_name, col_name, col_type))
        else:
            # try to find matching source column
            found = None
            for sc in src_col_names:
                if sc.replace('_','') == col_name.replace('_',''):
                    found = sc
                    break
            if found:
                result.append((col_name, found, col_type))
            else:
                result.append((col_name, None, col_type))
    return result


# ===================== 主逻辑 =====================

domain_dirs = {}
for dim in dimensions:
    dom = dim['domain']
    ddir = os.path.join(base_etl, dom)
    if dom not in domain_dirs:
        os.makedirs(ddir, exist_ok=True)
        domain_dirs[dom] = ddir

    ddl_path = os.path.join(ddir, f"{dim['table']}.ddl.sql")
    etl_path = os.path.join(ddir, f"{dim['table']}.etl.sql")

    with open(ddl_path, 'w', encoding='utf-8') as f:
        f.write(make_ddl(dim))
    with open(etl_path, 'w', encoding='utf-8') as f:
        f.write(make_etl(dim))

    print(f"✅ [{dim['domain']:5s} | {dim['biz_process']:15s}] {dim['table']:45s} ({len(dim['cols'])}列)")

print(f"\n总计: {len(dimensions)} 张维度表")
print(f"数据域目录: {len(domain_dirs)} 个")
