--MaxCompute SQL
--********************************************************************--
--author: 吴延俊
--create time: 2026-05-06 16:16:42
-- 数据域:   itm (商品域)
-- 业务过程: prod_mgr (商品管理)
-- 表名:     dim_itm_item_df
-- 表类型:   维度表 (Dimension) - 日全量快照
-- 描述:     商品SPU维度表，整合类目、详情、供应商、平台优选商品信息
-- 来源:     ods_mysql_tang_product_product_item_ri         (商品主表, 31列全量映射)
--           ods_mysql_tang_product_preferred_product_category_ri (平台优选类目 - LEFT JOIN)
--           ods_mysql_tang_product_product_details_ri      (详情 - LEFT JOIN 取最新)
--           ods_mysql_tang_product_product_provider_info_ri(供应商 - LEFT JOIN)
--           ods_mysql_tang_product_preferred_product_ri    (平台优选商品 - LEFT JOIN 取最新)
-- 防膨胀:   splr_info / tb_prod 分别按 provider_key / item_id ROW_NUMBER 取 rn=1
-- 调度周期: 日
--********************************************************************--

with item_detail AS (
    SELECT item_id, detail, description, spec_param,
           product_attributes_json, lang_pack_map_json as lang_pack_json,
           risk_info_json, remark, remark_images
    FROM demo_dw.ods_mysql_tang_product_product_details_ri
)
,tb_prod AS (
    SELECT item_id, owner_name, choice_score, increase_rate,
           suitable_country, owner_time, suggest_sale_price_json,
           CASE WHEN level = 50 THEN 'S'
                WHEN level = 40 THEN 'A'
                WHEN level = 30 THEN 'B'
                WHEN level = 20 THEN 'C'
                ELSE '未知'
           END AS level_nm,
           ROW_NUMBER() OVER(PARTITION BY item_id ORDER BY update_time DESC) AS rn
    FROM demo_dw.ods_mysql_tang_product_preferred_product_ri
)
,splr_info AS (
    SELECT provider_key                                      AS splr_item_key,
           provider_shop_name                                AS splr_nm,
           provider_shop_url                                 AS splr_shop_url,
           provider_shop_logo                                AS splr_logo,
           provider_item_id                                  AS splr_item_id,
           provider_detail_url                               AS splr_detail_url,
           provider_price                                    AS splr_prc,
           provider_max_price                                AS splr_max_prc,
           ROW_NUMBER() OVER(PARTITION BY provider_key ORDER BY update_time DESC) AS rn
    FROM demo_dw.ods_mysql_tang_product_product_provider_info_ri
)

INSERT OVERWRITE TABLE demo_dw.dim_itm_item_df PARTITION (ds = '${bizdate}')
SELECT
    i.id                                                        AS item_id,
    i.item_name                                  AS item_nm,
    i.item_name_lang                              AS item_nm_cn,
    i.images                                    AS imgs,
    i.item_mv                                   AS item_mv,
    i.detail_url                                  AS detail_url,
    d.detail                                  AS detail,
    d.spec_param                                 AS spec_param,
    NVL(d.product_attributes_json,        '{}')                  AS item_attr_json,
    d.description                                  AS item_desc,
    NVL(d.lang_pack_json,                 '{}')                  AS lang_pack_json,
    NVL(d.risk_info_json,                 '{}')                  AS risk_info_json,
    d.remark                                      AS detail_rmk,
    d.remark_images                              AS detail_rmk_imgs,
    NVL(CAST(i.price            AS DECIMAL(18,4)), 0)          AS min_prc,
    NVL(CAST(i.max_price        AS DECIMAL(18,4)), 0)          AS max_prc,
    NVL(CAST(i.crossed_price    AS DECIMAL(18,4)), 0)          AS crossed_prc,
    NVL(CAST(i.post_fee         AS DECIMAL(18,4)), 0)          AS post_fee,
    i.freight_type                              AS freight_type_cd,
    NVL(i.commission_price_config_json,   '{}')                  AS cmsn_prc_cfg_json,
    NVL(i.status,                          -1)                   AS item_stat,
    NVL(i.platform_status,                 -1)                   AS pltf_stat,
    NVL(i.sold_out_flag,                   0)                    AS is_sold_out,
    NVL(i.hot_flag,                        0)                    AS is_hot,
    NVL(i.has_tiered_price,                0)                    AS is_tiered_prc,
    NVL(i.accept_provider_flag,            0)                    AS is_accept_splr_chg,
    NVL(i.assemble_status,                 -1)                   AS item_assemble_stat,
    CAST(i.invalid_time AS DATETIME)                                     AS invalid_time,
    i.data_source                                   AS data_src,
    i.provider_type                                 AS splr_type_cd,
    i.provider_key                                 AS splr_item_key,
    i.provider_info_id                                AS splr_item_info_id,
    p.splr_nm                                      AS splr_nm,
    p.splr_shop_url                                AS splr_shop_url,
    p.splr_logo                                    AS splr_logo,
    p.splr_item_id                                 AS splr_item_id,
    p.splr_detail_url                              AS splr_detail_url,
    NVL(CAST(p.splr_prc     AS DECIMAL(18,4)), 0)          AS splr_prc,
    NVL(CAST(p.splr_max_prc AS DECIMAL(18,4)), 0)          AS splr_max_prc,
    NVL(i.adjust_num,                      0)                    AS adjust_cnt,
   i.category_id                              AS ctgy_id,
    c.name                                 AS ctgy_nm,
    NVL(c.name_lang_json,                 '{}')                  AS ctgy_nm_lang_json,
   c.ancestors                                AS ctgy_path,
    NVL(c.level,                           0)                    AS ctgy_lvl,
    c.parent_id                                      AS parent_ctgy_id,
    NVL(c.leaf_node,                       0)                    AS ctgy_is_leaf,
   c.logo                                 AS ctgy_logo,
    NVL(c.sort_order,                      0)                    AS ctgy_sort_order,
    NVL(c.status,                         -1)                    AS ctgy_stat,
    i.shop_id                                     AS shop_id,
    NVL(i.del_flag,                        0)                    AS is_del,
    NVL(i.version,                         0)                    AS ver,
    CAST(i.create_time AS DATETIME)                                     AS crt_time,
    CAST(i.update_time AS DATETIME)                                     AS upd_time,
    CASE WHEN pp.item_id IS NOT NULL THEN 1 ELSE 0 END                  AS is_tb,
   pp.level_nm                                         AS tb_lvl,
   pp.owner_name                                       AS tb_ownr_nm,
    NVL(pp.choice_score,                           0)                    AS tb_choice_score,
    NVL(CAST(pp.increase_rate AS DECIMAL(18,6)),   0)                    AS tb_incr_rate,
    pp.suitable_country                         AS tb_suit_cntry,
    CAST(pp.owner_time AS DATETIME)                                       AS tb_ownr_time,
    NVL(pp.suggest_sale_price_json,               '{}')                  AS tb_sgst_sale_prc_json
FROM demo_dw.ods_mysql_tang_product_product_item_ri i
LEFT JOIN demo_dw.ods_mysql_tang_product_preferred_product_category_ri c ON i.category_id = c.id
LEFT JOIN splr_info p ON i.provider_key = p.splr_item_key AND p.rn = 1
LEFT JOIN item_detail d ON i.id = d.item_id
LEFT JOIN tb_prod pp ON i.id = pp.item_id AND pp.rn = 1;
