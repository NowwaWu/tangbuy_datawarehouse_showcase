CREATE TABLE demo_dw.`dim_pay_exch_rate_df` (
  `rate_id` BIGINT COMMENT '汇率配置ID（自然键，对应dim_pay_channel_df.rate_id）',
  `ccy_cd` STRING COMMENT '币种代码(USD/EUR/GBP等)',
  `ccy_symbol` STRING COMMENT '币种符号($€£等)',
  `ccy_lang` STRING COMMENT '币种语言标识(源字段language)',
  `exch_ccy` STRING COMMENT '兑换目标币种(源字段exchange_currency, 理论值CNY)',
  `pub_rate` DECIMAL(18,6) COMMENT '银行间公开汇率(public_fx_rate)',
  `fin_rate` DECIMAL(18,6) COMMENT '财务设置汇率(follow_rate)',
  `exch_rate` DECIMAL(18,6) COMMENT '综合汇率(rate)',
  `pref_rate` DECIMAL(18,6) COMMENT '生效汇率(优先级: pub_rate > fin_rate > exch_rate > 兜底值)',
  `rate_src_cd` STRING COMMENT '汇率来源枚举: PUB-银行公开/FIN-财务设置/RATE-综合/FALLBACK-兜底/NONE-无',
  `sort_num` BIGINT COMMENT '币种排序号',
  `show_loc_cd` BIGINT COMMENT '展示位置: 0-数字在前, 1-符号在前',
  `ccy_stat` BIGINT COMMENT '币种状态: 0-禁用, 1-启用',
  `pub_rate_upd_time` DATETIME COMMENT '银行公开汇率更新时间',
  `upd_usr` STRING COMMENT '修改人',
  `upd_time` DATETIME COMMENT '记录更新时间'
)
COMMENT '币种汇率维度表-日全量快照(支持多币种兑CNY)'
PARTITIONED BY (
  `ds` STRING NOT NULL COMMENT '分区日期 yyyyMMdd'
)
STORED AS AliOrc
LIFECYCLE 36500;
