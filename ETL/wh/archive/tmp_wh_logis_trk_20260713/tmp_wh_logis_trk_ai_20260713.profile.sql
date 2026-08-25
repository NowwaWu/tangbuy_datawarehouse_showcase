--MaxCompute SQL
-- 本地归档：20260713 物流轨迹临时分析，仅供历史复现，不作为生产调度节点。
-- 数据画像查询：所有源表查询固定 ds='20260713'，不输出明细原文

-- 总体规模、维度基数和描述基数
SELECT  COUNT(1) AS node_cnt,
        COUNT(DISTINCT express_no) AS tracking_cnt,
        COUNT(DISTINCT IF(exprs_nm IS NOT NULL AND TRIM(exprs_nm) <> '', exprs_nm, NULL)) AS carrier_cnt,
        COUNT(DISTINCT IF(line_nm IS NOT NULL AND TRIM(line_nm) <> '', line_nm, NULL)) AS line_cnt,
        COUNT(DISTINCT IF(rcv_cntry IS NOT NULL AND TRIM(rcv_cntry) <> '', rcv_cntry, NULL)) AS country_cnt,
        COUNT(DISTINCT CONCAT(
            NVL(NULLIF(TRIM(exprs_nm), ''), '[EMPTY]'), CHR(1),
            NVL(NULLIF(TRIM(line_nm), ''), '[EMPTY]'), CHR(1),
            NVL(NULLIF(TRIM(rcv_cntry), ''), '[EMPTY]')
        )) AS carrier_line_country_cnt,
        COUNT(DISTINCT description) AS description_cnt,
        COUNT(DISTINCT CONCAT(NVL(position, '[NULL]'), CHR(1), NVL(description, '[NULL]'))) AS position_description_cnt
FROM demo_dw.tmp_wh_logis_trk_point
WHERE ds = '20260713';

-- 包裹状态分布
SELECT  pkg_stat_nm,
        COUNT(DISTINCT express_no) AS tracking_cnt,
        COUNT(1) AS node_cnt
FROM demo_dw.tmp_wh_logis_trk_point
WHERE ds = '20260713'
GROUP BY pkg_stat_nm
ORDER BY tracking_cnt DESC;

-- 单票节点数分布
WITH
with_ship AS
(
    SELECT  express_no,
            COUNT(1) AS node_cnt
    FROM demo_dw.tmp_wh_logis_trk_point
    WHERE ds = '20260713'
    GROUP BY express_no
)
SELECT  MIN(node_cnt) AS min_node_cnt,
        PERCENTILE_APPROX(node_cnt, 0.50) AS p50_node_cnt,
        PERCENTILE_APPROX(node_cnt, 0.90) AS p90_node_cnt,
        PERCENTILE_APPROX(node_cnt, 0.99) AS p99_node_cnt,
        MAX(node_cnt) AS max_node_cnt
FROM with_ship;

-- 关键字段空值数量与比例
WITH
with_null_cnt AS
(
    SELECT  COUNT(1) AS node_cnt,
            SUM(IF(express_no IS NULL OR TRIM(express_no) = '', 1, 0)) AS express_no_empty_cnt,
            SUM(IF(exprs_nm IS NULL OR TRIM(exprs_nm) = '', 1, 0)) AS exprs_nm_empty_cnt,
            SUM(IF(line_nm IS NULL OR TRIM(line_nm) = '', 1, 0)) AS line_nm_empty_cnt,
            SUM(IF(rcv_cntry IS NULL OR TRIM(rcv_cntry) = '', 1, 0)) AS rcv_cntry_empty_cnt,
            SUM(IF(description IS NULL OR TRIM(description) = '', 1, 0)) AS description_empty_cnt,
            SUM(IF(change_time IS NULL OR TRIM(change_time) = '', 1, 0)) AS change_time_empty_cnt
    FROM demo_dw.tmp_wh_logis_trk_point
    WHERE ds = '20260713'
)
SELECT  node_cnt,
        express_no_empty_cnt,
        CAST(express_no_empty_cnt * 100.0 / node_cnt AS DECIMAL(18,4)) AS express_no_empty_pct,
        exprs_nm_empty_cnt,
        CAST(exprs_nm_empty_cnt * 100.0 / node_cnt AS DECIMAL(18,4)) AS exprs_nm_empty_pct,
        line_nm_empty_cnt,
        CAST(line_nm_empty_cnt * 100.0 / node_cnt AS DECIMAL(18,4)) AS line_nm_empty_pct,
        rcv_cntry_empty_cnt,
        CAST(rcv_cntry_empty_cnt * 100.0 / node_cnt AS DECIMAL(18,4)) AS rcv_cntry_empty_pct,
        description_empty_cnt,
        CAST(description_empty_cnt * 100.0 / node_cnt AS DECIMAL(18,4)) AS description_empty_pct,
        change_time_empty_cnt,
        CAST(change_time_empty_cnt * 100.0 / node_cnt AS DECIMAL(18,4)) AS change_time_empty_pct
FROM with_null_cnt;

-- 完全重复节点：exact_duplicate_cnt 表示超过首条的重复行数
WITH
with_dup AS
(
    SELECT  express_no,
            change_time,
            position,
            description,
            COUNT(1) AS dup_group_node_cnt
    FROM demo_dw.tmp_wh_logis_trk_point
    WHERE ds = '20260713'
    GROUP BY express_no, change_time, position, description
    HAVING COUNT(1) > 1
)
SELECT  COUNT(1) AS duplicate_group_cnt,
        SUM(dup_group_node_cnt - 1) AS exact_duplicate_cnt,
        SUM(dup_group_node_cnt) AS nodes_in_duplicate_groups
FROM with_dup;

-- 同一物流号的包裹元数据冲突
WITH
with_conflict AS
(
    SELECT  express_no,
            COUNT(DISTINCT IF(exprs_nm IS NOT NULL AND TRIM(exprs_nm) <> '', exprs_nm, NULL)) AS carrier_value_cnt,
            COUNT(DISTINCT IF(line_nm IS NOT NULL AND TRIM(line_nm) <> '', line_nm, NULL)) AS line_value_cnt,
            COUNT(DISTINCT IF(rcv_cntry IS NOT NULL AND TRIM(rcv_cntry) <> '', rcv_cntry, NULL)) AS country_value_cnt,
            COUNT(DISTINCT IF(pkg_stat_nm IS NOT NULL AND TRIM(pkg_stat_nm) <> '', pkg_stat_nm, NULL)) AS pkg_stat_value_cnt
    FROM demo_dw.tmp_wh_logis_trk_point
    WHERE ds = '20260713'
    GROUP BY express_no
)
SELECT  SUM(IF(carrier_value_cnt > 1, 1, 0)) AS carrier_conflict_tracking_cnt,
        SUM(IF(line_value_cnt > 1, 1, 0)) AS line_conflict_tracking_cnt,
        SUM(IF(country_value_cnt > 1, 1, 0)) AS country_conflict_tracking_cnt,
        SUM(IF(pkg_stat_value_cnt > 1, 1, 0)) AS pkg_stat_conflict_tracking_cnt,
        SUM(IF(carrier_value_cnt > 1 OR line_value_cnt > 1 OR country_value_cnt > 1 OR pkg_stat_value_cnt > 1, 1, 0)) AS any_conflict_tracking_cnt
FROM with_conflict;

-- 时间转换有效性
SELECT  SUM(IF(
            change_time IS NULL
            OR TRIM(change_time) = ''
            OR NOT ISDATE(TRIM(change_time), 'yyyy-mm-dd hh:mi:ss'),
            1, 0
        )) AS invalid_event_time_cnt,
        SUM(IF(
            change_time IS NOT NULL
            AND TRIM(change_time) <> ''
            AND ISDATE(TRIM(change_time), 'yyyy-mm-dd hh:mi:ss'),
            1, 0
        )) AS valid_event_time_cnt
FROM demo_dw.tmp_wh_logis_trk_point
WHERE ds = '20260713';

-- 受执行边界约束，仅核对指定快照；物理分区属性由 MaxCompute 元数据单独确认
SELECT  ds,
        COUNT(1) AS node_cnt,
        COUNT(DISTINCT express_no) AS tracking_cnt
FROM demo_dw.tmp_wh_logis_trk_point
WHERE ds = '20260713'
GROUP BY ds;
