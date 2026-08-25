--MaxCompute SQL
--********************************************************************--
--author: 吴延俊
--create time: 2026-06-24
-- 数据域:   trd (交易域)
-- 业务过程: ord (Tangbuy内部订单)
-- 表名:     dws_trd_ord_line_td
-- 表类型:   公共明细服务表 (DWS Detail Service) - 周期快照(全量截至当日, 每日重算)
-- 描述:     以 Tangbuy 内部订单子单 ord_line_no 为粒度，组合内部订单主子表、DS订单关联、用户维度、商品类目、包裹费用分摊和物流信息。
--           表名已表达内部订单视角，因此内部订单字段默认不加 tb_ 前缀；DS侧字段统一 ds_ 前缀。
-- 粒度:     一行 = 一个 Tangbuy 内部订单子单(dwd_trd_ord_line_df.ord_line_no)
-- ETL方式:  每日读取 DWD/DIM 当日全量分区重算, INSERT OVERWRITE 写入当日分区
-- 调度变量: ${bizdate} 格式 yyyyMMdd
-- 依赖:
--   dwd_trd_ord_line_df             (当日分区, Tangbuy内部订单子单)
--   dwd_trd_ord_header_df           (当日分区, Tangbuy内部订单主单)
--   dwd_trd_ds_ord_line_df          (当日分区, DS订单子单; 按ds_ord_line_no补充DS侧订单行)
--   dwd_trd_ds_ord_header_df        (当日分区, DS订单主单; 按ds_ord_no补充DS侧订单头)
--   dim_usr_info_df                 (当日分区, 用户信息)
--   dim_itm_category_df             (当日分区, Tangbuy内部商品类目)
--   dwd_wh_pkg_mgr_df               (当日分区, 包裹费用和物流信息)
--   dwd_trd_order_operation_di      (全量历史分区 ds<=bizdate, 操作流水; pivot出履约关键节点时间)
--   dim_pay_exch_rate_df            (当日分区, 汇率)
-- 防膨胀:
--   内部订单子单作为驱动表，所有关联表均按 ord_line_no / ord_no / pkg_no / ctgy_id 单点补充。
--   DS订单只按已沉淀的 ds_ord_line_no / ds_ord_no 补充字段，不反向展开DS订单行集合。
--   包裹字段按 dwd_trd_ord_line_df.pkg_no 关联包裹快照，包裹费用使用 alloc_* 字段提供子单可加口径；商品金额分母为0时按包裹内子单行数兜底分摊。
-- 过滤口径:
--   DWS公共服务层不做已支付、作废、删除单等应用过滤，仅保留状态字段供下游筛选。
--   新增 is_gmv_abn 标记和 ord_gmv/pkg_gmv/tot_gmv 拆分GMV，基于本表状态字段做异常门控，下游ADS可直接取用。
-- NULL口径:
--   费用分摊字段按 0 兜底；其余缺失字段保留 NULL。
--********************************************************************--

WITH
-- -----------------------------------------------------------
-- CTE-1: Tangbuy内部订单子单，当日全量快照
-- -----------------------------------------------------------
ord_line AS (
    SELECT
        ord_line_no,
        ord_no,
        usr_id AS line_usr_id,
        cmpny_id AS line_cmpny_id,
        usr_nm AS line_usr_nm,
        email AS line_email,
        wh_id AS line_wh_id,
        wh_nm AS line_wh_nm,
        item_id,
        sku_id,
        item_nm,
        item_nm_cn,
        item_attr,
        item_attr_cn,
        item_url,
        item_img,
        ord_line_stat,
        ord_line_stat_nm,
        cfm_stat,
        rtn_stat,
        sales_type_cd,
        abn_type_cd,
        cart_pur_type_cd,
        show_way_cd,
        is_exprs_dlyd,
        is_need_cfm,
        is_deferred,
        ord_cnt,
        prc,
        pur_prc,
        CAST(NVL(pur_prc, 0) * NVL(ord_cnt, 0) AS DECIMAL(18,4)) AS item_ord_amt,
        vrtl_prc,
        disc_amt,
        item_xtra_amt,
        item_pend_xtra_amt,
        booked_xtra_amt,
        rtn_amt,
        rtn_fee,
        back_post_amt,
        ins_back_amt,
        custom_fee,
        wt,
        vol_desc,
        CAST(
            CAST(NVL(REGEXP_EXTRACT(vol_desc, '([0-9.]+)\\*([0-9.]+)\\*([0-9.]+)', 1), '0') AS DECIMAL(18,4))
            * CAST(NVL(REGEXP_EXTRACT(vol_desc, '([0-9.]+)\\*([0-9.]+)\\*([0-9.]+)', 2), '0') AS DECIMAL(18,4))
            * CAST(NVL(REGEXP_EXTRACT(vol_desc, '([0-9.]+)\\*([0-9.]+)\\*([0-9.]+)', 3), '0') AS DECIMAL(18,4))
            AS DECIMAL(18,4)
        ) AS line_vol,
        pkg_no,
        exprs_no,
        exprs_id,
        exprs_nm,
        pur_no,
        bin_no,
        ml_lmt,
        inv_id,
        ctgy_id,
        stor_out_time,
        item_rmk,
        item_rmk_img,
        usr_rmk,
        rmk_time,
        data_src,
        ds_ord_no,
        ds_ord_line_no,
        bd_usr_nm,
        pur_sugg_prc,
        pur_sugg_post_prc,
        cmb_item_id,
        cmb_item_nm,
        cmb_item_attr,
        cmb_item_img,
        cmb_item_url,
        inner_sales_prc,
        inner_aff_prc,
        inner_src_prc,
        plugin_cnt_json,
        xtn_json AS line_xtn_json,
        crt_time AS line_crt_time,
        upd_time AS line_upd_time
    FROM demo_dw.dwd_trd_ord_line_df
    WHERE ds = '${bizdate}'
),

-- -----------------------------------------------------------
-- CTE-2: Tangbuy内部订单主单，当日全量快照
-- -----------------------------------------------------------
ord_hdr AS (
    SELECT
        ord_no,
        usr_id AS hdr_usr_id,
        cmpny_id,
        usr_nm AS hdr_usr_nm,
        usr_email AS hdr_email,
        ord_stat,
        ord_type_cd,
        brand_stat AS item_aud_stat,
        pay_no,
        slr_nm,
        buyer_nm AS pur_usr_nm,
        buyer_id AS pur_usr_id,
        buyer_dept AS pur_usr_dept,
        dst_cntry AS rcv_cntry,
        dst_cntry_id AS rcv_cntry_id,
        shop_src,
        shop_nm,
        shop_url,
        shop_id,
        splr_shop_nm,
        splr_shop_url,
        splr_shop_id,
        wh_id AS hdr_wh_id,
        wh_nm AS hdr_wh_nm,
        lang,
        ccy,
        crt_time AS ord_crt_time,
        pend_time AS ord_pend_time,
        pay_time,
        upd_time AS ord_upd_time,
        is_expd,
        is_del AS is_ord_del,
        usr_vip_lvl,
        sys_tag,
        dev,
        inner_data_src,
        merge_item_json,
        acty_disc_json,
        xtn_json AS ord_xtn_json
    FROM demo_dw.dwd_trd_ord_header_df
    WHERE ds = '${bizdate}'
),

-- -----------------------------------------------------------
-- CTE-3: 用户维度，当日全量快照
-- -----------------------------------------------------------
usr_dim AS (
    SELECT
        usr_id,
        usr_nm,
        email,
        cntry_cd AS usr_cntry_cd,
        cntry_nm AS usr_cntry_nm,
        lang AS usr_lang,
        usr_stat,
        is_frz AS is_usr_frz,
        is_risk AS is_usr_risk,
        lvl_id AS usr_lvl_id,
        lvl_nm AS usr_lvl_nm,
        lvl AS usr_lvl,
        crt_time AS usr_crt_time
    FROM demo_dw.dim_usr_info_df
    WHERE ds = '${bizdate}'
),

-- -----------------------------------------------------------
-- CTE-4: 汇率维表，当日全量快照
-- -----------------------------------------------------------
exch_rate AS (
    SELECT
        UPPER(ccy_cd) AS ccy_cd,
        pref_rate
    FROM demo_dw.dim_pay_exch_rate_df
    WHERE ds = '${bizdate}'
),

-- -----------------------------------------------------------
-- CTE-5: DS订单子单，当日全量快照
-- -----------------------------------------------------------
ds_ord_line AS (
    SELECT
        CAST(ord_line_no AS STRING) AS ds_ord_line_no,
        CAST(ord_no AS STRING) AS ds_ord_no,
        ord_line_stat AS ds_ord_line_stat,
        is_del AS ds_is_line_del,
        ccy AS ds_line_ccy,
        ord_amt AS ds_item_amt
    FROM demo_dw.dwd_trd_ds_ord_line_df
    WHERE ds = '${bizdate}'
),

-- -----------------------------------------------------------
-- CTE-6: DS订单主单，当日全量快照
-- -----------------------------------------------------------
ds_ord_hdr AS (
    SELECT
        CAST(ord_no AS STRING) AS ds_ord_no,
        ord_stat AS ds_ord_stat,
        ord_type_cd AS ds_ord_type_cd,
        pay_no AS ds_pay_no,
        pay_time AS ds_pay_time,
        UPPER(shop_pltf_cd) AS ds_shop_pltf_cd,
        shop_id AS ds_shop_id,
        shop_nm AS ds_shop_nm,
        out_ord_id AS ds_out_ord_id,
        out_ord_no AS ds_out_ord_no,
        ccy AS ds_ccy,
        crt_time AS ds_ord_crt_time,
        upd_time AS ds_ord_upd_time
    FROM demo_dw.dwd_trd_ds_ord_header_df
    WHERE ds = '${bizdate}'
),

-- -----------------------------------------------------------
-- CTE-7: Tangbuy内部商品类目维度，当日全量快照
-- -----------------------------------------------------------
ctgy_dim AS (
    SELECT
        lvl1_ctgy_id,
        lvl1_ctgy_nm,
        lvl2_ctgy_id,
        lvl2_ctgy_nm,
        lvl3_ctgy_id,
        lvl3_ctgy_nm,
        lvl4_ctgy_id,
        lvl4_ctgy_nm,
        dcl_cn_nm,
        dcl_en_nm,
        cstm_hs_cd
    FROM demo_dw.dim_itm_category_df
    WHERE ds = '${bizdate}'
),

-- -----------------------------------------------------------
-- CTE-8: Tangbuy内部子单履约关键节点时间
-- -----------------------------------------------------------
item_life AS (
    SELECT
        ord_line_no AS life_ord_line_no,
        MAX(CASE WHEN op_type_cn = '订单提交'                 THEN crt_time END) AS ord_submit_time,
        MAX(CASE WHEN op_type_cn = '待支付'                   THEN crt_time END) AS pend_pay_time,
        MAX(CASE WHEN op_type_cn = '已支付'                   THEN crt_time END) AS ord_pay_time,
        MAX(CASE WHEN op_type_cn = '已订购'                   THEN crt_time END) AS pur_time,
        MAX(CASE WHEN op_type_cn = '处理中'                   THEN crt_time END) AS proc_time,
        MAX(CASE WHEN op_type_cn IN ('仓库已入库','系统入库') THEN crt_time END) AS wh_stock_in_time,
        MAX(CASE WHEN op_type_cn = '等待出库'                 THEN crt_time END) AS pend_ob_time,
        MAX(CASE WHEN op_type_cn = '正在出库中'               THEN crt_time END) AS ob_ing_time,
        MAX(CASE WHEN op_type_cn = '出库打包完毕'             THEN crt_time END) AS pkg_cmpl_time,
        MAX(CASE WHEN op_type_cn = '已寄送海外'               THEN crt_time END) AS snd_ovs_time,
        MAX(CASE WHEN op_type_cn = '已到货'                   THEN crt_time END) AS arv_time,
        MAX(CASE WHEN op_type_cn = '已签收'                   THEN crt_time END) AS sign_time,
        MAX(CASE WHEN op_type_cn = '已收到货'                 THEN crt_time END) AS rcv_time,
        MAX(CASE WHEN op_type_cn = '取消订购'                 THEN crt_time END) AS ord_cxl_time,
        MAX(CASE WHEN op_type_cn = '申请退货'                 THEN crt_time END) AS rtn_req_time,
        MAX(CASE WHEN op_type_cn = '退货完成'                 THEN crt_time END) AS rtn_cmpl_time,
        MAX(CASE WHEN op_type_cn = '订单退款'                 THEN crt_time END) AS ord_ref_time
    FROM demo_dw.dwd_trd_order_operation_di
    WHERE ds <= '${bizdate}'
    GROUP BY ord_line_no
),

-- -----------------------------------------------------------
-- CTE-9: 包裹快照，当日全量分区
-- -----------------------------------------------------------
pkg_mgr AS (
    SELECT
        pkg_no,
        dep_amt,
        actl_dep_amt,
        tot_pre_amt,
        tot_actl_amt,
        tech_srv_pre_fee,
        tech_srv_actl_fee,
        ins_amt,
        diff_amt,
        succ_diff_amt,
        cpn_amt,
        disc_amt,
        pred_wt,
        actl_wt,
        diff_wt,
        item_wt,
        pkg_actl_wt,
        pkg_len,
        pkg_wid,
        pkg_hgt,
        is_vol_wt_on,
        pkg_stat,
        pay_stat AS pkg_pay_stat,
        bag_stat AS pkg_bag_stat,
        exprs_no AS pkg_exprs_no,
        exprs_nm AS pkg_exprs_nm,
        line_nm AS pkg_line_nm,
        line_id AS pkg_line_id,
        snd_area,
        rcv_cntry_cd AS pkg_rcv_cntry_cd,
        rcv_cntry AS pkg_rcv_cntry,
        rcv_cntry_cn AS pkg_rcv_cntry_cn,
        rcv_area AS pkg_rcv_area,
        rcv_city AS pkg_rcv_city,
        pkg_type_cd,
        pkg_cond_cd,
        snd_time AS pkg_snd_time,
        trk_crt_time,
        trk_dly_time,
        back_time AS pkg_back_time,
        dly_time AS pkg_dly_time,
        biz_rmk AS pkg_biz_rmk
    FROM demo_dw.dwd_wh_pkg_mgr_df
    WHERE ds = '${bizdate}'
),

-- -----------------------------------------------------------
-- CTE-10: 分摊计算基表，仅计算比例，不过滤主表输出行
-- -----------------------------------------------------------
alloc_line_base AS (
    SELECT
        ord_line_no,
        ord_no,
        pkg_no,
        NVL(item_ord_amt, 0) AS item_ord_amt,
        NVL(wt, 0) AS wt,
        NVL(line_vol, 0) AS line_vol,
        ROW_NUMBER() OVER (PARTITION BY pkg_no ORDER BY ord_line_no) AS pkg_line_rn,
        COUNT(1) OVER (PARTITION BY pkg_no) AS pkg_line_cnt
    FROM ord_line
),

-- -----------------------------------------------------------
-- CTE-11: 包裹费用、重量、体积分摊比例
-- -----------------------------------------------------------
alloc_rate_calc AS (
    SELECT
        ord_line_no,
        ord_no,
        pkg_no,
        pkg_line_rn,
        pkg_line_cnt,
        CASE
            WHEN pkg_no IS NULL OR TRIM(pkg_no) = '' OR pkg_no = '-99' THEN 0
            ELSE 1
        END AS is_valid_pkg,
        CASE
            WHEN pkg_no IS NULL OR TRIM(pkg_no) = '' OR pkg_no = '-99' THEN CAST(0 AS DECIMAL(18,4))
            WHEN SUM(item_ord_amt) OVER (PARTITION BY pkg_no) = 0 THEN
                CASE
                    WHEN pkg_line_rn = pkg_line_cnt THEN CAST(
                        1 - CAST(CAST(1 AS DECIMAL(18,8)) / pkg_line_cnt AS DECIMAL(18,4)) * (pkg_line_cnt - 1)
                        AS DECIMAL(18,4)
                    )
                    ELSE CAST(CAST(1 AS DECIMAL(18,8)) / pkg_line_cnt AS DECIMAL(18,4))
                END
            ELSE CAST(item_ord_amt / SUM(item_ord_amt) OVER (PARTITION BY pkg_no) AS DECIMAL(18,4))
        END AS fee_alloc_rate,
        CASE
            WHEN pkg_no IS NULL OR TRIM(pkg_no) = '' OR pkg_no = '-99' THEN CAST(0 AS DECIMAL(18,4))
            WHEN SUM(wt) OVER (PARTITION BY pkg_no) = 0 THEN CAST(0 AS DECIMAL(18,4))
            ELSE CAST(wt / SUM(wt) OVER (PARTITION BY pkg_no) AS DECIMAL(18,4))
        END AS wt_alloc_rate,
        CASE
            WHEN pkg_no IS NULL OR TRIM(pkg_no) = '' OR pkg_no = '-99' THEN CAST(0 AS DECIMAL(18,4))
            WHEN SUM(line_vol) OVER (PARTITION BY pkg_no) = 0 THEN CAST(0 AS DECIMAL(18,4))
            ELSE CAST(line_vol / SUM(line_vol) OVER (PARTITION BY pkg_no) AS DECIMAL(18,4))
        END AS vol_alloc_rate
    FROM alloc_line_base
),

-- -----------------------------------------------------------
-- CTE-12: 包裹费用按内部子单分摊
--   费用类字段按最后一行承接尾差，保证包裹内alloc_*聚合后100%回到包裹金额。
-- -----------------------------------------------------------
fee_alloc_base AS (
    SELECT
        a.ord_line_no,
        a.pkg_no,
        a.pkg_line_rn,
        a.pkg_line_cnt,
        a.is_valid_pkg,
        NVL(a.fee_alloc_rate, 0) AS fee_alloc_rate,
        NVL(a.wt_alloc_rate, 0) AS wt_alloc_rate,
        NVL(a.vol_alloc_rate, 0) AS vol_alloc_rate,
        NVL(p.tot_pre_amt, 0) AS pkg_tot_pre_amt,
        NVL(p.tot_actl_amt, 0) AS pkg_tot_actl_amt,
        NVL(p.tech_srv_pre_fee, 0) AS pkg_tech_srv_pre_fee,
        NVL(p.tech_srv_actl_fee, 0) AS pkg_tech_srv_actl_fee,
        NVL(p.ins_amt, 0) AS pkg_ins_amt,
        NVL(p.diff_amt, 0) AS pkg_diff_amt,
        NVL(p.succ_diff_amt, 0) AS pkg_succ_diff_amt,
        NVL(p.cpn_amt, 0) AS pkg_cpn_amt,
        NVL(p.disc_amt, 0) AS pkg_disc_amt,
        NVL(p.dep_amt, 0) AS pkg_dep_amt,
        NVL(p.actl_dep_amt, 0) AS pkg_actl_dep_amt,
        CAST(NVL(a.fee_alloc_rate, 0) * NVL(p.tot_pre_amt, 0) AS DECIMAL(18,4)) AS base_alloc_tot_pre_amt,
        CAST(NVL(a.fee_alloc_rate, 0) * NVL(p.tot_actl_amt, 0) AS DECIMAL(18,4)) AS base_alloc_tot_actl_amt,
        CAST(NVL(a.fee_alloc_rate, 0) * NVL(p.tech_srv_pre_fee, 0) AS DECIMAL(18,4)) AS base_alloc_tech_srv_pre_fee,
        CAST(NVL(a.fee_alloc_rate, 0) * NVL(p.tech_srv_actl_fee, 0) AS DECIMAL(18,4)) AS base_alloc_tech_srv_actl_fee,
        CAST(NVL(a.fee_alloc_rate, 0) * NVL(p.ins_amt, 0) AS DECIMAL(18,4)) AS base_alloc_ins_amt,
        CAST(NVL(a.fee_alloc_rate, 0) * NVL(p.diff_amt, 0) AS DECIMAL(18,4)) AS base_alloc_diff_amt,
        CAST(NVL(a.fee_alloc_rate, 0) * NVL(p.succ_diff_amt, 0) AS DECIMAL(18,4)) AS base_alloc_succ_diff_amt,
        CAST(NVL(a.fee_alloc_rate, 0) * NVL(p.cpn_amt, 0) AS DECIMAL(18,4)) AS base_alloc_cpn_amt,
        CAST(NVL(a.fee_alloc_rate, 0) * NVL(p.disc_amt, 0) AS DECIMAL(18,4)) AS base_alloc_disc_amt,
        CAST(NVL(a.fee_alloc_rate, 0) * NVL(p.dep_amt, 0) AS DECIMAL(18,4)) AS base_alloc_dep_amt,
        CAST(NVL(a.fee_alloc_rate, 0) * NVL(p.actl_dep_amt, 0) AS DECIMAL(18,4)) AS base_alloc_actl_dep_amt,
        CAST(CASE
            WHEN NVL(p.is_vol_wt_on, 0) = 0 THEN NVL(a.wt_alloc_rate, 0) * NVL(p.actl_wt, 0)
            ELSE 0
        END AS DECIMAL(18,4)) AS alloc_wt,
        CAST(CASE
            WHEN NVL(p.is_vol_wt_on, 0) = 1 THEN NVL(a.vol_alloc_rate, 0) * NVL(p.pkg_len, 0) * NVL(p.pkg_wid, 0) * NVL(p.pkg_hgt, 0)
            ELSE 0
        END AS DECIMAL(18,4)) AS alloc_vol
    FROM alloc_rate_calc a
    LEFT JOIN pkg_mgr p
        ON a.pkg_no = p.pkg_no
),
fee_alloc AS (
    SELECT
        ord_line_no,
        pkg_no,
        fee_alloc_rate,
        wt_alloc_rate,
        vol_alloc_rate,
        CASE WHEN is_valid_pkg = 1 AND pkg_line_rn = pkg_line_cnt
            THEN CAST(pkg_tot_pre_amt - SUM(CASE WHEN pkg_line_rn < pkg_line_cnt THEN base_alloc_tot_pre_amt ELSE 0 END) OVER (PARTITION BY pkg_no) AS DECIMAL(18,4))
            ELSE base_alloc_tot_pre_amt
        END AS alloc_tot_pre_amt,
        CASE WHEN is_valid_pkg = 1 AND pkg_line_rn = pkg_line_cnt
            THEN CAST(pkg_tot_actl_amt - SUM(CASE WHEN pkg_line_rn < pkg_line_cnt THEN base_alloc_tot_actl_amt ELSE 0 END) OVER (PARTITION BY pkg_no) AS DECIMAL(18,4))
            ELSE base_alloc_tot_actl_amt
        END AS alloc_tot_actl_amt,
        CASE WHEN is_valid_pkg = 1 AND pkg_line_rn = pkg_line_cnt
            THEN CAST(pkg_tech_srv_pre_fee - SUM(CASE WHEN pkg_line_rn < pkg_line_cnt THEN base_alloc_tech_srv_pre_fee ELSE 0 END) OVER (PARTITION BY pkg_no) AS DECIMAL(18,4))
            ELSE base_alloc_tech_srv_pre_fee
        END AS alloc_tech_srv_pre_fee,
        CASE WHEN is_valid_pkg = 1 AND pkg_line_rn = pkg_line_cnt
            THEN CAST(pkg_tech_srv_actl_fee - SUM(CASE WHEN pkg_line_rn < pkg_line_cnt THEN base_alloc_tech_srv_actl_fee ELSE 0 END) OVER (PARTITION BY pkg_no) AS DECIMAL(18,4))
            ELSE base_alloc_tech_srv_actl_fee
        END AS alloc_tech_srv_actl_fee,
        CASE WHEN is_valid_pkg = 1 AND pkg_line_rn = pkg_line_cnt
            THEN CAST(pkg_ins_amt - SUM(CASE WHEN pkg_line_rn < pkg_line_cnt THEN base_alloc_ins_amt ELSE 0 END) OVER (PARTITION BY pkg_no) AS DECIMAL(18,4))
            ELSE base_alloc_ins_amt
        END AS alloc_ins_amt,
        CASE WHEN is_valid_pkg = 1 AND pkg_line_rn = pkg_line_cnt
            THEN CAST(pkg_diff_amt - SUM(CASE WHEN pkg_line_rn < pkg_line_cnt THEN base_alloc_diff_amt ELSE 0 END) OVER (PARTITION BY pkg_no) AS DECIMAL(18,4))
            ELSE base_alloc_diff_amt
        END AS alloc_diff_amt,
        CASE WHEN is_valid_pkg = 1 AND pkg_line_rn = pkg_line_cnt
            THEN CAST(pkg_succ_diff_amt - SUM(CASE WHEN pkg_line_rn < pkg_line_cnt THEN base_alloc_succ_diff_amt ELSE 0 END) OVER (PARTITION BY pkg_no) AS DECIMAL(18,4))
            ELSE base_alloc_succ_diff_amt
        END AS alloc_succ_diff_amt,
        CASE WHEN is_valid_pkg = 1 AND pkg_line_rn = pkg_line_cnt
            THEN CAST(pkg_cpn_amt - SUM(CASE WHEN pkg_line_rn < pkg_line_cnt THEN base_alloc_cpn_amt ELSE 0 END) OVER (PARTITION BY pkg_no) AS DECIMAL(18,4))
            ELSE base_alloc_cpn_amt
        END AS alloc_cpn_amt,
        CASE WHEN is_valid_pkg = 1 AND pkg_line_rn = pkg_line_cnt
            THEN CAST(pkg_disc_amt - SUM(CASE WHEN pkg_line_rn < pkg_line_cnt THEN base_alloc_disc_amt ELSE 0 END) OVER (PARTITION BY pkg_no) AS DECIMAL(18,4))
            ELSE base_alloc_disc_amt
        END AS alloc_disc_amt,
        CASE WHEN is_valid_pkg = 1 AND pkg_line_rn = pkg_line_cnt
            THEN CAST(pkg_dep_amt - SUM(CASE WHEN pkg_line_rn < pkg_line_cnt THEN base_alloc_dep_amt ELSE 0 END) OVER (PARTITION BY pkg_no) AS DECIMAL(18,4))
            ELSE base_alloc_dep_amt
        END AS alloc_dep_amt,
        CASE WHEN is_valid_pkg = 1 AND pkg_line_rn = pkg_line_cnt
            THEN CAST(pkg_actl_dep_amt - SUM(CASE WHEN pkg_line_rn < pkg_line_cnt THEN base_alloc_actl_dep_amt ELSE 0 END) OVER (PARTITION BY pkg_no) AS DECIMAL(18,4))
            ELSE base_alloc_actl_dep_amt
        END AS alloc_actl_dep_amt,
        alloc_wt,
        alloc_vol
    FROM fee_alloc_base
)

-- -----------------------------------------------------------
-- 写入: 内部订单子单驱动，保持一行一个ord_line_no
-- -----------------------------------------------------------
INSERT OVERWRITE TABLE demo_dw.dws_trd_ord_line_td PARTITION (ds = '${bizdate}')
SELECT
    l.ord_line_no,
    l.ord_no,
    COALESCE(l.line_usr_id, h.hdr_usr_id) AS usr_id,
    COALESCE(u.usr_nm, l.line_usr_nm, h.hdr_usr_nm) AS usr_nm,
    COALESCE(u.email, l.line_email, h.hdr_email) AS email,
    u.usr_cntry_cd,
    u.usr_cntry_nm,
    u.usr_lang,
    u.usr_stat,
    u.is_usr_frz,
    u.is_usr_risk,
    u.usr_lvl_id,
    u.usr_lvl_nm,
    u.usr_lvl,
    u.usr_crt_time,
    COALESCE(l.line_cmpny_id, h.cmpny_id) AS cmpny_id,
    h.ord_stat,
    CASE
        WHEN h.ord_stat IS NULL THEN NULL
        WHEN h.ord_stat = 0 THEN '待付款'
        WHEN h.ord_stat = 1 THEN '待接单'
        WHEN h.ord_stat = 2 THEN '处理中'
        WHEN h.ord_stat = 3 THEN '转单中'
        WHEN h.ord_stat = 4 THEN '取消订购'
        WHEN h.ord_stat = 5 THEN '邮费补款'
        WHEN h.ord_stat = 6 THEN '风控中'
        WHEN h.ord_stat = 7 THEN '撤单退款'
        WHEN h.ord_stat = 8 THEN '支付中'
        WHEN h.ord_stat = 9 THEN '已完成'
        ELSE '未知'
    END AS ord_stat_nm,
    h.ord_type_cd,
    h.item_aud_stat,
    h.pay_no,
    h.slr_nm,
    h.pur_usr_nm,
    h.pur_usr_id,
    h.pur_usr_dept,
    h.rcv_cntry,
    h.rcv_cntry_id,
    COALESCE(h.inner_data_src, h.shop_src) AS shop_src,
    h.shop_nm,
    h.shop_url,
    h.shop_id,
    h.splr_shop_nm,
    h.splr_shop_url,
    h.splr_shop_id,
    COALESCE(l.line_wh_id, h.hdr_wh_id) AS wh_id,
    COALESCE(l.line_wh_nm, h.hdr_wh_nm) AS wh_nm,
    h.lang,
    h.ccy,
    h.ord_pend_time,
    h.pay_time,
    h.ord_upd_time,
    h.is_expd,
    h.is_ord_del,
    h.usr_vip_lvl,
    h.sys_tag,
    h.dev,
    h.merge_item_json,
    h.acty_disc_json,
    h.ord_xtn_json,
    l.item_id,
    l.sku_id,
    l.item_nm,
    l.item_nm_cn,
    l.item_attr,
    l.item_attr_cn,
    l.item_url,
    l.item_img,
    l.ord_line_stat,
    l.ord_line_stat_nm,
    l.cfm_stat,
    l.rtn_stat,
    l.sales_type_cd,
    l.abn_type_cd,
    l.cart_pur_type_cd,
    l.show_way_cd,
    l.is_exprs_dlyd,
    l.is_need_cfm,
    l.is_deferred,
    l.ord_cnt,
    l.prc,
    l.pur_prc,
    l.item_ord_amt,
    l.vrtl_prc,
    l.disc_amt,
    l.item_xtra_amt,
    l.item_pend_xtra_amt,
    l.booked_xtra_amt,
    l.rtn_amt,
    l.rtn_fee,
    l.back_post_amt,
    l.ins_back_amt,
    l.custom_fee,
    l.wt,
    l.vol_desc,
    l.line_vol,
    l.pkg_no,
    l.exprs_no,
    l.exprs_id,
    l.exprs_nm,
    l.pur_no,
    l.bin_no,
    l.ml_lmt,
    l.inv_id,
    l.ctgy_id,
    c.lvl1_ctgy_id,
    c.lvl1_ctgy_nm,
    c.lvl2_ctgy_id,
    c.lvl2_ctgy_nm,
    c.lvl3_ctgy_id,
    c.lvl3_ctgy_nm,
    c.lvl4_ctgy_id,
    c.lvl4_ctgy_nm,
    c.dcl_cn_nm,
    c.dcl_en_nm,
    c.cstm_hs_cd,
    l.stor_out_time,
    l.item_rmk,
    l.item_rmk_img,
    l.usr_rmk,
    l.rmk_time,
    l.data_src,
    l.ds_ord_no,
    l.ds_ord_line_no,
    l.bd_usr_nm,
    l.pur_sugg_prc,
    l.pur_sugg_post_prc,
    l.cmb_item_id,
    l.cmb_item_nm,
    l.cmb_item_attr,
    l.cmb_item_img,
    l.cmb_item_url,
    l.inner_sales_prc AS shop_prc,
    l.inner_aff_prc AS dist_prc,
    l.inner_src_prc AS orig_pur_prc,
    l.plugin_cnt_json AS ds_ord_line_cnt_json,
    l.line_xtn_json,
    l.line_crt_time,
    l.line_upd_time,
    dh.ds_ord_stat,
    CASE
        WHEN dh.ds_ord_stat IS NULL THEN NULL
        WHEN dh.ds_ord_stat = 1 THEN '待处理'
        WHEN dh.ds_ord_stat = 2 THEN '待支付'
        WHEN dh.ds_ord_stat = 3 THEN '备货中'
        WHEN dh.ds_ord_stat = 4 THEN '待发货'
        WHEN dh.ds_ord_stat = 5 THEN '待送达'
        WHEN dh.ds_ord_stat = 6 THEN '已完结'
        WHEN dh.ds_ord_stat = 9 THEN '已取消'
        WHEN dh.ds_ord_stat = 10 THEN '已退款'
        WHEN dh.ds_ord_stat = 11 THEN '已失效'
        ELSE '未知'
    END AS ds_ord_stat_nm,
    dh.ds_ord_type_cd,
    dh.ds_pay_no,
    dh.ds_pay_time,
    dh.ds_shop_pltf_cd,
    dh.ds_shop_id,
    dh.ds_shop_nm,
    dh.ds_out_ord_id,
    dh.ds_out_ord_no,
    COALESCE(dl.ds_line_ccy, dh.ds_ccy) AS ds_ccy,
    dh.ds_ord_crt_time,
    dh.ds_ord_upd_time,
    dl.ds_ord_line_stat,
    dl.ds_is_line_del,
    dl.ds_item_amt,
    CAST(dl.ds_item_amt * de.pref_rate AS DECIMAL(18,4)) AS ds_item_amt_cny,
    CASE
        WHEN NVL(dl.ds_is_line_del, 0) = 1
            OR dh.ds_ord_stat IN (9, 10, 11)
            OR dl.ds_ord_line_stat IN (9, 10, 11)
            OR h.ord_stat IN (4, 6, 7)
            OR l.ord_line_stat IN (11, 12, 16, 17, 18, 19, 20, 21, 24, 25, 26, 27, 33, 34, 35, 38, 39, 40, 41, 42, 49, 50, 51, 52, 53)
            OR pm.pkg_pay_stat IN (4, 5, 6)
            OR pm.pkg_bag_stat IN (1, 2, 3)
            OR NVL(l.rtn_amt, 0) > 0
            -- OR lc.ord_cxl_time IS NOT NULL
            OR lc.rtn_req_time IS NOT NULL
            OR lc.rtn_cmpl_time IS NOT NULL
            OR lc.ord_ref_time IS NOT NULL
        THEN 1
        ELSE 0
    END AS is_gmv_abn,
    CASE
        WHEN NVL(dl.ds_is_line_del, 0) = 1
            OR dh.ds_ord_stat IN (9, 10, 11)
            OR dl.ds_ord_line_stat IN (9, 10, 11)
            OR h.ord_stat IN (4, 6, 7)
            OR l.ord_line_stat IN (11, 12, 16, 17, 18, 19, 20, 21, 24, 25, 26, 27, 33, 34, 35, 38, 39, 40, 41, 42, 49, 50, 51, 52, 53)
            OR pm.pkg_pay_stat IN (4, 5, 6)
            OR pm.pkg_bag_stat IN (1, 2, 3)
            OR NVL(l.rtn_amt, 0) > 0
            -- OR lc.ord_cxl_time IS NOT NULL
            OR lc.rtn_req_time IS NOT NULL
            OR lc.rtn_cmpl_time IS NOT NULL
            OR lc.ord_ref_time IS NOT NULL
        THEN CAST(0 AS DECIMAL(18,4))
        ELSE CAST(GREATEST(NVL(l.item_ord_amt, 0) - NVL(l.disc_amt, 0), 0) AS DECIMAL(18,4))
    END AS ord_gmv,
    CASE
        WHEN NVL(dl.ds_is_line_del, 0) = 1
            OR dh.ds_ord_stat IN (9, 10, 11)
            OR dl.ds_ord_line_stat IN (9, 10, 11)
            OR h.ord_stat IN (4, 6, 7)
            OR l.ord_line_stat IN (11, 12, 16, 17, 18, 19, 20, 21, 24, 25, 26, 27, 33, 34, 35, 38, 39, 40, 41, 42, 49, 50, 51, 52, 53)
            OR pm.pkg_pay_stat IN (4, 5, 6)
            OR pm.pkg_bag_stat IN (1, 2, 3)
            OR NVL(l.rtn_amt, 0) > 0
            -- OR lc.ord_cxl_time IS NOT NULL
            OR lc.rtn_req_time IS NOT NULL
            OR lc.rtn_cmpl_time IS NOT NULL
            OR lc.ord_ref_time IS NOT NULL
        THEN CAST(0 AS DECIMAL(18,4))
        ELSE CAST(GREATEST(NVL(fa.alloc_tot_pre_amt, 0), 0) AS DECIMAL(18,4))
    END AS pkg_gmv,
    CASE
        WHEN NVL(dl.ds_is_line_del, 0) = 1
            OR dh.ds_ord_stat IN (9, 10, 11)
            OR dl.ds_ord_line_stat IN (9, 10, 11)
            OR h.ord_stat IN (4, 6, 7)
            OR l.ord_line_stat IN (11, 12, 16, 17, 18, 19, 20, 21, 24, 25, 26, 27, 33, 34, 35, 38, 39, 40, 41, 42, 49, 50, 51, 52, 53)
            OR pm.pkg_pay_stat IN (4, 5, 6)
            OR pm.pkg_bag_stat IN (1, 2, 3)
            OR NVL(l.rtn_amt, 0) > 0
            -- OR lc.ord_cxl_time IS NOT NULL
            OR lc.rtn_req_time IS NOT NULL
            OR lc.rtn_cmpl_time IS NOT NULL
            OR lc.ord_ref_time IS NOT NULL
        THEN CAST(0 AS DECIMAL(18,4))
        ELSE CAST(
            GREATEST(NVL(l.item_ord_amt, 0) - NVL(l.disc_amt, 0), 0)
            + GREATEST(NVL(fa.alloc_tot_pre_amt, 0), 0)
            AS DECIMAL(18,4)
        )
    END AS tot_gmv,
    pm.pkg_type_cd,
    pm.pkg_cond_cd,
    fa.fee_alloc_rate,
    fa.wt_alloc_rate,
    fa.vol_alloc_rate,
    fa.alloc_tot_pre_amt,
    fa.alloc_tot_actl_amt,
    fa.alloc_tech_srv_pre_fee,
    fa.alloc_tech_srv_actl_fee,
    fa.alloc_ins_amt,
    fa.alloc_diff_amt,
    fa.alloc_succ_diff_amt,
    fa.alloc_cpn_amt,
    fa.alloc_disc_amt,
    fa.alloc_dep_amt,
    fa.alloc_actl_dep_amt,
    fa.alloc_wt,
    fa.alloc_vol,
    pm.pkg_stat,
    CASE
        WHEN pm.pkg_stat IS NULL THEN NULL
        WHEN pm.pkg_stat = 0 THEN '待处理'
        WHEN pm.pkg_stat = 1 THEN '处理中'
        WHEN pm.pkg_stat = 2 THEN '出库中'
        WHEN pm.pkg_stat = 3 THEN '已出库'
        WHEN pm.pkg_stat = 4 THEN '已打包'
        WHEN pm.pkg_stat = 5 THEN '已称重'
        WHEN pm.pkg_stat = 6 THEN '已打印运单号'
        WHEN pm.pkg_stat = 7 THEN '已验证'
        WHEN pm.pkg_stat = 8 THEN '已交接'
        WHEN pm.pkg_stat = 9 THEN '已发货'
        WHEN pm.pkg_stat = 20 THEN '确认收货'
        ELSE '未知'
    END AS pkg_stat_nm,
    pm.pkg_pay_stat,
    CASE
        WHEN pm.pkg_pay_stat IS NULL THEN NULL
        WHEN pm.pkg_pay_stat = 0 THEN '待付款'
        WHEN pm.pkg_pay_stat = 1 THEN '处理中'
        WHEN pm.pkg_pay_stat = 2 THEN '已支付'
        WHEN pm.pkg_pay_stat = 3 THEN '已通知'
        WHEN pm.pkg_pay_stat = 4 THEN '已退款'
        WHEN pm.pkg_pay_stat = 5 THEN '失败'
        WHEN pm.pkg_pay_stat = 6 THEN '已取消'
        ELSE '未知'
    END AS pkg_pay_stat_nm,
    pm.pkg_bag_stat,
    CASE
        WHEN pm.pkg_bag_stat IS NULL THEN NULL
        WHEN pm.pkg_bag_stat = 0 THEN '正常包裹'
        WHEN pm.pkg_bag_stat = 1 THEN '国内退包'
        WHEN pm.pkg_bag_stat = 2 THEN '国外退包'
        WHEN pm.pkg_bag_stat = 3 THEN '取消包裹'
        WHEN pm.pkg_bag_stat = 4 THEN '包裹待补款'
        ELSE '未知'
    END AS pkg_bag_stat_nm,
    pm.pkg_exprs_no,
    pm.pkg_exprs_nm,
    pm.pkg_line_nm,
    pm.pkg_line_id,
    pm.snd_area,
    pm.pkg_rcv_cntry_cd,
    pm.pkg_rcv_cntry,
    pm.pkg_rcv_cntry_cn,
    pm.pkg_rcv_area,
    pm.pkg_rcv_city,
    pm.pred_wt,
    pm.actl_wt,
    pm.diff_wt,
    pm.item_wt,
    pm.pkg_actl_wt,
    pm.pkg_len,
    pm.pkg_wid,
    pm.pkg_hgt,
    pm.is_vol_wt_on,
    pm.pkg_snd_time,
    pm.pkg_back_time,
    pm.pkg_dly_time,
    pm.pkg_biz_rmk,
    lc.ord_submit_time,
    lc.pend_pay_time,
    lc.ord_pay_time,
    lc.pur_time,
    lc.proc_time,
    lc.wh_stock_in_time,
    lc.pend_ob_time,
    lc.ob_ing_time,
    lc.pkg_cmpl_time,
    pm.trk_crt_time AS snd_ovs_time,
    lc.arv_time,
    lc.sign_time,
    pm.trk_dly_time AS rcv_time,
    lc.ord_cxl_time,
    lc.rtn_req_time,
    lc.rtn_cmpl_time,
    lc.ord_ref_time,
    h.ord_crt_time
FROM ord_line l
LEFT JOIN ord_hdr h
    ON l.ord_no = h.ord_no
LEFT JOIN usr_dim u
    ON COALESCE(l.line_usr_id, h.hdr_usr_id) = u.usr_id
LEFT JOIN exch_rate e
    ON UPPER(h.ccy) = e.ccy_cd
LEFT JOIN ds_ord_line dl
    ON l.ds_ord_line_no = dl.ds_ord_line_no
LEFT JOIN ds_ord_hdr dh
    ON COALESCE(dl.ds_ord_no, l.ds_ord_no) = dh.ds_ord_no
LEFT JOIN exch_rate de
    ON UPPER(COALESCE(dl.ds_line_ccy, dh.ds_ccy)) = de.ccy_cd
LEFT JOIN ctgy_dim c
    ON l.ctgy_id = c.lvl4_ctgy_id
LEFT JOIN fee_alloc fa
    ON l.ord_line_no = fa.ord_line_no
LEFT JOIN pkg_mgr pm
    ON l.pkg_no = pm.pkg_no
LEFT JOIN item_life lc
    ON l.ord_line_no = lc.life_ord_line_no
;
