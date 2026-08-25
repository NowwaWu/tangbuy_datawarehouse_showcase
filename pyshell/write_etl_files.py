import os

ETL = "/Users/wuyanjun/TangBuyDataWarehouseShowcase/ETL"

# Each ETL file: (path, sql_content)
etl_files = []

# ==================== store 店铺域 ====================
etl_files.append((f"{ETL}/store/dim_plugin_fulfillment_service_df.etl.sql", """-- ============================================================
-- 数据域:   store (店铺域)
-- 业务过程: store_flfl (履约服务)
-- 表名:     dim_plugin_fulfillment_service_df
-- 表类型:   维度表 (Dimension) - 日全量快照
-- ETL方式:  INSERT OVERWRITE 按日分区全量覆盖
-- 调度变量: ${bizdate} 格式 yyyyMMdd
-- ============================================================
INSERT OVERWRITE TABLE dim_plugin_fulfillment_service_df PARTITION (dt = '${bizdate}')
SELECT
    NVL(fulfillment_service_id, '未知')                                    AS flfl_service_id,
    NVL(shop_name,               '未知')                                    AS shop_nm,
    NVL(location_id,             '未知')                                    AS location_id,
    NVL(handle,                  '未知')                                    AS handle,
    NVL(callback_url,            '未知')                                    AS callback_url,
    NVL(service_name,            '未知')                                    AS service_nm,
    NVL(status,                    -1)                                     AS flfl_stat,
    create_time                                                              AS crt_time,
    update_time                                                              AS upd_time
FROM ods_mysql_tang_plugin_shopify_fulfillment_service_ri;
"""))

# ==================== itm 商品域 ====================
etl_files.append((f"{ETL}/itm/dim_product_item_df.etl.sql", """-- ============================================================
-- 数据域:   itm (商品域)
-- 业务过程: prod_mgr (商品管理)
-- 表名:     dim_product_item_df
-- 表类型:   维度表 (Dimension) - 日全量快照
-- ETL方式:  INSERT OVERWRITE 按日分区全量覆盖
-- 调度变量: ${bizdate} 格式 yyyyMMdd
-- ============================================================
INSERT OVERWRITE TABLE dim_product_item_df PARTITION (dt = '${bizdate}')
SELECT
    id                                                              AS item_id,
    NVL(item_name,      '未知')                                     AS item_nm,
    NVL(item_name_lang, '未知')                                     AS item_nm_cn,
    NVL(images,         '未知')                                     AS imgs,
    NVL(item_mv,        '未知')                                     AS detail,
    NULL                                                            AS origin_item_id,
    NVL(data_source,    '未知')                                     AS data_src,
    NVL(provider_type,  '未知')                                     AS provider_key,
    NVL(status,         -1)                                         AS item_stat,
    NVL(sold_out_flag,   0)                                         AS sales_m,
    NULL                                                            AS invalid_time,
    NULL                                                            AS invalid_cd,
    NULL                                                            AS default_lang,
    NVL(del_flag,        0)                                         AS is_del,
    NULL                                                            AS crt_time,
    update_time                                                      AS upd_time
FROM ods_mysql_tang_product_product_item_ri;
"""))

etl_files.append((f"{ETL}/itm/dim_product_sku_df.etl.sql", """-- ============================================================
-- 数据域:   itm (商品域)
-- 业务过程: sku_mgr (SKU管理)
-- 表名:     dim_product_sku_df
-- 表类型:   维度表 (Dimension) - 日全量快照
-- ETL方式:  INSERT OVERWRITE 按日分区全量覆盖
-- 调度变量: ${bizdate} 格式 yyyyMMdd
-- ============================================================
INSERT OVERWRITE TABLE dim_product_sku_df PARTITION (dt = '${bizdate}')
SELECT
    sku_id,
    NVL(item_id,      -99)                                           AS item_id,
    NVL(sku_code,    '未知')                                         AS sku_cd,
    NVL(price,         0)                                            AS prc,
    NVL(crossed_price, 0)                                            AS cost_prc,
    NVL(inventory,     0)                                            AS inv,
    NVL(sales,         0)                                            AS sales,
    NVL(weight,        0)                                            AS wt,
    NULL                                                             AS vol,
    NVL(attr_json,    '{}')                                          AS attr_json,
    NVL(images,       '未知')                                        AS img,
    NVL(enable_flag,   0)                                            AS sku_stat,
    NVL(del_flag,      0)                                            AS is_del,
    create_time                                                       AS crt_time,
    update_time                                                       AS upd_time
FROM ods_mysql_tang_product_product_sku_ri;
"""))

etl_files.append((f"{ETL}/itm/dim_product_category_df.etl.sql", """-- ============================================================
-- 数据域:   itm (商品域)
-- 业务过程: ctgy_mgr (类目管理)
-- 表名:     dim_product_category_df
-- 表类型:   维度表 (Dimension) - 日全量快照
-- ETL方式:  INSERT OVERWRITE 按日分区全量覆盖
-- 调度变量: ${bizdate} 格式 yyyyMMdd
-- ============================================================
INSERT OVERWRITE TABLE dim_product_category_df PARTITION (dt = '${bizdate}')
SELECT
    id                                                              AS ctgy_id,
    NVL(name,         '未知')                                        AS ctgy_nm,
    NVL(parent_id,     -99)                                          AS parent_id,
    NVL(path,         '未知')                                        AS ancestors,
    NVL(level,          0)                                           AS lvl,
    NVL(leaf,          0)                                            AS is_leaf,
    NVL(logo,         '未知')                                        AS logo,
    NVL(sort,          0)                                            AS sort_num,
    NVL(status,       -1)                                            AS ctgy_stat,
    NVL(deleted,       0)                                            AS is_del,
    create_time                                                       AS crt_time,
    update_time                                                       AS upd_time
FROM ods_mysql_tang_product_product_category_ri;
"""))

etl_files.append((f"{ETL}/itm/dim_product_pallet_df.etl.sql", """-- ============================================================
-- 数据域:   itm (商品域)
-- 业务过程: pallet (货盘管理)
-- 表名:     dim_product_pallet_df
-- 表类型:   维度表 (Dimension) - 日全量快照
-- ETL方式:  INSERT OVERWRITE 按日分区全量覆盖
-- 调度变量: ${bizdate} 格式 yyyyMMdd
-- ============================================================
INSERT OVERWRITE TABLE dim_product_pallet_df PARTITION (dt = '${bizdate}')
SELECT
    id                                                              AS plt_id,
    NVL(name,              '未知')                                   AS plt_nm,
    NVL(pc_banner,         '未知')                                   AS pc_banner,
    NVL(app_banner,        '未知')                                   AS app_banner,
    NVL(status,             -1)                                     AS plt_stat,
    NVL(background_color,  '未知')                                   AS bg_color,
    NULL                                                             AS is_del,
    create_time                                                       AS crt_time,
    update_time                                                       AS upd_time
FROM ods_mysql_tang_product_pallet_ri;
"""))

etl_files.append((f"{ETL}/itm/dim_product_price_template_df.etl.sql", """-- ============================================================
-- 数据域:   itm (商品域)
-- 业务过程: prod_price (商品定价)
-- 表名:     dim_product_price_template_df
-- 表类型:   维度表 (Dimension) - 日全量快照
-- ETL方式:  INSERT OVERWRITE 按日分区全量覆盖
-- 调度变量: ${bizdate} 格式 yyyyMMdd
-- ============================================================
INSERT OVERWRITE TABLE dim_product_price_template_df PARTITION (dt = '${bizdate}')
SELECT
    id                                                              AS tpl_id,
    NVL(name,            '未知')                                     AS tpl_nm,
    NVL(platform,         -1)                                       AS platform,
    NVL(costs,           '{}')                                      AS costs_json,
    NVL(profit,           0)                                        AS prft_rate,
    NVL(status,          -1)                                        AS tpl_stat,
    NVL(shipping,         0)                                        AS is_free_ship,
    NVL(shipping_config, '{}')                                      AS ship_cfg_json,
    NVL(user_id,        -99)                                        AS usr_id,
    create_time                                                       AS crt_time,
    update_time                                                       AS upd_time
FROM ods_mysql_tang_plugin_price_template_ri;
"""))

# ==================== wh 仓储履约域 ====================
etl_files.append((f"{ETL}/wh/dim_storage_warehouse_df.etl.sql", """-- ============================================================
-- 数据域:   wh (仓储履约域)
-- 业务过程: wh_mgr (仓库管理)
-- 表名:     dim_storage_warehouse_df
-- 表类型:   维度表 (Dimension) - 日全量快照
-- ETL方式:  INSERT OVERWRITE 按日分区全量覆盖
-- 调度变量: ${bizdate} 格式 yyyyMMdd
-- ============================================================
INSERT OVERWRITE TABLE dim_storage_warehouse_df PARTITION (dt = '${bizdate}')
SELECT
    id                                                              AS wh_id,
    NVL(name,     '未知')                                           AS wh_nm,
    NVL(type,     '未知')                                           AS wh_type_cd,
    NVL(address,  '未知')                                           AS addr,
    NVL(contact,  '未知')                                           AS contact_nm,
    NVL(phone,    '未知')                                           AS contact_phn,
    NVL(status,    -1)                                             AS wh_stat,
    NVL(del_flag,   0)                                             AS is_del,
    create_time                                                      AS crt_time,
    update_time                                                      AS upd_time
FROM ods_mysql_tang_storage_storage_ri;
"""))

etl_files.append((f"{ETL}/wh/dim_storage_shop_df.etl.sql", """-- ============================================================
-- 数据域:   wh (仓储履约域)
-- 业务过程: wh_mgr (仓库管理)
-- 表名:     dim_storage_shop_df
-- 表类型:   维度表 (Dimension) - 日全量快照
-- ETL方式:  INSERT OVERWRITE 按日分区全量覆盖
-- 调度变量: ${bizdate} 格式 yyyyMMdd
-- ============================================================
INSERT OVERWRITE TABLE dim_storage_shop_df PARTITION (dt = '${bizdate}')
SELECT
    id                                                              AS shop_id,
    NVL(name,      '未知')                                           AS shop_nm,
    NVL(type,      '未知')                                           AS shop_type_cd,
    NVL(domain,    '未知')                                           AS shop_domain,
    NVL(status,     -1)                                             AS shop_stat,
    create_time                                                       AS crt_time,
    update_time                                                       AS upd_time
FROM ods_mysql_tang_storage_shop_ri;
"""))

# ==================== pay 支付结算域 ====================
etl_files.append((f"{ETL}/pay/dim_pay_channel_df.etl.sql", """-- ============================================================
-- 数据域:   pay (支付结算域)
-- 业务过程: pay_channel (支付渠道)
-- 表名:     dim_pay_channel_df
-- 表类型:   维度表 (Dimension) - 日全量快照
-- ETL方式:  INSERT OVERWRITE 按日分区全量覆盖
-- 调度变量: ${bizdate} 格式 yyyyMMdd
-- ============================================================
INSERT OVERWRITE TABLE dim_pay_channel_df PARTITION (dt = '${bizdate}')
SELECT
    id                                                              AS chnl_id,
    NVL(name,     '未知')                                           AS chnl_nm,
    NVL(type,     '未知')                                           AS chnl_type_cd,
    NVL(status,    -1)                                             AS chnl_stat,
    NVL(del_flag,   0)                                             AS is_del,
    create_time                                                      AS crt_time,
    update_time                                                      AS upd_time
FROM ods_mysql_tang_pay_pay_channel_ri;
"""))

etl_files.append((f"{ETL}/pay/dim_pay_currency_config_df.etl.sql", """-- ============================================================
-- 数据域:   pay (支付结算域)
-- 业务过程: pay_channel (支付渠道)
-- 表名:     dim_pay_currency_config_df
-- 表类型:   维度表 (Dimension) - 日全量快照
-- ETL方式:  INSERT OVERWRITE 按日分区全量覆盖
-- 调度变量: ${bizdate} 格式 yyyyMMdd
-- ============================================================
INSERT OVERWRITE TABLE dim_pay_currency_config_df PARTITION (dt = '${bizdate}')
SELECT
    id                                                              AS cfg_id,
    NVL(channel_id,    -99)                                         AS chnl_id,
    NVL(currency,      '未知')                                      AS ccy,
    NVL(currency_name, '未知')                                      AS ccy_nm,
    NVL(status,         -1)                                        AS cfg_stat,
    create_time                                                      AS crt_time,
    update_time                                                      AS upd_time
FROM ods_mysql_tang_pay_pay_currency_config_ri;
"""))

etl_files.append((f"{ETL}/pay/dim_pay_exchange_rate_df.etl.sql", """-- ============================================================
-- 数据域:   pay (支付结算域)
-- 业务过程: exch_rate (汇率管理)
-- 表名:     dim_pay_exchange_rate_df
-- 表类型:   维度表 (Dimension) - 日全量快照
-- ETL方式:  INSERT OVERWRITE 按日分区全量覆盖
-- 调度变量: ${bizdate} 格式 yyyyMMdd
-- ============================================================
INSERT OVERWRITE TABLE dim_pay_exchange_rate_df PARTITION (dt = '${bizdate}')
SELECT
    id                                                              AS rate_id,
    NVL(from_currency,  '未知')                                     AS from_ccy,
    NVL(to_currency,    '未知')                                     AS to_ccy,
    NVL(rate,            0)                                         AS exch_rate,
    NVL(status,         -1)                                        AS rate_stat,
    create_time                                                      AS crt_time,
    update_time                                                      AS upd_time
FROM ods_mysql_tang_pay_pay_exchange_rate_ri;
"""))

# ==================== usr 用户域 ====================
etl_files.append((f"{ETL}/usr/dim_user_info_df.etl.sql", """-- ============================================================
-- 数据域:   usr (用户域)
-- 业务过程: usr_reg (用户注册)
-- 表名:     dim_user_info_df
-- 表类型:   维度表 (Dimension) - 日全量快照
-- ETL方式:  INSERT OVERWRITE 按日分区全量覆盖
-- 调度变量: ${bizdate} 格式 yyyyMMdd
-- ============================================================
INSERT OVERWRITE TABLE dim_user_info_df PARTITION (dt = '${bizdate}')
SELECT
    user_id                                                             AS usr_id,
    NVL(user_name,         '未知')                                      AS usr_nm,
    NVL(nick_name,         '未知')                                      AS nick,
    NVL(email,             '未知')                                      AS email,
    NVL(phone,             '未知')                                      AS phn,
    CASE
        WHEN gender = 0 THEN '男'
        WHEN gender = 1 THEN '女'
        ELSE '未知'
    END                                                                 AS gndr,
    NVL(birthday,          '1970-01-01')                                AS dob,
    NVL(language,          '未知')                                      AS lang,
    NVL(avatar,            '未知')                                      AS img,
    NVL(register_country,  '未知')                                      AS cntry,
    NVL(status,             -1)                                        AS usr_stat,
    NVL(del_flag,           0)                                         AS is_del,
    register_time                                                        AS crt_time,
    update_time                                                          AS upd_time
FROM ods_mysql_tang_user_user_info_ri;
"""))

etl_files.append((f"{ETL}/usr/dim_user_member_level_df.etl.sql", """-- ============================================================
-- 数据域:   usr (用户域)
-- 业务过程: usr_member (会员等级)
-- 表名:     dim_user_member_level_df
-- 表类型:   维度表 (Dimension) - 日全量快照
-- ETL方式:  INSERT OVERWRITE 按日分区全量覆盖
-- 调度变量: ${bizdate} 格式 yyyyMMdd
-- ============================================================
INSERT OVERWRITE TABLE dim_user_member_level_df PARTITION (dt = '${bizdate}')
SELECT
    id                                                              AS lvl_id,
    NVL(level,    '未知')                                           AS lvl_nm,
    CAST(level AS BIGINT)                                           AS lvl,
    NVL(growth,    0)                                              AS growth_low,
    NVL(growth,    0)                                              AS growth_high,
    NULL                                                            AS lvl_stat,
    NULL                                                            AS crt_time,
    NULL                                                            AS upd_time
FROM ods_mysql_tang_user_member_config_ri;
"""))

# ==================== dist 分销域 ====================
etl_files.append((f"{ETL}/dist/dim_cps_proxy_level_df.etl.sql", """-- ============================================================
-- 数据域:   dist (分销域)
-- 业务过程: proxy (推广代理)
-- 表名:     dim_cps_proxy_level_df
-- 表类型:   维度表 (Dimension) - 日全量快照
-- ETL方式:  INSERT OVERWRITE 按日分区全量覆盖
-- 调度变量: ${bizdate} 格式 yyyyMMdd
-- ============================================================
INSERT OVERWRITE TABLE dim_cps_proxy_level_df PARTITION (dt = '${bizdate}')
SELECT
    id                                                              AS lvl_id,
    NVL(name,       '未知')                                         AS lvl_nm,
    NVL(level,       0)                                            AS lvl,
    NVL(commission,   0)                                            AS cmsn_rate,
    NVL(status,     -1)                                            AS lvl_stat,
    create_time                                                      AS crt_time,
    update_time                                                      AS upd_time
FROM ods_mysql_tang_cps_proxy_level_cfg_ri;
"""))

# ==================== comm 公共域 ====================
etl_files.append((f"{ETL}/comm/dim_comm_msg_config_df.etl.sql", """-- ============================================================
-- 数据域:   comm (公共域)
-- 业务过程: msg_cfg (消息配置)
-- 表名:     dim_comm_msg_config_df
-- 表类型:   维度表 (Dimension) - 日全量快照
-- ETL方式:  INSERT OVERWRITE 按日分区全量覆盖
-- 调度变量: ${bizdate} 格式 yyyyMMdd
-- ============================================================
INSERT OVERWRITE TABLE dim_comm_msg_config_df PARTITION (dt = '${bizdate}')
SELECT
    id                                                              AS cfg_id,
    NVL(user_id,  -99)                                             AS usr_id,
    NVL(config,   '{}')                                            AS cfg_json,
    create_time                                                      AS crt_time,
    update_time                                                      AS upd_time
FROM ods_mysql_tang_plugin_msg_config_ri;
"""))

# ===================== 写入 =====================
for path, content in etl_files:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f"✅ {os.path.basename(os.path.dirname(path)):6s} / {os.path.basename(path)}")

print(f"\n总计: {len(etl_files)} 个 ETL 文件")
