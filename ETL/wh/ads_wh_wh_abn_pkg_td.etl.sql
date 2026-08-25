--MaxCompute SQL
--********************************************************************--
-- 数据集市: wh (仓储履约集市)
-- 应用主题: wh (履约分析)
-- 表名:     ads_wh_wh_abn_pkg_td
-- 表类型:   应用数据表 (ADS Application) - 当前未处理且未收到货包裹日快照(_td, 每日重算)
-- 描述:     输出包裹创建时间在当前日期前2个月以内，且仍未收到货、未跟进/处理的正常包裹。
-- 粒度:     一行 = 一个当前未处理且未收到货包裹(pkg_no)
-- 来源:
--   dws_trd_ord_line_td                         (来源快照分区, 包裹/订单行/履约节点)
--   dws_wh_pkg_mgr_td                           (来源快照分区, 包裹创建时间)
--   ods_mysql_tang_logistics_track_point_z1_df  (来源快照分区, 第一物流商轨迹节点)
--   ods_mysql_tang_logistics_track_point_z2_df  (来源快照分区, 第二物流商轨迹节点)
--   ods_wh_logis_abn_flw_df                      (来源快照分区, 已跟进/处理异常物流单号及包裹单号)
-- 过滤:
--   仅保留正常包裹 pkg_bag_stat=0；
--   仅保留包裹创建时间大于等于 CURRENT_DATE() 往前2个月的包裹；
--   排除已确认收货包裹 pkg_stat=20；
--   排除取消/退款/退包/异常GMV状态 is_gmv_abn=0；
--   排除 ods_wh_logis_abn_flw_df 中已有的已跟进/处理物流单号或包裹单号；
--   入库待发货/发货待收货天数按 CURRENT_DATE() 计算，不使用 ${bizdate} 作为计算截止日；
--   ${bizdate} 为统计日期，来源快照分区取 ${bizdate}-1。
-- 调度变量: ${bizdate} 格式 yyyyMMdd
--********************************************************************--

WITH
-- 限制包裹创建时间在当前日期前2个月以内，按包裹号去重避免关联放大
with_recent_pkg AS
(
    SELECT  pkg_no
    FROM    demo_dw.dws_wh_pkg_mgr_td
    WHERE   ds = '${bizdate}'
    AND     pkg_no IS NOT NULL
    AND     TRIM(pkg_no) <> ''
    AND     crt_time >= DATEADD(CAST(CURRENT_DATE() AS DATETIME), -2, 'mm')
    GROUP BY pkg_no
),
-- 按包裹聚合订单行，避免同一包裹多子单重复输出
with_pkg_agg AS
(
    SELECT  '${bizdate}' AS stat_date
            ,TO_CHAR(DATEADD(TO_DATE('${bizdate}', 'yyyymmdd'), -1, 'dd'), 'yyyymmdd') AS data_ds
            ,a.pkg_no
            ,MAX(a.usr_id) AS usr_id
            ,MAX(a.usr_nm) AS usr_nm
            ,MAX(a.email) AS email
            ,MAX(a.wh_id) AS wh_id
            ,MAX(a.wh_nm) AS wh_nm
            ,MAX(a.pkg_stat) AS pkg_stat
            ,MAX(a.pkg_stat_nm) AS pkg_stat_nm
            ,MAX(a.pkg_pay_stat) AS pkg_pay_stat
            ,MAX(a.pkg_pay_stat_nm) AS pkg_pay_stat_nm
            ,MAX(a.pkg_bag_stat) AS pkg_bag_stat
            ,MAX(a.pkg_bag_stat_nm) AS pkg_bag_stat_nm
            ,MAX(a.pkg_exprs_no) AS pkg_exprs_no
            ,MAX(a.pkg_exprs_nm) AS pkg_exprs_nm
            ,MAX(a.pkg_line_nm) AS pkg_line_nm
            ,MAX(a.pkg_line_id) AS pkg_line_id
            ,MAX(a.pkg_rcv_cntry) AS pkg_rcv_cntry
            ,MAX(a.pkg_rcv_area) AS pkg_rcv_area
            ,MAX(a.pkg_rcv_city) AS pkg_rcv_city
            ,MAX(a.is_gmv_abn) AS is_gmv_abn
            ,COUNT(DISTINCT a.ord_line_no) AS ord_line_cnt
            ,CONCAT_WS(
                '；'
                ,SORT_ARRAY(
                    COLLECT_SET(
                        CONCAT(
                            IF(a.ord_line_no IS NULL OR TRIM(a.ord_line_no) = '', '未知TI号', TRIM(a.ord_line_no))
                            ,' | '
                            ,IF(a.ord_line_stat_nm IS NULL OR TRIM(a.ord_line_stat_nm) = '', '未知', TRIM(a.ord_line_stat_nm))
                        )
                    )
                )
             ) AS ord_line_stat_dtl
            ,MAX(a.wh_stock_in_time) AS last_wh_stock_in_time
            ,MAX(a.pkg_snd_time) AS pkg_snd_time
            ,MAX(a.rcv_time) AS rcv_time
    FROM    demo_dw.dws_trd_ord_line_td a
    JOIN    with_recent_pkg b
    ON      a.pkg_no = b.pkg_no
    WHERE   a.ds = '${bizdate}'
    AND     a.pkg_no IS NOT NULL
    AND     TRIM(a.pkg_no) <> ''
    AND     a.pkg_no <> '-99'
    GROUP BY a.pkg_no
),
-- 计算当前未闭环节点的等待天数，过滤取消/退款/退包等不需要监控的状态
with_pkg_calc AS
(
    SELECT  stat_date
            ,data_ds
            ,pkg_no
            ,NVL(usr_id, -99) AS usr_id
            ,NVL(usr_nm, '未知') AS usr_nm
            ,NVL(email, '未知') AS email
            ,NVL(wh_id, -99) AS wh_id
            ,NVL(wh_nm, '未知') AS wh_nm
            ,NVL(pkg_stat, -1) AS pkg_stat
            ,NVL(pkg_stat_nm, '未知') AS pkg_stat_nm
            ,NVL(pkg_pay_stat, -1) AS pkg_pay_stat
            ,NVL(pkg_pay_stat_nm, '未知') AS pkg_pay_stat_nm
            ,NVL(pkg_bag_stat, -1) AS pkg_bag_stat
            ,NVL(pkg_bag_stat_nm, '未知') AS pkg_bag_stat_nm
            ,NVL(pkg_exprs_no, '未知') AS pkg_exprs_no
            ,NVL(pkg_exprs_nm, '未知') AS pkg_exprs_nm
            ,NVL(pkg_line_nm, '未知') AS pkg_line_nm
            ,NVL(pkg_line_id, '-99') AS pkg_line_id
            ,NVL(pkg_rcv_cntry, '未知') AS pkg_rcv_cntry
            ,NVL(pkg_rcv_area, '未知') AS pkg_rcv_area
            ,NVL(pkg_rcv_city, '未知') AS pkg_rcv_city
            ,NVL(ord_line_cnt, 0) AS ord_line_cnt
            ,NVL(ord_line_stat_dtl, '未知') AS ord_line_stat_dtl
            ,last_wh_stock_in_time
            ,pkg_snd_time
            ,rcv_time
            ,IF(last_wh_stock_in_time IS NOT NULL AND pkg_snd_time IS NULL, CAST(GREATEST(DATEDIFF(CAST(CURRENT_DATE() AS DATETIME), last_wh_stock_in_time, 'ss') / 86400.0, 0) AS DECIMAL(18,2)), NULL) AS wh_stock_in_pend_snd_days
            ,IF(pkg_snd_time IS NOT NULL AND rcv_time IS NULL, CAST(GREATEST(DATEDIFF(CAST(CURRENT_DATE() AS DATETIME), pkg_snd_time, 'ss') / 86400.0, 0) AS DECIMAL(18,2)), NULL) AS snd_pend_rcv_days
    FROM    with_pkg_agg
    WHERE   pkg_bag_stat = 0
    AND     (pkg_stat IS NULL OR pkg_stat <> 20)
    AND     is_gmv_abn = 0
),
-- 监控所有当前未收到货的包裹，并标记是否已发货
with_abn_pkg AS
(
    SELECT  stat_date
            ,data_ds
            ,pkg_no
            ,IF(pkg_snd_time IS NOT NULL, 'NOT_RCV', 'NOT_SND') AS abn_type_cd
            ,IF(pkg_snd_time IS NOT NULL, '未收到货', '未发货') AS abn_type_nm
            ,IF(pkg_snd_time IS NOT NULL, 1, 0) AS is_snd
            ,wh_stock_in_pend_snd_days
            ,snd_pend_rcv_days
            ,usr_id
            ,usr_nm
            ,email
            ,wh_id
            ,wh_nm
            ,pkg_stat
            ,pkg_stat_nm
            ,pkg_pay_stat
            ,pkg_pay_stat_nm
            ,pkg_bag_stat
            ,pkg_bag_stat_nm
            ,pkg_exprs_no
            ,pkg_exprs_nm
            ,pkg_line_nm
            ,pkg_line_id
            ,pkg_rcv_cntry
            ,pkg_rcv_area
            ,pkg_rcv_city
            ,ord_line_cnt
            ,ord_line_stat_dtl
            ,last_wh_stock_in_time
            ,pkg_snd_time
            ,rcv_time
    FROM    with_pkg_calc
    WHERE   rcv_time IS NULL
),
-- 合并第一/第二物流商轨迹节点，避免只读z2导致漏轨迹
with_track_union AS
(
    SELECT  express_no
            ,position
            ,description
            ,change_time
    FROM    demo_dw.ods_mysql_tang_logistics_track_point_z1_df
    WHERE   ds = '${bizdate}'
    UNION ALL
    SELECT  express_no
            ,position
            ,description
            ,change_time
    FROM    demo_dw.ods_mysql_tang_logistics_track_point_z2_df
    WHERE   ds = '${bizdate}'
),
-- 只取异常包裹涉及的运单轨迹，避免全表无关聚合
with_track_src AS
(
    SELECT  b.express_no
            ,CAST(b.change_time AS DATETIME) AS trk_time
            ,NVL(b.position, '未知') AS trk_pos
            ,NVL(b.description, '未知') AS trk_desc
            ,CONCAT(
                NVL(b.change_time, '未知')
                ,' | '
                ,NVL(b.position, '未知')
                ,' | '
                ,NVL(b.description, '未知')
             ) AS trk_item
    FROM    with_abn_pkg a
    JOIN    with_track_union b
    ON      a.pkg_exprs_no = b.express_no
    WHERE   a.pkg_exprs_no IS NOT NULL
    AND     TRIM(a.pkg_exprs_no) <> ''
    AND     a.pkg_exprs_no NOT IN ('未知', '-99')
),
-- change_time 为 yyyy-mm-dd hh:mi:ss 字符串，拼在轨迹项前缀后排序等价于按时间升序排序
with_track_agg AS
(
    SELECT  express_no
            ,COUNT(1) AS trk_cnt
            ,CONCAT_WS('；', SORT_ARRAY(COLLECT_LIST(trk_item))) AS trk_dtl
    FROM    with_track_src
    GROUP BY express_no
),
-- 每个运单取最新一条轨迹，便于运营快速判断当前位置
with_track_rank AS
(
    SELECT  express_no
            ,trk_time
            ,trk_pos
            ,trk_desc
            ,ROW_NUMBER() OVER (PARTITION BY express_no ORDER BY trk_time DESC, trk_desc DESC) AS rn
    FROM    with_track_src
),
with_track_latest AS
(
    SELECT  express_no
            ,trk_time AS last_trk_time
            ,trk_pos AS last_trk_pos
            ,trk_desc AS last_trk_desc
    FROM    with_track_rank
    WHERE   rn = 1
),
-- 已跟进/处理的异常物流单号，去重避免关联放大异常包裹结果
with_abn_flw_trk AS
(
    SELECT  trk_no
    FROM    demo_dw.ods_wh_logis_abn_flw_df
    WHERE   ds IS NOT NULL
    AND     trk_no IS NOT NULL
    AND     TRIM(trk_no) <> ''
    GROUP BY trk_no
),
-- 已跟进/处理的异常包裹单号，用于排除尚未产生物流单号的已处理包裹
with_abn_flw_pkg AS
(
    SELECT  pkg_no
    FROM    demo_dw.ods_wh_logis_abn_flw_df
    WHERE   ds IS NOT NULL
    AND     pkg_no IS NOT NULL
    AND     TRIM(pkg_no) <> ''
    GROUP BY pkg_no
)

INSERT OVERWRITE TABLE demo_dw.ads_wh_wh_abn_pkg_td PARTITION(ds='${bizdate}')
SELECT  a.stat_date
        ,a.data_ds
        ,a.pkg_no
        ,a.abn_type_cd
        ,a.abn_type_nm
        ,a.is_snd
        ,NVL(a.wh_stock_in_pend_snd_days, 0) AS wh_stock_in_pend_snd_days
        ,NVL(a.snd_pend_rcv_days, 0) AS snd_pend_rcv_days
        ,a.usr_id
        ,a.usr_nm
        ,a.email
        ,a.wh_id
        ,a.wh_nm
        ,a.pkg_stat
        ,a.pkg_stat_nm
        ,a.pkg_pay_stat
        ,a.pkg_pay_stat_nm
        ,a.pkg_bag_stat
        ,a.pkg_bag_stat_nm
        ,a.pkg_exprs_no
        ,a.pkg_exprs_nm
        ,a.pkg_line_nm
        ,a.pkg_line_id
        ,a.pkg_rcv_cntry
        ,a.pkg_rcv_area
        ,a.pkg_rcv_city
        ,a.ord_line_cnt
        ,a.last_wh_stock_in_time
        ,a.pkg_snd_time
        ,a.rcv_time
        ,NVL(b.trk_cnt, 0) AS trk_cnt
        ,c.last_trk_time
        ,NVL(c.last_trk_pos, '未知') AS last_trk_pos
        ,NVL(c.last_trk_desc, '未知') AS last_trk_desc
        ,NVL(b.trk_dtl, '未知') AS trk_dtl
        ,0 AS is_flw
        ,'' AS abn_rsn
        ,NVL(a.ord_line_stat_dtl, '未知') AS ord_line_stat_dtl
FROM    with_abn_pkg a
LEFT JOIN with_track_agg b
ON      a.pkg_exprs_no = b.express_no
LEFT JOIN with_track_latest c
ON      a.pkg_exprs_no = c.express_no
LEFT JOIN with_abn_flw_trk d
ON      a.pkg_exprs_no = d.trk_no
LEFT JOIN with_abn_flw_pkg e
ON      a.pkg_no = e.pkg_no
WHERE   d.trk_no IS NULL
AND     e.pkg_no IS NULL
;
