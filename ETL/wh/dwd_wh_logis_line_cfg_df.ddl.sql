-- ============================================================
-- 数据域:   wh (仓储履约域)
-- 业务过程: logis_line (物流线路管理)
-- 表名:     dwd_wh_logis_line_cfg_df
-- 表类型:   DWD 配置全量快照
-- 粒度:     一行 = 一个物流线路配置记录(line_cfg_id)
-- 描述:     沉淀线路在国家/省份/重量段下的计费、申报、尺寸与寄送限制配置
-- 来源:     ods_mysql_tang_logistics_l_line_config_ri
--           ods_mysql_tang_logistics_l_delivery_line_ri
--           ods_mysql_tang_resource_r_data_region_ri(level=2)
-- 调度周期: 日
-- ============================================================

CREATE TABLE IF NOT EXISTS demo_dw.`dwd_wh_logis_line_cfg_df` (
  `line_cfg_id` BIGINT COMMENT '物流线路配置ID(id，本表粒度)',
  `line_id` STRING COMMENT '物流线路ID(line_id，统一为STRING)',
  `line_nm` STRING COMMENT '物流线路中文名称(l_delivery_line.name_cn)',
  `is_line_on` BIGINT COMMENT '线路配置是否启用: 0-否, 1-是(status)',
  `trait_id` BIGINT COMMENT '计抛特点ID(trait_id)',
  `cntry_id` BIGINT COMMENT '国家ID(country_id，关联二级区域)',
  `cntry_nm` STRING COMMENT '国家中文名称(resource_r_data_region.name, level=2)',
  `prov_id` BIGINT COMMENT '省份ID(province_id，0表示不限定省份)',
  `min_wt` DECIMAL(18,4) COMMENT '最低限重，单位g(weight_min)',
  `max_wt` DECIMAL(18,4) COMMENT '最高限重，单位g(weight_max)',
  `snd_day_scp` STRING COMMENT '运输时效天数范围(transit_time，源格式示例6-10)',
  `vol_wt_base` DECIMAL(18,4) COMMENT '体积重量基数(volume_base)',
  `site_url` STRING COMMENT '物流线路官网(website)',
  `first_wt` DECIMAL(18,4) COMMENT '首重重量，单位g(weight_first)',
  `cont_wt` DECIMAL(18,4) COMMENT '续重重量，单位g(weight_continue)',
  `first_frt_fee` DECIMAL(18,4) COMMENT '首重运费，人民币元(fee_first)',
  `cont_frt_fee` DECIMAL(18,4) COMMENT '续重运费，人民币元(fee_continue)',
  `cstm_dcl_fee` DECIMAL(18,4) COMMENT '报关费，人民币元(fee_customs)',
  `fuel_fee` DECIMAL(18,4) COMMENT '燃油费，人民币元(fee_fuel)',
  `srv_fee` DECIMAL(18,4) COMMENT '服务费，人民币元(fee_service)',
  `opt_fee` DECIMAL(18,4) COMMENT '操作费，人民币元(fee_operation)',
  `dcl_type_cd` BIGINT COMMENT '申报类型编码(declare_type，NULL统一为-1)',
  `dcl_ccy` STRING COMMENT '申报币种(declare_currency)',
  `self_dcl_cfg_json` STRING COMMENT '自主申报配置JSON(independent_config)',
  `fee_type_cd` BIGINT COMMENT '计费方式编码: 0-默认, 1-特殊, -1-未知(fee_type)',
  `dcl_mtd_cd_json` STRING COMMENT '申报方式编码列表JSON(declare_mode)',
  `tax_reg_type_cd_json` STRING COMMENT '税号登记类型编码列表JSON(registration_type)',
  `line_trait_cn` STRING COMMENT '线路特点中文(features_cn)',
  `line_trait_en` STRING COMMENT '线路特点英文(features_en)',
  `ml_lmt_item_cn` STRING COMMENT '禁寄物品中文(forbid_cn)',
  `ml_lmt_item_en` STRING COMMENT '禁寄物品英文(forbid_en)',
  `edge_tot_max_sz` DECIMAL(18,4) COMMENT '最大长宽高之和，单位cm(edge_total_max)',
  `long_edge_max_sz` DECIMAL(18,4) COMMENT '最大最长边，单位cm(edge_long_max)',
  `short_edge_max_sz` DECIMAL(18,4) COMMENT '最大最短边，单位cm(edge_short_max)',
  `second_long_edge_max_sz` DECIMAL(18,4) COMMENT '最大第二长边，单位cm(edge_tlong_max)',
  `double_short_edge_tot_max_sz` DECIMAL(18,4) COMMENT '最大两短边之和乘2，单位cm(edge_dshort_total)',
  `double_short_edge_plus_long_max_sz` DECIMAL(18,4) COMMENT '最大两短边之和乘2加最长边，单位cm(edge_dshort_total_and_max)',
  `spcl_cont_wt_cfg_json` STRING COMMENT '特殊续重配置JSON(weight_continue_special)',
  `disc_start_time` DATETIME COMMENT '折扣开始时间(discount_start_time)',
  `disc_end_time` DATETIME COMMENT '折扣结束时间(discount_end_time)',
  `disc_rate` DECIMAL(18,6) COMMENT '折扣率(discount_rate)',
  `show_rcv_cfg_json` STRING COMMENT '目的国显示收件人信息配置JSON(show_receiver)',
  `line_auth_type_cd` BIGINT COMMENT '线路权限类型: 0-所有用户, 1-部分用户, -1-未知(permission)',
  `auth_usr_id_json` STRING COMMENT '授权用户ID列表JSON(uid)',
  `auth_vip_lvl_json` STRING COMMENT '授权VIP等级列表JSON(vip)',
  `day_submit_wt_quota` DECIMAL(18,4) COMMENT '每日提交重量限额，单位g(weight_limit)',
  `day_submit_wt` DECIMAL(18,4) COMMENT '当日已提交重量，单位g(cur_weight)',
  `splr_cfg_json` STRING COMMENT '物流供应商配置JSON(providers_config)',
  `wh_print_tip` STRING COMMENT '仓库打单提醒(print_tip)',
  `is_invc_print` BIGINT COMMENT '是否打印发票: 0-否, 1-是(invoice_print)',
  `is_snd_timeliness_on` BIGINT COMMENT '运输时效是否开启: 0-否, 1-是(timeliness_status)',
  `snd_start_day_cnt` BIGINT COMMENT '运输时效开始天数(timeliness_start)',
  `snd_end_day_cnt` BIGINT COMMENT '运输时效结束天数(timeliness_end)',
  `unauth_usr_tip_cn` STRING COMMENT '非指定用户中文话术(limit_user_tips_cn)',
  `unauth_usr_tip_en` STRING COMMENT '非指定用户英文话术(limit_user_tips_en)',
  `print_min_wt` DECIMAL(18,4) COMMENT '最低打单重量，单位g(print_min_weight)',
  `print_max_wt` DECIMAL(18,4) COMMENT '最高打单重量，单位g(print_max_weight)',
  `ml_lmt_rgn_json` STRING COMMENT '禁止寄送地区列表JSON(forbid_area)',
  `ml_lmt_zip` STRING COMMENT '禁止寄送邮编，保留源换行分隔格式(forbid_code)',
  `remote_fee` DECIMAL(18,4) COMMENT '偏远费，人民币元(remote_fee)',
  `remote_zip` STRING COMMENT '偏远邮编，保留源换行分隔格式(remote_code)',
  `cstm_tax_fee` DECIMAL(18,4) COMMENT '关税税费，人民币元(tariff_fee)',
  `cstm_tax_ccy` STRING COMMENT '关税币种(tariff_currency)',
  `overlong_len` DECIMAL(18,4) COMMENT '超长尺寸阈值，单位cm(overlong_length)',
  `overlong_fee` DECIMAL(18,4) COMMENT '超长费，人民币元(overlong_fee)',
  `overweight_wt` DECIMAL(18,4) COMMENT '超重重量阈值，单位g(overweight_weight)',
  `overweight_fee` DECIMAL(18,4) COMMENT '超重费，人民币元(overweight_fee)',
  `is_actl_wt_only` BIGINT COMMENT '是否只计实重: 0-否, 1-是(only_real_weight)',
  `day_pkg_quota` BIGINT COMMENT '每日提包数量限额(package_limit)',
  `day_submit_pkg_cnt` BIGINT COMMENT '当日已提交包裹数量(cur_package)',
  `overlong_girth_sz` DECIMAL(18,4) COMMENT '超长横周长阈值，单位cm(overlong_girth)',
  `overlong_girth_fee` DECIMAL(18,4) COMMENT '超长横周长费用，人民币元(overlong_girth_fee)',
  `double_short_edge_plus_long_type_cd` BIGINT COMMENT '两短边之和乘2加最长边规则类型: 0-普通, 1-阶梯, -1-未知(edge_dshort_total_type)',
  `double_short_edge_plus_long_cfg_json` STRING COMMENT '两短边之和乘2加最长边规则配置JSON(edge_dshort_total_config)',
  `is_vld_required` BIGINT COMMENT '是否需要校验: 0-否, 1-是(need_check)',
  `spcl_ioss_acct_json` STRING COMMENT '特殊IOSS账号配置JSON(special_ioss)',
  `snd_cnt_lmt_cfg_json` STRING COMMENT '邮寄数量限制配置JSON(send_limit)',
  `overlong_perimeter_sz` DECIMAL(18,4) COMMENT '超长周长阈值，单位cm(overlong_perimeter)',
  `overlong_perimeter_fee` DECIMAL(18,4) COMMENT '超长周长费用，人民币元(overlong_perimeter_fee)',
  `is_vrtl_exprs_no` BIGINT COMMENT '是否使用虚拟运单号: 0-否, 1-是(virtually_waybill)',
  `trk_match_cnt` STRING COMMENT '物流轨迹匹配文案(match_content)',
  `carrier_cd` STRING COMMENT '交货地承运商编码(carrier_code)',
  `is_overdue_cmpstn_on` BIGINT COMMENT '超时必赔是否开启: 0-否, 1-是(overtime_status)',
  `overdue_cmpstn_day_cnt` BIGINT COMMENT '超时赔付时效天数(overtime_days)',
  `overdue_cmpstn_dtl_json` STRING COMMENT '超时赔付时效多语言说明JSON(overtime_desc)'
)
COMMENT '仓储履约域-物流线路配置日全量快照'
PARTITIONED BY (
  `ds` STRING NOT NULL COMMENT '分区日期 yyyyMMdd'
)
STORED AS AliOrc
LIFECYCLE 366;
