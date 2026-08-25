CREATE TABLE demo_dw.`ads_dist_cmsn_pmt_wthd_td` (
  `pmt_id` BIGINT COMMENT '推广者ID，对应MySQL导出字段promoterId',
  `pmt_nm` STRING COMMENT '推广者名称，对应MySQL导出字段promoterName，优先proxy_customer.user_name，兜底b_share.holder_name',
  `pmt_email` STRING COMMENT '推广者邮箱，对应MySQL导出字段email',
  `pmt_lvl` BIGINT COMMENT '推广者等级，对应MySQL导出字段proxyLevel',
  `tot_cmsn_amt` DECIMAL(18,4) COMMENT '累计佣金金额，对应MySQL导出字段totalCommission，delivery_time非空订单佣金汇总',
  `curr_mth_cmsn_amt` DECIMAL(18,4) COMMENT '当月佣金金额，对应MySQL导出字段currentMonthCommission，按bizdate所在自然月delivery_time汇总',
  `wthd_succ_amt` DECIMAL(18,4) COMMENT '提现成功金额，对应MySQL导出字段withdrawnAmount，提现状态status=1',
  `wthd_pend_amt` DECIMAL(18,4) COMMENT '待提现金额，对应MySQL导出字段pendingAmount，提现状态status=0'
)
COMMENT '分销集市-推广者佣金提现统计-历史截至当日，测试ODS源数据导出MySQL使用'
PARTITIONED BY (
  `ds` STRING NOT NULL COMMENT '分区日期 yyyyMMdd'
)
STORED AS AliOrc
LIFECYCLE 365;
