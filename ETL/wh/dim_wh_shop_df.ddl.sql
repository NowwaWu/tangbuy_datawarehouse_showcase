CREATE TABLE demo_dw.`dim_wh_shop_df` (
  `shop_id` BIGINT COMMENT '店铺ID（自然键）',
  `merchant_id` BIGINT COMMENT '商户ID',
  `shop_nm` STRING COMMENT '店铺名称',
  `intro` STRING COMMENT '店铺简介',
  `ctgy_id_1` BIGINT COMMENT '主营一级类目ID',
  `ctgy_id_2` BIGINT COMMENT '主营二级类目ID',
  `cover_img` STRING COMMENT '店铺封面图PC',
  `cover_img_app` STRING COMMENT '店铺封面图APP',
  `bg_img` STRING COMMENT '店铺背景图',
  `logo_img` STRING COMMENT '店铺Logo图',
  `contact_nm` STRING COMMENT '联系人',
  `contact_phn` STRING COMMENT '联系电话',
  `online_im` STRING COMMENT '在线客服',
  `ship_addr_ids` STRING COMMENT '发货地址ID集合',
  `ship_addr_nms` STRING COMMENT '发货地址名称集合',
  `ship_addr_detail` STRING COMMENT '发货详细地址',
  `rtn_addr_ids` STRING COMMENT '退货地址ID集合',
  `rtn_addr_nms` STRING COMMENT '退货地址名称集合',
  `rtn_addr_detail` STRING COMMENT '退货详细地址',
  `wthd_account` STRING COMMENT '提现账号',
  `customer_notice` STRING COMMENT '客户须知',
  `video_type_cd` BIGINT COMMENT '视频类型编码: 1-youtube, 2-tiktok',
  `video_url` STRING COMMENT '视频链接地址',
  `creation_time` DATETIME COMMENT '店铺成立时间',
  `shop_stat` BIGINT COMMENT '店铺状态: 1-正常, 2-禁用 (纠偏后)',
  `crt_time` DATETIME COMMENT '创建时间',
  `upd_time` DATETIME COMMENT '更新时间'
)
COMMENT '仓储商户店铺维度表-日全量快照'
PARTITIONED BY (
  `ds` STRING NOT NULL COMMENT '分区日期 yyyyMMdd'
)
STORED AS AliOrc
LIFECYCLE 36500;
