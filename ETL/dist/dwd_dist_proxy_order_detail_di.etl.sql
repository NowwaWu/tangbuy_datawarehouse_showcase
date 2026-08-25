--@exclude_input=demo_dw.dim_usr_info_df
--@exclude_input=demo_dw.ods_mysql_tang_plugin_t_draft_order_package_ri
--@exclude_input=demo_dw.ods_mysql_tang_cps_b_share_order_detail_ri
--@exclude_input=demo_dw.ods_mysql_tang_plugin_t_order_outer_ri
--@exclude_input=demo_dw.ods_mysql_tang_plugin_t_draft_order_ri
--MaxCompute SQL
--********************************************************************--
--author: 吴延俊
--create time: 2026-05-07 10:42:33
--********************************************************************--
INSERT OVERWRITE TABLE demo_dw.dwd_dist_proxy_order_detail_di PARTITION (ds = '${bizdate}')
SELECT  s.id AS proxy_ord_detail_id
        ,s.promoter_id AS pmt_id
        ,pmt.usr_nm AS pmt_nm
        ,pmt.nick AS pmt_nick
        ,pmt.email AS pmt_email
        ,pmt.lvl_nm AS pmt_lvl_nm
        ,pmt.crt_time AS pmt_crt_time
        ,s.user_id AS usr_id
        ,usr.usr_nm AS usr_nm
        ,usr.nick AS usr_nick
        ,usr.email AS email
        ,usr.cntry_cd AS usr_cntry_cd
        ,usr.crt_time  AS usr_crt_time
        ,s.order_id AS ord_id
        ,s.package_no AS pkg_no
        ,oo.outer_order_id AS out_ord_id
        ,oo.outer_order_no AS out_ord_no
        ,oo.channel AS chnl
        ,oo.outer_shop_id AS out_shop_id
        ,oo.outer_shop_name AS out_shop_nm
        ,oo.outer_currency AS out_ccy
        ,nvl(CAST(oo.outer_order_amount AS DECIMAL(18,4)),0) AS out_ord_amt
        ,oo.outer_comment AS out_ord_rmk
        ,cast(oo.outer_create_time as datetime) AS out_ord_crt_time
        ,cast(oo.outer_update_time as datetime) AS out_ord_upd_time
        ,o.country AS cntry
        ,NVL(o.type,-1) AS ord_type_cd
        ,NVL(o.status,-1) AS ord_stat
        ,NVL(CAST(o.order_amount AS DECIMAL(18,4)),0) AS ord_amt
        ,NVL(CAST(o.purchase_amount AS DECIMAL(18,4)),0) AS pur_amt
        ,p.express_no AS exprs_no
        ,p.bz_no AS biz_no
        ,p.line_id AS line_id
        ,p.line_name AS line_nm
        ,p.logistic AS logis_nm
        ,NVL(CAST(p.weight AS DECIMAL(18,6)),0) AS pkg_wt
        ,NVL(CAST(p.weight_act AS DECIMAL(18,6)),0) AS pkg_wt_actl
        ,NVL(CAST(p.total_amount_pre AS DECIMAL(18,4)),0) AS pkg_amt_pre
        ,NVL(CAST(p.total_amount_act AS DECIMAL(18,4)),0) AS pkg_amt_actl
        ,NVL(CAST(p.fill_amount AS DECIMAL(18,4)),0) AS pkg_xtra_amt
        ,NVL(CAST(p.filled_amount AS DECIMAL(18,4)),0) AS pkg_xtra_paid_amt
        ,NVL(CAST(p.refund_amount AS DECIMAL(18,4)),0) AS pkg_ref_amt
        ,NVL(p.logistics_status,-1) AS logis_stat
        ,NVL(p.logistics_exception_status,-1) AS logis_abn_stat
        ,p.outer_fulfillment_id AS out_flfl_id
        ,NVL(CAST(s.pay_amount AS DECIMAL(18,4)),0) AS pay_amt
        ,NVL(CAST(s.refund_amount AS DECIMAL(18,4)),0) AS ref_amt
        ,NVL(CAST(s.extra_amount AS DECIMAL(18,4)),0) AS xtra_amt
        ,NVL(CAST(s.actual_amount AS DECIMAL(18,4)),0) AS actl_amt
        ,NVL(CAST(s.commission_amount AS DECIMAL(18,4)),0) AS cmsn_amt
        ,NVL(CAST(s.commission_ratio AS DECIMAL(18,6)),0) AS cmsn_rate
        ,cast(s.pay_time as datetime)
        ,cast(s.delivery_time as datetime) AS dly_time
        ,cast(s.create_time as datetime) AS crt_time
FROM    demo_dw.ods_mysql_tang_cps_b_share_order_detail_ri s
LEFT JOIN demo_dw.ods_mysql_tang_plugin_t_order_outer_ri oo
ON      s.order_id = oo.order_id
LEFT JOIN demo_dw.ods_mysql_tang_plugin_t_draft_order_ri o
ON      s.order_id = o.id
LEFT JOIN demo_dw.ods_mysql_tang_plugin_t_draft_order_package_ri p
ON      s.package_no = p.package_no
LEFT JOIN demo_dw.dim_usr_info_df pmt
ON      s.promoter_id = pmt.usr_id
AND     pmt.ds = '${bizdate}'
LEFT JOIN demo_dw.dim_usr_info_df usr
ON      s.user_id = usr.usr_id
AND     usr.ds = '${bizdate}'
WHERE   CAST(s.create_time AS DATETIME) >= CAST('${bizdate}' AS DATETIME)
AND     CAST(s.create_time AS DATETIME) < DATEADD(CAST('${bizdate}' AS DATETIME),1,'dd')
;
