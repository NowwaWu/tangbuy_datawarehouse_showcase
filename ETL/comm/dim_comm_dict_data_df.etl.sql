-- ============================================================
-- 数据域:   comm (公共域)
-- 业务过程: cfg_mgr (配置管理)
-- 表名:     dim_comm_dict_data_df
-- 表类型:   维度表 - 日全量快照
-- ETL方式:  INSERT OVERWRITE, _ri 全量快照直写
-- 调度变量: ${bizdate} 格式 yyyyMMdd
-- ============================================================

INSERT OVERWRITE TABLE dim_comm_dict_data_df PARTITION (ds = '${bizdate}')
SELECT
    d.dict_code                    AS dict_cd
    ,d.dict_sort                      AS dict_sort_order
    ,d.dict_label                  AS dict_label
    ,d.dict_value                  AS dict_val
    ,d.dict_type                  AS dict_type_cd
    ,d.css_class                  AS css_class
    ,d.list_class                  AS list_class
    ,CASE WHEN LOWER(CAST(d.is_default AS STRING)) IN ('1','true','y','yes') THEN 1 ELSE 0 END AS is_dflt
    ,CASE WHEN CAST(d.status AS STRING) RLIKE '^-?[0-9]+$' THEN CAST(d.status AS BIGINT) ELSE -1 END AS dict_stat
    ,d.create_by                  AS crt_usr
    ,CAST(d.create_time AS DATETIME)                                AS crt_time
    ,d.update_by                  AS upd_usr
    ,CAST(d.update_time AS DATETIME)                                AS upd_time
    ,d.remark                  AS rmk
FROM    ods_mysql_tang_resource_r_dict_data_ri d
;
