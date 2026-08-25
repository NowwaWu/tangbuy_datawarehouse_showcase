CREATE TABLE demo_dw.`dws_trd_ds_ord_line_pkg_fee_td` (
  `ord_line_no` BIGINT COMMENT 'DS订单行ID(关联dwd_trd_ds_ord_line_df)',
  `ord_no` BIGINT COMMENT 'DS订单ID(关联dwd_trd_ds_ord_header_df)',
  `tb_ord_line_no` STRING COMMENT 'Tangbuy商品编号(对应ord_line_no)',
  `item_id` STRING COMMENT '商品ID(关联dws_trd_item_lifecycle_time_1d)',
  `item_nm` STRING COMMENT '商品名称(来自dwd_trd_ds_ord_line_df)',
  `pkg_no` STRING COMMENT '包裹单号(来自dwd_trd_ds_ord_line_df, 关联dwd_wh_pkg_mgr_df)',
  `usr_id` BIGINT COMMENT '用户ID(下单用户)',
  `ord_type_cd` BIGINT COMMENT '订单类型: 1-代发, 2-直购备货, 3-直购直发, 4-询盘备货, 5-询盘直发',
  `shop_pltf_cd` STRING COMMENT '店铺平台编码(shopify/tiktok/woocommerce)',
  `pkg_wrap_cd` STRING COMMENT '包裹包装类型: 极简包装/纸箱包装/未知包装',
  `ord_stat` BIGINT COMMENT '订单状态: 1-待处理, 2-待支付, 3-备货中, 4-待发货, 5-待送达, 6-已完结, 9-已取消, 10-已退款, 11-已失效',
  `pay_time` DATETIME COMMENT '支付时间',
  `crt_time` DATETIME COMMENT '订单创建时间',
  `ord_cnt` BIGINT COMMENT '商品数量(来自dwd_trd_ds_ord_line_df)',
  `fee_alloc_rate` DECIMAL(18,4) COMMENT '费用分摊比例(pur_amt / 包裹内所有子单pur_amt合计)',
  `wt_alloc_rate` DECIMAL(18,4) COMMENT '重量分摊比例(子单wt / 订单内所有子单wt合计, 按ord_no汇总)',
  `vol_alloc_rate` DECIMAL(18,4) COMMENT '体积分摊比例(子单体积 / 订单内所有子单体积合计, 按ord_no汇总)',
  `tot_pre_amt` DECIMAL(18,4) COMMENT '分摊预估总费用',
  `tot_actl_amt` DECIMAL(18,4) COMMENT '分摊实际总费用',
  `tech_srv_pre_fee` DECIMAL(18,4) COMMENT '分摊预估技术服务费',
  `tech_srv_actl_fee` DECIMAL(18,4) COMMENT '分摊实际技术服务费',
  `ins_amt` DECIMAL(18,4) COMMENT '分摊保险费',
  `diff_amt` DECIMAL(18,4) COMMENT '分摊费用差额',
  `succ_diff_amt` DECIMAL(18,4) COMMENT '分摊成功交易差额',
  `cpn_amt` DECIMAL(18,4) COMMENT '分摊优惠券金额',
  `disc_amt` DECIMAL(18,4) COMMENT '分摊折扣金额',
  `dep_amt` DECIMAL(18,4) COMMENT '分摊预存款',
  `actl_dep_amt` DECIMAL(18,4) COMMENT '分摊实际存款',
  `alloc_wt` DECIMAL(18,4) COMMENT '分摊重量(kg), is_vol_wt_on=0时=pkg_actl_wt×wt_alloc_rate, =1时为0',
  `alloc_vol` DECIMAL(18,4) COMMENT '分摊体积(cm³), is_vol_wt_on=1时=体积(长×宽×高)×vol_alloc_rate, =0时为0'
)
COMMENT '交易域-DS订单行包裹费用+重量/体积分摊全量快照(三类独立比例分摊, 排除备货订单)'
PARTITIONED BY (
  `ds` STRING NOT NULL COMMENT '分区日期 yyyyMMdd'
)
STORED AS AliOrc
LIFECYCLE 366;
