--MaxCompute SQL
-- 本地归档：20260713 物流轨迹临时分析，仅供历史复现，不作为生产调度节点。
-- 按 express_no 抽取整票完整轨迹，LOW/SPARSE 各取样本量最高的3个代表组合

DROP TABLE IF EXISTS demo_dw.tmp_wh_logis_trk_sample_ai_20260713;

CREATE TABLE demo_dw.tmp_wh_logis_trk_sample_ai_20260713
(
    sample_level        STRING          COMMENT '线路国家组合样本等级',
    express_no          STRING          COMMENT '物流单号',
    exprs_nm            STRING          COMMENT '承运商',
    line_nm             STRING          COMMENT '物流线路',
    rcv_cntry           STRING          COMMENT '目的国家',
    pkg_stat_nm         STRING          COMMENT '源包裹状态名称，不作为可靠物流终态',
    event_seq           BIGINT          COMMENT '单票轨迹节点顺序',
    event_time          DATETIME        COMMENT '轨迹发生时间',
    create_time         TIMESTAMP       COMMENT '轨迹创建时间',
    position            STRING          COMMENT '轨迹地点',
    description_masked  STRING          COMMENT '脱敏后的轨迹描述',
    gap_hours           DECIMAL(18,2)   COMMENT '与上一节点间隔小时数',
    ds                  STRING          COMMENT '快照日期'
)
COMMENT '物流轨迹AI分析整票抽样-20260713'
LIFECYCLE 30;

WITH
-- LOW/SPARSE 代表组合按运单量排序，HIGH/MEDIUM 保留全部组合
with_route_rank AS
(
    SELECT  exprs_nm,
            line_nm,
            rcv_cntry,
            tracking_count,
            sample_level,
            ROW_NUMBER() OVER
            (
                PARTITION BY sample_level
                ORDER BY tracking_count DESC, exprs_nm, line_nm, rcv_cntry
            ) AS combo_rank
    FROM demo_dw.tmp_wh_logis_route_profile_ai_20260713
    WHERE ds = '20260713'
),
-- 每个组合、每种指定状态内稳定排序运单
with_ship_rank AS
(
    SELECT  a.express_no,
            a.exprs_nm,
            a.line_nm,
            a.rcv_cntry,
            a.pkg_stat_nm,
            b.sample_level,
            b.combo_rank,
            ROW_NUMBER() OVER
            (
                PARTITION BY a.exprs_nm, a.line_nm, a.rcv_cntry, a.pkg_stat_nm
                ORDER BY a.express_no
            ) AS ship_rank
    FROM demo_dw.tmp_wh_logis_trk_ship_summary_ai_20260713 a
    JOIN with_route_rank b
    ON NVL(a.exprs_nm, '[NULL]') = NVL(b.exprs_nm, '[NULL]')
    AND NVL(a.line_nm, '[NULL]') = NVL(b.line_nm, '[NULL]')
    AND NVL(a.rcv_cntry, '[NULL]') = NVL(b.rcv_cntry, '[NULL]')
    WHERE a.ds = '20260713'
    AND a.pkg_stat_nm IN ('确认收货', '已发货')
),
-- HIGH: 3/2票，MEDIUM: 2/1票，LOW/SPARSE: 前3组合每状态各1票
with_selected_ship AS
(
    SELECT  sample_level,
            express_no
    FROM with_ship_rank
    WHERE (sample_level = 'HIGH' AND pkg_stat_nm = '确认收货' AND ship_rank <= 3)
       OR (sample_level = 'HIGH' AND pkg_stat_nm = '已发货' AND ship_rank <= 2)
       OR (sample_level = 'MEDIUM' AND pkg_stat_nm = '确认收货' AND ship_rank <= 2)
       OR (sample_level = 'MEDIUM' AND pkg_stat_nm = '已发货' AND ship_rank <= 1)
       OR (sample_level IN ('LOW', 'SPARSE') AND combo_rank <= 3 AND ship_rank <= 1)
)

INSERT OVERWRITE TABLE demo_dw.tmp_wh_logis_trk_sample_ai_20260713
SELECT  a.sample_level,
        b.express_no,
        b.exprs_nm,
        b.line_nm,
        b.rcv_cntry,
        b.pkg_stat_nm,
        b.event_seq,
        b.event_time,
        b.create_time,
        b.position,
        b.description_masked,
        b.gap_hours,
        b.ds
FROM with_selected_ship a
JOIN demo_dw.tmp_wh_logis_trk_point_clean_ai_20260713 b
ON a.express_no = b.express_no
AND b.ds = '20260713';
