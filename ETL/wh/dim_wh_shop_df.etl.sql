-- ============================================================
-- 数据域:   wh (仓储履约域)
-- 业务过程: wh_mgr (仓库管理)
-- 表名:     dim_wh_shop_df
-- 表类型:   维度表 (Dimension) - 日全量快照
-- ETL方式:  INSERT OVERWRITE 单表直出
-- 调度变量: ${bizdate} 格式 yyyyMMdd
-- 布尔纠偏: ODS status(1=正常2=禁用) → shop_stat(保留, 语义清晰无需纠偏)
-- ============================================================

INSERT OVERWRITE TABLE dim_wh_shop_df PARTITION (ds = '${bizdate}')
SELECT
    id                                                              AS shop_id,
    merchant_id                                  AS merchant_id,
    shop_name                                AS shop_nm,
    intro                                AS intro,
    first_category_id                                  AS ctgy_id_1,
    second_category_id                                  AS ctgy_id_2,
    cover_img                                AS cover_img,
    app_cover_img                                AS cover_img_app,
    background_img                                AS bg_img,
    logo_img                                AS logo_img,
    concat_user                                AS contact_nm,
    concat_phone                                AS contact_phn,
    online_im                                AS online_im,
    shipping_address_ids                            AS ship_addr_ids,
    shipping_address_names                            AS ship_addr_nms,
    shipping_address_detail                            AS ship_addr_detail,
    return_address_ids                            AS rtn_addr_ids,
    return_address_names                            AS rtn_addr_nms,
    return_address_detail                            AS rtn_addr_detail,
    withdrawal_account                                AS wthd_account,
    customer_notice                                AS customer_notice,
    video_type                                  AS video_type_cd,
    video_url                                AS video_url,
    CAST(creation_time AS DATETIME)                                   AS creation_time,
    status                                  AS shop_stat,
    CAST(create_time AS DATETIME)                                     AS crt_time,
    CAST(update_time AS DATETIME)                                     AS upd_time
FROM ods_mysql_tang_storage_shop_ri;
