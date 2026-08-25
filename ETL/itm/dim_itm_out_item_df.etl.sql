--@exclude_output=Tang_Data_Warehouse.dim_itm_out_item_df
--MaxCompute SQL
--********************************************************************--
--author: 吴延俊
--create time: 2026-04-29 18:43:01
-- 数据域:   itm (商品域)
-- 业务过程: out_prod (外部商品库)
-- 表名:     dim_itm_out_item_df
-- 表类型:   维度表 (Dimension) - 日全量快照
-- 描述:     三方平台商品维度表，记录从 Shopify / TikTok / WooCommerce 等外部平台采集的商品主数据
-- 来源:     ods_mysql_tang_plugin_third_platform_product_ri
--           ods_mysql_tang_plugin_shopify_store_auth_ri (用于 Shopify 商品链接拼接店铺域名)
-- 调度周期: 日
--********************************************************************--
WITH ranked_pub_rec AS 
(
    SELECT  publish_product_id
            ,product_id AS item_id
            ,data_source
            ,provider_key
            ,confirm_status
            ,ROW_NUMBER() OVER (PARTITION BY publish_product_id ORDER BY update_time DESC,create_time DESC,id DESC ) AS rn
    FROM    demo_dw.ods_mysql_tang_plugin_publish_product_records_ri
    WHERE   publish_product_id IS NOT NULL
    AND     publish_product_id <> ''
)
,dedup_pub_rec AS 
(
    SELECT  publish_product_id
            ,item_id
            ,data_source AS pub_src
            ,provider_key AS splr_key
            ,confirm_status AS cfm_stat
    FROM    ranked_pub_rec
    WHERE   rn = 1
)
INSERT OVERWRITE TABLE demo_dw.dim_itm_out_item_df PARTITION (ds = '${bizdate}')
SELECT  id AS out_item_dim_id
        ,draft_id
        ,unique_key
        ,third_platform_item_name AS item_nm
        ,third_platform_item_id AS item_id
        ,NVL(p.item_id,-1) AS tb_item_id
        ,NVL(p.pub_src,'') AS pub_src
        ,NVL(p.splr_key,'') AS splr_key
        ,NVL(p.cfm_stat,-1) AS cfm_stat
        ,third_platform_graphql_api_id AS graphql_api_id
        ,third_platform_item_status AS item_stat_cd
        ,CAST(third_platform_shop_id AS BIGINT) AS shop_id
        ,third_platform_shop_name AS shop_nm
        ,third_shop_platform AS shop_pltf_cd
        ,description AS item_desc
        ,NVL(attribute_json,'{}') AS attr_json
        ,images AS imgs
        ,NVL(relation_status,-1) AS rel_stat
        ,NVL(CAST(min_price AS DECIMAL(18,4)),0) AS min_prc
        ,NVL(CAST(max_price AS DECIMAL(18,4)),0) AS max_prc
        ,NVL(CAST(min_weight AS DECIMAL(18,4)),0) AS min_wt
        ,NVL(CAST(max_weight AS DECIMAL(18,4)),0) AS max_wt
        ,NVL(inventory,0) AS inv
        ,NVL(sales_m,0) AS sales_cnt_30d
        ,NVL(create_type,-1) AS crt_type_cd
        ,NVL(bd_relation_status,-1) AS bd_rel_stat
        ,CAST(bd_operate_time AS DATETIME) AS bd_opt_time
        ,NVL(no_relation_sort,-1) AS no_rel_sort
        ,NVL(custom_submit_flag,0) AS cust_submit_stat
        ,NVL(ai_recommend_flag,0) AS is_ai_recmd
        ,NVL(order_unrelated_status,0) AS is_order_unrel
        ,NVL(relate_logistics_template,0) AS is_logis_tpl_rel
        ,CAST(operate_time AS DATETIME) AS opt_time
        ,NVL(product_detail,'{}') AS out_item_dtl_json
        ,NVL(del_flag,0) AS is_del
        ,CAST(create_time AS DATETIME) AS crt_time
        ,CAST(update_time AS DATETIME) AS upd_time
        ,CASE   WHEN UPPER(NVL(third_shop_platform,'')) = 'WOOCOMMERCE'
                    AND GET_JSON_OBJECT(NVL(product_detail,'{}'),'$.product.permalink') IS NOT NULL
                    AND GET_JSON_OBJECT(NVL(product_detail,'{}'),'$.product.permalink') <> ''
                THEN GET_JSON_OBJECT(NVL(product_detail,'{}'),'$.product.permalink')
                WHEN UPPER(NVL(third_shop_platform,'')) = 'SHOPIFY'
                    AND sh.shop_domain IS NOT NULL
                    AND sh.shop_domain <> ''
                    AND GET_JSON_OBJECT(NVL(product_detail,'{}'),'$.handle') IS NOT NULL
                    AND GET_JSON_OBJECT(NVL(product_detail,'{}'),'$.handle') <> ''
                THEN CONCAT(
                    CASE    WHEN LOWER(sh.shop_domain) LIKE 'http%'
                            THEN REGEXP_REPLACE(sh.shop_domain,'/+$','')
                            ELSE CONCAT('https://',REGEXP_REPLACE(sh.shop_domain,'/+$',''))
                    END,
                    '/products/',
                    GET_JSON_OBJECT(NVL(product_detail,'{}'),'$.handle')
                )
                ELSE NULL
        END AS out_item_url
FROM    demo_dw.ods_mysql_tang_plugin_third_platform_product_ri t
LEFT JOIN dedup_pub_rec p
ON      t.third_platform_item_id = p.publish_product_id
LEFT JOIN demo_dw.ods_mysql_tang_plugin_shopify_store_auth_ri sh
ON      UPPER(NVL(t.third_shop_platform,'')) = 'SHOPIFY'
AND     CAST(t.third_platform_shop_id AS BIGINT) = sh.shop_id
;
