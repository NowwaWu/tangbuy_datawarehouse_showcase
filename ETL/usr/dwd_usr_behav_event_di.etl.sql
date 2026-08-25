--MaxCompute SQL
--********************************************************************--
--author: 吴延俊
--create time: 2026-05-21 18:51:50
-- 数据域:   usr (用户域)
-- 业务过程: behav (用户行为埋点)
-- 表名:     dwd_usr_behav_event_di
-- 表类型:   事务事实表 (DWD Detail) - 日增量
-- ETL方式:  读取当日 ODS 增量分区, GET_JSON_OBJECT 提取设备/地域/应用/流量/隐私维度,
--           REGEXP_EXTRACT 提取事件参数与用户属性中的常用分析字段, INSERT OVERWRITE 写入当日分区
-- 调度变量: ${bizdate} 格式 yyyyMMdd
-- 零NULL:
--   数值度量 → 0, ID → -99, 字符串 → '未知', JSON → '{}', 时间保留 NULL
-- 依赖:     ods_google_firebase_events_di (当日分区 ds=${bizdate})
--********************************************************************--
USE prod
;

INSERT OVERWRITE TABLE dwd_usr_behav_event_di PARTITION(ds='${bizdate}')
SELECT
    -- 核心事件字段
    event_date
    ,CAST(FROM_UNIXTIME(CAST(event_timestamp / 1000000 AS BIGINT)) AS DATETIME) AS event_time
    ,HOUR(FROM_UNIXTIME(CAST(event_timestamp / 1000000 AS BIGINT))) AS event_hour
    ,event_name                                        AS event_nm
    ,'FIREBASE'                                                     AS src_cd
    ,user_pseudo_id                                    AS usr_pseudo_id
    ,user_id                                           AS usr_id
    ,platform                                          AS pltf_cd
    ,stream_id                                            AS stream_id
    ,CASE   WHEN stream_id = 12023371567 THEN 'TANGBUY-DS-WEB'
     WHEN stream_id = 10108868892 THEN 'TANGBUY-IOS'
     WHEN stream_id = 14980159443 THEN 'TANGBUY-EASYBRANDKIT-WEB'
     WHEN stream_id = 10090785743 THEN 'TANGBUY-WEB'
     WHEN stream_id = 14277570083 THEN 'TANGBUY-DS-IOS'
     WHEN stream_id = 10252076131 THEN 'TANGBUY-ANDROID'
     ELSE 'UNKNOWN'
    END AS stream_nm
    ,event_value_in_usd                                     AS event_usd_amt

    -- === 从 event_params_json 提取会话/参与/批次字段 ===
    ,CAST(REGEXP_EXTRACT(event_params_json, '"key":"ga_session_id","value":[{]"string_value":null,"int_value":"?([0-9]+)"?', 1) AS BIGINT) AS sess_id
    ,CAST(REGEXP_EXTRACT(event_params_json, '"key":"ga_session_number","value":[{]"string_value":null,"int_value":"?([0-9]+)"?', 1) AS BIGINT) AS sess_seq_no
    ,CAST(COALESCE(
        REGEXP_EXTRACT(event_params_json, '"key":"session_engaged","value":[{]"string_value":"([0-9]+)"', 1),
        REGEXP_EXTRACT(event_params_json, '"key":"session_engaged","value":[{]"string_value":null,"int_value":"?([0-9]+)"?', 1)
    ) AS BIGINT) AS is_sess_engaged
    ,CAST(REGEXP_EXTRACT(event_params_json, '"key":"engaged_session_event","value":[{]"string_value":null,"int_value":"?([0-9]+)"?', 1) AS BIGINT) AS is_engaged_sess_event
    ,CAST(REGEXP_EXTRACT(event_params_json, '"key":"engagement_time_msec","value":[{]"string_value":null,"int_value":"?([0-9]+)"?', 1) AS BIGINT) AS engage_time_ms
    ,CAST(REGEXP_EXTRACT(event_params_json, '"key":"entrances","value":[{]"string_value":null,"int_value":"?([0-9]+)"?', 1) AS BIGINT) AS entrance_cnt
    ,REGEXP_EXTRACT(event_params_json, '"key":"batch_page_id","value":[{]"string_value":null,"int_value":"?([^",}]*)"?', 1) AS batch_page_id
    ,CAST(REGEXP_EXTRACT(event_params_json, '"key":"batch_ordering_id","value":[{]"string_value":null,"int_value":"?([0-9]+)"?', 1) AS BIGINT) AS batch_seq_no
    ,REGEXP_EXTRACT(event_params_json, '"key":"origin","value":[{]"string_value":"([^"]*)"', 1) AS event_orig_cd

    -- === 从 event_params_json 提取 (COALESCE: WEB page_* / 移动端 firebase_screen_*) ===
    ,COALESCE(
        REGEXP_EXTRACT(event_params_json, '"key":"page_title","value":[{]"string_value":"([^"]*)"', 1),
        REGEXP_EXTRACT(event_params_json, '"key":"firebase_screen","value":[{]"string_value":"([^"]*)"', 1)
    )                                                                                     AS view_nm
    ,REGEXP_EXTRACT(event_params_json, '"key":"page_location","value":[{]"string_value":"([^"]*)"', 1)   AS view_url
    ,REGEXP_EXTRACT(event_params_json, '"key":"page_path","value":[{]"string_value":"([^"]*)"', 1) AS page_path
    ,REGEXP_EXTRACT(event_params_json, '"key":"page_referrer","value":[{]"string_value":"([^"]*)"', 1) AS page_referrer_url
    ,REGEXP_EXTRACT(event_params_json, '"key":"firebase_screen_class","value":[{]"string_value":"([^"]*)"', 1)    AS view_class
    ,REGEXP_EXTRACT(event_params_json, '"key":"firebase_screen_id","value":[{]"string_value":null,"int_value":"?([^",}]*)"?', 1) AS view_id
    ,REGEXP_EXTRACT(event_params_json, '"key":"firebase_previous_screen","value":[{]"string_value":"([^"]*)"', 1) AS prev_view_nm
    ,REGEXP_EXTRACT(event_params_json, '"key":"firebase_previous_class","value":[{]"string_value":"([^"]*)"', 1)  AS prev_view_class
    ,REGEXP_EXTRACT(event_params_json, '"key":"firebase_previous_id","value":[{]"string_value":null,"int_value":"?([^",}]*)"?', 1) AS prev_view_id
    ,REGEXP_EXTRACT(event_params_json, '"key":"firebase_event_origin","value":[{]"string_value":"([^"]*)"', 1) AS firebase_event_orig_cd
    ,REGEXP_EXTRACT(event_params_json, '"key":"source","value":[{]"string_value":"([^"]*)"', 1) AS event_src_nm
    ,REGEXP_EXTRACT(event_params_json, '"key":"medium","value":[{]"string_value":"([^"]*)"', 1) AS event_medium
    ,REGEXP_EXTRACT(event_params_json, '"key":"campaign","value":[{]"string_value":"([^"]*)"', 1) AS event_acty_nm
    ,REGEXP_EXTRACT(event_params_json, '"key":"gclid","value":[{]"string_value":"([^"]*)"', 1) AS gclid
    ,REGEXP_EXTRACT(event_params_json, '"key":"gad_source","value":[{]"string_value":"([^"]*)"', 1) AS gad_src_cd
    ,REGEXP_EXTRACT(event_params_json, '"key":"gad_campaignid","value":[{]"string_value":"([^"]*)"', 1) AS gad_acty_id

    -- === 从 user_properties_json 提取 ===
    ,COALESCE(
        REGEXP_EXTRACT(user_properties_json, '"key":"user_id","value":[{]"string_value":"([^"]*)"', 1),
        REGEXP_EXTRACT(user_properties_json, '"key":"user_id","value":[{]"string_value":null,"int_value":"?([^",}]*)"?', 1)
    ) AS attr_usr_id
    ,REGEXP_EXTRACT(user_properties_json, '"key":"share_code","value":[{]"string_value":"([^"]*)"', 1) AS shr_cd
    ,CAST(FROM_UNIXTIME(CAST(CAST(REGEXP_EXTRACT(user_properties_json, '"key":"first_open_time","value":[{]"string_value":null,"int_value":"?([0-9]+)"?', 1) AS BIGINT) / 1000 AS BIGINT)) AS DATETIME) AS first_open_time
    ,CAST(REGEXP_EXTRACT(user_properties_json, '"key":"ga_session_id","value":[{]"string_value":null,"int_value":"?([0-9]+)"?', 1) AS BIGINT) AS attr_sess_id
    ,CAST(REGEXP_EXTRACT(user_properties_json, '"key":"ga_session_number","value":[{]"string_value":null,"int_value":"?([0-9]+)"?', 1) AS BIGINT) AS attr_sess_seq_no
    ,CAST(FROM_UNIXTIME(CAST(CAST(REGEXP_EXTRACT(user_properties_json, '"key":"user_id".*?"set_timestamp_micros":"?([0-9]+)"?', 1) AS BIGINT) / 1000000 AS BIGINT)) AS DATETIME) AS attr_usr_id_set_time
    ,CAST(FROM_UNIXTIME(CAST(CAST(REGEXP_EXTRACT(user_properties_json, '"key":"share_code".*?"set_timestamp_micros":"?([0-9]+)"?', 1) AS BIGINT) / 1000000 AS BIGINT)) AS DATETIME) AS shr_cd_set_time
    ,CAST(FROM_UNIXTIME(CAST(CAST(REGEXP_EXTRACT(user_properties_json, '"key":"first_open_time".*?"set_timestamp_micros":"?([0-9]+)"?', 1) AS BIGINT) / 1000000 AS BIGINT)) AS DATETIME) AS first_open_set_time
    ,CAST(FROM_UNIXTIME(CAST(CAST(REGEXP_EXTRACT(user_properties_json, '"key":"ga_session_id".*?"set_timestamp_micros":"?([0-9]+)"?', 1) AS BIGINT) / 1000000 AS BIGINT)) AS DATETIME) AS attr_sess_set_time

    -- === 从 privacy_info_json 提取 ===
    ,GET_JSON_OBJECT(privacy_info_json, '$.analytics_storage') AS analytics_stor_cd
    ,GET_JSON_OBJECT(privacy_info_json, '$.ads_storage') AS ads_stor_cd
    ,GET_JSON_OBJECT(privacy_info_json, '$.uses_transient_token') AS uses_tmp_tkn_cd

    -- === 从 device_json 提取 ===
    ,GET_JSON_OBJECT(device_json, '$.category')            AS dev_ctgy
    ,GET_JSON_OBJECT(device_json, '$.mobile_brand_name')   AS dev_brand_nm
    ,GET_JSON_OBJECT(device_json, '$.mobile_model_name')   AS dev_model_nm
    ,GET_JSON_OBJECT(device_json, '$.operating_system')    AS dev_os_nm
    ,GET_JSON_OBJECT(device_json, '$.language')            AS dev_lang
    ,CAST(GET_JSON_OBJECT(device_json, '$.time_zone_offset_seconds') AS BIGINT) AS dev_tz_offset

    -- === 从 geo_json 提取 ===
    ,GET_JSON_OBJECT(geo_json, '$.country')               AS geo_cntry
    ,GET_JSON_OBJECT(geo_json, '$.region')                AS geo_rgn
    ,GET_JSON_OBJECT(geo_json, '$.city')                  AS geo_city

    -- === 从 app_info_json 提取 ===
    ,GET_JSON_OBJECT(app_info_json, '$.version')          AS app_ver
    ,GET_JSON_OBJECT(app_info_json, '$.firebase_app_id')  AS app_id
    ,GET_JSON_OBJECT(app_info_json, '$.app_store')        AS app_store_nm

    -- === 从 traffic_source_json 提取 ===
    ,GET_JSON_OBJECT(traffic_source_json, '$.source')    AS trfc_src_nm
    ,GET_JSON_OBJECT(traffic_source_json, '$.medium')    AS trfc_medium

    -- === 保留 JSON 兜底 ===
    ,CASE WHEN event_params_json IS NULL OR event_params_json = '' THEN '{}' ELSE event_params_json END AS event_params_json
    ,CASE WHEN user_properties_json IS NULL OR user_properties_json = '' THEN '{}' ELSE user_properties_json END AS usr_props_json
    ,CASE WHEN ecommerce_json IS NULL OR ecommerce_json = '' THEN '{}' ELSE ecommerce_json END AS ecommerce_json
    ,CASE WHEN items_json IS NULL OR items_json = '' THEN '{}' ELSE items_json END AS items_json
    ,CASE WHEN privacy_info_json IS NULL OR privacy_info_json = '' THEN '{}' ELSE privacy_info_json END AS priv_info_json
    ,event_dimensions_json                                 AS event_dim_json
    ,CAST(SUBSTR(bq_sync_time, 1, 19) AS DATETIME)         AS bq_sync_time

FROM ods_google_firebase_events_di
WHERE ds = '${bizdate}'
;
