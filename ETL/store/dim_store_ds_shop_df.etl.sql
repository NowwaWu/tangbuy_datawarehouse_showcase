--MaxCompute SQL
--********************************************************************--
--author: 吴延俊
--create time: 2026-04-29 18:19:27
-- 数据域:   store (店铺域)
-- 业务过程: store_auth (店铺授权)
-- 表名:     dim_store_ds_shop_df
-- 表类型:   维度表 (Dimension) - 日全量快照
-- ETL方式:  三平台UNION ALL后 LEFT JOIN fulfillment_service
-- 调度变量: ${bizdate} 格式 yyyyMMdd
-- 防膨胀:   fulfillment_service 按 fulfillment_service_id ROW_NUMBER 取 rn=1
--********************************************************************--

WITH usr_shop_rn AS 
(
    SELECT  UPPER(shop_type) AS shop_type
             ,CAST(shop_id AS BIGINT) AS shop_id
             ,user_id
             ,shop_name
             ,status
             ,CAST(create_time AS DATETIME) AS create_time
             ,CAST(update_time AS DATETIME) AS update_time
             ,ROW_NUMBER() OVER (PARTITION BY UPPER(shop_type),CAST(shop_id AS BIGINT) ORDER BY update_time DESC ) AS rn
    FROM    demo_dw.ods_mysql_tang_plugin_user_auth_shop_ri
)
,usr_shop AS 
(
    SELECT  shop_type
            ,shop_id
            ,user_id
            ,shop_name
            ,status
            ,create_time
            ,update_time
    FROM    usr_shop_rn
    WHERE   rn = 1
)
,flfl_rn AS 
(
    SELECT  fulfillment_service_id
            ,handle AS flfl_handle
            ,callback_url AS flfl_callback_url
            ,service_name AS flfl_service_nm
            ,status AS flfl_stat
            ,ROW_NUMBER() OVER (PARTITION BY fulfillment_service_id ORDER BY CAST(update_time AS DATETIME) DESC ) AS rn
    FROM    demo_dw.ods_mysql_tang_plugin_shopify_fulfillment_service_ri
)
,flfl AS 
(
    SELECT  fulfillment_service_id
            ,flfl_handle
            ,flfl_callback_url
            ,flfl_service_nm
            ,flfl_stat
    FROM    flfl_rn
    WHERE   rn = 1
)
,store_union AS 
(
    -- Shopify: 平台授权表 LEFT JOIN usr_shop 补充 usr_id
    SELECT  sh.shop_id
            ,sh.shop_name AS shop_nm
            ,'SHOPIFY' AS shop_type_cd
            ,sh.shop_domain AS shop_url
            ,NULL AS shop_rgn_cd
            ,NULL AS shop_cd
            ,COALESCE(u.user_id,sh.user_id) AS usr_id
            ,sh.shop_owner AS slr_nm
            ,NULL AS slr_type_cd
            ,NULL AS tk_usr_type_cd
            ,sh.email
            ,sh.status AS shop_stat
            ,NULL AS auth_stat
            ,CASE   WHEN NVL(sh.error_code,0) <> 0 THEN 1
                    ELSE 0
             END AS is_shop_unreachable
            ,sh.error_msg AS shop_unreachable_rsn
            ,NULL AS is_ssl_on
            ,sh.fulfillment_service_id
            ,sh.location_id
            ,NULL AS api_ver
            ,CAST(sh.install_time AS DATETIME) AS inst_time
            ,CAST(sh.shop_create_time AS DATETIME) AS shop_crt_time
            ,NULL AS last_sync_time
            ,NULL AS rmk
            ,NULL AS is_del
            ,CAST(sh.install_time AS DATETIME) AS crt_time
            ,CAST(sh.update_time AS DATETIME) AS upd_time
    FROM    demo_dw.ods_mysql_tang_plugin_shopify_store_auth_ri sh
    LEFT JOIN usr_shop u
    ON      u.shop_type = 'SHOPIFY'
    AND     u.shop_id = sh.shop_id
    UNION ALL -- TikTok: 平台授权表 LEFT JOIN usr_shop 补充 usr_id 和 shop_stat
    SELECT  CAST(tk.shop_id AS BIGINT) AS shop_id
            ,tk.shop_name AS shop_nm
            ,'TIKTOK' AS shop_type_cd
            ,NULL AS shop_url
            ,tk.shop_region AS shop_rgn_cd
            ,tk.shop_code AS shop_cd
            ,u.user_id AS usr_id
            ,tk.seller_name AS slr_nm
            ,tk.seller_type AS slr_type_cd
            ,tk.user_type AS tk_usr_type_cd
            ,NULL AS email
            ,u.status AS shop_stat
            ,NULL AS auth_stat
            ,0 AS is_shop_unreachable
            ,NULL AS shop_unreachable_rsn
            ,NULL AS is_ssl_on
            ,NULL AS fulfillment_service_id
            ,NULL AS location_id
            ,NULL AS api_ver
            ,NULL AS inst_time
            ,NULL AS shop_crt_time
            ,NULL AS last_sync_time
            ,NULL AS rmk
            ,NULL AS is_del
            ,CAST(tk.created_at AS DATETIME) AS crt_time
            ,CAST(tk.updated_at AS DATETIME) AS upd_time
    FROM    demo_dw.ods_mysql_tang_plugin_tiktok_store_auth_ri tk
    LEFT JOIN usr_shop u
    ON      u.shop_type = 'TIKTOK'
    AND     u.shop_id = CAST(tk.shop_id AS BIGINT)
    UNION ALL -- WooCommerce: 平台授权表 LEFT JOIN usr_shop 补充 usr_id
    SELECT  wo.id AS shop_id
            ,wo.shop_name AS shop_nm
            ,'WOOCOMMERCE' AS shop_type_cd
            ,wo.site_url AS shop_url
            ,NULL AS shop_rgn_cd
            ,NULL AS shop_cd
            ,COALESCE(u.user_id,wo.user_id) AS usr_id
            ,NULL AS slr_nm
            ,NULL AS slr_type_cd
            ,NULL AS tk_usr_type_cd
            ,NULL AS email
            ,wo.status AS shop_stat
            ,wo.auth_status AS auth_stat
            ,0 AS is_shop_unreachable
            ,NULL AS shop_unreachable_rsn
            ,wo.ssl_enabled AS is_ssl_on
            ,NULL AS fulfillment_service_id
            ,NULL AS location_id
            ,wo.api_version AS api_ver
            ,NULL AS inst_time
            ,NULL AS shop_crt_time
            ,CAST(wo.last_sync_time AS DATETIME) AS last_sync_time
            ,wo.remark AS rmk
            ,wo.del_flag AS is_del
            ,CAST(wo.create_time AS DATETIME) AS crt_time
            ,CAST(wo.update_time AS DATETIME) AS upd_time
    FROM    demo_dw.ods_mysql_tang_plugin_woocommerce_store_auth_ri wo
    LEFT JOIN usr_shop u
    ON      u.shop_type = 'WOOCOMMERCE'
    AND     u.shop_id = wo.id
    UNION ALL -- 仅存于 usr_shop 的店铺（不在任何平台授权表中）
    SELECT  u.shop_id
            ,u.shop_name AS shop_nm
            ,u.shop_type AS shop_type_cd
            ,NULL AS shop_url
            ,NULL AS shop_rgn_cd
            ,NULL AS shop_cd
            ,u.user_id AS usr_id
            ,NULL AS slr_nm
            ,NULL AS slr_type_cd
            ,NULL AS tk_usr_type_cd
            ,NULL AS email
            ,u.status AS shop_stat
            ,NULL AS auth_stat
            ,0 AS is_shop_unreachable
            ,NULL AS shop_unreachable_rsn
            ,NULL AS is_ssl_on
            ,NULL AS fulfillment_service_id
            ,NULL AS location_id
            ,NULL AS api_ver
            ,NULL AS inst_time
            ,NULL AS shop_crt_time
            ,NULL AS last_sync_time
            ,NULL AS rmk
            ,NULL AS is_del
            ,u.create_time AS crt_time
            ,u.update_time AS upd_time
    FROM    usr_shop u
    WHERE   NOT 
EXISTS(
                SELECT  1
                FROM    demo_dw.ods_mysql_tang_plugin_shopify_store_auth_ri sh
                WHERE   u.shop_type = 'SHOPIFY'
                AND     u.shop_id = sh.shop_id
            ) 
    AND     NOT 
EXISTS(
                SELECT  1
                FROM    demo_dw.ods_mysql_tang_plugin_tiktok_store_auth_ri tk
                WHERE   u.shop_type = 'TIKTOK'
                AND     u.shop_id = CAST(tk.shop_id AS BIGINT)
            ) 
    AND     NOT 
EXISTS(
                SELECT  1
                FROM    demo_dw.ods_mysql_tang_plugin_woocommerce_store_auth_ri wo
                WHERE   u.shop_type = 'WOOCOMMERCE'
                AND     u.shop_id = wo.id
            ) 
)
INSERT OVERWRITE TABLE demo_dw.dim_store_ds_shop_df PARTITION (ds = '${bizdate}')
SELECT  s.shop_id
        ,s.shop_nm
        ,shop_type_cd
        ,shop_url 
        ,shop_rgn_cd
        ,shop_cd
        ,usr_id
        ,slr_nm
        ,slr_type_cd
        ,NVL(s.tk_usr_type_cd,-1) AS tk_usr_type_cd
        ,email
        ,NVL(s.shop_stat,-1) AS shop_stat
        ,NVL(s.auth_stat,-1) AS auth_stat
        ,NVL(s.is_shop_unreachable,0) AS is_shop_unreachable
        ,s.shop_unreachable_rsn
        ,NVL(s.is_ssl_on,0) AS is_ssl_on
        ,s.fulfillment_service_id AS flfl_service_id
        ,flfl_handle
        ,flfl_callback_url
        ,flfl_service_nm
        ,flfl_stat
        ,location_id
        ,api_ver
        ,s.inst_time
        ,s.shop_crt_time
        ,s.last_sync_time
        ,rmk
        ,NVL(s.is_del,0) AS is_del
        ,s.crt_time
        ,s.upd_time
FROM    store_union s
LEFT JOIN flfl f
ON      s.fulfillment_service_id = f.fulfillment_service_id
;
