--MaxCompute SQL
-- 本地归档：20260713 物流轨迹临时分析，仅供历史复现，不作为生产调度节点。
-- 脱敏轨迹描述词典：不做物流节点语义分类

DROP TABLE IF EXISTS demo_dw.tmp_wh_logis_trk_desc_dict_ai_20260713;

CREATE TABLE demo_dw.tmp_wh_logis_trk_desc_dict_ai_20260713
(
    description_masked  STRING      COMMENT '脱敏后的轨迹描述',
    node_count          BIGINT      COMMENT '节点数',
    tracking_count      BIGINT      COMMENT '运单数',
    carrier_count       BIGINT      COMMENT '承运商数',
    line_count          BIGINT      COMMENT '线路数',
    country_count       BIGINT      COMMENT '国家数',
    first_seen_time     DATETIME    COMMENT '首次有效出现时间',
    last_seen_time      DATETIME    COMMENT '最后有效出现时间',
    sample_position     STRING      COMMENT '示例轨迹地点',
    sample_exprs_nm     STRING      COMMENT '示例承运商',
    sample_line_nm      STRING      COMMENT '示例线路',
    sample_rcv_cntry    STRING      COMMENT '示例目的国家',
    ds                  STRING      COMMENT '快照日期'
)
COMMENT '物流轨迹AI分析脱敏描述词典-20260713'
LIFECYCLE 30;

INSERT OVERWRITE TABLE demo_dw.tmp_wh_logis_trk_desc_dict_ai_20260713
SELECT  description_masked,
        COUNT(1) AS node_count,
        COUNT(DISTINCT express_no) AS tracking_count,
        COUNT(DISTINCT IF(exprs_nm IS NOT NULL AND TRIM(exprs_nm) <> '', exprs_nm, NULL)) AS carrier_count,
        COUNT(DISTINCT IF(line_nm IS NOT NULL AND TRIM(line_nm) <> '', line_nm, NULL)) AS line_count,
        COUNT(DISTINCT IF(rcv_cntry IS NOT NULL AND TRIM(rcv_cntry) <> '', rcv_cntry, NULL)) AS country_count,
        MIN(event_time) AS first_seen_time,
        MAX(event_time) AS last_seen_time,
        MAX(position) AS sample_position,
        MAX(exprs_nm) AS sample_exprs_nm,
        MAX(line_nm) AS sample_line_nm,
        MAX(rcv_cntry) AS sample_rcv_cntry,
        MAX(ds) AS ds
FROM demo_dw.tmp_wh_logis_trk_point_clean_ai_20260713
WHERE ds = '20260713'
GROUP BY description_masked;
