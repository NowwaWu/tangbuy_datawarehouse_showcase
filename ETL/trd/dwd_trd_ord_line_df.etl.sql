--MaxCompute SQL
--********************************************************************--
--author: 吴延俊
--create time: 2026-05-11 12:07:06
-- 数据域:   trd (交易域)
-- 业务过程: ord (网站原生订单)
-- 表名:     dwd_trd_ord_line_df
-- 表类型:   明细事实表 (DWD Detail) - 日全量快照
-- 描述:     网站原生订单子单日全量快照，以 item_no 为粒度，
--           整合子单主表/插件商品扩展/订单主表(拿user_id/storage_no)，
--           冗余用户维度(usr_nm/email)和仓库维度(wh_nm)，
--           为下游 DWS/ADS 提供统一的网站原生订单子单主数据出口。
-- 粒度:     一行 = 一个网站原生订单子单 (item_no)
-- 来源:
--   ods_mysql_tang_order_t_order_item_ri      (子单主表, 驱动表)
--   ods_mysql_tang_order_t_order_ri           (订单主表, N:1→取user_id/storage_no)
--   ods_mysql_tang_order_t_item_plugin_ri     (插件商品扩展, 1:N→ROW_NUMBER取最新)
-- 维度冗余:
--   dim_usr_info_df       (LEFT JOIN usr_id → usr_nm, email)
--   dim_wh_warehouse_df   (LEFT JOIN wh_id → wh_nm)
-- 更新策略: 底层源表为全量表，每日从源表全量重算并 INSERT OVERWRITE 写入当日分区
-- 调度周期: 日
-- 调度变量: ${bizdate} 格式 yyyyMMdd
-- 防膨胀:
--   t_item_plugin 1:N → ROW_NUMBER 取 rn=1
-- 零NULL:
--   数值度量 → 0/-99, 字符串 → '未知', JSON → '{}', 布尔 → 0, 时间保留 NULL
--********************************************************************--
WITH -- -----------------------------------------------------------
-- CTE-1: 插件商品扩展 (防1:N膨胀, 取最新)
-- -----------------------------------------------------------
plugin_latest AS 
(
    SELECT  item_no
            ,plugin_order_id AS ds_ord_no
            ,plugin_line_id AS ds_ord_line_no
            ,bd_user_name AS bd_usr_nm
            ,CAST(purchase_suggestion_price AS DECIMAL(18,4)) AS pur_sugg_prc
            ,CAST(purchase_suggestion_post_price AS DECIMAL(18,4)) AS pur_sugg_post_prc
            ,combine_goods_id AS cmb_item_id
            ,combine_goods_name AS cmb_item_nm
            ,combine_goods_attribute AS cmb_item_attr
            ,combine_goods_img AS cmb_item_img
            ,combine_goods_url AS cmb_item_url
            ,CAST(GET_JSON_OBJECT(content,'$.preferredAmount') AS DECIMAL(18,4)) AS inner_sales_prc
            ,CAST(GET_JSON_OBJECT(content,'$.affiliatesAmount') AS DECIMAL(18,4)) AS inner_aff_prc
            ,CAST(GET_JSON_OBJECT(content,'$.preferredAmountOrigin') AS DECIMAL(18,4)) AS inner_src_prc
            ,content AS plugin_cnt_json
    FROM    (
                SELECT  item_no
                        ,plugin_order_id
                        ,plugin_line_id
                        ,bd_user_name
                        ,purchase_suggestion_price
                        ,purchase_suggestion_post_price
                        ,combine_goods_id
                        ,combine_goods_name
                        ,combine_goods_attribute
                        ,combine_goods_img
                        ,combine_goods_url
                        ,content
                        ,ROW_NUMBER() OVER (PARTITION BY item_no ORDER BY update_time DESC ) AS rn
                FROM    demo_dw.ods_mysql_tang_order_t_item_plugin_ri
                union all
                SELECT  item_no
                        ,plugin_order_id
                        ,plugin_line_id
                        ,bd_user_name
                        ,purchase_suggestion_price
                        ,purchase_suggestion_post_price
                        ,combine_goods_id
                        ,combine_goods_name
                        ,combine_goods_attribute
                        ,combine_goods_img
                        ,combine_goods_url
                        ,content
                        ,1 AS rn
                FROM    demo_dw.ods_mysql_tang_order_t_item_plugin_supplement_df
            ) t
    WHERE   rn = 1
)
-- -----------------------------------------------------------
-- CTE-2: 用户维度 (取前一天快照)
-- -----------------------------------------------------------
,usr_dim AS 
(
    SELECT  usr_id
            ,usr_nm
            ,email AS email
    FROM    demo_dw.dim_usr_info_df
    WHERE   ds = '${bizdate}'
)
-- -----------------------------------------------------------
-- CTE-2b: 主站指定用户BD映射
-- -----------------------------------------------------------
,main_site_bd_usr AS
(
    SELECT CAST('0a33a7a008f982c' AS BIGINT) AS usr_id, 'fiona_li' AS bd_usr_nm
    UNION ALL SELECT CAST('cb7cbe375c84d79' AS BIGINT), 'fiona_li'
    UNION ALL SELECT CAST('649c7bee151d50' AS BIGINT), 'fiona_li'
    UNION ALL SELECT CAST('390ccbe666beac' AS BIGINT), 'fiona_li'
    UNION ALL SELECT CAST('3ceb4aad1d4b754' AS BIGINT), 'fiona_li'
    UNION ALL SELECT CAST('5cf5b1bc6b7693a' AS BIGINT), 'fiona_li'
    UNION ALL SELECT CAST('10c4687ea6d155e' AS BIGINT), 'ryan'
    UNION ALL SELECT CAST('b61369531a66e03' AS BIGINT), 'ryan'
    UNION ALL SELECT CAST('68ca56e605f41b' AS BIGINT), 'even_chen'
    UNION ALL SELECT CAST('56435b1c2cf20f' AS BIGINT), 'even_chen'
    UNION ALL SELECT CAST('739039cf4a03a7' AS BIGINT), 'even_chen'
    UNION ALL SELECT CAST('e4e5a865ddb650' AS BIGINT), 'even_chen'
    UNION ALL SELECT CAST('f2e93d3cbc1e78' AS BIGINT), 'even_chen'
    UNION ALL SELECT CAST('fe2c161ac14a525' AS BIGINT), 'lydia_wen'
    UNION ALL SELECT CAST('706e27169cc863' AS BIGINT), 'jiayi_Li'
)
-- -----------------------------------------------------------
-- CTE-3: 仓库维度 (取前一天快照)
-- -----------------------------------------------------------
,wh_dim AS 
(
    SELECT  wh_id
            ,wh_nm
    FROM    demo_dw.dim_wh_warehouse_df
    WHERE   ds = '${bizdate}'
)
-- -----------------------------------------------------------
-- CTE-4: 包裹关系 (防1:N膨胀, 取最新)
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
-- CTE-5: 源表全量快照
-- -----------------------------------------------------------
,source_full AS
(
    SELECT      -- 主键/外键
            i.item_no AS ord_line_no
            ,i.order_no AS ord_no -- 订单维度键 (来自父单)
            ,o.user_id AS usr_id
            ,o.storage_no AS wh_id
            ,o.company_id AS cmpny_id -- 用户维度冗余
            ,u.usr_nm AS usr_nm
            ,u.email AS email -- 仓库维度冗余
            ,w.wh_nm AS wh_nm -- 商品信息 (子单快照)
            -- Reviewer Fix: item_id/sku_id 源表为STRING, DWD统一CAST为BIGINT, 兜底 -99
            ,NVL(CAST(i.goods_id AS BIGINT),-99) AS item_id
            ,NVL(CAST(i.sku_id AS BIGINT),-99) AS sku_id
            ,i.goods_name AS item_nm
            ,i.goods_name_cn AS item_nm_cn
            ,i.goods_attribute AS item_attr
            ,i.goods_attribute_cn AS item_attr_cn
            ,i.goods_url AS item_url
            ,i.goods_img AS item_img -- 状态/类型
            ,NVL(i.goods_status,-1) AS ord_line_stat
            ,CASE   WHEN i.goods_status = -1 THEN '待支付'
                    WHEN i.goods_status = 0 THEN '待接单'
                    WHEN i.goods_status = 2 THEN '待补款'
                    WHEN i.goods_status = 5 THEN '已发货'
                    WHEN i.goods_status = 6 THEN '分开发货'
                    WHEN i.goods_status = 8 THEN '已签收'
                    WHEN i.goods_status = 9 THEN '已到货'
                    WHEN i.goods_status = 10 THEN '已入库'
                    WHEN i.goods_status = 11 THEN '作废'
                    WHEN i.goods_status = 12 THEN '销毁'
                    WHEN i.goods_status = 14 THEN '待确认'
                    WHEN i.goods_status = 16 THEN '退货等待中'
                    WHEN i.goods_status = 17 THEN '换货等待中'
                    WHEN i.goods_status = 18 THEN '退货处理中'
                    WHEN i.goods_status = 19 THEN '换货处理中'
                    WHEN i.goods_status = 20 THEN '退货完成'
                    WHEN i.goods_status = 22 THEN '已订购'
                    WHEN i.goods_status = 24 THEN '取消订购'
                    WHEN i.goods_status = 25 THEN '异常订单'
                    WHEN i.goods_status = 26 THEN '退货等待退款'
                    WHEN i.goods_status = 27 THEN '换货等待卖家发货'
                    WHEN i.goods_status = 28 THEN '出库中'
                    WHEN i.goods_status = 29 THEN '出库打包完毕'
                    WHEN i.goods_status = 30 THEN '寄送海外'
                    WHEN i.goods_status = 31 THEN '已收到货'
                    WHEN i.goods_status = 33 THEN '风控审核'
                    WHEN i.goods_status = 34 THEN '已撤单'
                    WHEN i.goods_status = 35 THEN '冻结列表'
                    WHEN i.goods_status = 36 THEN '预定补款'
                    WHEN i.goods_status = 37 THEN '等待出库'
                    WHEN i.goods_status = 38 THEN '退款审核中'
                    WHEN i.goods_status = 39 THEN '拒签商品'
                    WHEN i.goods_status = 40 THEN '拒签完成'
                    WHEN i.goods_status = 41 THEN '异常未入'
                    WHEN i.goods_status = 42 THEN '异常已入'
                    WHEN i.goods_status = 50 THEN '强制完成'
                    WHEN i.goods_status = 23 THEN '处理中'
                    WHEN i.goods_status = -2 THEN '支付中'
                    WHEN i.goods_status = 45 THEN '已签收待处理'
                    WHEN i.goods_status = 46 THEN '巴拿马待生成'
                    WHEN i.goods_status = 47 THEN '巴拿马待支付'
                    WHEN i.goods_status = 21 THEN '换货作废'
                    WHEN i.goods_status = 49 THEN '放弃商品'
                    WHEN i.goods_status = 51 THEN '等待卖家同意退货'
                    WHEN i.goods_status = 53 THEN '退包作废'
                    WHEN i.goods_status = 52 THEN '等待卖家同意换货'
                    WHEN i.goods_status = 54 THEN '1688待生成'
                    WHEN i.goods_status = 55 THEN '1688待支付'
                    WHEN i.goods_status = 56 THEN 'yino待生成'
                    WHEN i.goods_status = 57 THEN 'yino待支付'
                    WHEN i.goods_status = 58 THEN '仓库处理中'
                    ELSE '未知状态'
            END AS ord_line_stat_nm
            ,NVL(i.confirm_status,-1) AS cfm_stat
            ,NVL(i.return_status,-1) AS rtn_stat
            ,NVL(i.sale_type,-1) AS sales_type_cd
            ,NVL(i.exception_type,-1) AS abn_type_cd
            ,NVL(i.cart_purchase_type,-1) AS cart_pur_type_cd
            ,NVL(i.show_way,-1) AS show_way_cd -- 布尔标记
            ,NVL(i.express_delivery,0) AS is_exprs_dlyd
            ,NVL(i.need_confirm,0) AS is_need_cfm
            ,NVL(i.deferred_type,0) AS is_deferred -- 数量/价格度量
            ,NVL(i.nums,0) AS ord_cnt
            ,NVL(CAST(i.unit_price AS DECIMAL(18,4)),0) AS prc
            ,NVL(CAST(i.write_price AS DECIMAL(18,4)),0) AS pur_prc
            ,NVL(CAST(i.virtual_price AS DECIMAL(18,4)),0) AS vrtl_prc
            ,NVL(CAST(i.discount_amount AS DECIMAL(18,4)),0) AS disc_amt
            ,NVL(CAST(i.goods_fil AS DECIMAL(18,4)),0) AS item_xtra_amt
            ,NVL(CAST(i.goods_need_fil AS DECIMAL(18,4)),0) AS item_pend_xtra_amt
            ,NVL(CAST(i.booked_fil AS DECIMAL(18,4)),0) AS booked_xtra_amt
            ,NVL(CAST(i.goods_return AS DECIMAL(18,4)),0) AS rtn_amt
            ,NVL(CAST(i.return_fee AS DECIMAL(18,4)),0) AS rtn_fee
            ,NVL(CAST(i.back_postage AS DECIMAL(18,4)),0) AS back_post_amt
            ,NVL(CAST(i.insurance_back AS DECIMAL(18,4)),0) AS ins_back_amt
            ,NVL(CAST(i.fee_customize AS DECIMAL(18,4)),0) AS custom_fee -- 重量
            ,NVL(CAST(i.weight AS DECIMAL(18,4)),0) AS wt -- 快递/物流
            ,pkg.pkg_no AS pkg_no
            ,i.express_no AS exprs_no
            ,i.express_id AS exprs_id
            ,i.express AS exprs_nm -- 采购/寻源
            ,i.purchase_no AS pur_no -- 仓储
            ,i.position_no AS bin_no
            ,i.mail_limit AS ml_lmt
            ,i.inventory_id AS inv_id -- 类目/用户分类
            ,i.category_id AS ctgy_id
            ,i.user_cid AS usr_cid -- 时间里程碑
            ,CAST(i.purchase_time AS DATETIME) AS pur_time
            ,CAST(i.signed_time AS DATETIME) AS sign_time
            ,CAST(i.storage_out_time AS DATETIME) AS stor_out_time -- 备注/扩展
            ,i.goods_comment AS item_rmk
            ,i.goods_extension AS item_rmk_img
            ,i.comment AS usr_rmk
            ,CAST(i.goods_comment_time AS DATETIME) AS rmk_time
            ,i.data_source AS data_src
            ,i.volume AS vol_desc -- 插件商品扩展 (DS代发订单关联)
            ,p.ds_ord_no AS ds_ord_no
            ,p.ds_ord_line_no AS ds_ord_line_no
            ,CASE   WHEN p.bd_usr_nm IS NOT NULL
                        AND TRIM(p.bd_usr_nm) <> ''
                    THEN p.bd_usr_nm
                    ELSE b.bd_usr_nm
            END AS bd_usr_nm
            ,NVL(p.pur_sugg_prc,0) AS pur_sugg_prc
            ,NVL(p.pur_sugg_post_prc,0) AS pur_sugg_post_prc
            ,p.cmb_item_id AS cmb_item_id
            ,p.cmb_item_nm AS cmb_item_nm
            ,p.cmb_item_attr AS cmb_item_attr
            ,p.cmb_item_img AS cmb_item_img
            ,p.cmb_item_url AS cmb_item_url
            ,NVL(CAST(GET_JSON_OBJECT(i.extend_field,'$.preferredAmount') AS DECIMAL(18,4)),0) AS inner_sales_prc
            ,NVL(CAST(GET_JSON_OBJECT(i.extend_field,'$.affiliatesAmount') AS DECIMAL(18,4)),0) AS inner_aff_prc
            ,NVL(CAST(GET_JSON_OBJECT(i.extend_field,'$.preferredAmountOrigin') AS DECIMAL(18,4)),0) AS inner_src_prc
            ,NVL(p.plugin_cnt_json,'{}') AS plugin_cnt_json -- JSON扩展
            ,NVL(i.extend_field,'{}') AS xtn_json -- 时间
            ,CAST(i.create_time AS DATETIME) AS crt_time
            ,CAST(i.update_time AS DATETIME) AS upd_time
    FROM    demo_dw.ods_mysql_tang_order_t_order_item_ri i
    LEFT JOIN demo_dw.ods_mysql_tang_order_t_order_ri o
    ON      i.order_no = o.order_no
    LEFT JOIN plugin_latest p
    ON      i.item_no = p.item_no
    LEFT JOIN pkg_latest pkg
    ON      i.item_no = pkg.item_no
    LEFT JOIN usr_dim u
    ON      o.user_id = u.usr_id
    LEFT JOIN wh_dim w
    ON      o.storage_no = w.wh_id
    LEFT JOIN main_site_bd_usr b
    ON      o.user_id = b.usr_id
)
-- -----------------------------------------------------------
-- 写入: 源表全量快照直接覆盖当日分区
-- -----------------------------------------------------------
INSERT OVERWRITE TABLE demo_dw.dwd_trd_ord_line_df PARTITION (ds = '${bizdate}')
SELECT  ord_line_no AS ord_line_no
        ,ord_no AS ord_no
        ,usr_id AS usr_id
        ,wh_id AS wh_id
        ,cmpny_id AS cmpny_id
        ,usr_nm AS usr_nm
        ,email AS email
        ,wh_nm AS wh_nm
        ,item_id AS item_id
        ,sku_id AS sku_id
        ,item_nm AS item_nm
        ,item_nm_cn AS item_nm_cn
        ,item_attr AS item_attr
        ,item_attr_cn AS item_attr_cn
        ,item_url AS item_url
        ,item_img AS item_img
        ,ord_line_stat AS ord_line_stat
        ,ord_line_stat_nm AS ord_line_stat_nm
        ,cfm_stat AS cfm_stat
        ,rtn_stat AS rtn_stat
        ,sales_type_cd AS sales_type_cd
        ,abn_type_cd AS abn_type_cd
        ,cart_pur_type_cd AS cart_pur_type_cd
        ,show_way_cd AS show_way_cd
        ,is_exprs_dlyd AS is_exprs_dlyd
        ,is_need_cfm AS is_need_cfm
        ,is_deferred AS is_deferred
        ,ord_cnt AS ord_cnt
        ,prc AS prc
        ,pur_prc AS pur_prc
        ,vrtl_prc AS vrtl_prc
        ,disc_amt AS disc_amt
        ,item_xtra_amt AS item_xtra_amt
        ,item_pend_xtra_amt AS item_pend_xtra_amt
        ,booked_xtra_amt AS booked_xtra_amt
        ,rtn_amt AS rtn_amt
        ,rtn_fee AS rtn_fee
        ,back_post_amt AS back_post_amt
        ,ins_back_amt AS ins_back_amt
        ,custom_fee AS custom_fee
        ,wt AS wt
        ,pkg_no AS pkg_no
        ,exprs_no AS exprs_no
        ,exprs_id AS exprs_id
        ,exprs_nm AS exprs_nm
        ,pur_no AS pur_no
        ,bin_no AS bin_no
        ,ml_lmt AS ml_lmt
        ,inv_id AS inv_id
        ,ctgy_id AS ctgy_id
        ,usr_cid AS usr_cid
        ,pur_time AS pur_time
        ,sign_time AS sign_time
        ,stor_out_time AS stor_out_time
        ,item_rmk AS item_rmk
        ,item_rmk_img AS item_rmk_img
        ,usr_rmk AS usr_rmk
        ,rmk_time AS rmk_time
        ,data_src AS data_src
        ,vol_desc AS vol_desc
        ,ds_ord_no AS ds_ord_no
        ,ds_ord_line_no AS ds_ord_line_no
        ,bd_usr_nm AS bd_usr_nm
        ,pur_sugg_prc AS pur_sugg_prc
        ,pur_sugg_post_prc AS pur_sugg_post_prc
        ,cmb_item_id AS cmb_item_id
        ,cmb_item_nm AS cmb_item_nm
        ,cmb_item_attr AS cmb_item_attr
        ,cmb_item_img AS cmb_item_img
        ,cmb_item_url AS cmb_item_url
        ,inner_sales_prc AS inner_sales_prc
        ,inner_aff_prc AS inner_aff_prc
        ,inner_src_prc AS inner_src_prc
        ,plugin_cnt_json AS plugin_cnt_json
        ,xtn_json AS xtn_json
        ,crt_time AS crt_time
        ,upd_time AS upd_time
FROM    source_full
;
