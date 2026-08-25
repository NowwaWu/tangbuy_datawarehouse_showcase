CREATE TABLE demo_dw.`dim_comm_dict_data_df` (
  `dict_cd` BIGINT COMMENT '字典编码',
  `dict_sort_order` BIGINT COMMENT '字典排序',
  `dict_label` STRING COMMENT '字典标签',
  `dict_val` STRING COMMENT '字典键值',
  `dict_type_cd` STRING COMMENT '字典类型编码',
  `css_class` STRING COMMENT '样式属性（CSS类名）',
  `list_class` STRING COMMENT '表格回显样式',
  `is_dflt` BIGINT COMMENT '是否默认（1是 0否）',
  `dict_stat` BIGINT COMMENT '状态（0正常 1停用）',
  `crt_usr` STRING COMMENT '创建者',
  `crt_time` DATETIME COMMENT '创建时间',
  `upd_usr` STRING COMMENT '更新者',
  `upd_time` DATETIME COMMENT '更新时间',
  `rmk` STRING COMMENT '备注'
)
COMMENT '字典数据维度表-日全量快照'
PARTITIONED BY (
  `ds` STRING NOT NULL COMMENT '分区日期 yyyyMMdd'
)
STORED AS AliOrc
LIFECYCLE 36500;
