CREATE TABLE demo_dw.`dwd_pay_rechg_rcd_di` (
  `rechg_no` STRING COMMENT '充值交易单号(源pay_recharge_record.trade_no)',
  `pay_rcd_id` BIGINT COMMENT '关联支付记录ID(源pay_payment.id)',
  `txn_id` BIGINT COMMENT '交易记录ID(源pay_transaction.id)',
  `txn_no` STRING COMMENT '交易编号(源pay_transaction.transaction_no)',
  `out_trade_no` STRING COMMENT '三方交易号(源serial_no)',
  `usr_id` BIGINT COMMENT '用户ID',
  `biz_type_cd` BIGINT COMMENT '业务类型编码',
  `rcd_type_cd` BIGINT COMMENT '账单类型编码: 1-支付, 2-退款, 3-充值, 4-提现',
  `trade_type_cd` BIGINT COMMENT '交易类型编码: 0-入账, 1-出账, 2-转移',
  `pay_mtd_cd` STRING COMMENT '支付方式枚举(源pay_way, 大写)',
  `pay_acct` STRING COMMENT '付款/收款账户',
  `payer_id` STRING COMMENT '付款人ID',
  `payer_acct` STRING COMMENT '付款人账号',
  `ccy` STRING COMMENT '币种代码',
  `ccy_amt` DECIMAL(18,4) COMMENT '到账币种金额',
  `rechg_amt` DECIMAL(18,4) COMMENT '充值金额',
  `rechg_actl_amt` DECIMAL(18,4) COMMENT '充值实际到账金额',
  `wthd_amt` DECIMAL(18,4) COMMENT '可提现金额',
  `rechg_loss_amt` DECIMAL(18,4) COMMENT '充值损耗金额',
  `pay_fee` DECIMAL(18,4) COMMENT '支付手续费',
  `fixed_loss_amt` DECIMAL(18,4) COMMENT '固定损耗金额',
  `fx_rate` DECIMAL(18,6) COMMENT '兑换人民币汇率',
  `rechg_stat` BIGINT COMMENT '充值状态: 0-待付款, 1-成功, 2-失败',
  `txn_stat` BIGINT COMMENT '账单状态: 0-初始, 1-处理中, 3-成功, 5-失败, 6-取消',
  `pay_stat` BIGINT COMMENT '支付业务状态: 0-待付款, 1-支付中, 2-已支付, 3-成功, 4-退款, 5-失败, 6-取消, 7-订单退款',
  `call_stat` BIGINT COMMENT '三方回调状态: 0-支付中, 1-已支付, 2-已退款, 3-支付失败, 4-取消',
  `is_succ` BIGINT COMMENT '是否充值成功: 0-否, 1-是',
  `rechg_time` DATETIME COMMENT '充值成功通知时间',
  `exp_time` DATETIME COMMENT '充值过期时间',
  `crt_time` DATETIME COMMENT '充值记录创建时间',
  `pay_time` DATETIME COMMENT '关联支付交易时间',
  `ntfy_time` DATETIME COMMENT '关联支付通知时间',
  `rmk` STRING COMMENT '备注',
  `ver` BIGINT COMMENT '版本号'
)
COMMENT '支付结算域-充值记录事务事实表-日增量(成功入账口径)'
PARTITIONED BY (
  `ds` STRING NOT NULL COMMENT '分区日期 yyyyMMdd（充值成功通知日期）'
)
STORED AS AliOrc
LIFECYCLE 366;
