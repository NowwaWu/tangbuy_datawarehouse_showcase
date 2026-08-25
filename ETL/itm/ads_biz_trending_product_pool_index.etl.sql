--MaxCompute SQL
--********************************************************************--
-- author: 吴延俊
-- create time: 2026-06-16
-- 数据域:   itm (商品域)
-- 表名:     ads_biz_trending_product_pool_index
-- 描述:     大家都在买商品池索引，基于订单售卖商品、ODS 商品主表、ODS 外部商品、趋势分和 QC 图片生成
-- 来源:     ods_mysql_tang_order_t_order_item_ri
--           ods_mysql_tang_order_t_order_ri
--           ods_mysql_tang_order_t_order_operation_ri
--           ods_mysql_tang_product_product_item_ri
--           ods_mysql_tang_product_product_provider_info_ri
--           ods_mysql_tang_product_t_external_item_ri
--           ods_mysql_tang_product_t_external_store_ri
--           ods_mysql_tang_product_preferred_product_ri
--           ods_mysql_tang_product_preferred_product_category_ri
--           ods_mysql_tang_product_preferred_product_activity_ri
--           ods_mysql_tang_product_preferred_activity_ri
--           ods_mysql_tang_product_trend_product_score_ri
--           ods_mysql_tang_statistics_order_statistics_ri
--********************************************************************--

WITH order_stock_in AS
(
    SELECT  item_id AS item_no
            ,MAX(CAST(create_time AS DATETIME)) AS in_storage_time
    FROM    demo_dw.ods_mysql_tang_order_t_order_operation_ri
    WHERE   (
                op_type LIKE '仓库已入库%'
                OR      op_type LIKE '系统入库%'
            )
    GROUP BY item_id
)
,order_item_base AS
(
    SELECT  CASE    WHEN GET_JSON_OBJECT(i.extend_field,'$.tangGoodsId') IS NOT NULL
                        AND GET_JSON_OBJECT(i.extend_field,'$.tangGoodsId') <> ''
                    THEN GET_JSON_OBJECT(i.extend_field,'$.tangGoodsId')
                    ELSE i.goods_id
            END AS item_id
            ,i.item_no
            ,i.goods_status
            ,CAST(i.unit_price AS DECIMAL(38,18)) AS unit_price
            ,CAST(i.write_price AS DECIMAL(38,18)) AS write_price
            ,CAST(o.pay_time AS DATETIME) AS pay_time
            ,CAST(o.create_time AS DATETIME) AS order_create_time
            ,s.in_storage_time
    FROM    demo_dw.ods_mysql_tang_order_t_order_item_ri i
    JOIN    demo_dw.ods_mysql_tang_order_t_order_ri o
    ON      i.order_no = o.order_no
    JOIN    order_stock_in s
    ON      i.item_no = s.item_no
)
,order_sale_item AS
(
    SELECT  item_id
            ,COUNT(1) AS sale_cnt
            ,MIN(COALESCE(unit_price,write_price)) AS sale_min_price
            ,MAX(COALESCE(unit_price,write_price)) AS sale_max_price
    FROM    order_item_base
    WHERE   pay_time IS NOT NULL
    AND     in_storage_time IS NOT NULL
    AND     order_create_time >= DATEADD(TO_DATE('${bizdate}','yyyymmdd'),-180,'dd')
    AND     order_create_time < DATEADD(TO_DATE('${bizdate}','yyyymmdd'),1,'dd')
    AND     NVL(goods_status,-1) NOT IN (34,38)
    GROUP BY item_id
)
,provider_info_ranked AS
(
    SELECT  provider_key
            ,provider_type
            ,provider_item_id
            ,provider_detail_url
            ,provider_shop_id
            ,provider_shop_name
            ,provider_shop_url
            ,provider_price
            ,provider_max_price
            ,provider_item_name
            ,provider_item_images
            ,update_time
            ,create_time
            ,ROW_NUMBER() OVER(PARTITION BY provider_key ORDER BY update_time DESC,create_time DESC,id DESC) AS rn
    FROM    demo_dw.ods_mysql_tang_product_product_provider_info_ri
    WHERE   provider_key IS NOT NULL
)
,provider_info AS
(
    SELECT  provider_key
            ,provider_type
            ,provider_item_id
            ,provider_detail_url
            ,provider_shop_id
            ,provider_shop_name
            ,provider_shop_url
            ,provider_price
            ,provider_max_price
            ,provider_item_name
            ,provider_item_images
            ,update_time
            ,create_time
    FROM    provider_info_ranked
    WHERE   rn = 1
)
,external_store_ranked AS
(
    SELECT  store_id
            ,provider_type
            ,store_name
            ,store_url
            ,ROW_NUMBER() OVER(PARTITION BY provider_type,store_id ORDER BY update_time DESC,create_time DESC,id DESC) AS rn
    FROM    demo_dw.ods_mysql_tang_product_t_external_store_ri
    WHERE   store_id IS NOT NULL
    AND     NVL(del_flag,0) = 0
)
,external_store AS
(
    SELECT  store_id
            ,provider_type
            ,store_name
            ,store_url
    FROM    external_store_ranked
    WHERE   rn = 1
)
,product_item AS
(
    SELECT  id
            ,item_name
            ,item_name_lang
            ,images
            ,item_mv
            ,price
            ,max_price
            ,platform_status
            ,provider_type
            ,provider_key
            ,shop_id
            ,status
            ,CAST(update_time AS DATETIME) AS update_time
            ,assemble_status
            ,category_id
            ,CAST(create_time AS DATETIME) AS create_time
            ,crossed_price
            ,data_source
            ,del_flag
            ,freight_type
            ,CAST(invalid_time AS DATETIME) AS invalid_time
            ,detail_url
            ,post_fee
    FROM    demo_dw.ods_mysql_tang_product_product_item_ri
    WHERE   assemble_status = 0
)
,product_item_base AS
(
    SELECT  CAST(i.id AS STRING) AS goods_id
            ,0 AS assemble_status
            ,i.item_mv
            ,i.item_name AS goods_name
            ,CASE   WHEN i.images IS NOT NULL AND i.images <> ''
                    THEN TO_JSON(SPLIT(REGEXP_REPLACE(i.images,'\\]|\\[|"',''),','))
                    ELSE NULL
            END AS images
            ,i.price
            ,i.max_price
            ,i.provider_key
            ,i.provider_type
            ,CAST(NULL AS STRING) AS owner_id
            ,CAST(i.shop_id AS STRING) AS shop_id
            ,p.provider_shop_name AS owner_name
            ,p.provider_shop_url AS shop_url
            ,i.update_time
            ,i.create_time
            ,i.post_fee
            ,i.detail_url
            ,COALESCE(i.data_source,'OUTER') AS data_source
            ,1 AS src_priority
    FROM    product_item i
    LEFT JOIN provider_info p
    ON      i.provider_key = p.provider_key
)
,external_item_ranked AS
(
    SELECT  item_id
            ,provider_type
            ,item_name
            ,main_picture
            ,item_url
            ,store_id
            ,category_id
            ,CAST(create_time AS DATETIME) AS create_time
            ,CAST(update_time AS DATETIME) AS update_time
            ,NVL(del_flag,0) AS del_flag
            ,CONCAT(provider_type,':',item_id) AS provider_key
            ,ROW_NUMBER() OVER(PARTITION BY provider_type,item_id ORDER BY update_time DESC,create_time DESC,id DESC) AS rn
    FROM    demo_dw.ods_mysql_tang_product_t_external_item_ri
    WHERE   item_id IS NOT NULL
    AND     NVL(del_flag,0) = 0
)
,external_item AS
(
    SELECT  item_id
            ,provider_type
            ,item_name
            ,main_picture
            ,item_url
            ,store_id
            ,category_id
            ,create_time
            ,update_time
            ,del_flag
            ,provider_key
    FROM    external_item_ranked
    WHERE   rn = 1
)
,external_item_base AS
(
    SELECT  e.item_id AS goods_id
            ,0 AS assemble_status
            ,CAST(NULL AS STRING) AS item_mv
            ,COALESCE(e.item_name,p.provider_item_name) AS goods_name
            ,CASE   WHEN COALESCE(e.main_picture,p.provider_item_images) IS NOT NULL
                        AND COALESCE(e.main_picture,p.provider_item_images) <> ''
                    THEN TO_JSON(SPLIT(REGEXP_REPLACE(COALESCE(e.main_picture,p.provider_item_images),'\\]|\\[|"',''),','))
                    ELSE NULL
            END AS images
            ,p.provider_price AS price
            ,p.provider_max_price AS max_price
            ,COALESCE(e.provider_key,p.provider_key) AS provider_key
            ,COALESCE(e.provider_type,p.provider_type) AS provider_type
            ,CAST(NULL AS STRING) AS owner_id
            ,COALESCE(e.store_id,p.provider_shop_id) AS shop_id
            ,COALESCE(s.store_name,p.provider_shop_name) AS owner_name
            ,COALESCE(s.store_url,p.provider_shop_url) AS shop_url
            ,COALESCE(e.update_time,CAST(p.update_time AS DATETIME),e.create_time) AS update_time
            ,COALESCE(e.create_time,CAST(p.create_time AS DATETIME)) AS create_time
            ,CAST(0 AS DECIMAL(38,18)) AS post_fee
            ,COALESCE(e.item_url,p.provider_detail_url) AS detail_url
            ,'OUTER' AS data_source
            ,2 AS src_priority
    FROM    external_item e
    LEFT JOIN provider_info p
    ON      e.provider_key = p.provider_key
    LEFT JOIN external_store s
    ON      e.provider_type = s.provider_type
    AND     e.store_id = s.store_id
)
,base_item_ranked AS
(
    SELECT  goods_id
            ,assemble_status
            ,item_mv
            ,goods_name
            ,images
            ,price
            ,max_price
            ,provider_key
            ,provider_type
            ,owner_id
            ,shop_id
            ,owner_name
            ,shop_url
            ,update_time
            ,create_time
            ,post_fee
            ,detail_url
            ,data_source
            ,ROW_NUMBER() OVER(PARTITION BY goods_id ORDER BY src_priority,update_time DESC,create_time DESC) AS rn
    FROM    (
                SELECT  goods_id
                        ,assemble_status
                        ,item_mv
                        ,goods_name
                        ,images
                        ,price
                        ,max_price
                        ,provider_key
                        ,provider_type
                        ,owner_id
                        ,shop_id
                        ,owner_name
                        ,shop_url
                        ,update_time
                        ,create_time
                        ,post_fee
                        ,detail_url
                        ,data_source
                        ,src_priority
                FROM    product_item_base
                UNION ALL
                SELECT  goods_id
                        ,assemble_status
                        ,item_mv
                        ,goods_name
                        ,images
                        ,price
                        ,max_price
                        ,provider_key
                        ,provider_type
                        ,owner_id
                        ,shop_id
                        ,owner_name
                        ,shop_url
                        ,update_time
                        ,create_time
                        ,post_fee
                        ,detail_url
                        ,data_source
                        ,src_priority
                FROM    external_item_base
            ) t
)
,base_sale_item AS
(
    SELECT  b.goods_id
            ,b.assemble_status
            ,b.item_mv
            ,b.goods_name
            ,b.images
            ,COALESCE(b.price,o.sale_min_price) AS price
            ,COALESCE(b.max_price,o.sale_max_price,o.sale_min_price) AS max_price
            ,b.provider_key
            ,b.provider_type
            ,b.owner_id
            ,b.shop_id
            ,b.owner_name
            ,b.shop_url
            ,b.update_time
            ,b.create_time
            ,b.post_fee
            ,b.detail_url
            ,b.data_source
    FROM    order_sale_item o
    JOIN    base_item_ranked b
    ON      o.item_id = b.goods_id
    AND     b.rn = 1
    WHERE   b.goods_id NOT IN (
                '850826779944','830712720697','862445269703','847146799632','746507380051','904860464102','892117787335','890710796066','823492504199','903980070684',
                '9a8afda12d6b9bc','896725741127','797165929481','796984523377','796967885347','771019431222','847719104333','869646308504','838450599235','899571219683',
                '890719441196','857810230021','785797899228','903301400383','669823731901','898131629977','892792581893','892793133968','859795451143','875601401464',
                '798357767786','898699533334','812300827116','898469292644','880862682233'
            )
    AND     b.shop_id NOT IN (
                '106275146','155022305','162621665','165820376','180572657','188285136','220300238','222075578','236450347','250412383','336469564','456317760',
                '500318446','576220365','582642129','b2b-7f0a8b08fb673cc7de','b2b-e0834309c767bed224','b2b-58022c4db2ba165cf3','b2b-f3320f0a0d05a16baf',
                'b2b-d9937777a0e64d5e12','b2b-d025b9a9116a15dc85','b2b-c41e1271859a18b8cd','b2b-b8459d7d4725cccd30','b2b-1be671564af71e7cbc'
            )
)
,preferred_product_ranked AS
(
    SELECT  item_id
            ,owner_id
            ,owner_name
            ,owner_source
            ,choice_score
            ,level AS item_level
            ,ROW_NUMBER() OVER(PARTITION BY item_id ORDER BY update_time DESC,create_time DESC,id DESC) AS rn
    FROM    demo_dw.ods_mysql_tang_product_preferred_product_ri
)
,preferred_product AS
(
    SELECT  item_id
            ,owner_id
            ,owner_name
            ,owner_source
            ,choice_score
            ,item_level
    FROM    preferred_product_ranked
    WHERE   rn = 1
)
,preferred_active_activity AS
(
    SELECT  id
    FROM    demo_dw.ods_mysql_tang_product_preferred_activity_ri
    WHERE   status = 2
    AND     NVL(del_flag,0) = 0
)
,preferred_activity AS
(
    SELECT  a.item_id
            ,TO_JSON(COLLECT_LIST(a.activity_id)) AS activity_list
            ,IF(SIZE(COLLECT_LIST(a.activity_id)) > 0,1,0) AS has_active
    FROM    demo_dw.ods_mysql_tang_product_preferred_product_activity_ri a
    JOIN    preferred_active_activity b
    ON      a.activity_id = b.id
    WHERE   NVL(a.del_flag,0) = 0
    GROUP BY a.item_id
)
,preferred_item AS
(
    SELECT  i.id
            ,i.item_name
            ,TO_JSON(
                NAMED_STRUCT(
                    'en',GET_JSON_OBJECT(i.item_name_lang,'$.ENGLISH'),
                    'es',GET_JSON_OBJECT(i.item_name_lang,'$.ES'),
                    'ko',GET_JSON_OBJECT(i.item_name_lang,'$.KOREA'),
                    'ms',GET_JSON_OBJECT(i.item_name_lang,'$.MS'),
                    'fr',GET_JSON_OBJECT(i.item_name_lang,'$.FR'),
                    'de',GET_JSON_OBJECT(i.item_name_lang,'$.DE')
                )
            ) AS item_name_lang
            ,CASE   WHEN i.images IS NOT NULL AND i.images <> ''
                    THEN TO_JSON(SPLIT(REGEXP_REPLACE(i.images,'\\]|\\[|"',''),','))
                    ELSE NULL
            END AS images
            ,i.item_mv
            ,i.price
            ,i.max_price
            ,i.platform_status
            ,i.provider_type
            ,i.provider_key
            ,CAST(i.shop_id AS STRING) AS shop_id
            ,i.status
            ,i.update_time
            ,i.assemble_status
            ,i.category_id
            ,i.create_time
            ,i.crossed_price
            ,i.data_source
            ,i.del_flag
            ,i.freight_type
            ,i.invalid_time
            ,i.detail_url
            ,i.post_fee
            ,CAST(pp.owner_id AS STRING) AS owner_id
            ,pp.owner_name
            ,pp.owner_source
            ,pp.choice_score
            ,pp.item_level
            ,p.provider_price
            ,p.provider_item_id
            ,p.provider_max_price
            ,c.ancestors AS category_ancestors
            ,NVL(CAST(SPLIT(REGEXP_REPLACE(c.ancestors,'\\]|\\[|"',''),',')[2] AS BIGINT),0) AS root_category_id
            ,a.activity_list
            ,NVL(a.has_active,0) AS has_active
    FROM    product_item i
    LEFT JOIN preferred_product pp
    ON      i.id = pp.item_id
    LEFT JOIN provider_info p
    ON      i.provider_key = p.provider_key
    LEFT JOIN demo_dw.ods_mysql_tang_product_preferred_product_category_ri c
    ON      i.category_id = c.id
    LEFT JOIN preferred_activity a
    ON      i.id = a.item_id
    WHERE   i.data_source IN ('PREFERRED','SHOP')
)
,merged_sale_item AS
(
    SELECT  CASE WHEN p.provider_item_id IS NOT NULL THEN p.provider_item_id ELSE b.goods_id END AS item_id
            ,CASE WHEN p.provider_item_id IS NOT NULL THEN CAST(p.id AS STRING) ELSE b.goods_id END AS preferred_item_id
            ,CASE WHEN p.provider_item_id IS NOT NULL THEN p.item_name ELSE b.goods_name END AS item_name
            ,CASE WHEN p.provider_item_id IS NOT NULL THEN p.item_name_lang ELSE NULL END AS item_name_lang
            ,CASE WHEN p.provider_item_id IS NOT NULL THEN p.images ELSE b.images END AS images
            ,CASE WHEN p.provider_item_id IS NOT NULL THEN p.item_mv ELSE b.item_mv END AS item_mv
            ,CASE WHEN p.provider_item_id IS NOT NULL THEN p.price ELSE b.price END AS price
            ,CASE WHEN p.provider_item_id IS NOT NULL THEN p.max_price ELSE b.max_price END AS max_price
            ,CASE WHEN p.provider_item_id IS NOT NULL THEN p.platform_status ELSE NULL END AS platform_status
            ,CASE WHEN p.provider_item_id IS NOT NULL THEN p.provider_type ELSE b.provider_type END AS provider_type
            ,CASE WHEN p.provider_item_id IS NOT NULL THEN p.provider_key ELSE b.provider_key END AS provider_key
            ,CASE WHEN p.provider_item_id IS NOT NULL THEN p.shop_id ELSE b.shop_id END AS shop_id
            ,CASE WHEN p.provider_item_id IS NOT NULL THEN p.status ELSE NULL END AS status
            ,CASE WHEN p.provider_item_id IS NOT NULL THEN p.update_time ELSE b.update_time END AS update_time
            ,CASE WHEN p.provider_item_id IS NOT NULL THEN p.assemble_status ELSE b.assemble_status END AS assemble_status
            ,CASE WHEN p.provider_item_id IS NOT NULL THEN p.category_id ELSE NULL END AS category_id
            ,CASE WHEN p.provider_item_id IS NOT NULL THEN p.create_time ELSE b.create_time END AS create_time
            ,CASE WHEN p.provider_item_id IS NOT NULL THEN p.crossed_price ELSE NULL END AS crossed_price
            ,CASE WHEN p.provider_item_id IS NOT NULL THEN p.data_source ELSE b.data_source END AS data_source
            ,CASE WHEN p.provider_item_id IS NOT NULL THEN p.del_flag ELSE NULL END AS del_flag
            ,CASE WHEN p.provider_item_id IS NOT NULL THEN p.freight_type ELSE NULL END AS freight_type
            ,CASE WHEN p.provider_item_id IS NOT NULL THEN p.invalid_time ELSE NULL END AS invalid_time
            ,CASE WHEN p.provider_item_id IS NOT NULL THEN p.detail_url ELSE b.detail_url END AS detail_url
            ,CASE WHEN p.provider_item_id IS NOT NULL THEN p.post_fee ELSE b.post_fee END AS post_fee
            ,CASE WHEN p.provider_item_id IS NOT NULL THEN p.owner_id ELSE b.owner_id END AS owner_id
            ,CASE WHEN p.provider_item_id IS NOT NULL THEN p.owner_name ELSE b.owner_name END AS owner_name
            ,CASE WHEN p.provider_item_id IS NOT NULL THEN p.owner_source ELSE NULL END AS owner_source
            ,CASE WHEN p.provider_item_id IS NOT NULL THEN p.choice_score ELSE NULL END AS choice_score
            ,CASE WHEN p.provider_item_id IS NOT NULL THEN p.item_level ELSE NULL END AS level
            ,CASE WHEN p.provider_item_id IS NOT NULL THEN p.provider_price ELSE b.price END AS provider_price
            ,CASE WHEN p.provider_item_id IS NOT NULL THEN p.provider_item_id ELSE b.goods_id END AS provider_item_id
            ,CASE WHEN p.provider_item_id IS NOT NULL THEN p.provider_max_price ELSE b.max_price END AS provider_max_price
            ,CASE WHEN p.provider_item_id IS NOT NULL THEN p.category_ancestors ELSE NULL END AS category_ancestors
            ,CASE WHEN p.provider_item_id IS NOT NULL THEN p.root_category_id ELSE NULL END AS root_category_id
            ,CASE WHEN p.provider_item_id IS NOT NULL THEN p.activity_list ELSE NULL END AS activity_list
            ,CASE WHEN p.provider_item_id IS NOT NULL THEN p.has_active ELSE 0 END AS has_active
    FROM    base_sale_item b
    LEFT JOIN preferred_item p
    ON      b.goods_id = CAST(p.id AS STRING)
)
,trend_score AS
(
    SELECT  item_id
            ,MAX(CAST(trend_comprehensive_score AS DOUBLE)) AS trend_comprehensive_score
    FROM    demo_dw.ods_mysql_tang_product_trend_product_score_ri
    GROUP BY item_id
)
,qc_image AS
(
    SELECT  goods_id
            ,GET_JSON_OBJECT(MAX(goods_info),'$.images') AS qc_imgs
    FROM    demo_dw.ods_mysql_tang_statistics_order_statistics_ri
    GROUP BY goods_id
)

INSERT OVERWRITE TABLE ads_biz_trending_product_pool_index
SELECT  s1.item_id
        ,s1.preferred_item_id
        ,s1.item_name
        ,s1.item_name_lang
        ,s1.images
        ,s1.item_mv
        ,CAST(s1.price AS DOUBLE) AS price
        ,CAST(s1.max_price AS DOUBLE) AS max_price
        ,s1.platform_status
        ,s1.provider_type
        ,s1.provider_key
        ,s1.shop_id
        ,s1.status
        ,TO_CHAR(s1.update_time,'yyyy-mm-dd HH:mi:ss') AS update_time
        ,s1.assemble_status
        ,s1.category_id
        ,TO_CHAR(s1.create_time,'yyyy-mm-dd HH:mi:ss') AS create_time
        ,CAST(s1.crossed_price AS DOUBLE) AS crossed_price
        ,s1.data_source
        ,s1.del_flag
        ,s1.freight_type
        ,TO_CHAR(s1.invalid_time,'yyyy-mm-dd HH:mi:ss') AS invalid_time
        ,s1.detail_url
        ,CAST(s1.post_fee AS DOUBLE) AS post_fee
        ,s1.owner_id
        ,s1.owner_name
        ,s1.owner_source
        ,COALESCE(CAST(s1.choice_score AS DOUBLE),0) AS choice_score
        ,CAST(s1.provider_price AS DOUBLE) AS provider_price
        ,s1.provider_item_id
        ,CAST(s1.provider_max_price AS DOUBLE) AS provider_max_price
        ,s1.category_ancestors
        ,CAST(s1.root_category_id AS STRING) AS root_category_id
        ,s1.activity_list
        ,COALESCE(s2.trend_comprehensive_score,0) AS trend_comprehensive_score
        ,s3.qc_imgs
        ,IF(s3.qc_imgs IS NOT NULL,1,0) AS has_qc
        ,s1.has_active
        ,s1.level
FROM    merged_sale_item s1
LEFT JOIN trend_score s2
ON      s1.item_id = s2.item_id
LEFT JOIN qc_image s3
ON      s1.item_id = s3.goods_id
;
