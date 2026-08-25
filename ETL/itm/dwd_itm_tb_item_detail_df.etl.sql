-- ============================================================
-- 数据域:   itm (商品域)
-- 业务过程: prod_mgr (商品管理)
-- 表名:     dwd_itm_tb_item_detail_df
-- 表类型:   周期快照事实表 - 日全量
-- ETL方式:  INSERT OVERWRITE, _ri 全量快照, 按 tb_item_id 聚合标签列表
-- _df 合规: 源表 _ri 每日全量同步，当期快照天然剔除已删除记录，等效 FULL OUTER JOIN
-- 调度变量: ${bizdate} 格式 yyyyMMdd
-- ============================================================

INSERT OVERWRITE TABLE dwd_itm_tb_item_detail_df PARTITION (ds = '${bizdate}')
SELECT
    l.item_id                    AS tb_item_id
    ,l.tag_id_list                AS tag_id_list
    ,CAST(l.min_crt_time AS DATETIME)                              AS crt_time
    ,CAST(l.max_upd_time AS DATETIME)                              AS upd_time
FROM (
    SELECT  item_id
            ,COLLECT_SET(preferred_label_id)    AS tag_id_list
            ,MIN(create_time)                   AS min_crt_time
            ,MAX(update_time)                   AS max_upd_time
    FROM    ods_mysql_tang_product_preferred_product_label_ri
    WHERE   preferred_label_id IS NOT NULL
    GROUP BY item_id
) l
;
