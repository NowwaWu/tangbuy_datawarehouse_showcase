--MaxCompute SQL
--********************************************************************--
--author: 吴延俊
--create time: 2026-06-30
-- 数据域:   wh (仓储履约域)
-- 业务过程: pkg_mgr (包裹管理)
-- 表名:     dws_wh_pkg_mgr_td
-- 表类型:   公共明细服务表 (DWS Detail Service) - 周期快照(全量截至当日, 每日重算)
-- 描述:     以包裹号 pkg_no 为粒度，继承 dwd_wh_pkg_mgr_df 包裹、申报、税务、轨迹字段，
--           新增 ord_crt_time(订单下单时间)、ord_pay_time(订单支付时间)，通过 dwd_trd_ord_line_df.pkg_no→ord_no
--           关联 dwd_trd_ord_header_df.crt_time/pay_time 获取，一个包裹关联多个订单时取最晚时间。
--           字段按业务分组排列：标识→单号→用户→仓库→收件→物流→重量→费用→状态→标记→属性→备注→时间。
-- 粒度:     一行 = 一个包裹 (pkg_no)
-- ETL方式:  每日读取 DWD 当日全量分区, INSERT OVERWRITE 写入当日分区
-- 调度周期: 日
-- 调度变量: ${bizdate} 格式 yyyyMMdd
-- 依赖:
--   dwd_wh_pkg_mgr_df            (当日分区, 包裹全生命周期, 驱动表)
--   dwd_trd_ord_line_df          (当日分区, 子单→包裹→订单映射)
--   dwd_trd_ord_header_df        (当日分区, 订单下单/支付时间)
-- 防膨胀:
--   包裹作为驱动表，LEFT JOIN 子单取 ord_no，LEFT JOIN 订单头取 crt_time/pay_time,
--   按 pkg_no 聚合 MAX(crt_time/pay_time) 兜底多订单场景。
-- NULL口径:
--   ord_crt_time/ord_pay_time 关联不上时保留 NULL，其余字段继承 DWD 的 Zero-NULL 策略。
--********************************************************************--

WITH
-- -----------------------------------------------------------
-- CTE-1: 包裹基表, 当日全量快照 (驱动表)
-- -----------------------------------------------------------
pkg_base AS (
    SELECT
        pkg_no,
        trade_no,
        stor_ord_no,
        usr_id,
        usr_nm,
        email,
        wh_id,
        wh_nm,
        rcv_first_nm,
        rcv_last_nm,
        rcv_cntry_cd,
        rcv_cntry,
        rcv_cntry_cn,
        rcv_area,
        rcv_city,
        rcv_zip,
        rcv_addr,
        rcv_phn,
        logistic_id,
        carrier_id,
        line_id,
        line_nm,
        exprs_nm,
        exprs_no,
        pxy_lbl_no,
        snd_area,
        pred_wt,
        actl_wt,
        diff_wt,
        item_wt,
        pkg_actl_wt,
        pkg_pre_actl_wt,
        is_vol_wt_on,
        pkg_len,
        pkg_wid,
        pkg_hgt,
        pkg_vol,
        ccy,
        exch_rate,
        dep_amt,
        actl_dep_amt,
        tot_amt,
        tot_pre_amt,
        tot_actl_amt,
        tech_srv_pre_fee,
        tech_srv_actl_fee,
        ins_amt,
        ins_srv_fee,
        vat_amt,
        diff_amt,
        succ_diff_amt,
        cpn_amt,
        disc_amt,
        pkg_item_amt,
        dcl_cn_nm_list,
        dcl_en_nm_list,
        dcl_item_cnt,
        dcl_amt,
        tax_type_cd,
        tax_type_nm,
        is_pltf_ioss,
        pkg_stat,
        pkg_stat_nm,
        pay_stat,
        pay_stat_nm,
        bag_stat,
        bag_stat_nm,
        exprs_stat,
        sys_stat,
        artif_stat,
        risk_stat,
        is_frz,
        dcl_stat,
        logis_stat,
        cmpstn_stat,
        is_after_sale,
        is_rtn,
        is_pend,
        is_del,
        is_growth,
        is_custom_aud,
        pkg_type_cd,
        pkg_cond_cd,
        spcl_stat_cd,
        risk_cd,
        risk_lvl,
        handle_cd,
        custom_id,
        pkg_usr,
        item_cnt,
        lang,
        pltf_cd,
        biz_rmk,
        bag_rmk,
        crt_time,
        pay_time,
        upd_time,
        snd_time,
        trk_crt_time,
        pick_time,
        exp_time,
        clr_time,
        trk_dly_time,
        last_trk_time,
        dly_time,
        dly_day_cnt,
        back_time,
        cmpstn_time,
        growth_time
    FROM demo_dw.dwd_wh_pkg_mgr_df
    WHERE ds = '${bizdate}'
),

-- -----------------------------------------------------------
-- CTE-2: 子单取 pkg_no→ord_no 映射 (去重, 过滤无效包裹号)
-- -----------------------------------------------------------
ord_line_pkg_rel AS (
    SELECT
        pkg_no,
        ord_no
    FROM demo_dw.dwd_trd_ord_line_df
    WHERE ds = '${bizdate}'
      AND pkg_no IS NOT NULL
      AND TRIM(pkg_no) <> ''
      AND pkg_no <> '-99'
      AND ord_no IS NOT NULL
      AND TRIM(ord_no) <> ''
    GROUP BY pkg_no, ord_no
),

-- -----------------------------------------------------------
-- CTE-3: 订单下单/支付时间按包裹聚合 (多订单取最晚)
-- -----------------------------------------------------------
ord_time_agg AS (
    SELECT
        ol.pkg_no,
        MAX(h.crt_time) AS ord_crt_time,
        MAX(h.pay_time) AS ord_pay_time
    FROM ord_line_pkg_rel ol
    JOIN demo_dw.dwd_trd_ord_header_df h
        ON ol.ord_no = h.ord_no
        AND h.ds = '${bizdate}'
    GROUP BY ol.pkg_no
)

-- -----------------------------------------------------------
-- 写入: 包裹驱动, LEFT JOIN 补充 ord_crt_time/ord_pay_time, 字段按业务分组顺序输出
-- -----------------------------------------------------------
INSERT OVERWRITE TABLE demo_dw.dws_wh_pkg_mgr_td PARTITION (ds = '${bizdate}')
SELECT
    -- === 包裹标识 ===
    b.pkg_no,
    -- === 关联单号 ===
    b.trade_no,
    b.stor_ord_no,
    -- === 用户信息 ===
    b.usr_id,
    b.usr_nm,
    b.email,
    -- === 仓库信息 ===
    b.wh_id,
    b.wh_nm,
    -- === 收件信息 ===
    b.rcv_first_nm,
    b.rcv_last_nm,
    b.rcv_cntry_cd,
    b.rcv_cntry,
    b.rcv_cntry_cn,
    b.rcv_area,
    b.rcv_city,
    b.rcv_zip,
    b.rcv_addr,
    b.rcv_phn,
    -- === 物流线路与快递 ===
    b.logistic_id,
    b.carrier_id,
    b.line_id,
    b.line_nm,
    b.exprs_nm,
    b.exprs_no,
    b.snd_area,
    -- === 重量与体积 ===
    b.pred_wt,
    b.actl_wt,
    b.diff_wt,
    b.item_wt,
    b.pkg_actl_wt,
    b.pkg_pre_actl_wt,
    b.is_vol_wt_on,
    b.pkg_len,
    b.pkg_wid,
    b.pkg_hgt,
    b.pkg_vol,
    -- === 金额与费用 ===
    b.ccy,
    b.exch_rate,
    b.dep_amt,
    b.actl_dep_amt,
    b.tot_amt,
    b.tot_pre_amt,
    b.tot_actl_amt,
    b.tech_srv_pre_fee,
    b.tech_srv_actl_fee,
    b.ins_amt,
    b.ins_srv_fee,
    b.vat_amt,
    b.diff_amt,
    b.succ_diff_amt,
    b.cpn_amt,
    b.disc_amt,
    b.pkg_item_amt,
    -- === 申报与税务 ===
    b.dcl_cn_nm_list,
    b.dcl_en_nm_list,
    b.dcl_item_cnt,
    b.dcl_amt,
    b.tax_type_cd,
    b.tax_type_nm,
    b.is_pltf_ioss,
    -- === 包裹状态 ===
    b.pkg_stat,
    b.pkg_stat_nm,
    b.pay_stat,
    b.pay_stat_nm,
    b.bag_stat,
    b.bag_stat_nm,
    b.exprs_stat,
    -- === 审核与标记 ===
    b.sys_stat,
    b.artif_stat,
    b.risk_stat,
    b.is_frz,
    b.dcl_stat,
    b.logis_stat,
    b.cmpstn_stat,
    b.is_after_sale,
    b.is_rtn,
    b.is_pend,
    b.is_del,
    b.is_growth,
    b.is_custom_aud,
    -- === 包裹属性与标签 ===
    b.pkg_type_cd,
    b.pkg_cond_cd,
    b.spcl_stat_cd,
    b.risk_cd,
    b.risk_lvl,
    b.handle_cd,
    b.custom_id,
    b.pkg_usr,
    b.item_cnt,
    b.lang,
    b.pltf_cd,
    -- === 业务备注 ===
    b.biz_rmk,
    b.bag_rmk,
    -- === 时间里程碑（业务顺序） ===
    b.crt_time,
    o.ord_crt_time,
    o.ord_pay_time,
    b.pay_time,
    b.upd_time,
    b.snd_time,
    b.trk_crt_time,
    b.pick_time,
    b.exp_time,
    b.clr_time,
    b.trk_dly_time,
    b.last_trk_time,
    b.dly_time,
    b.dly_day_cnt,
    b.back_time,
    b.cmpstn_time,
    b.growth_time,
    -- === 追加字段 ===
    b.pxy_lbl_no
FROM pkg_base b
LEFT JOIN ord_time_agg o
    ON b.pkg_no = o.pkg_no
;
