--MaxCompute SQL
-- 本地归档：20260713 物流轨迹临时分析，仅供历史复现，不作为生产调度节点。
--********************************************************************--
-- 表名:     tmp_wh_logis_trk_point
-- 描述:     临时物流轨迹明细，合并 z1/z2 轨迹并补充包裹线路、承运商、发往国家和最终状态
-- 粒度:     一行 = 一个物流轨迹节点
-- 来源:
--   ods_mysql_tang_logistics_track_point_z1_df
--   ods_mysql_tang_logistics_track_point_z2_df
--   dwd_wh_pkg_mgr_df
-- 分区口径: 各来源表自动读取最新可用分区
-- 生命周期: 7 天
--********************************************************************--

DROP TABLE IF EXISTS demo_dw.tmp_wh_logis_trk_point;

CREATE TABLE demo_dw.tmp_wh_logis_trk_point
(
    `express_no`   STRING    COMMENT '物流号（轨迹 ODS 原字段）',
    `line_nm`      STRING    COMMENT '物流线路名称',
    `exprs_nm`     STRING    COMMENT '承运商名称',
    `rcv_cntry`    STRING    COMMENT '发往国家（英文标准名称）',
    `pkg_stat_nm`  STRING    COMMENT '包裹最终状态名称',
    `position`     STRING    COMMENT '包裹所在地（轨迹 ODS 原字段）',
    `description`  STRING    COMMENT '轨迹描述（轨迹 ODS 原字段）',
    `change_time`  STRING    COMMENT '快递变动时间（轨迹 ODS 原字段）',
    `create_time`  TIMESTAMP COMMENT '轨迹创建时间（轨迹 ODS 原字段）',
    `ds`           STRING    COMMENT '轨迹 ODS 快照分区'
)
COMMENT '临时物流轨迹明细-z1/z2轨迹补充线路、承运商、发往国家和最终状态'
LIFECYCLE 7;

WITH track_union AS
(
    SELECT  express_no,
            position,
            description,
            change_time,
            create_time,
            ds
    FROM    demo_dw.ods_mysql_tang_logistics_track_point_z1_df
    WHERE   ds = MAX_PT('demo_dw.ods_mysql_tang_logistics_track_point_z1_df')

    UNION ALL

    SELECT  express_no,
            position,
            description,
            change_time,
            create_time,
            ds
    FROM    demo_dw.ods_mysql_tang_logistics_track_point_z2_df
    WHERE   ds = MAX_PT('demo_dw.ods_mysql_tang_logistics_track_point_z2_df')
),
pkg_rank AS
(
    SELECT  exprs_no,
            line_nm,
            exprs_nm,
            rcv_cntry,
            pkg_stat_nm,
            ROW_NUMBER() OVER
            (
                PARTITION BY exprs_no
                ORDER BY upd_time DESC, pkg_no DESC
            ) AS rn
    FROM    demo_dw.dwd_wh_pkg_mgr_df
    WHERE   ds = MAX_PT('demo_dw.dwd_wh_pkg_mgr_df')
    AND     exprs_no IS NOT NULL
    AND     TRIM(exprs_no) <> ''
)

INSERT OVERWRITE TABLE demo_dw.tmp_wh_logis_trk_point
SELECT  a.express_no,
        b.line_nm,
        b.exprs_nm,
        b.rcv_cntry,
        b.pkg_stat_nm,
        a.position,
        a.description,
        a.change_time,
        a.create_time,
        a.ds
FROM    track_union a
JOIN    pkg_rank b
ON      a.express_no = b.exprs_no
AND     b.rn = 1;
