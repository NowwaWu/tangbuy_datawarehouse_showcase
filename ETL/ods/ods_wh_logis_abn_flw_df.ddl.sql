CREATE TABLE demo_dw.`ods_wh_logis_abn_flw_df` (
  `trk_no` STRING COMMENT '已跟进/处理的物流单号，未产生物流单号时可为空',
  `pkg_no` STRING COMMENT '已跟进/处理的包裹单号'
)
COMMENT 'ODS-仓储履约-异常包裹已跟进处理标识日全量快照'
PARTITIONED BY (
  `ds` STRING NOT NULL COMMENT '分区日期 yyyyMMdd'
)
STORED AS AliOrc
LIFECYCLE 366;
