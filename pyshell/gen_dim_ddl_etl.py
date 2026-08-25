# 维度：店铺履约服务 (store域) - store_flfl
# 来源: ods_mysql_tang_plugin_shopify_fulfillment_service_ri
dim_fulfillment_service_df = {
    'domain': 'store', 'biz_process': 'store_flfl',
    'table': 'dim_plugin_fulfillment_service_df',
    'comment': '店铺履约服务维度表-日全量快照',
    'source': ['ods_mysql_tang_plugin_shopify_fulfillment_service_ri'],
    'cols': [
        ('flfl_service_id', 'STRING', '履约服务ID'),
        ('shop_nm', 'STRING', '店铺名称'),
        ('location_id', 'STRING', '地址ID'),
        ('status', 'BIGINT', '状态: 1-有效, 0-失效'),
        ('handle', 'STRING', '履约服务唯一标识'),
        ('callback_url', 'STRING', '回调URL'),
        ('service_nm', 'STRING', '服务名称'),
        ('crt_time', 'DATETIME', '创建时间'),
        ('upd_time', 'DATETIME', '更新时间'),
    ],
    'etl_single_table': True,
}

# 维度：商品SPU (itm域) - prod_mgr
dim_item_df = {
    'domain': 'itm', 'biz_process': 'prod_mgr',
    'table': 'dim_product_item_df',
    'comment': '商品SPU维度表-日全量快照',
    'source': ['ods_mysql_tang_product_product_item_ri'],
    'cols': [
        ('item_id', 'BIGINT', '商品ID'),
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
    'etl_single_table': True,
}

# 维度：SKU (itm域) - sku_mgr
dim_sku_df = {
    'domain': 'itm', 'biz_process': 'sku_mgr',
    'table': 'dim_product_sku_df',
    'comment': '商品SKU维度表-日全量快照',
    'source': ['ods_mysql_tang_product_product_sku_ri'],
    'cols': [
        ('sku_id', 'BIGINT', 'SKU ID'),
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
    'etl_single_table': True,
}

# 维度：类目 (itm域) - ctgy_mgr
dim_category_df = {
    'domain': 'itm', 'biz_process': 'ctgy_mgr',
    'table': 'dim_product_category_df',
    'comment': '商品类目维度表-日全量快照',
    'source': ['ods_mysql_tang_product_product_category_ri'],
    'cols': [
        ('ctgy_id', 'BIGINT', '类目ID'),
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
    'etl_single_table': True,
}

# 维度：货盘 (itm域) - pallet
dim_pallet_df = {
    'domain': 'itm', 'biz_process': 'pallet',
    'table': 'dim_product_pallet_df',
    'comment': '货盘维度表-日全量快照',
    'source': ['ods_mysql_tang_product_pallet_ri'],
    'cols': [
        ('plt_id', 'BIGINT', '货盘ID'),
        ('plt_nm', 'STRING', '货盘名称'),
        ('pc_banner', 'STRING', 'PC端横幅图'),
        ('app_banner', 'STRING', 'APP端横幅图'),
        ('plt_stat', 'BIGINT', '货盘状态'),
        ('bg_color', 'STRING', '背景色'),
        ('crt_time', 'DATETIME', '创建时间'),
        ('upd_time', 'DATETIME', '更新时间'),
    ],
    'etl_single_table': True,
}

# 维度：价格模板 (itm域) - prod_price
dim_price_template_df = {
    'domain': 'itm', 'biz_process': 'prod_price',
    'table': 'dim_product_price_template_df',
    'comment': '价格模板维度表-日全量快照',
    'source': ['ods_mysql_tang_plugin_price_template_ri'],
    'cols': [
        ('tpl_id', 'BIGINT', '价格模板ID'),
        ('tpl_nm', 'STRING', '模板名称'),
        ('platform', 'BIGINT', '平台: 1-Shopify'),
        ('costs', 'STRING', '成本配置JSON'),
        ('prft_rate', 'DECIMAL(18,4)', '利润率'),
        ('tpl_stat', 'BIGINT', '模板状态: 0-下架, 1-上架'),
        ('is_free_ship', 'BIGINT', '是否包邮: 0-否, 1-是'),
        ('ship_cfg', 'STRING', '配送配置JSON'),
        ('usr_id', 'BIGINT', '用户ID'),
        ('crt_time', 'DATETIME', '创建时间'),
        ('upd_time', 'DATETIME', '更新时间'),
    ],
    'etl_single_table': True,
}

# 维度：仓库 (wh域) - wh_mgr
dim_warehouse_df = {
    'domain': 'wh', 'biz_process': 'wh_mgr',
    'table': 'dim_storage_warehouse_df',
    'comment': '仓库维度表-日全量快照',
    'source': ['ods_mysql_tang_storage_storage_ri'],
    'cols': [
        ('wh_id', 'BIGINT', '仓库ID'),
        ('wh_nm', 'STRING', '仓库名称'),
        ('wh_type', 'STRING', '仓库类型'),
        ('addr', 'STRING', '仓库地址'),
        ('contact_nm', 'STRING', '联系人'),
        ('contact_phn', 'STRING', '联系电话'),
        ('wh_stat', 'BIGINT', '仓库状态'),
        ('is_del', 'BIGINT', '是否删除: 0-否, 1-是'),
        ('crt_time', 'DATETIME', '创建时间'),
        ('upd_time', 'DATETIME', '更新时间'),
    ],
    'etl_single_table': True,
}

# 维度：支付渠道 (pay域) - pay_channel
dim_pay_channel_df = {
    'domain': 'pay', 'biz_process': 'pay_channel',
    'table': 'dim_pay_channel_df',
    'comment': '支付渠道维度表-日全量快照',
    'source': ['ods_mysql_tang_pay_pay_channel_ri'],
    'cols': [
        ('chnl_id', 'BIGINT', '支付渠道ID'),
        ('chnl_nm', 'STRING', '渠道名称'),
        ('chnl_type_cd', 'STRING', '渠道类型枚举'),
        ('chnl_stat', 'BIGINT', '渠道状态'),
        ('is_del', 'BIGINT', '是否删除: 0-否, 1-是'),
        ('crt_time', 'DATETIME', '创建时间'),
        ('upd_time', 'DATETIME', '更新时间'),
    ],
    'etl_single_table': True,
}

# 维度：推广等级 (dist域) - proxy
dim_proxy_level_df = {
    'domain': 'dist', 'biz_process': 'proxy',
    'table': 'dim_cps_proxy_level_df',
    'comment': '推广等级维度表-日全量快照',
    'source': ['ods_mysql_tang_cps_proxy_level_cfg_ri'],
    'cols': [
        ('lvl_id', 'BIGINT', '等级ID'),
        ('lvl_nm', 'STRING', '等级名称'),
        ('lvl', 'BIGINT', '等级值'),
        ('cmsn_rate', 'DECIMAL(18,4)', '佣金比例'),
        ('lvl_stat', 'BIGINT', '等级状态'),
        ('crt_time', 'DATETIME', '创建时间'),
        ('upd_time', 'DATETIME', '更新时间'),
    ],
    'etl_single_table': True,
}

# 维度：用户信息 (usr域) - usr_reg
dim_user_df = {
    'domain': 'usr', 'biz_process': 'usr_reg',
    'table': 'dim_user_info_df',
    'comment': '用户维度表-日全量快照',
    'source': ['ods_mysql_tang_user_user_info_ri'],
    'cols': [
        ('usr_id', 'BIGINT', '用户ID'),
        ('usr_nm', 'STRING', '用户名'),
        ('nick', 'STRING', '昵称'),
        ('email', 'STRING', '邮箱'),
        ('phn', 'STRING', '手机号'),
        ('gndr', 'STRING', '性别'),
        ('dob', 'STRING', '生日'),
        ('lang', 'STRING', '语言偏好'),
        ('img', 'STRING', '头像'),
        ('cntry', 'STRING', '国家'),
        ('usr_stat', 'BIGINT', '用户状态'),
        ('is_del', 'BIGINT', '是否删除: 0-否, 1-是'),
        ('crt_time', 'DATETIME', '注册时间'),
        ('upd_time', 'DATETIME', '更新时间'),
    ],
    'etl_single_table': True,
}

all_dims = [
    dim_fulfillment_service_df, dim_item_df, dim_sku_df, dim_category_df,
    dim_pallet_df, dim_price_template_df, dim_warehouse_df, dim_pay_channel_df,
    dim_proxy_level_df, dim_user_df,
]

print(f'总维度数: {len(all_dims)}')
for d in all_dims:
    print(f"  [{d['domain']}] {d['table']:40s} {d['comment']} ({len(d['cols'])}列) 来源: {','.join([s.split('_')[-3]+'_'+s.split('_')[-2]+'_'+s.split('_')[-1] for s in d['source']])}")
