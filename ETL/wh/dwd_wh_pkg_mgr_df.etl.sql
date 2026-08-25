--MaxCompute SQL
--********************************************************************--
--author: 吴延俊
--create time: 2026-05-11 17:12:21
-- 数据域:   wh (仓储履约域)
-- 业务过程: pkg_mgr (包裹管理)
-- 表名:     dwd_wh_pkg_mgr_df
-- 表类型:   明细事实表 (DWD Detail) - 累积快照
-- 描述:     包裹全生命周期累积快照，以 package_no 为粒度，
--           整合包裹主表/地址/费用/申报/称重/扩展/打包/交易/物流轨迹/订单子单金额，
--           冗余用户维度(usr_nm/email)和仓库维度(wh_nm)，
--           为下游 DWS/ADS 提供统一的包裹履约数据出口。
-- 粒度:     一行 = 一个包裹 (package_no)
-- 来源:
--   ods_mysql_tang_storage_s_package_ri            (包裹主表, 驱动表)
--   ods_mysql_tang_storage_s_pack_addr_ri          (收件信息, 1:1)
--   ods_mysql_tang_storage_s_pack_fee_ri           (费用明细, 1:1)
--   ods_mysql_tang_storage_s_declare_fee_ri        (申报明细, 1:N→聚合申报名称/数量/金额)
--   ods_mysql_tang_storage_s_pack_info_ri          (扩展信息, 1:1)
--   ods_mysql_tang_storage_s_pack_weight_ri        (称重记录, 1:1)
--   ods_mysql_tang_storage_s_pack_record_ri        (打包记录, 1:1)
--   (已移除 ods_mysql_tang_storage_s_pack_oqc_ri — oqc_line_nm 字段已删除)
--   ods_mysql_tang_storage_s_pack_item_ri          (包裹商品, 1:N→聚合cnt)
--   ods_mysql_tang_order_t_order_item_ri           (订单子单, 经s_pack_item关系聚合商品实付金额)
--   ods_mysql_tang_storage_s_pack_trade_ri         (交易记录, 1:N→取最新)
--   ods_mysql_tang_logistics_track_ri              (物流轨迹, 1:1→取最新兜底)
-- 维度冗余:
--   dim_usr_info_df       (LEFT JOIN usr_id → usr_nm, email)
--   dim_wh_warehouse_df   (LEFT JOIN wh_id → wh_nm)
--   dim_comm_country_df   (LEFT JOIN 源country → rcv_cntry_cd/rcv_cntry/rcv_cntry_cn, 使用最新可用静态分区)
-- 更新策略: 每日全量读取ODS源表, INSERT OVERWRITE 写入当日分区
-- 调度周期: 日
-- 调度变量: ${bizdate} 格式 yyyyMMdd
-- 防膨胀:
--   s_pack_item     1:N → COUNT 聚合取商品件数
--   s_declare_fee   1:N → 排序拼接/SUM 聚合申报信息
--   s_pack_item+t_order_item 1:N → 按包裹当前明细关系SUM商品实付金额
--   s_pack_trade    1:N → ROW_NUMBER 取最新交易
--   logistics_track 1:1 → ROW_NUMBER 取最新轨迹兜底
-- 零NULL:
--   数值度量 → 0/-99, 字符串 → '未知', JSON → '{}', 布尔 → 0, 时间保留 NULL
--********************************************************************--


WITH
-- -----------------------------------------------------------
-- CTE-1: 包裹商品聚合 (防1:N膨胀, COUNT件数)
-- -----------------------------------------------------------
pkg_item_agg AS (
    SELECT
        package_no,
        COUNT(1)                                        AS item_cnt
    FROM demo_dw.ods_mysql_tang_storage_s_pack_item_ri
    GROUP BY package_no
),

-- -----------------------------------------------------------
-- CTE-2: 包裹申报信息聚合 (防1:N膨胀)
-- -----------------------------------------------------------
dcl_fee_agg AS (
    SELECT
        package_no,
        CONCAT_WS(',', SORT_ARRAY(COLLECT_LIST(name_cn)))                    AS dcl_cn_nm_list,
        CONCAT_WS(',', SORT_ARRAY(COLLECT_LIST(name_en)))                    AS dcl_en_nm_list,
        SUM(NVL(nums, 0))                                                    AS dcl_item_cnt,
        CAST(SUM(NVL(CAST(amount AS DECIMAL(18,4)), 0)) AS DECIMAL(18,4))    AS dcl_amt
    FROM demo_dw.ods_mysql_tang_storage_s_declare_fee_ri
    GROUP BY package_no
),

-- -----------------------------------------------------------
-- CTE-3: 包裹商品实付金额聚合 (按包裹明细关系, 防1:N膨胀)
-- -----------------------------------------------------------
pkg_item_amt_agg AS (
    SELECT
        pi.package_no,
        CAST(
            SUM(
                NVL(CAST(oi.write_price AS DECIMAL(18,4)), 0) * NVL(oi.nums, 0)
                - NVL(CAST(oi.discount_amount AS DECIMAL(18,4)), 0)
            ) AS DECIMAL(18,4)
        ) AS pkg_item_amt
    FROM demo_dw.ods_mysql_tang_storage_s_pack_item_ri pi
    LEFT JOIN demo_dw.ods_mysql_tang_order_t_order_item_ri oi
        ON pi.item_no = oi.item_no
    GROUP BY pi.package_no
),

-- -----------------------------------------------------------
-- CTE-4: 交易记录取最新 (防1:N膨胀)
-- -----------------------------------------------------------
pkg_trade_latest AS (
    SELECT
        package_no,
        trade_no
    FROM (
        SELECT
            package_no,
            trade_no,
            ROW_NUMBER() OVER (PARTITION BY package_no ORDER BY create_time DESC) AS rn
        FROM demo_dw.ods_mysql_tang_storage_s_pack_trade_ri
    ) t
    WHERE rn = 1
),

-- -----------------------------------------------------------
-- CTE-5: 物流轨迹取最新 (当前源表1:1, 保留防膨胀兜底)
-- -----------------------------------------------------------
logis_track_latest AS (
    SELECT
        package_no,
        express_status,
        pick_time,
        clear_time,
        delivery_time,
        last_time,
        delivery_days,
        create_time
    FROM (
        SELECT
            package_no,
            express_status,
            pick_time,
            clear_time,
            delivery_time,
            last_time,
            delivery_days,
            create_time,
            ROW_NUMBER() OVER (PARTITION BY package_no ORDER BY update_time DESC, create_time DESC, express_no DESC) AS rn
        FROM demo_dw.ods_mysql_tang_logistics_track_ri
        WHERE del_flag = 0
    ) t
    WHERE rn = 1
),

-- -----------------------------------------------------------
-- CTE-6: 用户维度 (取前一天快照)
-- -----------------------------------------------------------
usr_dim AS (
    SELECT
        usr_id,
        usr_nm,
        email                                       AS email
    FROM demo_dw.dim_usr_info_df
    WHERE ds ='${bizdate}'
),

-- -----------------------------------------------------------
-- CTE-7: 仓库维度 (取前一天快照)
-- -----------------------------------------------------------
wh_dim AS (
    SELECT
        wh_id,
        wh_nm
    FROM demo_dw.dim_wh_warehouse_df
    WHERE ds = '${bizdate}'
),

-- -----------------------------------------------------------
-- CTE-8: 国家维度匹配键 (静态维取最新分区, 国家二字码/三字码/英文名归一)
-- -----------------------------------------------------------
country_dim AS (
    SELECT
        match_key,
        cntry_cd,
        cntry_nm,
        cntry_nm_en
    FROM (
        SELECT
            match_key,
            cntry_cd,
            cntry_nm,
            cntry_nm_en,
            ROW_NUMBER() OVER (PARTITION BY match_key ORDER BY pri) AS rn
        FROM (
            SELECT
                UPPER(TRIM(cntry_cd)) AS match_key,
                cntry_cd,
                cntry_nm,
                cntry_nm_en,
                1 AS pri
            FROM demo_dw.dim_comm_country_df
            WHERE ds = MAX_PT('demo_dw.dim_comm_country_df')

            UNION ALL

            SELECT
                UPPER(TRIM(iso_alpha3_cd)) AS match_key,
                cntry_cd,
                cntry_nm,
                cntry_nm_en,
                2 AS pri
            FROM demo_dw.dim_comm_country_df
            WHERE ds = MAX_PT('demo_dw.dim_comm_country_df')

            UNION ALL

            SELECT
                REGEXP_REPLACE(UPPER(REGEXP_REPLACE(TRIM(cntry_nm_en), '[^A-Za-z0-9]', '')), '^THE', '') AS match_key,
                cntry_cd,
                cntry_nm,
                cntry_nm_en,
                3 AS pri
            FROM demo_dw.dim_comm_country_df
            WHERE ds = MAX_PT('demo_dw.dim_comm_country_df')

            UNION ALL

            SELECT
                TRIM(cntry_nm) AS match_key,
                cntry_cd,
                cntry_nm,
                cntry_nm_en,
                4 AS pri
            FROM demo_dw.dim_comm_country_df
            WHERE ds = MAX_PT('demo_dw.dim_comm_country_df')

            UNION ALL

            SELECT
                CASE
                    WHEN cntry_cd = 'US' THEN 'UNITEDSTATES'
                    WHEN cntry_cd = 'GB' THEN 'UNITEDKINGDOM'
                    WHEN cntry_cd = 'RE' THEN 'REUNION'
                    WHEN cntry_cd = 'TZ' THEN 'TANZANIA'
                    WHEN cntry_cd = 'TT' THEN 'REPUBLICOFTRINIDADANDTOBAGO'
                    WHEN cntry_cd = 'PR' THEN 'USAPUERTORICO'
                    WHEN cntry_cd = 'ES' THEN '巴利阿里群岛'
                    ELSE NULL
                END AS match_key,
                cntry_cd,
                cntry_nm,
                cntry_nm_en,
                5 AS pri
            FROM demo_dw.dim_comm_country_df
            WHERE ds = MAX_PT('demo_dw.dim_comm_country_df')
        ) k
        WHERE match_key IS NOT NULL
          AND match_key <> ''
    ) r
    WHERE rn = 1
),

-- -----------------------------------------------------------
-- CTE-9: ODS全量 (每日全量读取包裹主表及关联表)
-- -----------------------------------------------------------
pkg_full AS (
    SELECT
        -- 主键/外键
        p.package_no              AS pkg_no,
        p.user_id                AS usr_id,
        p.storage_id                AS wh_id,
        p.items_no              AS stor_ord_no,
        tl.trade_no              AS trade_no,
        -- 用户维度冗余
        u.usr_nm              AS usr_nm,
        u.email              AS email,
        -- 仓库维度冗余
        wd.wh_nm              AS wh_nm,
        -- 物流线路/快递
        p.express_no              AS exprs_no,
        p.track_no                AS pxy_lbl_no,
        TRIM(REGEXP_REPLACE(p.logistic, '[|｜].*$', ''))                      AS exprs_nm,
        CASE
            WHEN p.line IS NULL THEN NULL
            WHEN TRIM(REGEXP_REPLACE(p.line, '[|｜].*$', '')) = '' THEN NULL
            ELSE TRIM(REGEXP_REPLACE(p.line, '[|｜].*$', ''))
        END                                                               AS line_nm,
        p.line_id              AS line_id,
        p.send_area              AS snd_area,
        CAST(p.carrier_id AS STRING)                                           AS carrier_id,
        p.logistic_id              AS logistic_id,
        -- 收件信息
        a.first_name              AS rcv_first_nm,
        a.last_name              AS rcv_last_nm,
        NVL(cd.cntry_cd, 'UNKNOWN')                                  AS rcv_cntry_cd,
        NVL(cd.cntry_nm_en, 'UNKNOWN')                               AS rcv_cntry,
        NVL(cd.cntry_nm, '未知')                                      AS rcv_cntry_cn,
        a.area              AS rcv_area,
        a.city              AS rcv_city,
        a.address              AS rcv_addr,
        a.post_code              AS rcv_zip,
        a.phone              AS rcv_phn,
        -- 称重信息
        NVL(CAST(pw.predict_weight     AS DECIMAL(18,4)),  0)               AS pred_wt,
        NVL(CAST(pw.act_weight         AS DECIMAL(18,4)),  0)               AS actl_wt,
        NVL(CAST(pw.diff_weight        AS DECIMAL(18,4)),  0)               AS diff_wt,
        NVL(CAST(pw.items_weight       AS DECIMAL(18,4)),  0)               AS item_wt,
        NVL(CAST(pw.pack_weight_act    AS DECIMAL(18,4)),  0)               AS pkg_actl_wt,
        NVL(CAST(p.pre_weight_act      AS DECIMAL(18,4)),  0)               AS pkg_pre_actl_wt,
        CAST(pw.lengths            AS DECIMAL(18,4))               AS pkg_len,
        CAST(pw.width              AS DECIMAL(18,4))               AS pkg_wid,
        CAST(pw.height             AS DECIMAL(18,4))               AS pkg_hgt,
        p.pre_volume_act              AS pkg_vol,
        -- 金额/费用
        NVL(CAST(p.deposit             AS DECIMAL(18,4)),  0)               AS dep_amt,
        NVL(CAST(p.act_deposit         AS DECIMAL(18,4)),  0)               AS actl_dep_amt,
        NVL(CAST(p.total_amount        AS DECIMAL(18,4)),  0)               AS tot_amt,
        NVL(CAST(f.total_amount_pre    AS DECIMAL(18,4)),  0)               AS tot_pre_amt,
        NVL(CAST(f.total_amount_act    AS DECIMAL(18,4)),  0)               AS tot_actl_amt,
        NVL(CAST(f.technical_service_fee_pre  AS DECIMAL(18,4)), 0)         AS tech_srv_pre_fee,
        NVL(CAST(f.technical_service_fee_act  AS DECIMAL(18,4)), 0)         AS tech_srv_actl_fee,
        NVL(CAST(f.insurance           AS DECIMAL(18,4)),  0)               AS ins_amt,
        NVL(CAST(f.insurance_service   AS DECIMAL(18,4)),  0)               AS ins_srv_fee,
        NVL(CAST(f.value_added_tax     AS DECIMAL(18,4)),  0)               AS vat_amt,
        NVL(CAST(p.difference          AS DECIMAL(18,4)),  0)               AS diff_amt,
        NVL(CAST(p.success_difference  AS DECIMAL(18,4)),  0)               AS succ_diff_amt,
        NVL(CAST(f.coupon              AS DECIMAL(18,4)),  0)               AS cpn_amt,
        NVL(CAST(f.discount            AS DECIMAL(18,4)),  0)               AS disc_amt,
        NVL(piaa.pkg_item_amt, 0)                                           AS pkg_item_amt,
        NVL(dfa.dcl_cn_nm_list, '未知')                                      AS dcl_cn_nm_list,
        NVL(dfa.dcl_en_nm_list, 'UNKNOWN')                                  AS dcl_en_nm_list,
        NVL(dfa.dcl_item_cnt, 0)                                             AS dcl_item_cnt,
        NVL(dfa.dcl_amt, 0)                                                  AS dcl_amt,
        -- 商品件数
        pia.item_cnt               AS item_cnt,
        -- 汇率
        CAST(p.rate                AS DECIMAL(18,4))               AS exch_rate,
        -- 币种/语言/平台
        GET_JSON_OBJECT(p.currency, '$.enName')                              AS ccy,
        UPPER(TRIM(CAST(p.lang AS STRING)))                                AS lang,
        UPPER(TRIM(CAST(p.plateform AS STRING)))                            AS pltf_cd,
        -- 状态
        p.status              AS pkg_stat,
        CASE
            WHEN p.status IS NULL THEN NULL
            WHEN p.status = 0 THEN '待处理'
            WHEN p.status = 1 THEN '处理中'
            WHEN p.status = 2 THEN '出库中'
            WHEN p.status = 3 THEN '已出库'
            WHEN p.status = 4 THEN '已打包'
            WHEN p.status = 5 THEN '已称重'
            WHEN p.status = 6 THEN '已打印运单号'
            WHEN p.status = 7 THEN '已验证'
            WHEN p.status = 8 THEN '已交接'
            WHEN p.status = 9 THEN '已发货'
            WHEN p.status = 20 THEN '确认收货'
            ELSE '未知'
        END                                                               AS pkg_stat_nm,
        p.pay_status              AS pay_stat,
        CASE
            WHEN p.pay_status IS NULL THEN NULL
            WHEN p.pay_status = 0 THEN '待付款'
            WHEN p.pay_status = 1 THEN '处理中'
            WHEN p.pay_status = 2 THEN '已支付'
            WHEN p.pay_status = 3 THEN '已通知'
            WHEN p.pay_status = 4 THEN '已退款'
            WHEN p.pay_status = 5 THEN '失败'
            WHEN p.pay_status = 6 THEN '已取消'
            ELSE '未知'
        END                                                               AS pay_stat_nm,
        p.bag_status              AS bag_stat,
        CASE
            WHEN p.bag_status IS NULL THEN NULL
            WHEN p.bag_status = 0 THEN '正常包裹'
            WHEN p.bag_status = 1 THEN '国内退包'
            WHEN p.bag_status = 2 THEN '国外退包'
            WHEN p.bag_status = 3 THEN '取消包裹'
            WHEN p.bag_status = 4 THEN '包裹待补款'
            ELSE '未知'
        END                                                               AS bag_stat_nm,
        p.sys_status              AS sys_stat,
        p.artificial_status              AS artif_stat,
        p.risk_status              AS risk_stat,
        p.lock_status                                                     AS is_frz,
        p.declare_status              AS dcl_stat,
        NVL(p.tax_type, -1)                                                AS tax_type_cd,
        CASE
            WHEN p.tax_type IS NULL THEN NULL
            WHEN p.tax_type = 0 THEN '收件人缴税'
            WHEN p.tax_type = 1 THEN '平台GST/VAT'
            WHEN p.tax_type = 2 THEN '个人GST/VAT'
            WHEN p.tax_type = 3 THEN '平台IOSS'
            WHEN p.tax_type = 4 THEN '个人IOSS'
            WHEN p.tax_type = 5 THEN '公司GST/VAT'
            WHEN p.tax_type = 6 THEN '物流商GST/VAT'
            WHEN p.tax_type = 7 THEN '物流商IOSS'
            WHEN p.tax_type = 8 THEN '免税'
            ELSE '未知'
        END                                                               AS tax_type_nm,
        CASE WHEN p.tax_type = 3 THEN 1 ELSE 0 END                         AS is_pltf_ioss,
        p.logistics_status              AS logis_stat,
        trk.express_status              AS exprs_stat,
        p.compensation_status              AS cmpstn_stat,
        p.after_sales_status                                              AS is_after_sale,
        pi.return_status                                                  AS is_rtn,
        -- 布尔/标记
        p.is_pending               AS is_pend,
        p.is_delete               AS is_del,
        p.is_growth               AS is_growth,
        p.customized_audit               AS is_custom_aud,
        pw.use_volume_weight               AS is_vol_wt_on,
        -- 定制/特殊标签
        p.customized_id              AS custom_id,
        UPPER(TRIM(CAST(p.risk_type AS STRING)))                          AS risk_cd,
        p.risk                                                            AS risk_lvl,
        UPPER(TRIM(CAST(p.handle AS STRING)))                              AS handle_cd,
        UPPER(TRIM(CAST(p.package_type AS STRING)))                        AS pkg_type_cd,
        UPPER(TRIM(CAST(p.special_status AS STRING)))                      AS spcl_stat_cd,
        -- 打包/OQC
        UPPER(TRIM(CAST(pr.package_condition AS STRING)))                  AS pkg_cond_cd,
        pr.create_by              AS pkg_usr,

        -- 时间里程碑
        CAST(p.create_time              AS DATETIME)                             AS crt_time,
        CAST(p.update_time              AS DATETIME)                             AS upd_time,
        CAST(p.pay_time                 AS DATETIME)                             AS pay_time,
        CAST(p.expire_time              AS DATETIME)                             AS exp_time,
        CAST(p.send_time                AS DATETIME)                             AS snd_time,
        CAST(p.back_time                AS DATETIME)                             AS back_time,
        CAST(pi.delivery_time           AS DATETIME)                             AS dly_time,
        CAST(trk.create_time AS DATETIME)                                  AS trk_crt_time,
        CASE
            WHEN trk.pick_time IS NOT NULL AND trk.pick_time > 0
            THEN CAST(FROM_UNIXTIME(CAST(trk.pick_time / 1000 AS BIGINT)) AS DATETIME)
            ELSE NULL
        END                                                               AS pick_time,
        CASE
            WHEN trk.clear_time IS NOT NULL AND trk.clear_time > 0
            THEN CAST(FROM_UNIXTIME(CAST(trk.clear_time / 1000 AS BIGINT)) AS DATETIME)
            ELSE NULL
        END                                                               AS clr_time,
        CASE
            WHEN trk.delivery_time IS NOT NULL AND trk.delivery_time > 0
            THEN CAST(FROM_UNIXTIME(CAST(trk.delivery_time / 1000 AS BIGINT)) AS DATETIME)
            ELSE NULL
        END                                                               AS trk_dly_time,
        CASE
            WHEN trk.last_time IS NOT NULL AND trk.last_time > 0
            THEN CAST(FROM_UNIXTIME(CAST(trk.last_time / 1000 AS BIGINT)) AS DATETIME)
            ELSE NULL
        END                                                               AS last_trk_time,
        trk.delivery_days              AS dly_day_cnt,
        CAST(p.compensation_time        AS DATETIME)                             AS cmpstn_time,
        CAST(p.growth_time              AS DATETIME)                             AS growth_time,
        -- 备注/扩展
        p.remark                                                          AS biz_rmk,
        p.bag_remark                                                      AS bag_rmk
    FROM demo_dw.ods_mysql_tang_storage_s_package_ri                     p
    LEFT JOIN pkg_item_agg                                      pia ON p.package_no = pia.package_no
    LEFT JOIN dcl_fee_agg                                      dfa ON p.package_no = dfa.package_no
    LEFT JOIN pkg_item_amt_agg                                piaa ON p.package_no = piaa.package_no
    LEFT JOIN pkg_trade_latest                                   tl ON p.package_no = tl.package_no
    LEFT JOIN logis_track_latest                                trk ON p.package_no = trk.package_no
    LEFT JOIN usr_dim                                             u ON p.user_id    = u.usr_id
    LEFT JOIN wh_dim                                             wd ON p.storage_id = wd.wh_id
    LEFT JOIN demo_dw.ods_mysql_tang_storage_s_pack_addr_ri               a ON p.package_no = a.package_no
    LEFT JOIN country_dim                                          cd ON CASE
        WHEN REGEXP_REPLACE(UPPER(REGEXP_REPLACE(TRIM(a.country), '[^A-Za-z0-9]', '')), '^THE', '') = '' THEN TRIM(a.country)
        ELSE REGEXP_REPLACE(UPPER(REGEXP_REPLACE(TRIM(a.country), '[^A-Za-z0-9]', '')), '^THE', '')
    END = cd.match_key
    LEFT JOIN demo_dw.ods_mysql_tang_storage_s_pack_fee_ri                f ON p.package_no = f.package_no
    LEFT JOIN demo_dw.ods_mysql_tang_storage_s_pack_info_ri              pi ON p.package_no = pi.package_no
    LEFT JOIN demo_dw.ods_mysql_tang_storage_s_pack_weight_ri            pw ON p.package_no = pw.package_no
    LEFT JOIN demo_dw.ods_mysql_tang_storage_s_pack_record_ri            pr ON p.package_no = pr.package_no

)

-- -----------------------------------------------------------
-- 写入: 全量覆盖当日分区
-- -----------------------------------------------------------
INSERT OVERWRITE TABLE demo_dw.dwd_wh_pkg_mgr_df PARTITION (ds = '${bizdate}')
SELECT
    pkg_no, usr_id, wh_id, stor_ord_no, trade_no,
    usr_nm, email, wh_nm,
    exprs_no, exprs_nm, line_nm, line_id, snd_area, carrier_id, logistic_id,
    rcv_first_nm, rcv_last_nm, rcv_cntry_cd, rcv_cntry, rcv_cntry_cn, rcv_area, rcv_city, rcv_addr, rcv_zip, rcv_phn,
    pred_wt, actl_wt, diff_wt, item_wt, pkg_actl_wt, pkg_pre_actl_wt, pkg_len, pkg_wid, pkg_hgt, pkg_vol,
    dep_amt, actl_dep_amt, tot_amt, tot_pre_amt, tot_actl_amt, tech_srv_pre_fee, tech_srv_actl_fee,
    ins_amt, ins_srv_fee, vat_amt, diff_amt, succ_diff_amt, cpn_amt, disc_amt,
    pkg_item_amt, dcl_cn_nm_list, dcl_en_nm_list, dcl_item_cnt, dcl_amt,
    item_cnt, exch_rate,
    ccy, lang, pltf_cd,
    pkg_stat, pkg_stat_nm, pay_stat, pay_stat_nm, bag_stat, bag_stat_nm,
    sys_stat, artif_stat, risk_stat, is_frz, dcl_stat, tax_type_cd, tax_type_nm, is_pltf_ioss, logis_stat, cmpstn_stat, is_after_sale, is_rtn,
    is_pend, is_del, is_growth, is_custom_aud, is_vol_wt_on,
    custom_id, risk_cd, risk_lvl, handle_cd, pkg_type_cd, spcl_stat_cd,
    pkg_cond_cd, pkg_usr,
    crt_time, upd_time, pay_time, exp_time, snd_time, back_time, dly_time, cmpstn_time, growth_time,
    biz_rmk, bag_rmk,
    exprs_stat, trk_crt_time, pick_time, clr_time, trk_dly_time, last_trk_time, dly_day_cnt,
    pxy_lbl_no
FROM pkg_full
;
