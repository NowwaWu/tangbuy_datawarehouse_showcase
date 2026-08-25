CREATE TABLE demo_dw.`ods_google_firebase_events_di` (
  `event_date` STRING COMMENT '事件日期(yyyyMMdd)',
  `event_timestamp` BIGINT COMMENT '事件时间戳(微秒)',
  `event_name` STRING COMMENT '事件名称(如 screen_view/purchase)',
  `user_pseudo_id` STRING COMMENT '用户伪ID(设备级匿名标识)',
  `user_id` STRING COMMENT '用户ID(登录后)',
  `platform` STRING COMMENT '平台(ANDROID/IOS/WEB)',
  `stream_id` BIGINT COMMENT '数据流ID',
  `event_value_in_usd` DOUBLE COMMENT '事件价值(USD)',
  `event_params_json` STRING COMMENT '事件参数(ARRAY<STRUCT>)JSON',
  `user_properties_json` STRING COMMENT '用户属性(ARRAY<STRUCT>)JSON',
  `user_ltv_json` STRING COMMENT '用户LTV(STRUCT)JSON',
  `device_json` STRING COMMENT '设备信息(STRUCT)JSON',
  `geo_json` STRING COMMENT '地理位置(STRUCT)JSON',
  `app_info_json` STRING COMMENT '应用信息(STRUCT)JSON',
  `traffic_source_json` STRING COMMENT '流量来源(STRUCT)JSON',
  `ecommerce_json` STRING COMMENT '电商数据(STRUCT)JSON',
  `items_json` STRING COMMENT '商品列表(ARRAY<STRUCT>)JSON',
  `privacy_info_json` STRING COMMENT '隐私设置(STRUCT)JSON',
  `event_dimensions_json` STRING COMMENT '事件维度(STRUCT)JSON',
  `raw_json` STRING COMMENT '完整事件原始JSON(兜底)',
  `bq_sync_time` STRING COMMENT 'BigQuery同步时间戳'
)
COMMENT 'Firebase Analytics 埋点事件-日增量'
PARTITIONED BY (
  `ds` STRING NOT NULL COMMENT '分区日期 yyyyMMdd'
)
STORED AS AliOrc
LIFECYCLE 36500;
