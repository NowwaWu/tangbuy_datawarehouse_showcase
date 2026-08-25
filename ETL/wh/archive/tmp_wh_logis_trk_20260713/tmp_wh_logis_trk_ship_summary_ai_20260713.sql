--MaxCompute SQL
-- 本地归档：20260713 物流轨迹临时分析，仅供历史复现，不作为生产调度节点。
-- 一票一行运单汇总：状态仅保留源 pkg_stat_nm，不推断物流终态

DROP TABLE IF EXISTS demo_dw.tmp_wh_logis_trk_ship_summary_ai_20260713;

CREATE TABLE demo_dw.tmp_wh_logis_trk_ship_summary_ai_20260713
(
    express_no                  STRING          COMMENT '物流单号',
    exprs_nm                    STRING          COMMENT '承运商',
    line_nm                     STRING          COMMENT '物流线路',
    rcv_cntry                   STRING          COMMENT '目的国家',
    pkg_stat_nm                 STRING          COMMENT '源包裹状态名称，不作为可靠物流终态',
    node_count                  BIGINT          COMMENT '去重后节点数',
    first_event_time            DATETIME        COMMENT '首个有效轨迹发生时间',
    last_event_time             DATETIME        COMMENT '最后有效轨迹发生时间',
    total_elapsed_hours         DECIMAL(18,2)   COMMENT '首尾有效轨迹跨度小时数',
    first_description_masked    STRING          COMMENT '排序后首节点脱敏描述',
    last_description_masked     STRING          COMMENT '排序后末节点脱敏描述',
    missing_description_count   BIGINT          COMMENT '描述缺失节点数',
    missing_event_time_count    BIGINT          COMMENT '轨迹时间缺失或无效节点数',
    exact_duplicate_count       BIGINT          COMMENT '源表完全重复且被去除的节点数',
    metadata_conflict_flag      BIGINT          COMMENT '承运商/线路/国家/包裹状态冲突标识',
    ds                          STRING          COMMENT '快照日期'
)
COMMENT '物流轨迹AI分析运单汇总-20260713'
LIFECYCLE 30;

WITH
-- 清洗表按票统计节点、时间和缺失情况
with_ship_agg AS
(
    SELECT  express_no,
            MAX(exprs_nm) AS exprs_nm,
            MAX(line_nm) AS line_nm,
            MAX(rcv_cntry) AS rcv_cntry,
            MAX(pkg_stat_nm) AS pkg_stat_nm,
            COUNT(1) AS node_count,
            MIN(event_time) AS first_event_time,
            MAX(event_time) AS last_event_time,
            SUM(IF(description_masked IS NULL OR TRIM(description_masked) = '', 1, 0)) AS missing_description_count,
            SUM(invalid_event_time) AS missing_event_time_count,
            MAX(ds) AS ds
    FROM demo_dw.tmp_wh_logis_trk_point_clean_ai_20260713
    WHERE ds = '20260713'
    GROUP BY express_no
),
-- 使用 event_seq 获取完整排序后的首末描述
with_ship_desc AS
(
    SELECT  a.express_no,
            a.exprs_nm,
            a.line_nm,
            a.rcv_cntry,
            a.pkg_stat_nm,
            a.node_count,
            a.first_event_time,
            a.last_event_time,
            MAX(IF(b.event_seq = 1, b.description_masked, NULL)) AS first_description_masked,
            MAX(IF(b.event_seq = a.node_count, b.description_masked, NULL)) AS last_description_masked,
            a.missing_description_count,
            a.missing_event_time_count,
            a.ds
    FROM with_ship_agg a
    JOIN demo_dw.tmp_wh_logis_trk_point_clean_ai_20260713 b
    ON a.express_no = b.express_no
    AND b.ds = '20260713'
    GROUP BY a.express_no,
             a.exprs_nm,
             a.line_nm,
             a.rcv_cntry,
             a.pkg_stat_nm,
             a.node_count,
             a.first_event_time,
             a.last_event_time,
             a.missing_description_count,
             a.missing_event_time_count,
             a.ds
),
-- 按用户定义的四字段键统计源表中超过首条的完全重复节点
with_dup_group AS
(
    SELECT  express_no,
            change_time,
            position,
            description,
            COUNT(1) AS dup_group_node_count
    FROM demo_dw.tmp_wh_logis_trk_point
    WHERE ds = '20260713'
    GROUP BY express_no, change_time, position, description
    HAVING COUNT(1) > 1
),
with_dup_ship AS
(
    SELECT  express_no,
            SUM(dup_group_node_count - 1) AS exact_duplicate_count
    FROM with_dup_group
    GROUP BY express_no
),
-- 源表元数据冲突只做标记，不擅自选择或修正终态
with_conflict AS
(
    SELECT  express_no,
            IF(
                COUNT(DISTINCT IF(exprs_nm IS NOT NULL AND TRIM(exprs_nm) <> '', exprs_nm, NULL)) > 1
                OR COUNT(DISTINCT IF(line_nm IS NOT NULL AND TRIM(line_nm) <> '', line_nm, NULL)) > 1
                OR COUNT(DISTINCT IF(rcv_cntry IS NOT NULL AND TRIM(rcv_cntry) <> '', rcv_cntry, NULL)) > 1
                OR COUNT(DISTINCT IF(pkg_stat_nm IS NOT NULL AND TRIM(pkg_stat_nm) <> '', pkg_stat_nm, NULL)) > 1,
                1, 0
            ) AS metadata_conflict_flag
    FROM demo_dw.tmp_wh_logis_trk_point
    WHERE ds = '20260713'
    GROUP BY express_no
)

INSERT OVERWRITE TABLE demo_dw.tmp_wh_logis_trk_ship_summary_ai_20260713
SELECT  a.express_no,
        a.exprs_nm,
        a.line_nm,
        a.rcv_cntry,
        a.pkg_stat_nm,
        a.node_count,
        a.first_event_time,
        a.last_event_time,
        IF(
            a.first_event_time IS NOT NULL AND a.last_event_time IS NOT NULL,
            CAST(DATEDIFF(a.last_event_time, a.first_event_time, 'ss') / 3600.0 AS DECIMAL(18,2)),
            NULL
        ) AS total_elapsed_hours,
        a.first_description_masked,
        a.last_description_masked,
        a.missing_description_count,
        a.missing_event_time_count,
        NVL(b.exact_duplicate_count, 0) AS exact_duplicate_count,
        NVL(c.metadata_conflict_flag, 0) AS metadata_conflict_flag,
        a.ds
FROM with_ship_desc a
LEFT JOIN with_dup_ship b
ON a.express_no = b.express_no
LEFT JOIN with_conflict c
ON a.express_no = c.express_no;
