--MaxCompute SQL
--********************************************************************--
--author: 吴延俊
--create time: 2026-05-08 16:13:39
-- 数据域:   trd (交易域)
-- 业务过程: ds_ord (DS代发订单)
-- 表名:     dwd_trd_ds_ord_line_df
-- 表类型:   明细事实表 (DWD Detail) - 日全量快照
-- 描述:     DS代发订单子单明细，整合草稿订单行/外部订单行/采购补充，
--           冗余常用维度(用户/店铺/商品)，为下游 DWS/ADS 提供统一订单行主数据出口。
-- 粒度:     一行 = 一个 DS 订单子单 (draft_order_line.id)
-- 来源:
--   ods_mysql_tang_plugin_t_draft_order_line_ri       (草稿订单行主表, 不含弃用的outer_*)
--   ods_mysql_tang_plugin_t_order_line_outer_ri       (外部订单行扩展, LEFT JOIN)
--   ods_mysql_tang_plugin_t_order_line_purchase_ri    (采购补充, LEFT JOIN 取item_no和rate)
--   ods_mysql_tang_order_t_item_plugin_ri             (插件商品扩展, LEFT JOIN 取BD信息和内部子单号)
--   ods_mysql_tang_order_t_item_plugin_supplement_df  (插件商品扩展补充, LEFT JOIN 兜底BD信息和内部子单号)
-- 维度冗余:
--   dim_usr_info_df       (LEFT JOIN usr_id → usr_nm, email)
--   dim_store_ds_shop_df   (LEFT JOIN out_shop_id → shop_pltf_cd)
--   dim_itm_item_df       (LEFT JOIN tb_ord_line_no → item_nm)
-- 更新策略: 底层源表为全量快照，每日从源表全量重算并 INSERT OVERWRITE 写入当日分区
-- 调度周期: 日
-- 调度变量: ${bizdate} 格式 yyyyMMdd
-- 零NULL:
--   数值度量 → 0, ID → -99, 字符串 → '未知', JSON → '{}', 布尔 → 0, 时间保留 NULL
--********************************************************************--
WITH -- -----------------------------------------------------------
-- CTE-1: 用户维度 (取当日快照)
-- -----------------------------------------------------------
usr_dim AS 
(
    SELECT  usr_id
            ,usr_nm
            ,email AS email
    FROM    demo_dw.dim_usr_info_df
    WHERE   ds = '${bizdate}'
)
-- -----------------------------------------------------------
-- CTE-2: 店铺维度 (取当日快照)
-- -----------------------------------------------------------
,shop_dim AS 
(
    SELECT  CAST(shop_id AS STRING) AS shop_id_str
            ,shop_pltf_cd
    FROM    demo_dw.dim_store_ds_shop_df
    WHERE   ds = '${bizdate}'
)
-- -----------------------------------------------------------
-- -----------------------------------------------------------
-- CTE-3: 三方商品维度 (取当日快照)
-- -----------------------------------------------------------
,out_item_dim AS 
(
    SELECT  item_id
            ,out_item_dim_id
            ,item_stat_cd
            ,sales_cnt_30d
    FROM    demo_dw.dim_itm_out_item_df
    WHERE   ds = '${bizdate}'
)
-- -----------------------------------------------------------
-- CTE-4: 包裹-子单映射 (防1:N膨胀, 取最新, 来源ODS)
-- -----------------------------------------------------------
,pkg_latest AS 
(
    SELECT  item_no
            ,package_no AS pkg_no
    FROM    (
                SELECT  item_no
                        ,package_no
                        ,ROW_NUMBER() OVER (PARTITION BY item_no ORDER BY id DESC ) AS rn
                FROM    demo_dw.ods_mysql_tang_storage_s_pack_item_ri
            ) t
    WHERE   rn = 1
)
-- -----------------------------------------------------------
-- CTE-5: 采购补充 (防1:N膨胀, 取最新)
-- -----------------------------------------------------------
,pur_latest AS 
(
    SELECT  order_line_id
            ,item_no
            ,rate
    FROM    (
                SELECT  order_line_id
                        ,item_no
                        ,rate
                        ,ROW_NUMBER() OVER (PARTITION BY order_line_id ORDER BY update_time DESC ) AS rn
                FROM    demo_dw.ods_mysql_tang_plugin_t_order_line_purchase_ri
            ) t
    WHERE   rn = 1
)
-- -----------------------------------------------------------
-- CTE-6: 插件商品扩展 (防1:N膨胀, 取最新)
-- -----------------------------------------------------------
,plugin_latest AS
(
    SELECT  item_no
            ,plugin_line_id AS ds_ord_line_no
            ,bd_user_id AS bd_usr_id
            ,bd_user_name AS bd_usr_nm
    FROM    (
                SELECT  item_no
                        ,plugin_line_id
                        ,bd_user_id
                        ,bd_user_name
                        ,ROW_NUMBER() OVER (
                            PARTITION BY plugin_line_id
                            ORDER BY CASE WHEN item_no IS NOT NULL AND TRIM(item_no) <> '' THEN 0 ELSE 1 END
                                     ,CASE WHEN bd_user_id IS NOT NULL OR (bd_user_name IS NOT NULL AND TRIM(bd_user_name) <> '') THEN 0 ELSE 1 END
                                     ,src_pri
                                     ,upd_time DESC
                        ) AS rn
                FROM    (
                            SELECT  item_no
                                    ,plugin_line_id
                                    ,bd_user_id
                                    ,bd_user_name
                                    ,CAST(update_time AS DATETIME) AS upd_time
                                    ,1 AS src_pri
                            FROM    demo_dw.ods_mysql_tang_order_t_item_plugin_ri
                            WHERE   plugin_line_id IS NOT NULL
                            UNION ALL
                            SELECT  item_no
                                    ,plugin_line_id
                                    ,bd_user_id
                                    ,bd_user_name
                                    ,CAST(NULL AS DATETIME) AS upd_time
                                    ,2 AS src_pri
                            FROM    demo_dw.ods_mysql_tang_order_t_item_plugin_supplement_df
                            WHERE   plugin_line_id IS NOT NULL
                        ) s
            ) t
    WHERE   rn = 1
)
-- -----------------------------------------------------------
-- CTE-7: 源表全量快照
-- -----------------------------------------------------------
,source_full AS
(
    SELECT  l.id AS ord_line_no
            ,l.order_id AS ord_no
            ,l.draft_id AS draft_no
            ,l.user_id AS usr_id
            ,u.usr_nm AS usr_nm
            ,u.email AS email
            ,CAST(l.shop_id AS BIGINT)  AS tb_shop_id
            ,l.shop_url AS tb_shop_url
            ,l.shop_name AS tb_shop_nm
            ,NVL(s.shop_pltf_cd,l.channel) AS shop_pltf_cd
            ,NVL(l.status,-1) AS ord_line_stat
            ,pkg.pkg_no AS pkg_no
            ,COALESCE(pl.item_no,p.item_no) AS tb_ord_line_no
            ,pl.bd_usr_id AS bd_usr_id
            ,pl.bd_usr_nm AS bd_usr_nm
            ,NVL(l.goods_type,-1) AS tb_item_type_cd
            ,l.data_source AS data_src
            ,NVL(l.del_flag,0) AS is_del
            ,CAST(l.goods_id AS BIGINT) AS tb_item_id
            ,CAST(l.sku_id AS BIGINT) AS tb_sku_id
            ,l.goods_name AS tb_item_nm
            ,l.goods_name_cn AS tb_item_nm_cn
            ,l.goods_attribute AS tb_item_attr
            ,l.goods_attribute_cn AS tb_item_attr_cn
            ,l.goods_url AS tb_item_url
            ,l.goods_img AS tb_item_img
            ,NVL(CAST(l.price AS DECIMAL(18,4)),0) AS prc
            ,NVL(CAST(l.purchase_amount AS DECIMAL(18,4)),0) AS pur_amt
            ,NVL(CAST(l.discount_amount AS DECIMAL(18,4)),0) AS disc_amt
            ,NVL(CAST(l.return_amount AS DECIMAL(18,4)),0) AS rtn_amt
            ,NVL(CAST(l.postage AS DECIMAL(18,4)),0) AS post_fee
            ,l.provider_type AS splr_type_cd
            ,NVL(l.purchase_type,-1) AS pur_type_cd
            ,NVL(CAST(p.rate AS DECIMAL(18,4)),0) AS pur_rate
            ,NVL(l.nums,0) AS ord_cnt
            ,NVL(l.refund_nums,0) AS ref_cnt
            ,NVL(l.stock_nums,0) AS crsh_cnt
            ,NVL(l.refund_stock_nums,0) AS crsh_ref_cnt
            ,l.third_goods_id AS splr_item_id
            ,l.third_shop_id AS splr_shop_id
            ,NVL(CAST(l.weight AS DECIMAL(18,4)),0) AS wt
            ,l.volume AS vol_desc
            ,l.comment AS rmk
            ,NVL(l.content,'{}') AS xtn_json
            ,o.outer_shop_id AS shop_id
            ,o.outer_shop_name AS shop_nm
            ,o.outer_currency AS ccy
            ,NVL(CAST(o.outer_amount AS DECIMAL(18,4)),0) AS ord_amt
            ,o.outer_goods_attribute AS item_attr
            ,o.outer_goods_name AS item_nm
            ,o.outer_goods_img AS item_img
            ,NVL(o.outer_nums,0) AS item_cnt
            ,o.outer_line_id AS line_id
            ,o.outer_goods_id AS item_id
            ,o.outer_sku_id AS sku_id
            ,tp.out_item_dim_id AS item_dim_id
            ,tp.item_stat_cd AS item_stat_cd
            ,NVL(tp.sales_cnt_30d,0) AS sales_cnt_30d
            ,CAST(l.create_time AS DATETIME) AS crt_time
            ,CAST(l.update_time AS DATETIME) AS upd_time
            ,CAST(o.create_time AS DATETIME) AS rcd_crt_time
    FROM    demo_dw.ods_mysql_tang_plugin_t_draft_order_line_ri l
    LEFT JOIN demo_dw.ods_mysql_tang_plugin_t_order_line_outer_ri o
    ON      l.id = o.order_line_id
    LEFT JOIN pur_latest p
    ON      l.id = p.order_line_id
    LEFT JOIN plugin_latest pl
    ON      l.id = pl.ds_ord_line_no
    LEFT JOIN pkg_latest pkg
    ON      l.item_no = pkg.item_no
    LEFT JOIN usr_dim u
    ON      l.user_id = u.usr_id
    LEFT JOIN shop_dim s
    ON      o.outer_shop_id = s.shop_id_str
    LEFT JOIN out_item_dim tp
    ON      o.outer_goods_id = tp.item_id
)
-- -----------------------------------------------------------
-- 写入: 源表全量快照直接覆盖当日分区
-- -----------------------------------------------------------
INSERT OVERWRITE TABLE demo_dw.dwd_trd_ds_ord_line_df PARTITION (ds = '${bizdate}')
SELECT  ord_line_no AS ord_line_no
        ,ord_no AS ord_no
        ,draft_no AS draft_no
        ,usr_id AS usr_id
        ,usr_nm AS usr_nm
        ,email AS email
        ,tb_shop_id AS tb_shop_id
        ,tb_shop_url AS tb_shop_url
        ,tb_shop_nm AS tb_shop_nm
        ,shop_pltf_cd AS shop_pltf_cd
        ,ord_line_stat AS ord_line_stat
        ,pkg_no AS pkg_no
        ,tb_ord_line_no AS tb_ord_line_no
        ,tb_item_type_cd AS tb_item_type_cd
        ,data_src AS data_src
        ,is_del AS is_del
        ,tb_item_id AS tb_item_id
        ,tb_sku_id AS tb_sku_id
        ,tb_item_nm AS tb_item_nm
        ,tb_item_nm_cn AS tb_item_nm_cn
        ,tb_item_attr AS tb_item_attr
        ,tb_item_attr_cn AS tb_item_attr_cn
        ,tb_item_url AS tb_item_url
        ,tb_item_img AS tb_item_img
        ,prc AS prc
        ,pur_amt AS pur_amt
        ,disc_amt AS disc_amt
        ,rtn_amt AS rtn_amt
        ,post_fee AS post_fee
        ,splr_type_cd AS splr_type_cd
        ,pur_type_cd AS pur_type_cd
        ,pur_rate AS pur_rate
        ,ord_cnt AS ord_cnt
        ,ref_cnt AS ref_cnt
        ,crsh_cnt AS crsh_cnt
        ,crsh_ref_cnt AS crsh_ref_cnt
        ,splr_item_id AS splr_item_id
        ,splr_shop_id AS splr_shop_id
        ,wt AS wt
        ,vol_desc AS vol_desc
        ,rmk AS rmk
        ,xtn_json AS xtn_json
        ,shop_id AS shop_id
        ,shop_nm AS shop_nm
        ,ccy AS ccy
        ,ord_amt AS ord_amt
        ,item_attr AS item_attr
        ,item_nm AS item_nm
        ,item_img AS item_img
        ,item_cnt AS item_cnt
        ,line_id AS line_id
        ,item_id AS item_id
        ,sku_id AS sku_id
        ,item_dim_id AS item_dim_id
        ,item_stat_cd AS item_stat_cd
        ,sales_cnt_30d AS sales_cnt_30d
        ,crt_time AS crt_time
        ,upd_time AS upd_time
        ,rcd_crt_time AS rcd_crt_time
        ,bd_usr_id AS bd_usr_id
        ,bd_usr_nm AS bd_usr_nm
FROM    source_full
;
