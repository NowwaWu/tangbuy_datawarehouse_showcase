--MaxCompute SQL
-- 本地归档：20260713 物流轨迹临时分析，仅供历史复现，不作为生产调度节点。
-- 承运商+线路+国家覆盖画像

DROP TABLE IF EXISTS demo_dw.tmp_wh_logis_route_profile_ai_20260713;

CREATE TABLE demo_dw.tmp_wh_logis_route_profile_ai_20260713
(
    exprs_nm                    STRING          COMMENT '承运商',
    line_nm                     STRING          COMMENT '物流线路',
    rcv_cntry                   STRING          COMMENT '目的国家',
    tracking_count              BIGINT          COMMENT '运单数',
    node_count                  BIGINT          COMMENT '去重后节点数',
    confirmed_received_count    BIGINT          COMMENT '源包裹状态为确认收货的运单数',
    shipped_count               BIGINT          COMMENT '源包裹状态为已发货的运单数',
    first_event_time            DATETIME        COMMENT '组合内首个有效轨迹时间',
    last_event_time             DATETIME        COMMENT '组合内最后有效轨迹时间',
    nodes_per_shipment_p50      DECIMAL(18,2)   COMMENT '单票节点数P50',
    nodes_per_shipment_p90      DECIMAL(18,2)   COMMENT '单票节点数P90',
    total_elapsed_hours_p50     DECIMAL(18,2)   COMMENT '单票首尾轨迹跨度小时数P50',
    total_elapsed_hours_p80     DECIMAL(18,2)   COMMENT '单票首尾轨迹跨度小时数P80',
    total_elapsed_hours_p95     DECIMAL(18,2)   COMMENT '单票首尾轨迹跨度小时数P95',
    missing_description_count   BIGINT          COMMENT '描述缺失节点数',
    missing_event_time_count    BIGINT          COMMENT '轨迹时间缺失或无效节点数',
    sample_level                STRING          COMMENT '样本等级：HIGH/MEDIUM/LOW/SPARSE',
    ds                          STRING          COMMENT '快照日期'
)
COMMENT '物流轨迹AI分析线路国家覆盖画像-20260713'
LIFECYCLE 30;

WITH
with_route_agg AS
(
    SELECT  exprs_nm,
            line_nm,
            rcv_cntry,
            COUNT(1) AS tracking_count,
            SUM(node_count) AS node_count,
            SUM(IF(pkg_stat_nm = '确认收货', 1, 0)) AS confirmed_received_count,
            SUM(IF(pkg_stat_nm = '已发货', 1, 0)) AS shipped_count,
            MIN(first_event_time) AS first_event_time,
            MAX(last_event_time) AS last_event_time,
            CAST(PERCENTILE_APPROX(CAST(node_count AS DOUBLE), 0.50) AS DECIMAL(18,2)) AS nodes_per_shipment_p50,
            CAST(PERCENTILE_APPROX(CAST(node_count AS DOUBLE), 0.90) AS DECIMAL(18,2)) AS nodes_per_shipment_p90,
            CAST(PERCENTILE_APPROX(CAST(total_elapsed_hours AS DOUBLE), 0.50) AS DECIMAL(18,2)) AS total_elapsed_hours_p50,
            CAST(PERCENTILE_APPROX(CAST(total_elapsed_hours AS DOUBLE), 0.80) AS DECIMAL(18,2)) AS total_elapsed_hours_p80,
            CAST(PERCENTILE_APPROX(CAST(total_elapsed_hours AS DOUBLE), 0.95) AS DECIMAL(18,2)) AS total_elapsed_hours_p95,
            SUM(missing_description_count) AS missing_description_count,
            SUM(missing_event_time_count) AS missing_event_time_count,
            MAX(ds) AS ds
    FROM demo_dw.tmp_wh_logis_trk_ship_summary_ai_20260713
    WHERE ds = '20260713'
    GROUP BY exprs_nm, line_nm, rcv_cntry
)

INSERT OVERWRITE TABLE demo_dw.tmp_wh_logis_route_profile_ai_20260713
SELECT  exprs_nm,
        line_nm,
        rcv_cntry,
        tracking_count,
        node_count,
        confirmed_received_count,
        shipped_count,
        first_event_time,
        last_event_time,
        nodes_per_shipment_p50,
        nodes_per_shipment_p90,
        total_elapsed_hours_p50,
        total_elapsed_hours_p80,
        total_elapsed_hours_p95,
        missing_description_count,
        missing_event_time_count,
        CASE
            WHEN tracking_count >= 100 THEN 'HIGH'
            WHEN tracking_count >= 30 THEN 'MEDIUM'
            WHEN tracking_count >= 10 THEN 'LOW'
            ELSE 'SPARSE'
        END AS sample_level,
        ds
FROM with_route_agg;
