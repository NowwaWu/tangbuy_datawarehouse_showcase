CREATE TABLE demo_dw.`dim_wh_warehouse_df` (
  `wh_id` BIGINT COMMENT '仓库ID（自然键）',
  `wh_nm` STRING COMMENT '仓库名称',
  `wh_type_cd` STRING COMMENT '仓库类型枚举（暂无数据源，预留）',
  `addr` STRING COMMENT '仓库地址',
  `capacity` BIGINT COMMENT '仓库容量',
  `capacity_use` BIGINT COMMENT '已使用容量',
  `is_full` BIGINT COMMENT '仓库是否已满: 0-否, 1-是',
  `is_dflt_asgn` BIGINT COMMENT '是否默认分配: 0-否, 1-是',
  `wh_stat` BIGINT COMMENT '仓库状态: 0-禁用, 1-启用 (纠偏后)',
  `crt_usr` STRING COMMENT '创建人（ODS create_by 直出）',
  `is_del` BIGINT COMMENT '是否删除: 0-否, 1-是（从 status=无效 推导）',
  `crt_time` DATETIME COMMENT '创建时间',
  `upd_time` DATETIME COMMENT '更新时间'
)
COMMENT '仓库维度表-日全量快照'
PARTITIONED BY (
  `ds` STRING NOT NULL COMMENT '分区日期 yyyyMMdd'
)
STORED AS AliOrc
LIFECYCLE 36500;
