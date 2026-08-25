--MaxCompute SQL
--********************************************************************--
--author: 吴延俊
--create time: 2026-05-07 17:27:14
-- 数据域:   trd (交易域)
-- 业务过程: ds_ord (DS代发订单)
-- 表名:     dwd_trd_ds_ord_header_df
-- 表类型:   累积快照事实表 (Accumulating Snapshot) - 日全量快照
-- ETL方式:  当日增量(create_time OR update_time) FULL OUTER JOIN 昨日快照,
--           INSERT OVERWRITE 写入当日分区, 捕获订单创建及后续变更
-- 调度变量: ${bizdate} 格式 yyyyMMdd
-- 防膨胀:
--   draft_order_package 1:N → CTE中 ROW_NUMBER 取 rn=1 + WM_CONCAT 聚合包裹号
-- 零NULL:
--   数值度量 → 0/ -99, 字符串 → '未知', JSON → '{}', 布尔 → 0, 时间保留 NULL
--   地址表 LEFT JOIN 未匹配时 rcv_* 全部兜底
-- 依赖:
--   dim_usr_info_df (读取前一天分区)
--   dim_store_ds_shop_df (读取前一天分区)
--********************************************************************--

WITH -- -----------------------------------------------------------
-- CTE-1: 包裹聚合 (1:N → 1:1), 取最新包裹 + 汇总
-- -----------------------------------------------------------
pkg_agg AS 
(
    SELECT  order_id
            ,COUNT(1) AS pkg_cnt
            ,WM_CONCAT(',',package_no) AS pkg_no_list
            ,MAX(CASE    WHEN rn = 1 THEN package_no END) AS pkg_latest_no
            ,MAX(CASE    WHEN rn = 1 THEN line_id END) AS pkg_latest_line_id
            ,MAX(CASE    WHEN rn = 1 THEN line_name END) AS pkg_latest_line_nm
            ,MAX(CASE    WHEN rn = 1 THEN delivery_time END) AS pkg_latest_dly_tm
            ,MAX(CASE    WHEN rn = 1 THEN express_no END) AS pkg_latest_exprs_no
            ,MAX(CASE    WHEN rn = 1 THEN logistic END) AS pkg_latest_logis_nm
            ,MAX(CASE    WHEN rn = 1 THEN logistic_id END) AS pkg_latest_logis_id
            ,MAX(CASE    WHEN rn = 1 THEN CAST(total_amount_pre AS DECIMAL(18,4)) END) AS pkg_est_amt
            ,MAX(CASE    WHEN rn = 1 THEN CAST(total_amount_act AS DECIMAL(18,4)) END) AS pkg_actl_amt
            ,MAX(CASE    WHEN rn = 1 THEN CAST(weight AS DECIMAL(18,4)) END) AS pkg_est_wt
            ,MAX(CASE    WHEN rn = 1 THEN CAST(weight_act AS DECIMAL(18,4)) END) AS pkg_actl_wt
            ,MAX(CASE    WHEN rn = 1 THEN CAST(fill_amount AS DECIMAL(18,4)) END) AS pkg_pend_amt
            ,MAX(CASE    WHEN rn = 1 THEN CAST(filled_amount AS DECIMAL(18,4)) END) AS pkg_payd_amt
            ,MAX(CASE    WHEN rn = 1 THEN CAST(refund_amount AS DECIMAL(18,4)) END) AS pkg_ref_amt
            ,MAX(CASE    WHEN rn = 1 THEN comment END) AS pkg_rmk
            ,MAX(CASE    WHEN rn = 1 THEN package_choosed_content END) AS pkg_cfg_json
            ,MAX(CASE    WHEN rn = 1 THEN package_fee_content END) AS pkg_fee_json
            ,MAX(
                CASE    WHEN rn = 1 THEN CASE    WHEN INSTR(GET_JSON_OBJECT(package_choosed_content,'$.incrementList'),'"10"') > 0 THEN '极简包装'
                                WHEN INSTR(GET_JSON_OBJECT(package_choosed_content,'$.incrementList'),'"11"') > 0 THEN '纸箱包装'
                                ELSE '未知包装'
                        END END
            ) AS pkg_wrap_cd
    FROM    (
                SELECT  order_id
                        ,package_no
                        ,line_id
                        ,line_name
                        ,delivery_time
                        ,express_no
                        ,logistic
                        ,logistic_id
                        ,total_amount_pre
                        ,total_amount_act
                        ,weight
                        ,weight_act
                        ,fill_amount
                        ,filled_amount
                        ,refund_amount
                        ,comment
                        ,package_choosed_content
                        ,package_fee_content
                        ,ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY create_time DESC ) AS rn
                FROM    demo_dw.ods_mysql_tang_plugin_t_draft_order_package_ri
            ) t
    GROUP BY order_id
) -- -----------------------------------------------------------
-- CTE-2: 用户维度 (取前一天快照)
-- -----------------------------------------------------------
,usr_dim AS 
(
    SELECT  usr_id
            ,usr_nm
            ,email AS email
    FROM    demo_dw.dim_usr_info_df
    WHERE   ds = '${bizdate}'
) -- -----------------------------------------------------------
-- CTE-3: 店铺维度 (取前一天快照)
-- -----------------------------------------------------------
,shop_dim AS 
(
    SELECT  CAST(shop_id AS STRING) AS shop_id_str
            ,shop_pltf_cd
    FROM    demo_dw.dim_store_ds_shop_df
    WHERE   ds = '${bizdate}'
) -- -----------------------------------------------------------
-- CTE-4: 当日增量 (新建或更新的订单)
-- -----------------------------------------------------------
,today_delta AS 
(
    SELECT  o.id AS ord_no
            ,o.user_id AS usr_id
            ,u.usr_nm AS usr_nm
            ,u.email AS email
            ,NVL(o.status,-1) AS ord_stat
            ,NVL(o.type,-1) AS ord_type_cd
            ,o.pay_no AS pay_no
            ,CAST(o.pay_time AS DATETIME) AS pay_time
            ,NVL(CAST(o.purchase_amount AS DECIMAL(18,4)),0) AS pur_amt
            ,NVL(CAST(o.refund_goods_amount AS DECIMAL(18,4)),0) AS ref_amt
            ,o.language AS lang
            ,o.country AS cntry
            ,CAST(o.country_id AS BIGINT) AS cntry_id
            ,o.crash AS crsh
            ,o.cancel_reason AS cxl_rsn
            ,o.cancel_reason_id AS cxl_rsn_id
            ,NVL(o.expire_time,0) AS exp_tm
            ,NVL(o.content,'{}') AS xtn_json
            ,NVL(o.del_flag,0) AS is_del
            ,r.outer_order_id AS out_ord_id
            ,r.outer_order_no AS out_ord_no
            ,r.outer_shop_id AS shop_id
            ,r.outer_shop_name AS shop_nm
            ,s.shop_pltf_cd AS shop_pltf_cd
            ,r.outer_currency AS ccy
            ,NVL(CAST(r.outer_order_amount AS DECIMAL(18,4)),0) AS ord_amt
            ,r.outer_comment AS ord_rmk
            ,NVL(r.content,'{}') AS cnt_json
            ,CAST(r.outer_create_time AS DATETIME) AS out_crt_time
            ,CAST(r.outer_update_time AS DATETIME) AS out_upd_time
            ,a.name AS rcv_nm
            ,a.first_name AS rcv_fn
            ,a.last_name AS rcv_ln
            ,a.email AS rcv_email
            ,a.phone AS rcv_phn
            ,a.company AS rcv_cmpny
            ,a.country AS rcv_cntry
            ,CAST(a.country_id AS BIGINT) AS rcv_cntry_id
            ,a.country_code AS rcv_cntry_cd
            ,a.province AS rcv_prov
            ,a.province_code AS rcv_prov_cd
            ,a.city AS rcv_city
            ,a.address1 AS rcv_addr1
            ,a.address2 AS rcv_addr2
            ,a.zip AS rcv_zip
            ,a.latitude AS rcv_lat
            ,a.longitude AS rcv_lng
            ,NVL(p.pkg_cnt,0) AS pkg_cnt
            ,p.pkg_no_list AS pkg_no_list
            ,p.pkg_latest_no AS pkg_latest_no
            ,p.pkg_latest_line_id AS pkg_latest_line_id
            ,p.pkg_latest_line_nm AS pkg_latest_line_nm
            ,p.pkg_latest_dly_tm AS pkg_latest_dly_tm
            ,p.pkg_latest_exprs_no AS pkg_latest_exprs_no
            ,p.pkg_latest_logis_nm AS pkg_latest_logis_nm
            ,p.pkg_latest_logis_id AS pkg_latest_logis_id
            ,NVL(p.pkg_est_amt,0) AS pkg_est_amt
            ,NVL(p.pkg_actl_amt,0) AS pkg_actl_amt
            ,NVL(p.pkg_est_wt,0) AS pkg_est_wt
            ,NVL(p.pkg_actl_wt,0) AS pkg_actl_wt
            ,NVL(p.pkg_pend_amt,0) AS pkg_pend_amt
            ,NVL(p.pkg_payd_amt,0) AS pkg_payd_amt
            ,NVL(p.pkg_ref_amt,0) AS pkg_ref_amt
            ,p.pkg_rmk AS pkg_rmk
            ,NVL(p.pkg_cfg_json,'{}') AS pkg_cfg_json
            ,NVL(p.pkg_fee_json,'{}') AS pkg_fee_json
            ,NVL(p.pkg_wrap_cd,                      '未知包装')                 AS pkg_wrap_cd
            ,CAST(o.create_time AS DATETIME) AS crt_time
            ,CAST(o.update_time AS DATETIME) AS upd_time
            ,CAST(r.create_time AS DATETIME) AS rcd_crt_time
    FROM    demo_dw.ods_mysql_tang_plugin_t_draft_order_ri o
    LEFT JOIN demo_dw.ods_mysql_tang_plugin_t_order_outer_ri r
    ON      o.id = r.order_id
    LEFT JOIN demo_dw.ods_mysql_tang_plugin_t_draft_order_address_ri a
    ON      o.id = a.order_id
    LEFT JOIN pkg_agg p
    ON      o.id = p.order_id
    LEFT JOIN usr_dim u
    ON      o.user_id = u.usr_id
    LEFT JOIN shop_dim s
    ON      r.outer_shop_id = s.shop_id_str
    WHERE   (
                CAST(o.create_time AS DATETIME) >= TO_DATE('${bizdate}','yyyymmdd')
                AND     CAST(o.create_time AS DATETIME) < DATEADD(TO_DATE('${bizdate}','yyyymmdd'),1,'dd')
    )
    OR      (
                CAST(o.update_time AS DATETIME) >= TO_DATE('${bizdate}','yyyymmdd')
                AND     CAST(o.update_time AS DATETIME) < DATEADD(TO_DATE('${bizdate}','yyyymmdd'),1,'dd')
    )
) -- -----------------------------------------------------------
-- CTE-5: 昨日快照
-- -----------------------------------------------------------
,yesterday AS 
(
    SELECT  ord_no
            ,usr_id
            ,usr_nm
            ,email
            ,ord_stat
            ,ord_type_cd
            ,pay_no
            ,pay_time
            ,pur_amt
            ,ref_amt
            ,lang
            ,cntry
            ,cntry_id
            ,crsh
            ,cxl_rsn
            ,cxl_rsn_id
            ,exp_tm
            ,xtn_json
            ,is_del
            ,out_ord_id
            ,out_ord_no
            ,shop_id
            ,shop_nm
            ,shop_pltf_cd
            ,ccy
            ,ord_amt
            ,ord_rmk
            ,cnt_json
            ,out_crt_time
            ,out_upd_time
            ,rcv_nm
            ,rcv_fn
            ,rcv_ln
            ,rcv_email
            ,rcv_phn
            ,rcv_cmpny
            ,rcv_cntry
            ,rcv_cntry_id
            ,rcv_cntry_cd
            ,rcv_prov
            ,rcv_prov_cd
            ,rcv_city
            ,rcv_addr1
            ,rcv_addr2
            ,rcv_zip
            ,rcv_lat
            ,rcv_lng
            ,pkg_cnt
            ,pkg_no_list
            ,pkg_latest_no
            ,pkg_latest_line_id
            ,pkg_latest_line_nm
            ,pkg_latest_dly_tm
            ,pkg_latest_exprs_no
            ,pkg_latest_logis_nm
            ,pkg_latest_logis_id
            ,pkg_est_amt
            ,pkg_actl_amt
            ,pkg_est_wt
            ,pkg_actl_wt
            ,pkg_pend_amt
            ,pkg_payd_amt
            ,pkg_ref_amt
            ,pkg_rmk
            ,pkg_cfg_json
            ,pkg_fee_json
            ,pkg_wrap_cd
            ,crt_time
            ,upd_time
            ,rcd_crt_time
    FROM    demo_dw.dwd_trd_ds_ord_header_df
    WHERE   ds = TO_CHAR(DATEADD(TO_DATE('${bizdate}','yyyymmdd'),-1,'dd'),'yyyymmdd')
) -- -----------------------------------------------------------
-- 写入: 当日增量 FULL OUTER JOIN 昨日快照, COALESCE 取最新值
-- -----------------------------------------------------------
INSERT OVERWRITE TABLE demo_dw.dwd_trd_ds_ord_header_df PARTITION (ds = '${bizdate}')
SELECT  NVL(t.ord_no,y.ord_no) AS ord_no
        ,NVL(t.usr_id,y.usr_id) AS usr_id
        ,COALESCE(t.usr_nm,y.usr_nm) AS usr_nm
        ,COALESCE(t.email,y.email) AS email
        ,COALESCE(t.ord_stat,y.ord_stat) AS ord_stat
        ,COALESCE(t.ord_type_cd,y.ord_type_cd) AS ord_type_cd
        ,COALESCE(t.pay_no,y.pay_no) AS pay_no
        ,COALESCE(t.pay_time,y.pay_time) AS pay_time
        ,COALESCE(t.pur_amt,y.pur_amt) AS pur_amt
        ,COALESCE(t.ref_amt,y.ref_amt) AS ref_amt
        ,COALESCE(t.lang,y.lang) AS lang
        ,COALESCE(t.cntry,y.cntry) AS cntry
        ,COALESCE(t.cntry_id,y.cntry_id) AS cntry_id
        ,COALESCE(t.crsh,y.crsh) AS crsh
        ,COALESCE(t.cxl_rsn,y.cxl_rsn) AS cxl_rsn
        ,COALESCE(t.cxl_rsn_id,y.cxl_rsn_id) AS cxl_rsn_id
        ,COALESCE(t.exp_tm,y.exp_tm) AS exp_tm
        ,COALESCE(t.xtn_json,y.xtn_json) AS xtn_json
        ,COALESCE(t.is_del,y.is_del) AS is_del
        ,COALESCE(t.out_ord_id,y.out_ord_id) AS out_ord_id
        ,COALESCE(t.out_ord_no,y.out_ord_no) AS out_ord_no
        ,COALESCE(t.shop_id,y.shop_id) AS shop_id
        ,COALESCE(t.shop_nm,y.shop_nm) AS shop_nm
        ,COALESCE(t.shop_pltf_cd,y.shop_pltf_cd) AS shop_pltf_cd
        ,COALESCE(t.ccy,y.ccy) AS ccy
        ,COALESCE(t.ord_amt,y.ord_amt) AS ord_amt
        ,COALESCE(t.ord_rmk,y.ord_rmk) AS ord_rmk
        ,COALESCE(t.cnt_json,y.cnt_json) AS cnt_json
        ,COALESCE(t.out_crt_time,y.out_crt_time) AS out_crt_time
        ,COALESCE(t.out_upd_time,y.out_upd_time) AS out_upd_time
        ,COALESCE(t.rcv_nm,y.rcv_nm) AS rcv_nm
        ,COALESCE(t.rcv_fn,y.rcv_fn) AS rcv_fn
        ,COALESCE(t.rcv_ln,y.rcv_ln) AS rcv_ln
        ,COALESCE(t.rcv_email,y.rcv_email) AS rcv_email
        ,COALESCE(t.rcv_phn,y.rcv_phn) AS rcv_phn
        ,COALESCE(t.rcv_cmpny,y.rcv_cmpny) AS rcv_cmpny
        ,COALESCE(t.rcv_cntry,y.rcv_cntry) AS rcv_cntry
        ,COALESCE(t.rcv_cntry_id,y.rcv_cntry_id) AS rcv_cntry_id
        ,COALESCE(t.rcv_cntry_cd,y.rcv_cntry_cd) AS rcv_cntry_cd
        ,COALESCE(t.rcv_prov,y.rcv_prov) AS rcv_prov
        ,COALESCE(t.rcv_prov_cd,y.rcv_prov_cd) AS rcv_prov_cd
        ,COALESCE(t.rcv_city,y.rcv_city) AS rcv_city
        ,COALESCE(t.rcv_addr1,y.rcv_addr1) AS rcv_addr1
        ,COALESCE(t.rcv_addr2,y.rcv_addr2) AS rcv_addr2
        ,COALESCE(t.rcv_zip,y.rcv_zip) AS rcv_zip
        ,COALESCE(t.rcv_lat,y.rcv_lat) AS rcv_lat
        ,COALESCE(t.rcv_lng,y.rcv_lng) AS rcv_lng
        ,COALESCE(t.pkg_cnt,y.pkg_cnt) AS pkg_cnt
        ,COALESCE(t.pkg_no_list,y.pkg_no_list) AS pkg_no_list
        ,COALESCE(t.pkg_latest_no,y.pkg_latest_no) AS pkg_latest_no
        ,COALESCE(t.pkg_latest_line_id,y.pkg_latest_line_id) AS pkg_latest_line_id
        ,COALESCE(t.pkg_latest_line_nm,y.pkg_latest_line_nm) AS pkg_latest_line_nm
        ,COALESCE(t.pkg_latest_dly_tm,y.pkg_latest_dly_tm) AS pkg_latest_dly_tm
        ,COALESCE(t.pkg_latest_exprs_no,y.pkg_latest_exprs_no) AS pkg_latest_exprs_no
        ,COALESCE(t.pkg_latest_logis_nm,y.pkg_latest_logis_nm) AS pkg_latest_logis_nm
        ,COALESCE(t.pkg_latest_logis_id,y.pkg_latest_logis_id) AS pkg_latest_logis_id
        ,COALESCE(t.pkg_est_amt,y.pkg_est_amt) AS pkg_est_amt
        ,COALESCE(t.pkg_actl_amt,y.pkg_actl_amt) AS pkg_actl_amt
        ,COALESCE(t.pkg_est_wt,y.pkg_est_wt) AS pkg_est_wt
        ,COALESCE(t.pkg_actl_wt,y.pkg_actl_wt) AS pkg_actl_wt
        ,COALESCE(t.pkg_pend_amt,y.pkg_pend_amt) AS pkg_pend_amt
        ,COALESCE(t.pkg_payd_amt,y.pkg_payd_amt) AS pkg_payd_amt
        ,COALESCE(t.pkg_ref_amt,y.pkg_ref_amt) AS pkg_ref_amt
        ,COALESCE(t.pkg_rmk,y.pkg_rmk) AS pkg_rmk
        ,COALESCE(t.pkg_cfg_json,y.pkg_cfg_json) AS pkg_cfg_json
        ,COALESCE(t.pkg_fee_json,y.pkg_fee_json) AS pkg_fee_json
        ,COALESCE(t.pkg_wrap_cd,   y.pkg_wrap_cd   )                   AS pkg_wrap_cd
        ,COALESCE(t.crt_time,y.crt_time) AS crt_time
        ,COALESCE(t.upd_time,y.upd_time) AS upd_time
        ,COALESCE(t.rcd_crt_time,y.rcd_crt_time) AS rcd_crt_time
FROM    today_delta t
FULL OUTER JOIN yesterday y
ON      t.ord_no = y.ord_no
;
