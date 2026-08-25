--MaxCompute SQL
--********************************************************************--
--author: 吴延俊
--create time: 2026-05-19 00:00:00
--modify time: 2026-06-10
-- 数据域:   store (店铺域)
-- 业务过程: store_auth (店铺授权)
-- 表名:     dwd_store_ds_shop_auth_rel_df
-- 表类型:   累积快照事实表 - 日全量
-- 粒度:     一行 = 一条用户-店铺授权关系(user_auth_shop.id)
-- ETL方式:  INSERT OVERWRITE, 源表 _ri 全量快照 + 用户/BD/店铺维度信息冗余
-- _df口径:  源表 _ri 与维表当日分区均为全量快照，当日全量重算
-- 过滤口径:  对齐dim_plugin_shop_user_info有效店铺、测试用户、BD过滤口径
-- 防膨胀:   BD按user_id聚合; 店铺属性复用dim_store_ds_shop_df店铺粒度快照
-- 调度变量: ${bizdate} 格式 yyyyMMdd
--********************************************************************--

WITH auth_rel AS
(
    SELECT  id AS auth_rel_id
            ,user_id AS usr_id
            ,UPPER(shop_type) AS shop_pltf_cd
            ,shop_id AS shop_id
            ,shop_name AS shop_nm
            ,NVL(status,-1) AS auth_stat
            ,CAST(create_time AS DATETIME) AS crt_time
            ,CAST(update_time AS DATETIME) AS upd_time
            ,CAST(IF(status = 0,update_time,NULL) AS DATETIME) AS auth_revoke_time
    FROM    demo_dw.ods_mysql_tang_plugin_user_auth_shop_ri
    WHERE   user_id NOT IN (ee165a4e183c43f,75271529e9c57a)
)
,usr_info AS
(
    SELECT  usr_id
            ,usr_nm
            ,email
            ,cntry_cd
    FROM    demo_dw.dim_usr_info_df
    WHERE   ds = '${bizdate}'
)
,bd_distinct AS
(
    SELECT  DISTINCT
            user_id AS usr_id
            ,operate_name AS bd_usr_nm
    FROM    demo_dw.ods_mysql_tang_cps_business_cooperation_user_ri
    WHERE   operate_name IS NOT NULL
    AND     user_id IS NOT NULL
    AND     operate_name NOT IN ('Noa')
    AND     TRIM(operate_name) <> ''
)
,bd_agg AS
(
    SELECT  usr_id
            ,CONCAT_WS('; ',COLLECT_SET(bd_usr_nm)) AS bd_usr_nm
    FROM    bd_distinct
    GROUP BY usr_id
)
,shop_info AS
(
    SELECT  shop_pltf_cd
            ,CAST(shop_id AS STRING) AS shop_id
            ,REPLACE(REPLACE(TOLOWER(shop_url),'https://',''),'http://','') AS shop_url
            ,slr_nm
            ,shop_rgn_cd
            ,is_shop_unreachable
            ,shop_unreachable_rsn
            ,shop_crt_time
            ,NVL(is_del,0) AS is_del
    FROM    demo_dw.dim_store_ds_shop_df
    WHERE   ds = '${bizdate}'
    AND     (
                (
                    shop_pltf_cd = 'SHOPIFY'
                    AND slr_nm NOT IN ('楷文 吴','noa tangbuy')
                    AND email NOT LIKE '%tangbuy.com%'
                    AND email NOT LIKE '%shopify.com%'
                )
                OR
                (
                    shop_pltf_cd = 'WOOCOMMERCE'
                    AND shop_nm NOT IN ('woocommerce.tangbuy.cc','woocommerce.tangbuy.com','peru-albatross-514606.hostingersite.com')
                )
            )
)

INSERT OVERWRITE TABLE demo_dw.dwd_store_ds_shop_auth_rel_df PARTITION (ds = '${bizdate}')
SELECT  a.auth_rel_id
        ,a.usr_id
        ,u.usr_nm
        ,u.email
        ,u.cntry_cd
        ,a.shop_pltf_cd
        ,a.shop_id
        ,a.shop_nm
        ,s.shop_url
        ,s.slr_nm
        ,s.shop_rgn_cd
        ,NVL(s.is_shop_unreachable,0) AS is_shop_unreachable
        ,s.shop_unreachable_rsn
        ,s.shop_crt_time
        ,a.auth_stat
        ,CASE   WHEN a.auth_stat = 1 THEN '启用'
                WHEN a.auth_stat = 0 THEN '禁用'
                ELSE '未知'
         END AS auth_stat_nm
        ,b.bd_usr_nm
        ,NVL(s.is_del,0) AS is_del
        ,a.crt_time
        ,a.upd_time
        ,a.auth_revoke_time
FROM    auth_rel a
INNER JOIN shop_info s
ON      a.shop_pltf_cd = s.shop_pltf_cd
AND     a.shop_id = s.shop_id
LEFT JOIN usr_info u
ON      a.usr_id = u.usr_id
LEFT JOIN bd_agg b
ON      a.usr_id = b.usr_id
;
