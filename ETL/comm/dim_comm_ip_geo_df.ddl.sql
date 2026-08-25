CREATE TABLE demo_dw.`dim_comm_ip_geo_df` (
  `reg_ip` STRING COMMENT '注册IP地址(IPv4/IPv6)',
  `cntry_cd` STRING COMMENT '国家代码',
  `prov` STRING COMMENT '省份/地区',
  `city` STRING COMMENT '城市'
)
COMMENT 'IP地址地理位置映射表-每日增量更新'
PARTITIONED BY (
  `ds` STRING NOT NULL COMMENT '分区日期 yyyyMMdd'
)
STORED AS AliOrc
LIFECYCLE 36500;
