CREATE TABLE demo_dw.`dim_itm_out_item_df` (
  `out_item_dim_id` BIGINT COMMENT '三方平台商品维度ID（自然键，来自third_platform_product.id）',
  `draft_id` BIGINT COMMENT '商品草稿ID',
  `unique_key` STRING COMMENT '店铺唯一键(shopName_shopType)',
  `item_nm` STRING COMMENT '商品名称',
  `item_id` STRING COMMENT '三方商品ID',
  `tb_item_id` BIGINT COMMENT '自有商品ID',
  `pub_src` STRING COMMENT '刊登数据来源',
  `splr_key` STRING COMMENT '供应商标识',
  `cfm_stat` BIGINT COMMENT '确认状态: 1-客户确认, 2-BD推荐',
  `graphql_api_id` STRING COMMENT 'GraphQL ID(Shopify使用第三方商品别名)',
  `item_stat_cd` STRING COMMENT '商品状态枚举: active-上架, draft-草稿, archived-归档下架',
  `shop_id` BIGINT COMMENT '三方店铺ID',
  `shop_nm` STRING COMMENT '三方店铺名称',
  `shop_pltf_cd` STRING COMMENT '三方店铺平台编码: SHOPIFY / TIKTOK / WOOCOMMERCE',
  `item_desc` STRING COMMENT '商品描述',
  `attr_json` STRING COMMENT '属性值JSON',
  `imgs` STRING COMMENT '商品图片',
  `rel_stat` BIGINT COMMENT '关联关系状态: 1-全部关联, 2-部分关联',
  `min_prc` DECIMAL(18,4) COMMENT '最低价格',
  `max_prc` DECIMAL(18,4) COMMENT '最高价格',
  `min_wt` DECIMAL(18,4) COMMENT '最小重量',
  `max_wt` DECIMAL(18,4) COMMENT '最大重量',
  `inv` BIGINT COMMENT '库存数量',
  `sales_cnt_30d` BIGINT COMMENT '30日销量',
  `crt_type_cd` BIGINT COMMENT '创建方式枚举',
  `bd_rel_stat` BIGINT COMMENT 'BD关联状态: 0-未关联, 1-BD已推荐, 2-已关联',
  `bd_opt_time` DATETIME COMMENT 'BD操作时间',
  `no_rel_sort` BIGINT COMMENT '未关联排序字段',
  `cust_submit_stat` BIGINT COMMENT '客户提交状态: 0-未提交, 1-已申请, 2-已关联',
  `is_ai_recmd` BIGINT COMMENT 'AI推荐处理完成: 0-未处理, 1-处理完成',
  `is_order_unrel` BIGINT COMMENT '是否有未关联订单: 0-无, 1-有',
  `is_logis_tpl_rel` BIGINT COMMENT '是否关联发货模版: 0-未关联, 1-已关联',
  `opt_time` DATETIME COMMENT '最近操作时间',
  `out_item_dtl_json` STRING COMMENT '关联的三方商品详情JSON',
  `is_del` BIGINT COMMENT '是否删除: 0-否, 1-是',
  `crt_time` DATETIME COMMENT '创建时间',
  `upd_time` DATETIME COMMENT '更新时间',
  `out_item_url` STRING COMMENT '三方商品链接(WooCommerce取product.permalink; Shopify按店铺域名+handle拼接, 无法生成时为空)'
)
COMMENT '三方平台商品维度表-日全量快照'
PARTITIONED BY (
  `ds` STRING NOT NULL COMMENT '分区日期 yyyyMMdd'
)
STORED AS AliOrc
LIFECYCLE 36500;
