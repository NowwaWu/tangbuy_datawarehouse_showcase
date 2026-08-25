CREATE TABLE demo_dw.`dwd_itm_plt_subs_rel_df` (
  `id` BIGINT COMMENT '主键ID（自然键）',
  `subs_plt_id` BIGINT COMMENT '订阅货盘ID',
  `rel_biz_id` BIGINT COMMENT '关联业务ID',
  `rel_biz_type_cd` BIGINT COMMENT '关联业务类型: 0-类目, 1-店铺, 2-货盘',
  `is_del` BIGINT COMMENT '是否删除: 0-否, 1-是',
  `crt_time` DATETIME COMMENT '创建时间',
  `upd_time` DATETIME COMMENT '更新时间'
)
COMMENT '订阅货盘关联明细表-日全量'
PARTITIONED BY (
  `ds` STRING NOT NULL COMMENT '分区日期 yyyyMMdd'
)
STORED AS AliOrc
LIFECYCLE 365;
