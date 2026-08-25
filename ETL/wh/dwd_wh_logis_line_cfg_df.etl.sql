-- ============================================================
-- 数据域:   wh (仓储履约域)
-- 业务过程: logis_line (物流线路管理)
-- 表名:     dwd_wh_logis_line_cfg_df
-- 表类型:   DWD 配置全量快照
-- 粒度:     一行 = 一个物流线路配置记录(line_cfg_id)
-- 调度变量: ${bizdate} 格式 yyyyMMdd
-- 说明:
--   1. 三张 ODS 均为无 ds 分区的 RI 当前快照，每日全量覆盖目标分区。
--   2. 线路和国家均按 id 聚合，防止源异常重复放大配置行数；国家仅取 level=2。
--   3. 使用 LEFT JOIN 保留维度未匹配的线路配置，line_nm/cntry_nm 允许为空。
-- ============================================================

WITH delivery_line AS (
  SELECT
    id AS src_line_id,
    MAX(name_cn) AS line_nm
  FROM demo_dw.ods_mysql_tang_logistics_l_delivery_line_ri
  GROUP BY id
),
country AS (
  SELECT
    id AS cntry_id,
    MAX(name) AS cntry_nm
  FROM demo_dw.ods_mysql_tang_resource_r_data_region_ri
  WHERE level = 2
  GROUP BY id
)

INSERT OVERWRITE TABLE demo_dw.dwd_wh_logis_line_cfg_df PARTITION (ds = '${bizdate}')
SELECT
  l.id AS line_cfg_id,
  CAST(l.line_id AS STRING) AS line_id,
  dl.line_nm AS line_nm,
  CASE WHEN l.status = 1 THEN 1 ELSE 0 END AS is_line_on,
  l.trait_id AS trait_id,
  l.country_id AS cntry_id,
  c.cntry_nm AS cntry_nm,
  l.province_id AS prov_id,
  NVL(CAST(l.weight_min AS DECIMAL(18,4)), CAST(0 AS DECIMAL(18,4))) AS min_wt,
  NVL(CAST(l.weight_max AS DECIMAL(18,4)), CAST(0 AS DECIMAL(18,4))) AS max_wt,
  l.transit_time AS snd_day_scp,
  NVL(CAST(l.volume_base AS DECIMAL(18,4)), CAST(0 AS DECIMAL(18,4))) AS vol_wt_base,
  l.website AS site_url,
  NVL(CAST(l.weight_first AS DECIMAL(18,4)), CAST(0 AS DECIMAL(18,4))) AS first_wt,
  NVL(CAST(l.weight_continue AS DECIMAL(18,4)), CAST(0 AS DECIMAL(18,4))) AS cont_wt,
  NVL(CAST(l.fee_first AS DECIMAL(18,4)), CAST(0 AS DECIMAL(18,4))) AS first_frt_fee,
  NVL(CAST(l.fee_continue AS DECIMAL(18,4)), CAST(0 AS DECIMAL(18,4))) AS cont_frt_fee,
  NVL(CAST(l.fee_customs AS DECIMAL(18,4)), CAST(0 AS DECIMAL(18,4))) AS cstm_dcl_fee,
  NVL(CAST(l.fee_fuel AS DECIMAL(18,4)), CAST(0 AS DECIMAL(18,4))) AS fuel_fee,
  NVL(CAST(l.fee_service AS DECIMAL(18,4)), CAST(0 AS DECIMAL(18,4))) AS srv_fee,
  NVL(CAST(l.fee_operation AS DECIMAL(18,4)), CAST(0 AS DECIMAL(18,4))) AS opt_fee,
  NVL(l.declare_type, -1) AS dcl_type_cd,
  l.declare_currency AS dcl_ccy,
  CASE
    WHEN l.independent_config IS NULL OR TRIM(l.independent_config) = '' THEN '{}'
    ELSE l.independent_config
  END AS self_dcl_cfg_json,
  NVL(l.fee_type, -1) AS fee_type_cd,
  CASE
    WHEN l.declare_mode IS NULL OR TRIM(l.declare_mode) = '' THEN '[]'
    ELSE l.declare_mode
  END AS dcl_mtd_cd_json,
  CASE
    WHEN l.registration_type IS NULL OR TRIM(l.registration_type) = '' THEN '[]'
    ELSE l.registration_type
  END AS tax_reg_type_cd_json,
  l.features_cn AS line_trait_cn,
  l.features_en AS line_trait_en,
  l.forbid_cn AS ml_lmt_item_cn,
  l.forbid_en AS ml_lmt_item_en,
  NVL(CAST(l.edge_total_max AS DECIMAL(18,4)), CAST(0 AS DECIMAL(18,4))) AS edge_tot_max_sz,
  NVL(CAST(l.edge_long_max AS DECIMAL(18,4)), CAST(0 AS DECIMAL(18,4))) AS long_edge_max_sz,
  NVL(CAST(l.edge_short_max AS DECIMAL(18,4)), CAST(0 AS DECIMAL(18,4))) AS short_edge_max_sz,
  NVL(CAST(l.edge_tlong_max AS DECIMAL(18,4)), CAST(0 AS DECIMAL(18,4))) AS second_long_edge_max_sz,
  NVL(CAST(l.edge_dshort_total AS DECIMAL(18,4)), CAST(0 AS DECIMAL(18,4))) AS double_short_edge_tot_max_sz,
  NVL(CAST(l.edge_dshort_total_and_max AS DECIMAL(18,4)), CAST(0 AS DECIMAL(18,4))) AS double_short_edge_plus_long_max_sz,
  CASE
    WHEN l.weight_continue_special IS NULL OR TRIM(l.weight_continue_special) = '' THEN '[]'
    ELSE l.weight_continue_special
  END AS spcl_cont_wt_cfg_json,
  CAST(l.discount_start_time AS DATETIME) AS disc_start_time,
  CAST(l.discount_end_time AS DATETIME) AS disc_end_time,
  NVL(CAST(l.discount_rate AS DECIMAL(18,6)), CAST(0 AS DECIMAL(18,6))) AS disc_rate,
  CASE
    WHEN l.show_receiver IS NULL OR TRIM(l.show_receiver) = '' THEN '[]'
    ELSE l.show_receiver
  END AS show_rcv_cfg_json,
  NVL(l.permission, -1) AS line_auth_type_cd,
  CASE WHEN l.uid IS NULL OR TRIM(l.uid) = '' THEN '[]' ELSE l.uid END AS auth_usr_id_json,
  CASE WHEN l.vip IS NULL OR TRIM(l.vip) = '' THEN '[]' ELSE l.vip END AS auth_vip_lvl_json,
  NVL(CAST(l.weight_limit AS DECIMAL(18,4)), CAST(0 AS DECIMAL(18,4))) AS day_submit_wt_quota,
  NVL(CAST(l.cur_weight AS DECIMAL(18,4)), CAST(0 AS DECIMAL(18,4))) AS day_submit_wt,
  CASE
    WHEN l.providers_config IS NULL OR TRIM(l.providers_config) = '' THEN '{}'
    ELSE l.providers_config
  END AS splr_cfg_json,
  l.print_tip AS wh_print_tip,
  CASE WHEN l.invoice_print = 1 THEN 1 ELSE 0 END AS is_invc_print,
  CASE WHEN l.timeliness_status = 1 THEN 1 ELSE 0 END AS is_snd_timeliness_on,
  NVL(l.timeliness_start, 0) AS snd_start_day_cnt,
  NVL(l.timeliness_end, 0) AS snd_end_day_cnt,
  l.limit_user_tips_cn AS unauth_usr_tip_cn,
  l.limit_user_tips_en AS unauth_usr_tip_en,
  NVL(CAST(l.print_min_weight AS DECIMAL(18,4)), CAST(0 AS DECIMAL(18,4))) AS print_min_wt,
  NVL(CAST(l.print_max_weight AS DECIMAL(18,4)), CAST(0 AS DECIMAL(18,4))) AS print_max_wt,
  CASE WHEN l.forbid_area IS NULL OR TRIM(l.forbid_area) = '' THEN '[]' ELSE l.forbid_area END AS ml_lmt_rgn_json,
  l.forbid_code AS ml_lmt_zip,
  NVL(CAST(l.remote_fee AS DECIMAL(18,4)), CAST(0 AS DECIMAL(18,4))) AS remote_fee,
  l.remote_code AS remote_zip,
  NVL(CAST(l.tariff_fee AS DECIMAL(18,4)), CAST(0 AS DECIMAL(18,4))) AS cstm_tax_fee,
  l.tariff_currency AS cstm_tax_ccy,
  NVL(CAST(l.overlong_length AS DECIMAL(18,4)), CAST(0 AS DECIMAL(18,4))) AS overlong_len,
  NVL(CAST(l.overlong_fee AS DECIMAL(18,4)), CAST(0 AS DECIMAL(18,4))) AS overlong_fee,
  NVL(CAST(l.overweight_weight AS DECIMAL(18,4)), CAST(0 AS DECIMAL(18,4))) AS overweight_wt,
  NVL(CAST(l.overweight_fee AS DECIMAL(18,4)), CAST(0 AS DECIMAL(18,4))) AS overweight_fee,
  CASE WHEN l.only_real_weight = 1 THEN 1 ELSE 0 END AS is_actl_wt_only,
  NVL(l.package_limit, 0) AS day_pkg_quota,
  NVL(l.cur_package, 0) AS day_submit_pkg_cnt,
  NVL(CAST(l.overlong_girth AS DECIMAL(18,4)), CAST(0 AS DECIMAL(18,4))) AS overlong_girth_sz,
  NVL(CAST(l.overlong_girth_fee AS DECIMAL(18,4)), CAST(0 AS DECIMAL(18,4))) AS overlong_girth_fee,
  NVL(l.edge_dshort_total_type, -1) AS double_short_edge_plus_long_type_cd,
  CASE
    WHEN l.edge_dshort_total_config IS NULL OR TRIM(l.edge_dshort_total_config) = '' THEN '{}'
    ELSE l.edge_dshort_total_config
  END AS double_short_edge_plus_long_cfg_json,
  CASE WHEN l.need_check = 1 THEN 1 ELSE 0 END AS is_vld_required,
  CASE WHEN l.special_ioss IS NULL OR TRIM(l.special_ioss) = '' THEN '[]' ELSE l.special_ioss END AS spcl_ioss_acct_json,
  CASE WHEN l.send_limit IS NULL OR TRIM(l.send_limit) = '' THEN '[]' ELSE l.send_limit END AS snd_cnt_lmt_cfg_json,
  NVL(CAST(l.overlong_perimeter AS DECIMAL(18,4)), CAST(0 AS DECIMAL(18,4))) AS overlong_perimeter_sz,
  NVL(CAST(l.overlong_perimeter_fee AS DECIMAL(18,4)), CAST(0 AS DECIMAL(18,4))) AS overlong_perimeter_fee,
  CASE WHEN l.virtually_waybill = 1 THEN 1 ELSE 0 END AS is_vrtl_exprs_no,
  l.match_content AS trk_match_cnt,
  l.carrier_code AS carrier_cd,
  CASE WHEN l.overtime_status = 1 THEN 1 ELSE 0 END AS is_overdue_cmpstn_on,
  NVL(l.overtime_days, 0) AS overdue_cmpstn_day_cnt,
  CASE
    WHEN l.overtime_desc IS NULL OR TRIM(l.overtime_desc) = '' THEN '{}'
    ELSE l.overtime_desc
  END AS overdue_cmpstn_dtl_json
FROM demo_dw.ods_mysql_tang_logistics_l_line_config_ri l
LEFT JOIN delivery_line dl
  ON l.line_id = dl.src_line_id
LEFT JOIN country c
  ON l.country_id = c.cntry_id;
