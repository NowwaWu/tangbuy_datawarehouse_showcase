--MaxCompute SQL
--********************************************************************--
--author: 吴延俊
--create time: 2026-05-07 15:22:49
--********************************************************************--


INSERT OVERWRITE TABLE demo_dw.dwd_trd_order_operation_di PARTITION (ds = '${bizdate}')
SELECT
    id                                                               AS opt_id,
    NVL(item_id,   -99)                                              AS ord_line_no,
    NVL(create_by, '未知')                                           AS crt_usr,
    NVL(op_type,   '未知')                                           AS op_type_cd,
    NVL(REGEXP_EXTRACT(op_type,'([\\x{4e00}-\\x{9fa5}]+)'), '未知') AS op_type_cn,
    NVL(company_id, -99)                                             AS cmpny_id,
    cast(create_time as datetime)                                                     AS crt_time
FROM demo_dw.ods_mysql_tang_order_t_order_operation_ri
WHERE cast(create_time as datetime) >= TO_DATE('${bizdate}', 'yyyymmdd')
  AND cast(create_time as datetime) <  DATEADD(TO_DATE('${bizdate}', 'yyyymmdd'), 1, 'dd')
;
