INSERT OVERWRITE TABLE dwd_demo_order_line_di PARTITION(ds='${bizdate}')
SELECT
    order_line_id,
    shop_id,
    country_code,
    CAST(paid_amount AS DECIMAL(18, 4)) AS paid_amount,
    CAST(paid_at AS DATETIME) AS paid_at
FROM ods_demo_order_line_di
WHERE ds = '${bizdate}';
