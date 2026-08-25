-- ============================================================
-- 数据域:   itm (商品域)
-- 业务过程: prod_mgr (商品管理)
-- 表名:     dwd_itm_plt_subs_rel_df
-- 表类型:   事务事实表 - 日全量快照
-- ETL方式:  INSERT OVERWRITE, _ri 全量快照直写
-- _df 合规: 源表 _ri 每日全量同步，当期快照天然剔除已删除记录，等效 FULL OUTER JOIN
-- 调度变量: ${bizdate} 格式 yyyyMMdd
-- ============================================================

INSERT OVERWRITE TABLE dwd_itm_plt_subs_rel_df PARTITION (ds = '${bizdate}')
SELECT
    r.id                    AS id
    ,r.subscription_pallet_id                    AS subs_plt_id
    ,r.biz_id                    AS rel_biz_id
    ,r.biz_type                     AS rel_biz_type_cd
    ,r.del_flag                      AS is_del
    ,CAST(r.create_time AS DATETIME)                               AS crt_time
    ,CAST(r.update_time AS DATETIME)                               AS upd_time
FROM    ods_mysql_tang_product_subscription_pallet_relation_item_ri r
;
