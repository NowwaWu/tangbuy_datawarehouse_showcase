CREATE TABLE demo_dw.`dwd_itm_tb_item_detail_df` (
  `item_id` BIGINT COMMENT '商品ID',
  `tag_id_list` ARRAY<BIGINT> COMMENT '标签ID列表',
  `crt_time` DATETIME COMMENT '最早创建时间',
  `upd_time` DATETIME COMMENT '最新更新时间'
)
COMMENT '平台优选商品详情表（标签聚合）-日全量'
PARTITIONED BY (
  `ds` STRING NOT NULL COMMENT '分区日期 yyyyMMdd'
)
STORED AS AliOrc
LIFECYCLE 365;
