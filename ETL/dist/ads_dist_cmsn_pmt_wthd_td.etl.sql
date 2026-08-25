--MaxCompute SQL
--********************************************************************--
--author: 吴延俊
--create time: 2026-05-27 00:00:00
-- 数据集市: dist (分销集市)
-- 主题域:   cmsn (佣金)
-- 表名:     ads_dist_cmsn_pmt_wthd_td
-- 表类型:   ADS应用表 - 历史截至当日
-- 描述:     复刻Java pageCommissionStats结果，输出推广者佣金与提现汇总，供后续导出MySQL。
-- 来源:     测试环境ODS ods_mysql_test_tang_cps_*，当前不混用生产DWD。
-- 粒度:     一行 = 一个推广者
-- 调度周期: 日
--********************************************************************--

WITH
-- B端推广者主体，按holder_id取最新一条，避免多分享码导致结果膨胀
with_share AS
(
    SELECT  holder_id AS pmt_id
            ,holder_name AS holder_nm
    FROM    (
        SELECT  holder_id
                ,holder_name
                ,ROW_NUMBER() OVER(PARTITION BY holder_id ORDER BY update_time DESC, id DESC) AS rn
        FROM    demo_dw.ods_mysql_test_tang_cps_b_share_ri
        WHERE   holder_type = 2
        AND     holder_id IS NOT NULL
    ) t
    WHERE   rn = 1
)

-- 推广客户资料，按user_id取最新一条
,with_proxy_customer AS
(
    SELECT  user_id AS pmt_id
            ,user_name AS pmt_nm
            ,email AS pmt_email
            ,proxy_level AS pmt_lvl
    FROM    (
        SELECT  user_id
                ,user_name
                ,email
                ,proxy_level
                ,ROW_NUMBER() OVER(PARTITION BY user_id ORDER BY update_time DESC, id DESC) AS rn
        FROM    demo_dw.ods_mysql_test_tang_cps_proxy_customer_ri
        WHERE   user_id IS NOT NULL
    ) t
    WHERE   rn = 1
)

-- 订单佣金按推广者预聚合，保持与Java逻辑一致：delivery_time非空才计入佣金
,with_order_cmsn AS
(
    SELECT  promoter_id AS pmt_id
            ,SUM(NVL(CAST(commission_amount AS DECIMAL(18,4)), 0)) AS tot_cmsn_amt
            ,SUM(CASE WHEN CAST(delivery_time AS DATETIME) >= TO_DATE(CONCAT(SUBSTR('${bizdate}', 1, 6), '01'), 'yyyymmdd')
                       AND CAST(delivery_time AS DATETIME) <  DATEADD(TO_DATE(CONCAT(SUBSTR('${bizdate}', 1, 6), '01'), 'yyyymmdd'), 1, 'mm')
                      THEN NVL(CAST(commission_amount AS DECIMAL(18,4)), 0)
                      ELSE 0
                 END) AS curr_mth_cmsn_amt
    FROM    demo_dw.ods_mysql_test_tang_cps_b_share_order_detail_ri
    WHERE   delivery_time IS NOT NULL
    AND     promoter_id IS NOT NULL
    GROUP BY promoter_id
)

-- 提现金额按推广者预聚合，复刻Java状态口径：1=提现成功，0=审核中/待提现
,with_wthd AS
(
    SELECT  user_id AS pmt_id
            ,SUM(CASE WHEN status = 1 THEN NVL(CAST(amount AS DECIMAL(18,4)), 0) ELSE 0 END) AS wthd_succ_amt
            ,SUM(CASE WHEN status = 0 THEN NVL(CAST(amount AS DECIMAL(18,4)), 0) ELSE 0 END) AS wthd_pend_amt
    FROM    demo_dw.ods_mysql_test_tang_cps_b_share_withdraw_ri
    WHERE   user_id IS NOT NULL
    GROUP BY user_id
)

INSERT OVERWRITE TABLE demo_dw.ads_dist_cmsn_pmt_wthd_td PARTITION(ds='${bizdate}')
SELECT  s.pmt_id
        ,NVL(c.pmt_nm, NVL(s.holder_nm, '未知')) AS pmt_nm
        ,NVL(c.pmt_email, '未知') AS pmt_email
        ,NVL(c.pmt_lvl, -1) AS pmt_lvl
        ,CAST(NVL(o.tot_cmsn_amt, 0) AS DECIMAL(18,4)) AS tot_cmsn_amt
        ,CAST(NVL(o.curr_mth_cmsn_amt, 0) AS DECIMAL(18,4)) AS curr_mth_cmsn_amt
        ,CAST(NVL(w.wthd_succ_amt, 0) AS DECIMAL(18,4)) AS wthd_succ_amt
        ,CAST(NVL(w.wthd_pend_amt, 0) AS DECIMAL(18,4)) AS wthd_pend_amt
FROM    with_share s
JOIN    with_proxy_customer c
ON      s.pmt_id = c.pmt_id
LEFT JOIN with_order_cmsn o
ON      s.pmt_id = o.pmt_id
LEFT JOIN with_wthd w
ON      s.pmt_id = w.pmt_id
;
