CREATE TABLE demo_dw.`dwd_trd_order_operation_di` (
  `opt_id` BIGINT COMMENT '操作记录ID(源表id)',
  `ord_line_no` STRING COMMENT '子订单号',
  `crt_usr` STRING COMMENT '操作人(创建人)',
  `op_type_cd` STRING COMMENT '原始操作类型编码(源表op_type)',
  `op_type_cn` STRING COMMENT '操作类型中文(正则提取, 清洗后)',
  `cmpny_id` BIGINT COMMENT '公司ID',
  `crt_time` DATETIME COMMENT '操作时间(记录时间)'
)
COMMENT '交易域-订单操作明细-日增量(odm清洗, 提取op_type_cn)'
PARTITIONED BY (
  `ds` STRING NOT NULL COMMENT '分区日期 yyyyMMdd'
)
STORED AS AliOrc
LIFECYCLE 36500;
