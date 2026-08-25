CREATE TABLE demo_dw.`dim_store_ds_shop_df` (
  `shop_id` BIGINT COMMENT '店铺ID',
  `shop_nm` STRING COMMENT '店铺名称',
  `shop_pltf_cd` STRING COMMENT '店铺类型枚举: shopify / tiktok / woocommerce',
  `shop_url` STRING COMMENT '店铺URL/域名',
  `shop_rgn_cd` STRING COMMENT '店铺所在区域枚举',
  `shop_cd` STRING COMMENT '店铺编码(TikTok: shop_code)',
  `usr_id` BIGINT COMMENT '平台用户ID',
  `slr_nm` STRING COMMENT '商家/卖家名称',
  `slr_type_cd` STRING COMMENT '卖家类型枚举(TikTok)',
  `tk_usr_type_cd` BIGINT COMMENT 'TikTok用户类型枚举: 0-Seller, 1-Creator, 3-Partner',
  `email` STRING COMMENT '店铺关联邮箱',
  `shop_stat` BIGINT COMMENT '店铺状态: 0-禁用, 1-启用',
  `auth_stat` BIGINT COMMENT '认证状态(WooCommerce): 0-未认证, 1-已认证, 2-失败',
  `is_shop_unreachable` BIGINT COMMENT '店铺是否无法访问: 0-否, 1-是',
  `shop_unreachable_rsn` STRING COMMENT '店铺无法访问原因(Shopify error_msg)',
  `is_ssl_on` BIGINT COMMENT '是否启用SSL(WooCommerce): 0-否, 1-是',
  `flfl_service_id` STRING COMMENT '履约服务ID',
  `flfl_handle` STRING COMMENT '履约服务唯一标识(handle)',
  `flfl_callback_url` STRING COMMENT '履约服务回调URL',
  `flfl_service_nm` STRING COMMENT '履约服务名称',
  `flfl_stat` BIGINT COMMENT '履约服务状态: 0-失效, 1-有效',
  `location_id` STRING COMMENT '地址ID',
  `api_ver` STRING COMMENT 'API版本(WooCommerce)',
  `inst_time` DATETIME COMMENT '安装时间(Shopify)',
  `shop_crt_time` DATETIME COMMENT '店铺创建时间(Shopify)',
  `last_sync_time` DATETIME COMMENT '最后同步时间(WooCommerce)',
  `rmk` STRING COMMENT '备注信息(WooCommerce)',
  `is_del` BIGINT COMMENT '是否删除(WooCommerce): 0-否, 1-是',
  `crt_time` DATETIME COMMENT '创建时间',
  `upd_time` DATETIME COMMENT '最后更新时间'
)
COMMENT 'DS代发平台店铺维度表-日全量快照(合并履约服务)'
PARTITIONED BY (
  `ds` STRING NOT NULL COMMENT '分区日期 yyyyMMdd'
)
STORED AS AliOrc
LIFECYCLE 36500;
