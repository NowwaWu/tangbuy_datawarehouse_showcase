--MaxCompute SQL
--********************************************************************--
--author: 吴延俊
--create time: 2026-05-13 14:50:10
-- 数据域:   trd (交易域)
-- 业务过程: ds_ord (DS代发订单)
-- 表名:     dws_trd_ds_ord_line_pkg_fee_td
-- 表类型:   汇总事实表 (DWS Aggregate) - 周期快照(全量截至当日, 每日重算)
-- 描述:     从 DWD 层读取 DS 子单及包裹费用/重量/体积，按采购金额占比将
--           包裹级 11 项金额分摊到 ord_line_id 粒度，排除备货订单。
--           重量/体积分摊使用独立比例（wt_alloc_rate / vol_alloc_rate）：
--           从 dwd_trd_ds_ord_line_df 获取子单重量(wt)和体积(vol_desc解析)，
--           按 pkg_no 汇总后计算各子单占比，再根据 is_vol_wt_on 判定：
--           =1(体积重) → alloc_vol = 包裹体积 × vol_alloc_rate
--           =0(非体积重) → alloc_wt = 包裹重量 × wt_alloc_rate
--           底层 DWD 为累积快照(_df)，DWS 每日读取 DWD 当日全量分区重算，
--           使用 _td (Total to Date) 后缀，与 _1d (最近1天增量) 严格区分。
-- ETL方式:  每日从 DWD 层读取当日全量分区重新计算, INSERT OVERWRITE 写入当日分区
-- 调度变量: ${bizdate} 格式 yyyyMMdd
-- 依赖:
--   dwd_trd_ds_ord_line_df    (当日分区, 获取子单维度及pkg_no)
--   dwd_trd_ds_ord_header_df  (当日分区, 过滤 ord_type_cd)
--   dwd_wh_pkg_mgr_df         (当日分区, 获取包裹费用)
-- 防膨胀:
--   pkg_no 由 dwd_trd_ds_ord_line_df 统一保证 item_no→pkg_no 唯一映射 (ROW_NUMBER)
-- 零NULL:
--   数值度量 → 0, ID → -99, 字符串 → '-99'
--********************************************************************--

WITH
-- -----------------------------------------------------------
-- CTE-1: DS子单 + 主单过滤 (排除备货订单类型)
--   ord_type_cd: 1-代发, 2-直购备货, 3-直购直发, 4-询盘备货, 5-询盘直发
--   排除 2(直购备货) 和 4(询盘备货)
-- -----------------------------------------------------------
ds_ord_line_today AS (
    SELECT
        dl.ord_line_no,
        dl.ord_no,
        dl.tb_ord_line_no,
        dl.tb_item_id,
        NVL(dl.tb_item_nm, '未知')                                AS tb_item_nm,
        NVL(dl.ord_cnt, 0)                                       AS ord_cnt,
        dh.pkg_latest_no                                        AS pkg_no,
        NVL(dl.pur_amt, 0)                                      AS pur_amt,
        NVL(dl.wt, 0)                                           AS wt,
        -- 退化维度 (来自 ds_ord_header, 零额外 JOIN)
        NVL(dh.usr_id, -99)                                     AS usr_id,
        NVL(dh.ord_type_cd, -1)                                 AS ord_type_cd,
        NVL(dh.shop_pltf_cd, '未知')                             AS shop_pltf_cd,
        NVL(dh.pkg_wrap_cd, '未知包装')                           AS pkg_wrap_cd,
        NVL(dh.ord_stat, -1)                                    AS ord_stat,
        dh.pay_time                                             AS pay_time,
        dh.crt_time                                             AS crt_time,
        -- 从 vol_desc (格式: 长*宽*高) 解析体积(cm³), '未知'→0
        CAST(NVL(REGEXP_EXTRACT(dl.vol_desc, '([0-9.]+)\\*([0-9.]+)\\*([0-9.]+)', 1), '0') AS DECIMAL(18,4))
        * CAST(NVL(REGEXP_EXTRACT(dl.vol_desc, '([0-9.]+)\\*([0-9.]+)\\*([0-9.]+)', 2), '0') AS DECIMAL(18,4))
        * CAST(NVL(REGEXP_EXTRACT(dl.vol_desc, '([0-9.]+)\\*([0-9.]+)\\*([0-9.]+)', 3), '0') AS DECIMAL(18,4)) AS line_vol
    FROM demo_dw.dwd_trd_ds_ord_line_df dl
    LEFT JOIN demo_dw.dwd_trd_ds_ord_header_df dh
        ON dl.ord_no = dh.ord_no
        AND dh.ds = '${bizdate}'
    WHERE dl.ds = '${bizdate}'
      AND NVL(dh.ord_type_cd, -1) NOT IN (2, 4)
      AND dl.is_del = 0
),

-- -----------------------------------------------------------
-- CTE-2: 包裹费用+重量/体积 (当日快照)
-- -----------------------------------------------------------
pkg_fee_today AS (
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
        actl_wt,
        pkg_len,
        pkg_wid,
        pkg_hgt,
        is_vol_wt_on
    FROM demo_dw.dwd_wh_pkg_mgr_df
    WHERE ds = '${bizdate}'
),
-- -----------------------------------------------------------
-- CTE-3: 关联基表 + 计算三类分摊比例
--   fee_alloc_rate = pur_amt / SUM(pur_amt) OVER (PARTITION BY pkg_no)  → 费用按包裹分摊
--   wt_alloc_rate  = wt       / SUM(wt)      OVER (PARTITION BY ord_no) → 重量按订单内子单占比分摊
--   vol_alloc_rate = line_vol / SUM(line_vol) OVER (PARTITION BY ord_no) → 体积按订单内子单占比分摊
--   重量/体积按 ord_no 拆分确保比例总和=100%（包裹含包装材料，包裹重≠子单重之和）
--   分母为 0 或未关联到包裹时比例为 0
-- -----------------------------------------------------------
alloc_rate_calc AS (
    SELECT
        dl.ord_line_no,
        dl.ord_no,
        dl.tb_ord_line_no,
        dl.tb_item_id,
        dl.tb_item_nm,
        dl.ord_cnt,
        NVL(dl.pkg_no, '-99') AS pkg_no,
        dl.pur_amt,
        dl.wt,
        dl.line_vol,
        -- 退化维度
        dl.usr_id,
        dl.ord_type_cd,
        dl.shop_pltf_cd,
        dl.pkg_wrap_cd,
        dl.ord_stat,
        dl.pay_time,
        dl.crt_time,
        -- 包裹内 DS 子单采购金额合计
        SUM(dl.pur_amt) OVER (PARTITION BY dl.pkg_no) AS pkg_tot_pur_amt,
        -- 费用分摊比例
        CASE
            WHEN dl.pkg_no IS NULL THEN CAST(0 AS DECIMAL(18,4))
            WHEN SUM(dl.pur_amt) OVER (PARTITION BY dl.pkg_no) = 0 THEN CAST(0 AS DECIMAL(18,4))
            ELSE CAST(dl.pur_amt / SUM(dl.pur_amt) OVER (PARTITION BY dl.pkg_no) AS DECIMAL(18,4))
        END AS fee_alloc_rate,
        -- 重量分摊比例 (按 ord_no 汇总, 保证比例总和=100%)
        CASE
            WHEN SUM(dl.wt) OVER (PARTITION BY dl.ord_no) = 0 THEN CAST(0 AS DECIMAL(18,4))
            ELSE CAST(dl.wt / SUM(dl.wt) OVER (PARTITION BY dl.ord_no) AS DECIMAL(18,4))
        END AS wt_alloc_rate,
        -- 体积分摊比例 (按 ord_no 汇总, 保证比例总和=100%)
        CASE
            WHEN SUM(dl.line_vol) OVER (PARTITION BY dl.ord_no) = 0 THEN CAST(0 AS DECIMAL(18,4))
            ELSE CAST(dl.line_vol / SUM(dl.line_vol) OVER (PARTITION BY dl.ord_no) AS DECIMAL(18,4))
        END AS vol_alloc_rate,
        -- 包裹维度费用 (带回 NULL 由后续 NVL 处理)
        pf.dep_amt              AS pkg_dep_amt,
        pf.actl_dep_amt         AS pkg_actl_dep_amt,
        pf.tot_pre_amt          AS pkg_tot_pre_amt,
        pf.tot_actl_amt         AS pkg_tot_actl_amt,
        pf.tech_srv_pre_fee     AS pkg_tech_srv_pre_fee,
        pf.tech_srv_actl_fee    AS pkg_tech_srv_actl_fee,
        pf.ins_amt              AS pkg_ins_amt,
        pf.diff_amt             AS pkg_diff_amt,
        pf.succ_diff_amt        AS pkg_succ_diff_amt,
        pf.cpn_amt              AS pkg_cpn_amt,
        pf.disc_amt             AS pkg_disc_amt,
        -- 包裹重量/体积
        pf.actl_wt          AS actl_wt,
        pf.pkg_len              AS pkg_len,
        pf.pkg_wid              AS pkg_wid,
        pf.pkg_hgt              AS pkg_hgt,
        pf.is_vol_wt_on         AS is_vol_wt_on
    FROM ds_ord_line_today dl
    LEFT JOIN pkg_fee_today pf ON dl.pkg_no = pf.pkg_no
),

-- -----------------------------------------------------------
-- CTE-4: 分摊金额 + 重量/体积 (Zero-NULL 兜底)
--   费用按 fee_alloc_rate 分摊, 重量/体积按各自的独立比例分摊
--   alloc_wt:  is_vol_wt_on=0 → wt_alloc_rate  × pkg_actl_wt
--   alloc_vol: is_vol_wt_on=1 → vol_alloc_rate × (pkg_len × pkg_wid × pkg_hgt)
-- -----------------------------------------------------------
fee_alloc AS (
    SELECT
        ord_line_no,
        ord_no,
        tb_ord_line_no,
        tb_item_id,
        tb_item_nm,
        ord_cnt,
        pkg_no,
        -- 退化维度
        usr_id,
        ord_type_cd,
        shop_pltf_cd,
        pkg_wrap_cd,
        ord_stat,
        pay_time,
        crt_time,
        fee_alloc_rate,
        wt_alloc_rate,
        vol_alloc_rate,
        cast(NVL(fee_alloc_rate, 0) * NVL(pkg_dep_amt,              0) as decimal(18,4)) AS dep_amt,
        cast(NVL(fee_alloc_rate, 0) * NVL(pkg_actl_dep_amt,         0) as decimal(18,4)) AS actl_dep_amt,
        cast(NVL(fee_alloc_rate, 0) * NVL(pkg_tot_pre_amt,          0) as decimal(18,4)) AS tot_pre_amt,
        cast(NVL(fee_alloc_rate, 0) * NVL(pkg_tot_actl_amt,         0) as decimal(18,4)) AS tot_actl_amt,
        cast(NVL(fee_alloc_rate, 0) * NVL(pkg_tech_srv_pre_fee,     0) as decimal(18,4)) AS tech_srv_pre_fee,
        cast(NVL(fee_alloc_rate, 0) * NVL(pkg_tech_srv_actl_fee,    0) as decimal(18,4)) AS tech_srv_actl_fee,
        cast(NVL(fee_alloc_rate, 0) * NVL(pkg_ins_amt,              0) as decimal(18,4)) AS ins_amt,
        cast(NVL(fee_alloc_rate, 0) * NVL(pkg_diff_amt,             0) as decimal(18,4)) AS diff_amt,
        cast(NVL(fee_alloc_rate, 0) * NVL(pkg_succ_diff_amt,        0) as decimal(18,4)) AS succ_diff_amt,
        cast(NVL(fee_alloc_rate, 0) * NVL(pkg_cpn_amt,              0) as decimal(18,4)) AS cpn_amt,
        cast(NVL(fee_alloc_rate, 0) * NVL(pkg_disc_amt,             0) as decimal(18,4)) AS disc_amt,
        -- 分摊重量: is_vol_wt_on=0 时用 wt_alloc_rate, =1 时为0
        CAST(CASE
            WHEN NVL(is_vol_wt_on, 0) = 0
            THEN NVL(wt_alloc_rate, 0) *  NVL(actl_wt, 0)
            ELSE 0
        END AS DECIMAL(18,4)) AS alloc_wt,
        -- 分摊体积: is_vol_wt_on=1 时用 vol_alloc_rate, =0 时为0
        CAST(CASE
            WHEN NVL(is_vol_wt_on, 0) = 1
            THEN NVL(vol_alloc_rate, 0) * NVL(actl_wt, 0)
            ELSE 0
        END AS DECIMAL(18,4)) AS alloc_vol
    FROM alloc_rate_calc
)

-- -----------------------------------------------------------
-- 写入: INSERT OVERWRITE 当日分区 (全量截至当日)
-- -----------------------------------------------------------
INSERT OVERWRITE TABLE demo_dw.dws_trd_ds_ord_line_pkg_fee_td PARTITION (ds = '${bizdate}')
SELECT
    ord_line_no,
    ord_no,
    tb_ord_line_no,
    tb_item_id,
    NVL(tb_item_nm,            '未知')              AS tb_item_nm,
    pkg_no,
    NVL(usr_id,                    -99)              AS usr_id,
    NVL(ord_type_cd,               -1)               AS ord_type_cd,
    NVL(shop_pltf_cd,           '未知')              AS shop_pltf_cd,
    NVL(pkg_wrap_cd,         '未知包装')              AS pkg_wrap_cd,
    NVL(ord_stat,                  -1)               AS ord_stat,
    pay_time,
    crt_time,
    NVL(ord_cnt,                    0)               AS ord_cnt,
    NVL(fee_alloc_rate,         0) AS fee_alloc_rate,
    NVL(wt_alloc_rate,          0) AS wt_alloc_rate,
    NVL(vol_alloc_rate,         0) AS vol_alloc_rate,
    NVL(tot_pre_amt,            0) AS tot_pre_amt,
    NVL(tot_actl_amt,           0) AS tot_actl_amt,
    NVL(tech_srv_pre_fee,       0) AS tech_srv_pre_fee,
    NVL(tech_srv_actl_fee,      0) AS tech_srv_actl_fee,
    NVL(ins_amt,                0) AS ins_amt,
    NVL(diff_amt,               0) AS diff_amt,
    NVL(succ_diff_amt,          0) AS succ_diff_amt,
    NVL(cpn_amt,                0) AS cpn_amt,
    NVL(disc_amt,               0) AS disc_amt,
    NVL(dep_amt,                0) AS dep_amt,
    NVL(actl_dep_amt,           0) AS actl_dep_amt,
    NVL(alloc_wt,               0) AS alloc_wt,
    NVL(alloc_vol,              0) AS alloc_vol
FROM fee_alloc
;
