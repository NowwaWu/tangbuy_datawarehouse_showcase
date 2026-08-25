CREATE TABLE demo_dw.`dwd_pay_pay_rcd_di` (
  `pay_rcd_id` BIGINT COMMENT '支付记录ID(源pay_payment.id)',
  `txn_id` BIGINT COMMENT '交易记录ID(源pay_transaction.id)',
  `txn_no` STRING COMMENT '交易编号(源pay_transaction.transaction_no)',
  `biz_no` STRING COMMENT '业务单号(源pay_transaction.business_no)',
  `trade_no` STRING COMMENT '交易订单号(源pay_payment.trade_no)',
  `out_trade_no` STRING COMMENT '三方交易号(源pay_payment.serial_no)',
  `prepay_no` STRING COMMENT '支付机构预支付订单号',
  `usr_id` BIGINT COMMENT '用户ID',
  `biz_type_cd` BIGINT COMMENT '业务类型编码',
  `rcd_type_cd` BIGINT COMMENT '账单类型编码: 1-支付, 2-退款, 3-充值, 4-提现',
  `trade_type_cd` BIGINT COMMENT '交易类型编码: 0-入账, 1-出账, 2-转移',
  `pay_src_cd` STRING COMMENT '支付来源编码: BALANCE-余额支付, RECHG-充值支付, THIRD-三方渠道支付, UNKNOWN-未知',
  `pay_mtd_cd` STRING COMMENT '支付方式枚举(源pay_way, 大写)',
  `paypal_pay_mtd_cd` STRING COMMENT 'PayPal支付方式枚举(源payment_type, 大写)',
  `ccy` STRING COMMENT '币种代码',
  `ccy_amt` DECIMAL(18,4) COMMENT '币种金额',
  `pay_amt` DECIMAL(18,4) COMMENT '支付交易金额',
  `pay_disc_amt` DECIMAL(18,4) COMMENT '支付减免金额',
  `pay_ccy_disc_amt` DECIMAL(18,4) COMMENT '支付币种减免金额',
  `pay_fee` DECIMAL(18,4) COMMENT '支付手续费',
  `fixed_loss_amt` DECIMAL(18,4) COMMENT '固定损耗金额',
  `fx_rate` DECIMAL(18,6) COMMENT '兑换人民币汇率',
  `bal_before_amt` DECIMAL(18,4) COMMENT '交易前余额',
  `bal_after_amt` DECIMAL(18,4) COMMENT '交易后余额',
  `ref_frz_amt` DECIMAL(18,4) COMMENT '支付扣除的退款冻结金额',
  `txn_stat` BIGINT COMMENT '账单状态: 0-初始, 1-处理中, 3-成功, 5-失败, 6-取消',
  `pay_stat` BIGINT COMMENT '支付业务状态: 0-待付款, 1-支付中, 2-已支付, 3-成功, 4-退款, 5-失败, 6-取消, 7-订单退款',
  `call_stat` BIGINT COMMENT '三方回调状态: 0-支付中, 1-已支付, 2-已退款, 3-支付失败, 4-取消',
  `quick_pay_cd` BIGINT COMMENT '免密支付类型编码',
  `is_bal_pay` BIGINT COMMENT '是否余额支付: 0-否, 1-是',
  `is_rechg_pay` BIGINT COMMENT '是否充值支付: 0-否, 1-是',
  `is_succ` BIGINT COMMENT '是否成功支付: 0-否, 1-是',
  `pay_time` DATETIME COMMENT '支付发生时间(分区归属时间)',
  `trade_time` DATETIME COMMENT '源支付交易时间',
  `ntfy_time` DATETIME COMMENT '源支付通知时间',
  `crt_time` DATETIME COMMENT '支付记录创建时间',
  `upd_time` DATETIME COMMENT '支付记录更新时间',
  `payer_id` STRING COMMENT '付款人ID',
  `payer_acct` STRING COMMENT '付款人账号',
  `rmk` STRING COMMENT '备注',
  `memo` STRING COMMENT '备注2'
)
COMMENT '支付结算域-支付记录事务事实表-日增量(资金侧成功支付口径)'
PARTITIONED BY (
  `ds` STRING NOT NULL COMMENT '分区日期 yyyyMMdd（支付发生日期）'
)
STORED AS AliOrc
LIFECYCLE 366;
