--MaxCompute SQL
--********************************************************************--
--author: 吴延俊
--create time: 2026-06-17
-- 数据域:   trd (交易域)
-- 业务过程: ds_ord (DS代发订单)
-- 表名:     dws_trd_ds_ord_line_td
-- 表类型:   公共明细服务表 (DWS Detail Service) - 周期快照(全量截至当日, 每日重算)
-- 描述:     以 DS 订单行 ord_line_no 为粒度，组合 DS 订单主子表、Tangbuy内部订单最新关联、用户维度、店铺授权关系、包裹费用分摊和物流信息。
--           表名已表达 DS 业务视角，因此 DS 侧字段默认不再加 ds_ 前缀；Tangbuy内部订单字段统一 tb_ 前缀。
-- 粒度:     一行 = 一个 DS 订单子单(dwd_trd_ds_ord_line_df.ord_line_no)
-- ETL方式:  每日读取 DWD/DIM 当日全量分区重算, INSERT OVERWRITE 写入当日分区
-- 调度变量: ${bizdate} 格式 yyyyMMdd
-- 依赖:
--   dwd_trd_ds_ord_line_df          (当日分区, DS订单子单)
--   dwd_trd_ds_ord_header_df        (当日分区, DS订单主单)
--   dwd_trd_ord_line_df             (当日分区, Tangbuy内部订单子单; 按DS子单取最新关联)
--   dwd_trd_ord_header_df           (当日分区, Tangbuy内部订单主单; 补最新内部主单属性)
--   dim_usr_info_df                 (当日分区, 用户信息)
--   dwd_store_ds_shop_auth_rel_df   (当日分区, 店铺授权关系)
--   dwd_wh_pkg_mgr_df               (当日分区, 包裹费用和物流信息)
--   dim_itm_category_df             (当日分区, Tangbuy内部商品类目)
--   dwd_trd_order_operation_di      (全量历史分区 ds<=bizdate, 操作流水; pivot出履约关键节点时间)
--   dim_pay_exch_rate_df            (当日分区, 汇率)
-- 防膨胀:
--   Tangbuy内部订单子单: ds_ord_line_no 理论 1:1，异常换货/退货导致 1:N 时 ROW_NUMBER 取最新一条
--   店铺授权关系: 按 usr_id + shop_pltf_cd + shop_id ROW_NUMBER取最新授权关系
--   包裹费用/物流: 费用分摊严格沿用 dws_trd_ds_ord_line_pkg_fee_td，按订单最新包裹号关联包裹快照后回填
-- 过滤口径:
--   DWS公共服务层不做已支付、测试店铺、删除单等应用过滤，仅保留状态字段供下游筛选。
--   新增 is_gmv_abn 标记和 ord_gmv/pkg_gmv/tot_gmv 拆分GMV，基于本表状态字段做异常门控，下游ADS可直接取用。
--   原 ord_gmv 已拆分为 ord_gmv(采购金额pur_amt)+pkg_gmv(分摊费用)+tot_gmv(汇总)，含义有变更。
-- NULL口径:
--   除费用分摊字段沿用旧费用表 0/-99/'未知包装' 兜底外，缺失字段保留 NULL。
--********************************************************************--

WITH
-- -----------------------------------------------------------
-- CTE-1: DS订单子单，当日全量快照
-- -----------------------------------------------------------
ds_ord_line AS (
    SELECT
        ord_line_no,
        ord_no,
        draft_no,
        usr_id AS line_usr_id,
        usr_nm AS line_usr_nm,
        email AS line_email,
        bd_usr_nm,
        tb_shop_id,
        tb_shop_nm,
        tb_shop_url,
        UPPER(shop_pltf_cd) AS line_shop_pltf_cd,
        ord_line_stat,
        is_del AS is_line_del,
        pkg_no,
        tb_ord_line_no AS pur_tb_ord_line_no,
        tb_item_type_cd,
        data_src,
        tb_item_id,
        tb_sku_id,
        tb_item_nm_cn,
        tb_item_attr,
        tb_item_attr_cn,
        tb_item_url,
        prc AS item_prc,
        pur_amt,
        disc_amt,
        rtn_amt,
        post_fee,
        splr_type_cd,
        pur_type_cd,
        pur_rate,
        ord_cnt,
        ref_cnt,
        crsh_cnt,
        crsh_ref_cnt,
        splr_item_id,
        splr_shop_id,
        wt,
        vol_desc,
        rmk,
        shop_id AS line_shop_id,
        shop_nm AS line_shop_nm,
        ccy AS line_ccy,
        ord_amt AS item_amt,
        item_attr,
        item_nm,
        item_img,
        item_cnt,
        line_id AS out_ord_line_id,
        item_id,
        sku_id,
        item_dim_id,
        UPPER(item_stat_cd) AS item_stat_cd,
        crt_time,
        upd_time
    FROM demo_dw.dwd_trd_ds_ord_line_df
    WHERE ds = '${bizdate}'
),

-- -----------------------------------------------------------
-- CTE-2: DS订单主单，当日全量快照
-- -----------------------------------------------------------
ds_ord_hdr AS (
    SELECT
        ord_no,
        usr_id AS hdr_usr_id,
        usr_nm AS hdr_usr_nm,
        email AS hdr_email,
        ord_stat,
        ord_type_cd,
        pay_no,
        pay_time,
        lang,
        cntry_id,
        cxl_rsn,
        cxl_rsn_id,
        is_del AS is_ord_del,
        out_ord_id,
        out_ord_no,
        shop_id AS hdr_shop_id,
        shop_nm AS hdr_shop_nm,
        UPPER(shop_pltf_cd) AS hdr_shop_pltf_cd,
        ccy AS hdr_ccy,
        ord_amt,
        ord_rmk,
        out_crt_time AS out_ord_crt_time,
        out_upd_time AS out_ord_upd_time,
        rcv_nm,
        rcv_cntry_cd,
        rcv_prov,
        rcv_city,
        crt_time AS ord_crt_time,
        upd_time AS ord_upd_time,
        pkg_latest_no,
        pkg_wrap_cd
    FROM demo_dw.dwd_trd_ds_ord_header_df
    WHERE ds = '${bizdate}'
),

-- -----------------------------------------------------------
-- CTE-3: 用户维度，当日全量快照
-- -----------------------------------------------------------
usr_dim AS (
    SELECT
        usr_id,
        usr_nm,
        nick,
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
-- CTE-5: 店铺授权关系去重，防止授权表异常重复导致膨胀
-- -----------------------------------------------------------
shop_auth_ranked AS (
    SELECT
        auth_rel_id,
        usr_id,
        UPPER(shop_pltf_cd) AS shop_pltf_cd,
        shop_id,
        shop_nm,
        shop_url AS auth_shop_url,
        slr_nm AS auth_slr_nm,
        shop_rgn_cd AS auth_shop_rgn_cd,
        is_shop_unreachable AS is_auth_shop_unreachable,
        shop_unreachable_rsn AS auth_shop_unreachable_rsn,
        shop_crt_time AS auth_shop_crt_time,
        auth_stat,
        auth_stat_nm,
        bd_usr_nm AS auth_bd_usr_nm,
        is_del AS is_auth_del,
        crt_time AS auth_crt_time,
        upd_time AS auth_upd_time,
        auth_revoke_time,
        ROW_NUMBER() OVER (
            PARTITION BY usr_id, UPPER(shop_pltf_cd), shop_id
            ORDER BY auth_stat DESC, upd_time DESC, auth_rel_id DESC
        ) AS rn
    FROM demo_dw.dwd_store_ds_shop_auth_rel_df
    WHERE ds = '${bizdate}'
),
shop_auth AS (
    SELECT
        auth_rel_id,
        usr_id,
        shop_pltf_cd,
        shop_id,
        shop_nm,
        auth_shop_url,
        auth_slr_nm,
        auth_shop_rgn_cd,
        is_auth_shop_unreachable,
        auth_shop_unreachable_rsn,
        auth_shop_crt_time,
        auth_stat,
        auth_stat_nm,
        auth_bd_usr_nm,
        is_auth_del,
        auth_crt_time,
        auth_upd_time,
        auth_revoke_time
    FROM shop_auth_ranked
    WHERE rn = 1
),

-- -----------------------------------------------------------
-- CTE-6: Tangbuy内部订单子单，按DS子单取最新关联
-- -----------------------------------------------------------
tb_ord_line_ranked AS (
    SELECT
        ds_ord_line_no AS rel_ord_line_no,
        ord_no AS tb_ord_no,
        ord_line_no AS tb_ord_line_no,
        wh_id AS tb_wh_id,
        wh_nm AS tb_wh_nm,
        ord_line_stat AS tb_ord_line_stat,
        ord_line_stat_nm AS tb_ord_line_stat_nm,
        ctgy_id,
        CAST(pur_prc * ord_cnt AS DECIMAL(18,4)) AS tb_item_ord_amt,
        item_xtra_amt AS tb_item_xtra_amt,
        item_pend_xtra_amt AS tb_item_pend_xtra_amt,
        custom_fee AS tb_custom_fee,
        wt AS tb_wt,
        exprs_no AS tb_exprs_no,
        exprs_nm AS tb_exprs_nm,
        pur_no AS tb_pur_no,
        crt_time AS tb_line_crt_time,
        upd_time AS tb_line_upd_time,
        ROW_NUMBER() OVER (
            PARTITION BY ds_ord_line_no
            ORDER BY upd_time DESC, crt_time DESC, ord_line_no DESC
        ) AS rn
    FROM demo_dw.dwd_trd_ord_line_df
    WHERE ds = '${bizdate}'
      AND ds_ord_line_no IS NOT NULL
      AND TRIM(ds_ord_line_no) <> ''
      AND ds_ord_line_no <> '-99'
),
tb_ord_line_latest AS (
    SELECT
        rel_ord_line_no,
        tb_ord_no,
        tb_ord_line_no,
        tb_wh_id,
        tb_wh_nm,
        tb_ord_line_stat,
        tb_ord_line_stat_nm,
        ctgy_id,
        tb_item_ord_amt,
        tb_item_xtra_amt,
        tb_item_pend_xtra_amt,
        tb_custom_fee,
        tb_wt,
        tb_exprs_no,
        tb_exprs_nm,
        tb_pur_no,
        tb_line_crt_time,
        tb_line_upd_time
    FROM tb_ord_line_ranked
    WHERE rn = 1
),

-- -----------------------------------------------------------
-- CTE-7: Tangbuy内部订单主单，当日全量快照
-- -----------------------------------------------------------
tb_ord_hdr AS (
    SELECT
        ord_no AS tb_ord_no,
        ord_stat AS tb_ord_stat,
        ord_type_cd AS tb_ord_type_cd
    FROM demo_dw.dwd_trd_ord_header_df
    WHERE ds = '${bizdate}'
),

-- -----------------------------------------------------------
-- CTE-8: Tangbuy内部商品类目维度，当日全量快照
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
        cstm_hs_cd
    FROM demo_dw.dim_itm_category_df
    WHERE ds = '${bizdate}'
),

-- -----------------------------------------------------------
-- CTE-8b: Tangbuy内部子单履约关键节点时间
--   直接读 DWD 操作流水全量历史分区(ds<=bizdate), 按 ord_line_no(=item_no)
--   对关键 op_type_cn 取 MAX(crt_time) pivot, 只保留反映关键业务流程的主节点,
--   字段顺序按真实履约流程排列。
-- -----------------------------------------------------------
item_life AS (
    SELECT
        ord_line_no AS life_tb_ord_line_no,
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
        pkg_actl_wt,
        pkg_len,
        pkg_wid,
        pkg_hgt,
        is_vol_wt_on,
        pkg_stat,
        pay_stat AS pkg_pay_stat,
        bag_stat AS pkg_bag_stat,
        exprs_no,
        exprs_nm,
        line_nm AS pkg_line_nm,
        line_id AS pkg_line_id,
        snd_area,
        snd_time AS pkg_snd_time,
        trk_crt_time,
        trk_dly_time,
        back_time AS pkg_back_time,
        biz_rmk AS pkg_biz_rmk
    FROM demo_dw.dwd_wh_pkg_mgr_df
    WHERE ds = '${bizdate}'
),

-- -----------------------------------------------------------
-- CTE-10: 分摊计算基表，仅计算可分摊子单，不过滤主表输出行
-- -----------------------------------------------------------
alloc_line_base AS (
    SELECT
        l.ord_line_no,
        l.ord_no,
        l.pkg_no,
        NVL(l.pur_amt, 0) AS pur_amt,
        NVL(l.wt, 0) AS wt,
        CAST(NVL(REGEXP_EXTRACT(l.vol_desc, '([0-9.]+)\\*([0-9.]+)\\*([0-9.]+)', 1), '0') AS DECIMAL(18,4))
        * CAST(NVL(REGEXP_EXTRACT(l.vol_desc, '([0-9.]+)\\*([0-9.]+)\\*([0-9.]+)', 2), '0') AS DECIMAL(18,4))
        * CAST(NVL(REGEXP_EXTRACT(l.vol_desc, '([0-9.]+)\\*([0-9.]+)\\*([0-9.]+)', 3), '0') AS DECIMAL(18,4)) AS line_vol
    FROM ds_ord_line l
    LEFT JOIN ds_ord_hdr h
        ON l.ord_no = h.ord_no
    WHERE NVL(h.ord_type_cd, -1) NOT IN (2, 4)
      AND NVL(l.is_line_del, 0) = 0
),

-- -----------------------------------------------------------
-- CTE-11: 费用、重量、体积分摊比例
-- -----------------------------------------------------------
alloc_rate_calc AS (
    SELECT
        ord_line_no,
        ord_no,
        NVL(pkg_no, '-99') AS pkg_no,
        CASE
            WHEN pkg_no IS NULL THEN CAST(0 AS DECIMAL(18,4))
            WHEN SUM(pur_amt) OVER (PARTITION BY pkg_no) = 0 THEN CAST(0 AS DECIMAL(18,4))
            ELSE CAST(pur_amt / SUM(pur_amt) OVER (PARTITION BY pkg_no) AS DECIMAL(18,4))
        END AS fee_alloc_rate,
        CASE
            WHEN SUM(wt) OVER (PARTITION BY ord_no) = 0 THEN CAST(0 AS DECIMAL(18,4))
            ELSE CAST(wt / SUM(wt) OVER (PARTITION BY ord_no) AS DECIMAL(18,4))
        END AS wt_alloc_rate,
        CASE
            WHEN SUM(line_vol) OVER (PARTITION BY ord_no) = 0 THEN CAST(0 AS DECIMAL(18,4))
            ELSE CAST(line_vol / SUM(line_vol) OVER (PARTITION BY ord_no) AS DECIMAL(18,4))
        END AS vol_alloc_rate
    FROM alloc_line_base
),

-- -----------------------------------------------------------
-- CTE-12: 包裹费用按子单分摊
-- -----------------------------------------------------------
fee_alloc AS (
    SELECT
        a.ord_line_no,
        a.pkg_no,
        NVL(a.fee_alloc_rate, 0) AS fee_alloc_rate,
        NVL(a.wt_alloc_rate, 0) AS wt_alloc_rate,
        NVL(a.vol_alloc_rate, 0) AS vol_alloc_rate,
        CAST(NVL(a.fee_alloc_rate, 0) * NVL(p.tot_pre_amt, 0) AS DECIMAL(18,4)) AS alloc_tot_pre_amt,
        CAST(NVL(a.fee_alloc_rate, 0) * NVL(p.tot_actl_amt, 0) AS DECIMAL(18,4)) AS alloc_tot_actl_amt,
        CAST(NVL(a.fee_alloc_rate, 0) * NVL(p.tech_srv_pre_fee, 0) AS DECIMAL(18,4)) AS alloc_tech_srv_pre_fee,
        CAST(NVL(a.fee_alloc_rate, 0) * NVL(p.tech_srv_actl_fee, 0) AS DECIMAL(18,4)) AS alloc_tech_srv_actl_fee,
        CAST(NVL(a.fee_alloc_rate, 0) * NVL(p.ins_amt, 0) AS DECIMAL(18,4)) AS alloc_ins_amt,
        CAST(NVL(a.fee_alloc_rate, 0) * NVL(p.diff_amt, 0) AS DECIMAL(18,4)) AS alloc_diff_amt,
        CAST(NVL(a.fee_alloc_rate, 0) * NVL(p.succ_diff_amt, 0) AS DECIMAL(18,4)) AS alloc_succ_diff_amt,
        CAST(NVL(a.fee_alloc_rate, 0) * NVL(p.cpn_amt, 0) AS DECIMAL(18,4)) AS alloc_cpn_amt,
        CAST(NVL(a.fee_alloc_rate, 0) * NVL(p.disc_amt, 0) AS DECIMAL(18,4)) AS alloc_disc_amt,
        CAST(NVL(a.fee_alloc_rate, 0) * NVL(p.dep_amt, 0) AS DECIMAL(18,4)) AS alloc_dep_amt,
        CAST(NVL(a.fee_alloc_rate, 0) * NVL(p.actl_dep_amt, 0) AS DECIMAL(18,4)) AS alloc_actl_dep_amt,
        CAST(CASE
            WHEN NVL(p.is_vol_wt_on, 0) = 0 THEN NVL(a.wt_alloc_rate, 0) * NVL(p.actl_wt, 0)
            ELSE 0
        END AS DECIMAL(18,4)) AS alloc_wt,
        CAST(CASE
            WHEN NVL(p.is_vol_wt_on, 0) = 1 THEN NVL(a.vol_alloc_rate, 0) * NVL(p.actl_wt, 0)
            ELSE 0
        END AS DECIMAL(18,4)) AS alloc_vol
    FROM alloc_rate_calc a
    LEFT JOIN pkg_mgr p
        ON a.pkg_no = p.pkg_no
)

-- -----------------------------------------------------------
-- 写入: DS子单驱动，保持一行一个ord_line_no
-- -----------------------------------------------------------
INSERT OVERWRITE TABLE demo_dw.dws_trd_ds_ord_line_td PARTITION (ds = '${bizdate}')
SELECT
    l.ord_line_no,
    l.ord_no,
    l.draft_no,
    COALESCE(l.line_usr_id, h.hdr_usr_id) AS usr_id,
    COALESCE(u.usr_nm, l.line_usr_nm, h.hdr_usr_nm) AS usr_nm,
    u.nick,
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
    COALESCE(l.line_shop_pltf_cd, h.hdr_shop_pltf_cd) AS shop_pltf_cd,
    COALESCE(l.line_shop_id, h.hdr_shop_id) AS shop_id,
    COALESCE(l.line_shop_nm, h.hdr_shop_nm) AS shop_nm,
    a.auth_rel_id,
    a.auth_stat,
    a.auth_stat_nm,
    a.auth_shop_url,
    a.auth_slr_nm,
    a.auth_shop_rgn_cd,
    a.is_auth_shop_unreachable,
    a.auth_shop_unreachable_rsn,
    a.auth_shop_crt_time,
    a.auth_bd_usr_nm,
    a.is_auth_del,
    a.auth_crt_time,
    a.auth_upd_time,
    a.auth_revoke_time,
    h.ord_stat,
    CASE
        WHEN h.ord_stat IS NULL THEN NULL
        WHEN h.ord_stat = 1 THEN '待处理'
        WHEN h.ord_stat = 2 THEN '待支付'
        WHEN h.ord_stat = 3 THEN '备货中'
        WHEN h.ord_stat = 4 THEN '待发货'
        WHEN h.ord_stat = 5 THEN '待送达'
        WHEN h.ord_stat = 6 THEN '已完结'
        WHEN h.ord_stat = 9 THEN '已取消'
        WHEN h.ord_stat = 10 THEN '已退款'
        WHEN h.ord_stat = 11 THEN '已失效'
        ELSE '未知'
    END AS ord_stat_nm,
    h.ord_type_cd,
    h.pay_no,
    h.pay_time,
    h.lang,
    h.cntry_id,
    h.cxl_rsn,
    h.cxl_rsn_id,
    h.is_ord_del,
    h.out_ord_id,
    h.out_ord_no,
    COALESCE(l.line_ccy, h.hdr_ccy) AS ccy,
    h.ord_amt,
    CAST(h.ord_amt * e.pref_rate AS DECIMAL(18,4)) AS ord_amt_cny,
    h.ord_rmk,
    h.out_ord_crt_time,
    h.out_ord_upd_time,
    h.rcv_nm,
    h.rcv_cntry_cd,
    h.rcv_prov,
    h.rcv_city,
    h.ord_crt_time,
    h.ord_upd_time,
    l.ord_line_stat,
    l.is_line_del,
    l.tb_shop_id,
    l.tb_shop_nm,
    l.tb_shop_url,
    COALESCE(tl.tb_ord_line_no, l.pur_tb_ord_line_no) AS tb_ord_line_no,
    l.tb_item_type_cd,
    l.data_src,
    l.tb_item_id,
    l.tb_sku_id,
    l.tb_item_nm_cn,
    l.tb_item_attr,
    l.tb_item_attr_cn,
    l.tb_item_url,
    l.item_prc,
    l.pur_amt,
    l.disc_amt,
    l.rtn_amt,
    l.post_fee,
    l.splr_type_cd,
    l.pur_type_cd,
    l.pur_rate,
    l.ord_cnt,
    l.ref_cnt,
    l.crsh_cnt,
    l.crsh_ref_cnt,
    l.splr_item_id,
    l.splr_shop_id,
    l.wt,
    l.vol_desc,
    l.rmk,
    COALESCE(fa.pkg_no, l.pkg_no) AS pkg_no,
    CASE WHEN fa.ord_line_no IS NOT NULL THEN NVL(h.pkg_wrap_cd, '未知包装') ELSE h.pkg_wrap_cd END AS pkg_wrap_cd,
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
    CASE
        WHEN NVL(l.is_line_del, 0) = 1
            OR h.ord_stat IN (9, 10, 11)
            OR l.ord_line_stat IN (9, 10, 11)
            OR th.tb_ord_stat IN (4, 6, 7)
            OR tl.tb_ord_line_stat IN (11, 12, 16, 17, 18, 19, 20, 21, 24, 25, 26, 27, 33, 34, 35, 38, 39, 40, 41, 42, 49, 50, 51, 52, 53)
            OR pm.pkg_pay_stat IN (4, 5, 6)
            OR pm.pkg_bag_stat IN (1, 2, 3)
            OR NVL(l.rtn_amt, 0) > 0
            OR NVL(l.ref_cnt, 0) > 0
            OR NVL(l.crsh_ref_cnt, 0) > 0
            -- OR lc.ord_cxl_time IS NOT NULL
            OR lc.rtn_req_time IS NOT NULL
            OR lc.rtn_cmpl_time IS NOT NULL
            OR lc.ord_ref_time IS NOT NULL
        THEN 1
        ELSE 0
    END AS is_gmv_abn,
    CASE
        WHEN NVL(l.is_line_del, 0) = 1
            OR h.ord_stat IN (9, 10, 11)
            OR l.ord_line_stat IN (9, 10, 11)
            OR th.tb_ord_stat IN (4, 6, 7)
            OR tl.tb_ord_line_stat IN (11, 12, 16, 17, 18, 19, 20, 21, 24, 25, 26, 27, 33, 34, 35, 38, 39, 40, 41, 42, 49, 50, 51, 52, 53)
            OR pm.pkg_pay_stat IN (4, 5, 6)
            OR pm.pkg_bag_stat IN (1, 2, 3)
            OR NVL(l.rtn_amt, 0) > 0
            OR NVL(l.ref_cnt, 0) > 0
            OR NVL(l.crsh_ref_cnt, 0) > 0
            -- OR lc.ord_cxl_time IS NOT NULL
            OR lc.rtn_req_time IS NOT NULL
            OR lc.rtn_cmpl_time IS NOT NULL
            OR lc.ord_ref_time IS NOT NULL
        THEN CAST(0 AS DECIMAL(18,4))
        ELSE CAST(GREATEST(NVL(l.pur_amt, 0), 0) AS DECIMAL(18,4))
    END AS ord_gmv,
    CASE
        WHEN NVL(l.is_line_del, 0) = 1
            OR h.ord_stat IN (9, 10, 11)
            OR l.ord_line_stat IN (9, 10, 11)
            OR th.tb_ord_stat IN (4, 6, 7)
            OR tl.tb_ord_line_stat IN (11, 12, 16, 17, 18, 19, 20, 21, 24, 25, 26, 27, 33, 34, 35, 38, 39, 40, 41, 42, 49, 50, 51, 52, 53)
            OR pm.pkg_pay_stat IN (4, 5, 6)
            OR pm.pkg_bag_stat IN (1, 2, 3)
            OR NVL(l.rtn_amt, 0) > 0
            OR NVL(l.ref_cnt, 0) > 0
            OR NVL(l.crsh_ref_cnt, 0) > 0
            -- OR lc.ord_cxl_time IS NOT NULL
            OR lc.rtn_req_time IS NOT NULL
            OR lc.rtn_cmpl_time IS NOT NULL
            OR lc.ord_ref_time IS NOT NULL
        THEN CAST(0 AS DECIMAL(18,4))
        ELSE CAST(GREATEST(NVL(fa.alloc_tot_pre_amt, 0), 0) AS DECIMAL(18,4))
    END AS pkg_gmv,
    CASE
        WHEN NVL(l.is_line_del, 0) = 1
            OR h.ord_stat IN (9, 10, 11)
            OR l.ord_line_stat IN (9, 10, 11)
            OR th.tb_ord_stat IN (4, 6, 7)
            OR tl.tb_ord_line_stat IN (11, 12, 16, 17, 18, 19, 20, 21, 24, 25, 26, 27, 33, 34, 35, 38, 39, 40, 41, 42, 49, 50, 51, 52, 53)
            OR pm.pkg_pay_stat IN (4, 5, 6)
            OR pm.pkg_bag_stat IN (1, 2, 3)
            OR NVL(l.rtn_amt, 0) > 0
            OR NVL(l.ref_cnt, 0) > 0
            OR NVL(l.crsh_ref_cnt, 0) > 0
            -- OR lc.ord_cxl_time IS NOT NULL
            OR lc.rtn_req_time IS NOT NULL
            OR lc.rtn_cmpl_time IS NOT NULL
            OR lc.ord_ref_time IS NOT NULL
        THEN CAST(0 AS DECIMAL(18,4))
        ELSE CAST(
            GREATEST(NVL(l.pur_amt, 0), 0)
            + GREATEST(NVL(fa.alloc_tot_pre_amt, 0), 0)
            AS DECIMAL(18,4)
        )
    END AS tot_gmv,
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
    pm.exprs_no,
    pm.exprs_nm,
    pm.pkg_line_nm,
    pm.pkg_line_id,
    pm.snd_area,
    pm.pred_wt,
    pm.actl_wt,
    pm.pkg_actl_wt,
    pm.pkg_len,
    pm.pkg_wid,
    pm.pkg_hgt,
    pm.is_vol_wt_on,
    pm.pkg_snd_time,
    pm.pkg_back_time,
    pm.pkg_biz_rmk,
    l.item_attr,
    l.item_nm,
    l.item_img,
    l.item_cnt,
    l.out_ord_line_id,
    l.item_id,
    l.sku_id,
    l.item_amt,
    CAST(l.item_amt * e.pref_rate AS DECIMAL(18,4)) AS item_amt_cny,
    l.item_dim_id,
    l.item_stat_cd,
    l.crt_time,
    l.upd_time,
    tl.tb_ord_no,
    th.tb_ord_stat,
    CASE
        WHEN th.tb_ord_stat IS NULL THEN NULL
        WHEN th.tb_ord_stat = 0 THEN '待付款'
        WHEN th.tb_ord_stat = 1 THEN '待接单'
        WHEN th.tb_ord_stat = 2 THEN '处理中'
        WHEN th.tb_ord_stat = 3 THEN '转单中'
        WHEN th.tb_ord_stat = 4 THEN '取消订购'
        WHEN th.tb_ord_stat = 5 THEN '邮费补款'
        WHEN th.tb_ord_stat = 6 THEN '风控中'
        WHEN th.tb_ord_stat = 7 THEN '撤单退款'
        WHEN th.tb_ord_stat = 8 THEN '支付中'
        WHEN th.tb_ord_stat = 9 THEN '已完成'
        ELSE '未知'
    END AS tb_ord_stat_nm,
    th.tb_ord_type_cd,
    tl.tb_ord_line_stat,
    tl.tb_ord_line_stat_nm,
    c.lvl1_ctgy_id,
    c.lvl1_ctgy_nm,
    c.lvl2_ctgy_id,
    c.lvl2_ctgy_nm,
    c.lvl3_ctgy_id,
    c.lvl3_ctgy_nm,
    c.lvl4_ctgy_id,
    c.lvl4_ctgy_nm,
    c.cstm_hs_cd,
    tl.tb_wh_id,
    tl.tb_wh_nm,
    tl.tb_item_ord_amt,
    tl.tb_item_xtra_amt,
    tl.tb_item_pend_xtra_amt,
    tl.tb_custom_fee,
    tl.tb_wt,
    tl.tb_exprs_no,
    tl.tb_exprs_nm,
    tl.tb_pur_no,
    tl.tb_line_crt_time,
    tl.tb_line_upd_time,
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
    l.bd_usr_nm
FROM ds_ord_line l
LEFT JOIN ds_ord_hdr h
    ON l.ord_no = h.ord_no
LEFT JOIN usr_dim u
    ON COALESCE(l.line_usr_id, h.hdr_usr_id) = u.usr_id
LEFT JOIN shop_auth a
    ON COALESCE(l.line_usr_id, h.hdr_usr_id) = a.usr_id
   AND COALESCE(l.line_shop_pltf_cd, h.hdr_shop_pltf_cd) = a.shop_pltf_cd
   AND COALESCE(l.line_shop_id, h.hdr_shop_id) = a.shop_id
LEFT JOIN exch_rate e
    ON UPPER(COALESCE(l.line_ccy, h.hdr_ccy)) = e.ccy_cd
LEFT JOIN fee_alloc fa
    ON l.ord_line_no = fa.ord_line_no
LEFT JOIN pkg_mgr pm
    ON COALESCE(fa.pkg_no, l.pkg_no) = pm.pkg_no
LEFT JOIN tb_ord_line_latest tl
    ON CAST(l.ord_line_no AS STRING) = tl.rel_ord_line_no
LEFT JOIN tb_ord_hdr th
    ON tl.tb_ord_no = th.tb_ord_no
LEFT JOIN ctgy_dim c
    ON tl.ctgy_id = c.lvl4_ctgy_id
LEFT JOIN item_life lc
    ON COALESCE(tl.tb_ord_line_no, l.pur_tb_ord_line_no) = lc.life_tb_ord_line_no
;
