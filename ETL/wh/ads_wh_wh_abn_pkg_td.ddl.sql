CREATE TABLE demo_dw.`ads_wh_wh_abn_pkg_td` (
  `stat_date` STRING COMMENT '统计日期 yyyyMMdd，通常为调度业务日期',
  `data_ds` STRING COMMENT '来源快照分区日期 yyyyMMdd，通常为统计日期前一日',
  `pkg_no` STRING COMMENT '包裹单号',
  `abn_type_cd` STRING COMMENT '异常类型编码: NOT_SND-未发货, NOT_RCV-已发货未收到货',
  `abn_type_nm` STRING COMMENT '异常类型名称',
  `is_snd` BIGINT COMMENT '是否已发货: 0-否, 1-是',
  `wh_stock_in_pend_snd_days` DECIMAL(18,2) COMMENT '入库后等待发货天数，按当前日期计算，未发货包裹有效，最小值为0',
  `snd_pend_rcv_days` DECIMAL(18,2) COMMENT '发货后等待收到货天数，按当前日期计算，已发货未收到货包裹有效，最小值为0',
  `usr_id` BIGINT COMMENT '用户ID',
  `usr_nm` STRING COMMENT '用户姓名',
  `email` STRING COMMENT '用户邮箱',
  `wh_id` BIGINT COMMENT '仓库ID',
  `wh_nm` STRING COMMENT '仓库名称',
  `pkg_stat` BIGINT COMMENT '包裹主状态',
  `pkg_stat_nm` STRING COMMENT '包裹主状态名称',
  `pkg_pay_stat` BIGINT COMMENT '包裹支付状态',
  `pkg_pay_stat_nm` STRING COMMENT '包裹支付状态名称',
  `pkg_bag_stat` BIGINT COMMENT '包裹退包状态: 0-正常包裹, 1-国内退包, 2-国外退包, 3-取消包裹, 4-包裹待补款',
  `pkg_bag_stat_nm` STRING COMMENT '包裹退包状态名称',
  `pkg_exprs_no` STRING COMMENT '包裹快递单号',
  `pkg_exprs_nm` STRING COMMENT '包裹快递公司名称',
  `pkg_line_nm` STRING COMMENT '包裹物流线路名称',
  `pkg_line_id` STRING COMMENT '包裹物流线路ID',
  `pkg_rcv_cntry` STRING COMMENT '包裹收件国家',
  `pkg_rcv_area` STRING COMMENT '包裹收件地区',
  `pkg_rcv_city` STRING COMMENT '包裹收件城市',
  `ord_line_cnt` BIGINT COMMENT '包裹关联内部订单子单数量',
  `last_wh_stock_in_time` DATETIME COMMENT '包裹内子单最晚入库时间',
  `pkg_snd_time` DATETIME COMMENT '包裹发货时间',
  `rcv_time` DATETIME COMMENT '用户已收到货时间',
  `trk_cnt` BIGINT COMMENT '物流轨迹节点数量',
  `last_trk_time` DATETIME COMMENT '最新物流轨迹变动时间',
  `last_trk_pos` STRING COMMENT '最新物流轨迹所在地',
  `last_trk_desc` STRING COMMENT '最新物流轨迹描述',
  `trk_dtl` STRING COMMENT '物流轨迹详情，按change_time升序拼接: change_time | position | description',
  `is_flw` BIGINT COMMENT '运营是否已跟进/处理，当前表仅保留未处理包裹，固定为0',
  `abn_rsn` STRING COMMENT '异常原因，默认空字符串',
  `ord_line_stat_dtl` STRING COMMENT '包裹内TI号及对应订单子单状态明细，格式: TI号 | 状态名称；TI号 | 状态名称'
)
COMMENT '仓储履约集市-履约分析-最近2个月内当前未处理且未收到货包裹监控明细-历史截至当日'
PARTITIONED BY (
  `ds` STRING NOT NULL COMMENT '分区日期 yyyyMMdd'
)
STORED AS AliOrc
LIFECYCLE 366;
