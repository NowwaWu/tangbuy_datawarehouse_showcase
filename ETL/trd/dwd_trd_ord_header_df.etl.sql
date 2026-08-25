--MaxCompute SQL
--********************************************************************--
--author: 吴延俊
--create time: 2026-05-09 11:03:39
-- 数据域:   trd (交易域)
-- 业务过程: ord (网站原生订单)
-- 表名:     dwd_trd_ord_header_df
-- 表类型:   明细事实表 (DWD Detail) - 累积快照
-- 描述:     网站原生订单主单累积快照，以 order_no 为粒度，
--           整合订单主表/子单汇总/支付汇总/退款汇总，
--           冗余用户维度(usr_nm/usr_email)和仓库维度(wh_nm)，
--           为下游 DWS/ADS 提供统一的网站原生订单主数据出口。
-- 粒度:     一行 = 一个网站原生订单 (order_no)
-- 来源:
--   ods_mysql_tang_order_t_order_ri          (订单主表, 驱动表)
--   ods_mysql_tang_order_t_order_item_ri     (子订单, 1:N→聚合汇总)
--   ods_mysql_tang_order_t_order_pay_ri      (支付, 1:N→聚合汇总)
--   ods_mysql_tang_order_t_order_refund_ri   (退款, 1:N→聚合汇总)
-- 维度冗余:
--   dim_usr_info_df       (LEFT JOIN usr_id → usr_nm, usr_email)
--   dim_wh_warehouse_df   (LEFT JOIN wh_id → wh_nm)
-- 更新策略: 当日增量(create_time OR update_time) FULL OUTER JOIN 昨日快照,
--           INSERT OVERWRITE 写入当日分区, 捕获订单创建及后续变更
-- 调度周期: 日
-- 调度变量: ${bizdate} 格式 yyyyMMdd
-- 防膨胀:
--   t_order_item 1:N → 聚合 SUM/COUNT 汇总到主单
--   t_order_pay  1:N → 聚合 SUM/COUNT/MAX 汇总到主单
--   t_order_refund 1:N → 聚合 SUM/COUNT/MAX 汇总到主单
-- 零NULL:
--   数值度量 → 0, ID → -99, 字符串 → '未知', JSON → '{}', 布尔 → 0, 时间保留 NULL
--********************************************************************--


WITH
-- -----------------------------------------------------------
-- CTE-1: 子订单聚合 (1:N → 1:1), 按 order_no 汇总商品件数/SKU数/金额
-- -----------------------------------------------------------
itm_agg AS (
    SELECT
        order_no,
        SUM(NVL(nums,           0))                                  AS itm_cnt,
        COUNT(DISTINCT NVL(sku_id, '-99'))                        AS itm_sku_cnt,
        cast(SUM(NVL(write_price , 0)
          * NVL(nums, 0) )  as decimal(18,4))                                         AS itm_ord_amt,
        cast(SUM(NVL(discount_amount , 0)) AS DECIMAL(18,4))         AS itm_disc_amt
    FROM demo_dw.ods_mysql_tang_order_t_order_item_ri
    GROUP BY order_no
),

-- -----------------------------------------------------------
-- CTE-2: 用户维度 (取前一天快照)
-- -----------------------------------------------------------
usr_dim AS (
    SELECT
        usr_id,
        usr_nm,
        email AS usr_email
    FROM demo_dw.dim_usr_info_df
    WHERE ds ='${bizdate}'
),

-- -----------------------------------------------------------
-- CTE-3: 仓库维度 (取前一天快照)
-- -----------------------------------------------------------
wh_dim AS (
    SELECT
        wh_id,
        wh_nm
    FROM demo_dw.dim_wh_warehouse_df
    WHERE ds ='${bizdate}'
),

-- -----------------------------------------------------------
-- CTE-4: 当日增量 (新建或更新的订单)
-- -----------------------------------------------------------
today_delta AS (
    SELECT
        -- 主键
        o.order_no                                      AS ord_no,
        o.user_id                                          AS usr_id,
        o.company_id                                 AS cmpny_id,
        -- 用户维度冗余
        u.usr_nm                                          AS usr_nm,
        u.usr_email                                     AS usr_email,
        -- 订单状态/类型
        NVL(o.order_status,                              -1)            AS ord_stat,
        NVL(o.order_type,                                -1)            AS ord_type_cd,
        NVL(o.brand_status,                               0)            AS brand_stat,
        -- 支付单号
        o.pay_no             AS pay_no,
        -- 采购/卖家
        o.seller_name              AS slr_nm,
        o.buyer                                            AS buyer_nm,
        o.order_buyer_id                                   AS buyer_id,
        o.order_buyer_post                               AS buyer_dept,
        -- 目的地
        o.destination        AS dst_cntry,
        CAST(o.destination_id AS BIGINT)             AS dst_cntry_id,
        -- 供应商店铺/来源
        o.store_source                                AS shop_src,
        o.store_name                                  AS splr_shop_nm,
        o.store_url                                   AS splr_shop_url,
        o.store_id                                    AS splr_shop_id,
        -- 仓库维度冗余
        o.storage_no         AS wh_id,
        w.wh_nm             AS wh_nm,
        -- 语言/币种
        o.order_language                             AS lang,
        o.order_currency                         AS ccy,
        -- 时间里程碑
        CAST(o.create_time  AS DATETIME)                                AS crt_time,
        CAST(o.pending_time AS DATETIME)                                AS pend_time,
        CAST(o.pay_time     AS DATETIME)                                AS pay_time,
        CAST(o.update_time  AS DATETIME)                                AS upd_time,
        -- 费用/金额度量 (订单级)
        NVL(CAST(o.pay_rate                  AS DECIMAL(18,4)), 0)     AS pay_rate,
        NVL(CAST(o.store_rebate              AS DECIMAL(18,4)), 0)     AS cmsn_rate,
        NVL(CAST(o.postage                   AS DECIMAL(18,4)), 0)     AS post_fee,
        NVL(CAST(o.postage_fil               AS DECIMAL(18,4)), 0)     AS post_xtra_fee,
        NVL(CAST(o.postage_need_fil          AS DECIMAL(18,4)), 0)     AS post_pend_xtra_fee,
        NVL(CAST(o.postage_return            AS DECIMAL(18,4)), 0)     AS post_ref_amt,
        NVL(CAST(o.fee_service               AS DECIMAL(18,4)), 0)     AS srv_fee,
        NVL(CAST(o.platform_technical_fee    AS DECIMAL(18,4)), 0)     AS tech_fee,
        NVL(CAST(o.platform_technical_fee_return AS DECIMAL(18,4)), 0) AS tech_fee_ref_amt,
        -- 商品汇总
        NVL(i.itm_cnt,                                 0)              AS itm_cnt,
        NVL(i.itm_sku_cnt,                             0)              AS itm_sku_cnt,
        NVL(i.itm_ord_amt,                             0)              AS itm_ord_amt,
        NVL(i.itm_disc_amt,                            0)              AS itm_disc_amt,
        -- 标记/扩展
        NVL(o.expedited,                               0)              AS is_expd,
        NVL(o.del_flag,                                0)              AS is_del,
        NVL(o.user_vip,                                0)              AS usr_vip_lvl,
       o.sys_tag                                     AS sys_tag,
        o.device                                      AS dev,
        NVL(o.merge_item,                         '{}')               AS merge_item_json,
        NVL(o.activity_discount,                  '{}')               AS acty_disc_json,
        -- 接单店铺（从xtn_json解析）
        GET_JSON_OBJECT(o.extend_field, '$.shopId')        AS shop_id,
        GET_JSON_OBJECT(o.extend_field, '$.shopUrl')       AS shop_url,
        GET_JSON_OBJECT(o.extend_field, '$.shopName')      AS shop_nm,
        GET_JSON_OBJECT(o.extend_field, '$.dataSource')    AS inner_data_src,
        NVL(o.extend_field,                       '{}')               AS xtn_json
    FROM demo_dw.ods_mysql_tang_order_t_order_ri          o
    LEFT JOIN itm_agg                             i  ON o.order_no    = i.order_no
    LEFT JOIN usr_dim                             u  ON o.user_id     = u.usr_id
    LEFT JOIN wh_dim                              w  ON o.storage_no  = w.wh_id
    WHERE (cast(o.create_time as datetime) >= TO_DATE('${bizdate}', 'yyyymmdd')
       AND cast(o.create_time as datetime) <  DATEADD(TO_DATE('${bizdate}', 'yyyymmdd'), 1, 'dd'))
       OR (cast(o.update_time as datetime) >= TO_DATE('${bizdate}', 'yyyymmdd')
       AND cast(o.update_time as datetime) <  DATEADD(TO_DATE('${bizdate}', 'yyyymmdd'), 1, 'dd'))
),

-- -----------------------------------------------------------
-- CTE-5: 昨日快照
-- -----------------------------------------------------------
yesterday AS (
    SELECT
        ord_no, usr_id, cmpny_id,
        usr_nm, usr_email,
        ord_stat, ord_type_cd, brand_stat,
        pay_no,
        slr_nm, buyer_nm, buyer_id, buyer_dept,
        dst_cntry, dst_cntry_id,
        shop_src, splr_shop_nm, splr_shop_url, splr_shop_id,
        wh_id, wh_nm,
        lang, ccy,
        crt_time, pend_time, pay_time, upd_time,
        pay_rate, cmsn_rate,
        post_fee, post_xtra_fee, post_pend_xtra_fee, post_ref_amt,
        srv_fee, tech_fee, tech_fee_ref_amt,
        itm_cnt, itm_sku_cnt, itm_ord_amt, itm_disc_amt,
        is_expd, is_del, usr_vip_lvl,
        sys_tag, dev,
                merge_item_json, acty_disc_json, shop_id, shop_url, shop_nm, inner_data_src, xtn_json
    FROM demo_dw.dwd_trd_ord_header_df
    WHERE ds = TO_CHAR(DATEADD(TO_DATE('${bizdate}', 'yyyymmdd'), -1, 'dd'), 'yyyymmdd')
)

-- -----------------------------------------------------------
-- 写入: 当日增量 FULL OUTER JOIN 昨日快照, COALESCE 取最新值
-- -----------------------------------------------------------
INSERT OVERWRITE TABLE demo_dw.dwd_trd_ord_header_df PARTITION (ds = '${bizdate}')
SELECT
    -- 主键
    NVL(t.ord_no,            y.ord_no)                               AS ord_no,
    NVL(t.usr_id,            y.usr_id)                               AS usr_id,
    NVL(t.cmpny_id,            y.cmpny_id)                               AS cmpny_id,
    -- 用户维度冗余 (新增当日用当日值, 已存在用昨日值兜底)
    COALESCE(t.usr_nm,        y.usr_nm)                              AS usr_nm,
    COALESCE(t.usr_email,     y.usr_email)                           AS usr_email,
    -- 订单状态/类型
    COALESCE(t.ord_stat,      y.ord_stat)                            AS ord_stat,
    COALESCE(t.ord_type_cd,   y.ord_type_cd)                         AS ord_type_cd,
    COALESCE(t.brand_stat,    y.brand_stat)                          AS brand_stat,
    -- 支付单号
    COALESCE(t.pay_no,        y.pay_no)                              AS pay_no,
    -- 采购/卖家
    COALESCE(t.slr_nm,        y.slr_nm)                              AS slr_nm,
    COALESCE(t.buyer_nm,      y.buyer_nm)                            AS buyer_nm,
    COALESCE(t.buyer_id,      y.buyer_id)                            AS buyer_id,
    COALESCE(t.buyer_dept,    y.buyer_dept)                          AS buyer_dept,
    -- 目的地
    COALESCE(t.dst_cntry,     y.dst_cntry)                           AS dst_cntry,
    COALESCE(t.dst_cntry_id,  y.dst_cntry_id)                        AS dst_cntry_id,
    -- 供应商店铺/来源
    COALESCE(t.shop_src,     y.shop_src)                           AS shop_src,
    COALESCE(t.splr_shop_nm,      y.splr_shop_nm)                  AS splr_shop_nm,
    COALESCE(t.splr_shop_url,     y.splr_shop_url)                 AS splr_shop_url,
    COALESCE(t.splr_shop_id,      y.splr_shop_id)                  AS splr_shop_id,
    -- 仓库维度冗余
    COALESCE(t.wh_id,         y.wh_id)                               AS wh_id,
    COALESCE(t.wh_nm,         y.wh_nm)                               AS wh_nm,
    -- 语言/币种
    COALESCE(t.lang,          y.lang)                                AS lang,
    COALESCE(t.ccy,           y.ccy)                                 AS ccy,
    -- 时间里程碑 (更新时间用新的, 创建/接单/支付时间保留最早的)
    NVL(t.crt_time,           y.crt_time)                            AS crt_time,
    NVL(t.pend_time,          y.pend_time)                           AS pend_time,
    NVL(t.pay_time,           y.pay_time)                            AS pay_time,
    COALESCE(t.upd_time,      y.upd_time)                            AS upd_time,
    -- 费用/金额度量
    COALESCE(t.pay_rate,           y.pay_rate)                       AS pay_rate,
    COALESCE(t.cmsn_rate,           y.cmsn_rate)                       AS cmsn_rate,
    COALESCE(t.post_fee,           y.post_fee)                       AS post_fee,
    COALESCE(t.post_xtra_fee,       y.post_xtra_fee)                   AS post_xtra_fee,
    COALESCE(t.post_pend_xtra_fee,  y.post_pend_xtra_fee)              AS post_pend_xtra_fee,
    COALESCE(t.post_ref_amt,       y.post_ref_amt)                   AS post_ref_amt,
    COALESCE(t.srv_fee,           y.srv_fee)                       AS srv_fee,
    COALESCE(t.tech_fee,           y.tech_fee)                       AS tech_fee,
    COALESCE(t.tech_fee_ref_amt,   y.tech_fee_ref_amt)               AS tech_fee_ref_amt,
    -- 商品汇总
    COALESCE(t.itm_cnt,            y.itm_cnt)                        AS itm_cnt,
    COALESCE(t.itm_sku_cnt,        y.itm_sku_cnt)                    AS itm_sku_cnt,
    COALESCE(t.itm_ord_amt,        y.itm_ord_amt)                    AS itm_ord_amt,
    COALESCE(t.itm_disc_amt,       y.itm_disc_amt)                   AS itm_disc_amt,
    -- 标记/扩展
    COALESCE(t.is_expd,            y.is_expd)                        AS is_expd,
    COALESCE(t.is_del,             y.is_del)                         AS is_del,
    COALESCE(t.usr_vip_lvl,        y.usr_vip_lvl)                    AS usr_vip_lvl,
    COALESCE(t.sys_tag,            y.sys_tag)                        AS sys_tag,
    COALESCE(t.dev,             y.dev)                         AS dev,
    COALESCE(t.merge_item_json,    y.merge_item_json)                AS merge_item_json,
    COALESCE(t.acty_disc_json,      y.acty_disc_json)                  AS acty_disc_json,
        COALESCE(t.shop_id,       y.shop_id)                         AS shop_id,
    COALESCE(t.shop_url,      y.shop_url)                            AS shop_url,
    COALESCE(t.shop_nm,       y.shop_nm)                             AS shop_nm,
    COALESCE(t.inner_data_src,      y.inner_data_src)                  AS inner_data_src,
    COALESCE(t.xtn_json,           y.xtn_json)                       AS xtn_json
FROM today_delta     t
FULL OUTER JOIN yesterday y ON t.ord_no = y.ord_no
;
