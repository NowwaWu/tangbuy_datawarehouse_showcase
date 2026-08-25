CREATE TABLE demo_dw.`dwd_store_ds_shop_auth_rel_df` (
  `auth_rel_id` BIGINT COMMENT '授权关系ID(来源 user_auth_shop.id)',
  `usr_id` BIGINT COMMENT '用户ID(对应 dim_plugin_shop_user_info.user_id)',
  `usr_nm` STRING COMMENT '用户姓名(冗余 dim_usr_info_df)',
  `email` STRING COMMENT '用户邮箱(对应 dim_plugin_shop_user_info.email)',
  `cntry_cd` STRING COMMENT '注册国家简码(冗余 dim_usr_info_df)',
  `shop_pltf_cd` STRING COMMENT '店铺平台编码(对应 dim_plugin_shop_user_info.shop_type): SHOPIFY/TIKTOK/WOOCOMMERCE',
  `shop_id` STRING COMMENT '外部店铺ID(对应 dim_plugin_shop_user_info.shop_id)',
  `shop_nm` STRING COMMENT '外部店铺名称',
  `shop_url` STRING COMMENT '店铺URL/域名(对应 dim_plugin_shop_user_info.shop_domain; 已转小写并去除http/https协议)',
  `slr_nm` STRING COMMENT '卖家名称(冗余平台店铺授权表)',
  `shop_rgn_cd` STRING COMMENT '店铺所在区域编码(冗余平台店铺授权表)',
  `is_shop_unreachable` BIGINT COMMENT '店铺是否无法访问: 0-否, 1-是',
  `shop_unreachable_rsn` STRING COMMENT '店铺无法访问原因(Shopify error_msg)',
  `shop_crt_time` DATETIME COMMENT '店铺创建时间(Shopify)',
  `auth_stat` BIGINT COMMENT '授权状态ID(对应 dim_plugin_shop_user_info.status_id): 0-禁用, 1-启用, -1-未知',
  `auth_stat_nm` STRING COMMENT '授权状态名称(对应 dim_plugin_shop_user_info.status_name)',
  `bd_usr_nm` STRING COMMENT '当前关联BD名称列表(对应 dim_plugin_shop_user_info.bd_name, 多个分号分隔)',
  `is_del` BIGINT COMMENT '是否删除: 0-否, 1-是',
  `crt_time` DATETIME COMMENT '授权创建时间(对应 dim_plugin_shop_user_info.create_time)',
  `upd_time` DATETIME COMMENT '授权更新时间(对应 dim_plugin_shop_user_info.update_time)',
  `auth_revoke_time` DATETIME COMMENT '用户撤销店铺授权时间'
)
COMMENT 'DS店铺授权关系明细累积快照-日全量'
PARTITIONED BY (
  `ds` STRING NOT NULL COMMENT '分区日期 yyyyMMdd'
)
STORED AS AliOrc
LIFECYCLE 365;
