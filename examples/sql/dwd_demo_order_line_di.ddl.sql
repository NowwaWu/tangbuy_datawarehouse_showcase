CREATE TABLE IF NOT EXISTS dwd_demo_order_line_di (
    order_line_id STRING COMMENT 'Synthetic order-line identifier',
    shop_id STRING COMMENT 'Synthetic shop identifier',
    country_code STRING COMMENT 'ISO-style demo country code',
    paid_amount DECIMAL(18, 4) COMMENT 'Demo paid amount',
    paid_at DATETIME COMMENT 'Demo payment time'
)
COMMENT 'Anonymized order-line example for the public showcase'
PARTITIONED BY (ds STRING COMMENT 'Business date in yyyyMMdd format');
