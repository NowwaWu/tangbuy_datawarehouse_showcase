--MaxCompute SQL
-- 本地归档：20260713 物流轨迹临时分析，仅供历史复现，不作为生产调度节点。
-- 交付校验：所有查询固定 ds='20260713'

-- 五张临时表行数
SELECT 'clean' AS table_role, COUNT(1) AS row_cnt
FROM demo_dw.tmp_wh_logis_trk_point_clean_ai_20260713
WHERE ds = '20260713'
UNION ALL
SELECT 'ship_summary' AS table_role, COUNT(1) AS row_cnt
FROM demo_dw.tmp_wh_logis_trk_ship_summary_ai_20260713
WHERE ds = '20260713'
UNION ALL
SELECT 'route_profile' AS table_role, COUNT(1) AS row_cnt
FROM demo_dw.tmp_wh_logis_route_profile_ai_20260713
WHERE ds = '20260713'
UNION ALL
SELECT 'description_dict' AS table_role, COUNT(1) AS row_cnt
FROM demo_dw.tmp_wh_logis_trk_desc_dict_ai_20260713
WHERE ds = '20260713'
UNION ALL
SELECT 'shipment_sample' AS table_role, COUNT(1) AS row_cnt
FROM demo_dw.tmp_wh_logis_trk_sample_ai_20260713
WHERE ds = '20260713';

-- 运单汇总与源画像对账
SELECT  COUNT(1) AS tracking_cnt,
        SUM(node_count) AS clean_node_cnt,
        SUM(missing_description_count) AS missing_description_cnt,
        SUM(missing_event_time_count) AS missing_event_time_cnt,
        SUM(exact_duplicate_count) AS exact_duplicate_cnt,
        SUM(metadata_conflict_flag) AS metadata_conflict_tracking_cnt,
        SUM(IF(pkg_stat_nm = '确认收货', 1, 0)) AS confirmed_received_cnt,
        SUM(IF(pkg_stat_nm = '已发货', 1, 0)) AS shipped_cnt
FROM demo_dw.tmp_wh_logis_trk_ship_summary_ai_20260713
WHERE ds = '20260713';

-- sample_level 独立分层分布
SELECT  sample_level,
        COUNT(1) AS combo_cnt,
        SUM(tracking_count) AS tracking_cnt,
        SUM(node_count) AS node_cnt
FROM demo_dw.tmp_wh_logis_route_profile_ai_20260713
WHERE ds = '20260713'
GROUP BY sample_level
ORDER BY sample_level;

-- 抽样表整票连续性
WITH
with_sample_seq AS
(
    SELECT  express_no,
            COUNT(1) AS node_cnt,
            MIN(event_seq) AS min_event_seq,
            MAX(event_seq) AS max_event_seq,
            COUNT(DISTINCT event_seq) AS distinct_event_seq_cnt
    FROM demo_dw.tmp_wh_logis_trk_sample_ai_20260713
    WHERE ds = '20260713'
    GROUP BY express_no
)
SELECT  COUNT(1) AS sampled_tracking_cnt,
        SUM(IF(
            min_event_seq <> 1
            OR max_event_seq <> node_cnt
            OR distinct_event_seq_cnt <> node_cnt,
            1, 0
        )) AS discontinuous_tracking_cnt
FROM with_sample_seq;

-- 清洗表中复查可识别联系方式残留
SELECT  SUM(IF(REGEXP_INSTR(description_masked, '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}') > 0, 1, 0)) AS residual_email_node_cnt,
        SUM(IF(REGEXP_INSTR(description_masked, '\\+[0-9][0-9() .-]{6,}[0-9]') > 0, 1, 0)) AS residual_intl_phone_node_cnt,
        SUM(IF(REGEXP_INSTR(description_masked, '([0-9][ .()-]?){9,14}[0-9]') > 0, 1, 0)) AS residual_long_phone_node_cnt
FROM demo_dw.tmp_wh_logis_trk_point_clean_ai_20260713
WHERE ds = '20260713';
