--MaxCompute SQL
--********************************************************************--
--author: 吴延俊
--create time: 2026-05-09 14:51:39
--********************************************************************--

INSERT OVERWRITE TABLE demo_dw.dim_wh_warehouse_df PARTITION (ds = '${bizdate}')
SELECT  -- Reviewer Fix: 主键增加 NVL 兜底，防止脏数据产生 NULL 主键
        id AS wh_id
        ,name
       ,NULL AS wh_type_cd
        ,address AS addr
        ,NVL(capacity,0) AS capacity
        ,NVL(capacity_use,0) AS capacity_use
        ,NVL(full,0) AS is_full
        ,NVL(distribution,0) AS is_dflt_asgn
        ,CASE   WHEN status = 0 THEN 1
                ELSE 0
        END AS wh_stat
        ,create_by AS crt_usr -- Reviewer Note: ODS 无独立 del_flag，is_del 从 status 推导（假定 status=1=无效=已删除），与 wh_stat 线性相关
        ,CASE   WHEN status = 1 THEN 1
                ELSE 0
        END AS is_del -- Reviewer Fix: ODS TIMESTAMP → CAST AS DATETIME
        ,CAST(create_time AS DATETIME) AS crt_time
        ,CAST(update_time AS DATETIME) AS upd_time
FROM    demo_dw.ods_mysql_tang_storage_storage_ri
;
