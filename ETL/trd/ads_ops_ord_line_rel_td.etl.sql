--MaxCompute SQL
--********************************************************************--
--author: 吴延俊
--create time: 2026-06-24
-- 数据集市: ops (运营管理集市)
-- 应用主题: ord (订单分析)
-- 表名:     ads_ops_ord_line_rel_td
-- 表类型:   应用数据表 (ADS Application) - 历史截至当日(_td, 每日重算)
-- 描述:     基于 Tangbuy 内部订单行 DWS 与 DS 订单行 DWS 做 FULL OUTER JOIN，输出 BI 可直取的订单行关系宽表。
-- 粒度:     一行 = 一个 Tangbuy 内部订单子单与一个 DS 订单行的现有关联关系；未关联订单各自保留。
-- 口径:     同名字段优先取 dws_trd_ord_line_td，Tangbuy 侧缺失时取 dws_trd_ds_ord_line_td。
--           is_ds_ord=1 表示能关联到 DS 订单行宽表，is_ds_ord=0 表示主站订单。
-- GMV口径:  GMV计算已上移至DWS层(dws_trd_ord_line_td.is_gmv_abn+ord_gmv+pkg_gmv+tot_gmv; dws_trd_ds_ord_line_td同上)。
--           ADS仅保留跨表交叉门控：DS匹配行若关联TB子单is_gmv_abn=1则GMV置0；TB独立行直接取TB DWS的GMV。
-- NULL口径: 保留两张 DWS 原始 NULL，仅对同名字段和关键订单号字段做来源兜底，不把不适用字段强制置 0。
-- 调度变量: ${bizdate} 格式 yyyyMMdd
-- 依赖:
--   dws_trd_ord_line_td     (当日分区, Tangbuy内部订单行公共明细服务宽表)
--   dws_trd_ds_ord_line_td  (当日分区, DS订单行公共明细服务宽表)
--********************************************************************--

WITH
-- -----------------------------------------------------------
-- CTE-1: Tangbuy内部订单行宽表，当日全量快照
-- -----------------------------------------------------------
tb_ord_line AS (
    SELECT *
    FROM demo_dw.dws_trd_ord_line_td
    WHERE ds = '${bizdate}'
),

-- -----------------------------------------------------------
-- CTE-2: DS订单行宽表，当日全量快照（GMV字段已在DWS层完成异常状态门控）
-- -----------------------------------------------------------
ds_ord_line AS (
    SELECT *
    FROM demo_dw.dws_trd_ds_ord_line_td
    WHERE ds = '${bizdate}'
)
-- -----------------------------------------------------------
-- 写入: 以 Tangbuy 订单行关联的 ds_ord_line_no 对齐 DS 订单行
-- -----------------------------------------------------------
INSERT OVERWRITE TABLE demo_dw.ads_ops_ord_line_rel_td PARTITION (ds = '${bizdate}')
SELECT
    MD5(CONCAT(NVL(t.ord_line_no, '-99'), '|', NVL(CAST(d.ord_line_no AS STRING), '-99'))) AS ord_rel_id,
    CASE WHEN d.ord_line_no IS NOT NULL THEN 1 ELSE 0 END AS is_ds_ord,
    COALESCE(t.data_src, d.data_src) AS data_src,
    COALESCE(CAST(t.ord_no AS STRING), CAST(d.ord_no AS STRING)) AS ord_no,
    COALESCE(CAST(t.ord_line_no AS STRING), CAST(d.ord_line_no AS STRING)) AS ord_line_no,
    COALESCE(t.ds_ord_no, CAST(d.ord_no AS STRING)) AS ds_ord_no,
    COALESCE(t.ds_ord_line_no, CAST(d.ord_line_no AS STRING)) AS ds_ord_line_no,
    d.out_ord_id AS out_ord_id,
    d.out_ord_no AS out_ord_no,
    d.out_ord_line_id AS out_ord_line_id,
    COALESCE(t.pay_no, d.pay_no) AS pay_no,
    t.pur_no AS pur_no,
    t.cmpny_id AS cmpny_id,
    COALESCE(t.ord_stat, d.ord_stat) AS ord_stat,
    COALESCE(t.ord_stat_nm, d.ord_stat_nm) AS ord_stat_nm,
    COALESCE(t.ord_type_cd, d.ord_type_cd) AS ord_type_cd,
    COALESCE(t.ds_ord_stat, d.ord_stat) AS ds_ord_stat,
    COALESCE(t.ds_ord_stat_nm, d.ord_stat_nm) AS ds_ord_stat_nm,
    COALESCE(t.ds_ord_type_cd, d.ord_type_cd) AS ds_ord_type_cd,
    COALESCE(t.ord_line_stat, d.ord_line_stat) AS ord_line_stat,
    t.ord_line_stat_nm AS ord_line_stat_nm,
    t.cfm_stat AS cfm_stat,
    t.rtn_stat AS rtn_stat,
    t.sales_type_cd AS sales_type_cd,
    t.abn_type_cd AS abn_type_cd,
    t.cart_pur_type_cd AS cart_pur_type_cd,
    t.show_way_cd AS show_way_cd,
    COALESCE(t.is_ord_del, d.is_ord_del) AS is_ord_del,
    d.is_line_del AS is_line_del,
    t.is_expd AS is_expd,
    t.is_exprs_dlyd AS is_exprs_dlyd,
    t.is_need_cfm AS is_need_cfm,
    t.is_deferred AS is_deferred,
    d.cxl_rsn AS cxl_rsn,
    d.cxl_rsn_id AS cxl_rsn_id,
    COALESCE(t.ccy, d.ccy) AS ccy,
    COALESCE(t.ds_ccy, d.ccy) AS ds_ccy,
    t.dev AS dev,
    t.sys_tag AS sys_tag,
    d.ord_rmk AS ord_rmk,
    d.rmk AS rmk,
    COALESCE(t.usr_id, d.usr_id) AS usr_id,
    COALESCE(t.usr_nm, d.usr_nm) AS usr_nm,
    COALESCE(t.email, d.email) AS email,
    COALESCE(t.usr_cntry_cd, d.usr_cntry_cd) AS usr_cntry_cd,
    COALESCE(t.usr_cntry_nm, d.usr_cntry_nm) AS usr_cntry_nm,
    COALESCE(t.usr_lang, d.usr_lang) AS usr_lang,
    COALESCE(t.usr_stat, d.usr_stat) AS usr_stat,
    COALESCE(t.is_usr_frz, d.is_usr_frz) AS is_usr_frz,
    COALESCE(t.is_usr_risk, d.is_usr_risk) AS is_usr_risk,
    COALESCE(t.usr_lvl_id, d.usr_lvl_id) AS usr_lvl_id,
    COALESCE(t.usr_lvl_nm, d.usr_lvl_nm) AS usr_lvl_nm,
    COALESCE(t.usr_lvl, d.usr_lvl) AS usr_lvl,
    t.usr_vip_lvl AS usr_vip_lvl,
    COALESCE(CAST(t.shop_id AS STRING), CAST(d.tb_shop_id AS STRING)) AS shop_id,
    COALESCE(t.shop_nm, d.tb_shop_nm) AS shop_nm,
    COALESCE(t.shop_url, d.tb_shop_url) AS shop_url,
    COALESCE(t.ds_shop_id, d.shop_id) AS ds_shop_id,
    COALESCE(t.ds_shop_nm, d.shop_nm) AS ds_shop_nm,
    COALESCE(t.splr_shop_id, d.splr_shop_id) AS splr_shop_id,
    t.splr_shop_nm AS splr_shop_nm,
    t.splr_shop_url AS splr_shop_url,
    d.shop_pltf_cd AS shop_pltf_cd,
    t.slr_nm AS slr_nm,
    t.pur_usr_nm AS pur_usr_nm,
    t.pur_usr_id AS pur_usr_id,
    t.pur_usr_dept AS pur_usr_dept,
    CASE
        WHEN d.bd_usr_nm IS NOT NULL AND TRIM(d.bd_usr_nm) <> '' THEN d.bd_usr_nm
        ELSE t.bd_usr_nm
    END AS bd_usr_nm,
    d.auth_rel_id AS auth_rel_id,
    d.auth_stat AS auth_stat,
    d.auth_stat_nm AS auth_stat_nm,
    d.auth_shop_url AS auth_shop_url,
    d.auth_slr_nm AS auth_slr_nm,
    d.auth_shop_rgn_cd AS auth_shop_rgn_cd,
    d.is_auth_shop_unreachable AS is_auth_shop_unreachable,
    d.auth_shop_unreachable_rsn AS auth_shop_unreachable_rsn,
    d.is_auth_del AS is_auth_del,
    COALESCE(CAST(t.item_id AS STRING), CAST(d.item_id AS STRING)) AS item_id,
    COALESCE(CAST(t.sku_id AS STRING), CAST(d.sku_id AS STRING)) AS sku_id,
    COALESCE(t.item_nm, d.item_nm) AS item_nm,
    t.item_nm_cn AS item_nm_cn,
    COALESCE(t.item_attr, d.item_attr) AS item_attr,
    t.item_attr_cn AS item_attr_cn,
    t.item_url AS item_url,
    COALESCE(t.item_img, d.item_img) AS item_img,
    d.tb_item_type_cd AS item_type_cd,
    t.item_aud_stat AS item_aud_stat,
    d.item_cnt AS ds_item_cnt,
    d.item_dim_id AS item_dim_id,
    d.item_stat_cd AS item_stat_cd,
    t.ctgy_id AS ctgy_id,
    COALESCE(t.lvl1_ctgy_id, d.lvl1_ctgy_id) AS lvl1_ctgy_id,
    COALESCE(t.lvl1_ctgy_nm, d.lvl1_ctgy_nm) AS lvl1_ctgy_nm,
    COALESCE(t.lvl2_ctgy_id, d.lvl2_ctgy_id) AS lvl2_ctgy_id,
    COALESCE(t.lvl2_ctgy_nm, d.lvl2_ctgy_nm) AS lvl2_ctgy_nm,
    COALESCE(t.lvl3_ctgy_id, d.lvl3_ctgy_id) AS lvl3_ctgy_id,
    COALESCE(t.lvl3_ctgy_nm, d.lvl3_ctgy_nm) AS lvl3_ctgy_nm,
    COALESCE(t.lvl4_ctgy_id, d.lvl4_ctgy_id) AS lvl4_ctgy_id,
    COALESCE(t.lvl4_ctgy_nm, d.lvl4_ctgy_nm) AS lvl4_ctgy_nm,
    t.dcl_cn_nm AS dcl_cn_nm,
    t.dcl_en_nm AS dcl_en_nm,
    COALESCE(t.cstm_hs_cd, d.cstm_hs_cd) AS cstm_hs_cd,
    t.cmb_item_id AS cmb_item_id,
    t.cmb_item_nm AS cmb_item_nm,
    t.cmb_item_attr AS cmb_item_attr,
    t.cmb_item_img AS cmb_item_img,
    t.cmb_item_url AS cmb_item_url,
    t.item_rmk AS item_rmk,
    t.item_rmk_img AS item_rmk_img,
    t.usr_rmk AS usr_rmk,
    COALESCE(t.ord_cnt, d.ord_cnt) AS ord_cnt,
    t.prc AS prc,
    t.pur_prc AS pur_prc,
    d.pur_amt AS pur_amt,
    d.post_fee AS post_fee,
    t.item_ord_amt AS ord_amt,
    d.item_amt AS ds_ord_amt,
    d.item_amt_cny AS ds_ord_amt_cny,
    t.vrtl_prc AS vrtl_prc,
    COALESCE(t.disc_amt, d.disc_amt) AS disc_amt,
    t.item_xtra_amt AS item_xtra_amt,
    t.item_pend_xtra_amt AS item_pend_xtra_amt,
    t.booked_xtra_amt AS booked_xtra_amt,
    COALESCE(t.rtn_amt, d.rtn_amt) AS rtn_amt,
    t.rtn_fee AS rtn_fee,
    t.back_post_amt AS back_post_amt,
    t.ins_back_amt AS ins_back_amt,
    t.custom_fee AS custom_fee,
    d.ref_cnt AS ref_cnt,
    d.crsh_cnt AS crsh_cnt,
    d.crsh_ref_cnt AS crsh_ref_cnt,
    t.pur_sugg_prc AS pur_sugg_prc,
    t.pur_sugg_post_prc AS pur_sugg_post_prc,
    d.splr_type_cd AS splr_type_cd,
    d.pur_type_cd AS pur_type_cd,
    d.pur_rate AS pur_rate,
    d.splr_item_id AS splr_item_id,
    CASE
        WHEN d.ord_line_no IS NOT NULL THEN
            CASE
                WHEN NVL(t.is_gmv_abn, 0) = 1 THEN CAST(0 AS DECIMAL(18,4))
                ELSE d.tot_gmv
            END
        ELSE COALESCE(t.tot_gmv, d.tot_gmv)
    END AS tot_gmv,
    CASE
        WHEN d.ord_line_no IS NOT NULL THEN
            CASE
                WHEN NVL(t.is_gmv_abn, 0) = 1 THEN CAST(0 AS DECIMAL(18,4))
                ELSE d.ord_gmv
            END
        ELSE COALESCE(t.ord_gmv, d.ord_gmv)
    END AS ord_gmv,
    CASE
        WHEN d.ord_line_no IS NOT NULL THEN
            CASE
                WHEN NVL(t.is_gmv_abn, 0) = 1 THEN CAST(0 AS DECIMAL(18,4))
                ELSE d.pkg_gmv
            END
        ELSE COALESCE(t.pkg_gmv, d.pkg_gmv)
    END AS pkg_gmv,
    COALESCE(t.pkg_no, d.pkg_no) AS pkg_no,
    t.pkg_type_cd AS pkg_type_cd,
    d.pkg_wrap_cd AS pkg_wrap_cd,
    COALESCE(t.pkg_stat, d.pkg_stat) AS pkg_stat,
    COALESCE(t.pkg_stat_nm, d.pkg_stat_nm) AS pkg_stat_nm,
    COALESCE(t.pkg_pay_stat, d.pkg_pay_stat) AS pkg_pay_stat,
    COALESCE(t.pkg_bag_stat, d.pkg_bag_stat) AS pkg_bag_stat,
    COALESCE(t.pkg_bag_stat_nm, d.pkg_bag_stat_nm) AS pkg_bag_stat_nm,
    t.pkg_exprs_no AS pkg_exprs_no,
    t.pkg_exprs_nm AS pkg_exprs_nm,
    COALESCE(t.exprs_no, d.exprs_no) AS exprs_no,
    t.exprs_id AS exprs_id,
    COALESCE(t.exprs_nm, d.exprs_nm) AS exprs_nm,
    COALESCE(t.pkg_line_nm, d.pkg_line_nm) AS pkg_line_nm,
    COALESCE(t.pkg_line_id, d.pkg_line_id) AS pkg_line_id,
    t.pkg_rcv_cntry_cd AS pkg_rcv_cntry_cd,
    t.pkg_rcv_cntry AS pkg_rcv_cntry,
    t.pkg_rcv_cntry_cn AS pkg_rcv_cntry_cn,
    t.pkg_rcv_area AS pkg_rcv_area,
    t.pkg_rcv_city AS pkg_rcv_city,
    d.rcv_nm AS rcv_nm,
    t.wh_id AS wh_id,
    t.wh_nm AS wh_nm,
    t.bin_no AS bin_no,
    t.ml_lmt AS ml_lmt,
    COALESCE(t.wt, d.wt) AS wt,
    COALESCE(t.vol_desc, d.vol_desc) AS vol_desc,
    t.line_vol AS line_vol,
    COALESCE(t.pred_wt, d.pred_wt) AS pred_wt,
    COALESCE(t.actl_wt, d.actl_wt) AS actl_wt,
    t.diff_wt AS diff_wt,
    t.item_wt AS item_wt,
    COALESCE(t.pkg_actl_wt, d.pkg_actl_wt) AS pkg_actl_wt,
    COALESCE(t.pkg_len, d.pkg_len) AS pkg_len,
    COALESCE(t.pkg_wid, d.pkg_wid) AS pkg_wid,
    COALESCE(t.pkg_hgt, d.pkg_hgt) AS pkg_hgt,
    COALESCE(t.is_vol_wt_on, d.is_vol_wt_on) AS is_vol_wt_on,
    COALESCE(t.fee_alloc_rate, d.fee_alloc_rate) AS fee_alloc_rate,
    COALESCE(t.wt_alloc_rate, d.wt_alloc_rate) AS wt_alloc_rate,
    COALESCE(t.vol_alloc_rate, d.vol_alloc_rate) AS vol_alloc_rate,
    COALESCE(t.alloc_tot_pre_amt, d.alloc_tot_pre_amt) AS alloc_tot_pre_amt,
    COALESCE(t.alloc_tot_actl_amt, d.alloc_tot_actl_amt) AS alloc_tot_actl_amt,
    COALESCE(t.alloc_tech_srv_pre_fee, d.alloc_tech_srv_pre_fee) AS alloc_tech_srv_pre_fee,
    COALESCE(t.alloc_tech_srv_actl_fee, d.alloc_tech_srv_actl_fee) AS alloc_tech_srv_actl_fee,
    COALESCE(t.alloc_ins_amt, d.alloc_ins_amt) AS alloc_ins_amt,
    COALESCE(t.alloc_diff_amt, d.alloc_diff_amt) AS alloc_diff_amt,
    COALESCE(t.alloc_succ_diff_amt, d.alloc_succ_diff_amt) AS alloc_succ_diff_amt,
    COALESCE(t.alloc_cpn_amt, d.alloc_cpn_amt) AS alloc_cpn_amt,
    COALESCE(t.alloc_disc_amt, d.alloc_disc_amt) AS alloc_disc_amt,
    COALESCE(t.alloc_dep_amt, d.alloc_dep_amt) AS alloc_dep_amt,
    COALESCE(t.alloc_actl_dep_amt, d.alloc_actl_dep_amt) AS alloc_actl_dep_amt,
    COALESCE(t.alloc_wt, d.alloc_wt) AS alloc_wt,
    COALESCE(t.alloc_vol, d.alloc_vol) AS alloc_vol,
    COALESCE(t.pkg_biz_rmk, d.pkg_biz_rmk) AS pkg_biz_rmk,
    COALESCE(t.ord_crt_time, d.ord_crt_time) AS ord_crt_time,
    t.ord_pend_time AS ord_pend_time,
    COALESCE(t.ord_submit_time, d.ord_submit_time) AS ord_submit_time,
    COALESCE(t.pend_pay_time, d.pend_pay_time) AS pend_pay_time,
    COALESCE(t.pay_time, d.pay_time) AS pay_time,
    COALESCE(t.pur_time, d.pur_time) AS pur_time,
    COALESCE(t.wh_stock_in_time, d.wh_stock_in_time) AS wh_stock_in_time,
    t.stor_out_time AS stor_out_time,
    COALESCE(t.pend_ob_time, d.pend_ob_time) AS pend_ob_time,
    COALESCE(t.ob_ing_time, d.ob_ing_time) AS ob_ing_time,
    COALESCE(t.pkg_cmpl_time, d.pkg_cmpl_time) AS pkg_cmpl_time,
    COALESCE(t.pkg_snd_time, d.pkg_snd_time) AS pkg_snd_time,
    COALESCE(t.snd_ovs_time, d.snd_ovs_time) AS snd_ovs_time,
    COALESCE(t.arv_time, d.arv_time) AS arv_time,
    COALESCE(t.sign_time, d.sign_time) AS sign_time,
    COALESCE(t.rcv_time, d.rcv_time) AS rcv_time,
    t.pkg_dly_time AS pkg_dly_time,
    COALESCE(t.pkg_back_time, d.pkg_back_time) AS pkg_back_time,
    COALESCE(t.ord_cxl_time, d.ord_cxl_time) AS ord_cxl_time,
    COALESCE(t.rtn_req_time, d.rtn_req_time) AS rtn_req_time,
    COALESCE(t.rtn_cmpl_time, d.rtn_cmpl_time) AS rtn_cmpl_time,
    COALESCE(t.ord_ref_time, d.ord_ref_time) AS ord_ref_time,
    COALESCE(t.usr_crt_time, d.usr_crt_time) AS usr_crt_time,
    d.crt_time AS crt_time,
    d.upd_time AS upd_time,
    t.rmk_time AS rmk_time,
    d.auth_shop_crt_time AS auth_shop_crt_time,
    d.auth_crt_time AS auth_crt_time,
    d.auth_upd_time AS auth_upd_time,
    d.auth_revoke_time AS auth_revoke_time
FROM tb_ord_line t
FULL OUTER JOIN ds_ord_line d
    ON t.ds_ord_line_no = CAST(d.ord_line_no AS STRING)
;
