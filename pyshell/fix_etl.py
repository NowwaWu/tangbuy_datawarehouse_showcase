import os

ETL = "/Users/wuyanjun/TangBuyDataWarehouseShowcase/ETL"

fixes = {
    # ---------- wh 仓储履约域修正 ----------
    f"{ETL}/wh/dim_storage_warehouse_df.etl.sql": """-- ============================================================
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
    NVL(name,      '未知')                                           AS wh_nm,
    NULL                                                             AS wh_type_cd,
    NVL(address,   '未知')                                           AS addr,
    NULL                                                             AS contact_nm,
    NULL                                                             AS contact_phn,
    NVL(status,     -1)                                             AS wh_stat,
    NULL                                                             AS is_del,
    create_time                                                       AS crt_time,
    update_time                                                       AS upd_time
FROM ods_mysql_tang_storage_storage_ri;
""",

    f"{ETL}/wh/dim_storage_shop_df.etl.sql": """-- ============================================================
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
    NVL(shop_name,      '未知')                                      AS shop_nm,
    NULL                                                             AS shop_type_cd,
    NULL                                                             AS shop_domain,
    NULL                                                             AS shop_stat,
    create_time                                                       AS crt_time,
    update_time                                                       AS upd_time
FROM ods_mysql_tang_storage_shop_ri;
""",

    # ---------- pay 支付结算域修正 ----------
    f"{ETL}/pay/dim_pay_channel_df.etl.sql": """-- ============================================================
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
    NVL(pay_code, '未知')                                            AS chnl_type_cd,
    CASE WHEN status = 0 THEN 1 ELSE 0 END                           AS chnl_stat,
    CASE WHEN status = 1 THEN 1 ELSE 0 END                           AS is_del,
    create_time                                                       AS crt_time,
    update_time                                                       AS upd_time
FROM ods_mysql_tang_pay_pay_channel_ri;
""",

    f"{ETL}/pay/dim_pay_currency_config_df.etl.sql": """-- ============================================================
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
    NULL                                                             AS chnl_id,
    NVL(currency,  '未知')                                           AS ccy,
    NVL(pay_way,   '未知')                                           AS ccy_nm,
    CASE WHEN status = 0 THEN 1 ELSE 0 END                           AS cfg_stat,
    create_time                                                       AS crt_time,
    update_time                                                       AS upd_time
FROM ods_mysql_tang_pay_pay_currency_config_ri;
""",

    f"{ETL}/pay/dim_pay_exchange_rate_df.etl.sql": """-- ============================================================
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
    NVL(currency,          '未知')                                   AS from_ccy,
    NVL(exchange_currency, '未知')                                   AS to_ccy,
    NVL(rate,              0)                                       AS exch_rate,
    NVL(status,           -1)                                       AS rate_stat,
    NULL                                                              AS crt_time,
    update_time                                                       AS upd_time
FROM ods_mysql_tang_pay_pay_exchange_rate_ri;
""",

    # ---------- dist 分销域修正 ----------
    f"{ETL}/dist/dim_cps_proxy_level_df.etl.sql": """-- ============================================================
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
    NVL(name,         '未知')                                        AS lvl_nm,
    NVL(growth,        0)                                           AS lvl,
    NVL(bkge_scale,    0)                                           AS cmsn_rate,
    CASE WHEN del_flag = 0 THEN 1 ELSE 0 END                         AS lvl_stat,
    NULL                                                              AS crt_time,
    NULL                                                              AS upd_time
FROM ods_mysql_tang_cps_proxy_level_cfg_ri;
""",

    # ---------- usr 用户域修正 ----------
    f"{ETL}/usr/dim_user_member_level_df.etl.sql": """-- ============================================================
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
    NULL                                                             AS lvl,
    NULL                                                             AS growth_low,
    NVL(growth,    0)                                               AS growth_high,
    NULL                                                             AS lvl_stat,
    NULL                                                              AS crt_time,
    NULL                                                              AS upd_time
FROM ods_mysql_tang_user_member_config_ri;
""",
}

for path, content in fixes.items():
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f"✅ fixed: {os.path.basename(os.path.dirname(path))}/{os.path.basename(path)}")

print(f"\n修正完成: {len(fixes)} 个文件")
