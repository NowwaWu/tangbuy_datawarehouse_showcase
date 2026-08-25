--MaxCompute SQL
--********************************************************************--
--author: 吴延俊
--create time: 2026-05-13 11:32:32
-- 数据域:   pay (支付结算域)
-- 业务过程: exch_rate (汇率)
-- 表名:     dim_pay_exch_rate_df
-- 表类型:   维度表 (Dimension) - 日全量快照
-- 描述:     币种兑换汇率维度表，支持多币种兑人民币(CNY)汇率查询
--           汇率优先级：pub_rate(银行公开) > fin_rate(财务设置) > exch_rate(综合)
--           发行量较小币种(TRY/COP/DKK/NOK) 无汇率时使用历史经验值兜底
-- 来源:     ods_mysql_tang_pay_pay_exchange_rate_ri (汇率配置主表)
-- 调度周期: 日
-- 关联:     本表 rate_id 对应 dim_pay_channel_df.rate_id
-- 下游注意: 通过 ccy_stat = 1 过滤启用币种
--********************************************************************--


WITH
-- -----------------------------------------------------------
-- CTE-1: 按币种去重取最新 (同一币种存在多语言行)
-- -----------------------------------------------------------
rate_latest AS (
    SELECT
        id,
        currency,
        symbol,
        language,
        exchange_currency,
        public_fx_rate,
        follow_rate,
        rate,
        sort,
        show_location,
        status,
        system_update_time,
        update_by,
        update_time
    FROM (
        SELECT
            id,
            currency,
            symbol,
            language,
            exchange_currency,
            CAST(public_fx_rate     AS DECIMAL(18,6))  AS public_fx_rate,
            CAST(follow_rate        AS DECIMAL(18,6))  AS follow_rate,
            CAST(rate               AS DECIMAL(18,6))  AS rate,
            sort,
            show_location,
            status,
            CAST(system_update_time AS DATETIME)       AS system_update_time,
            update_by,
            CAST(update_time        AS DATETIME)       AS update_time,
            ROW_NUMBER() OVER (
                PARTITION BY currency
                ORDER BY update_time DESC, id DESC
            ) AS rn
        FROM demo_dw.ods_mysql_tang_pay_pay_exchange_rate_ri
    ) t
    WHERE t.rn = 1
)

INSERT OVERWRITE TABLE demo_dw.dim_pay_exch_rate_df PARTITION (ds = '${bizdate}')
SELECT
    -- 主键
    NVL(r.id,                       -99)                    AS rate_id,
    -- 币种信息
    NVL(r.currency,                 '未知')                 AS ccy_cd,
    NVL(r.symbol,                   '未知')                 AS ccy_symbol,
    NVL(r.language,                 '未知')                 AS ccy_lang,
    NVL(r.exchange_currency,        '未知')                 AS exch_ccy,
    -- 三级汇率
    NVL(r.public_fx_rate,                    0)             AS pub_rate,
    NVL(r.follow_rate,                       0)             AS fin_rate,
    NVL(r.rate,                              0)             AS exch_rate,
    -- 生效汇率：优先级 pub_rate > fin_rate > exch_rate > 兜底
    -- 兜底: TRY=0.164, COP=0.0019, DKK=1.11, NOK=0.701,
    --       AED=1.855, ARS=0.0049, CLP=0.0076, CZK=0.329, HUF=0.0226, PEN=1.984, UYU=0.171
    -- Reviewer Fix: 去除冗余CAST (CTE中已CAST为DECIMAL(18,6))
    CASE
        WHEN r.public_fx_rate IS NOT NULL AND r.public_fx_rate > 0 THEN r.public_fx_rate
        WHEN r.follow_rate   IS NOT NULL AND r.follow_rate   > 0 THEN r.follow_rate
        WHEN r.rate          IS NOT NULL AND r.rate          > 0 THEN r.rate
        WHEN r.currency = 'TRY' THEN 0.164
        WHEN r.currency = 'COP' THEN 0.0019
        WHEN r.currency = 'DKK' THEN 1.11
        WHEN r.currency = 'NOK' THEN 0.701
        WHEN r.currency = 'AED' THEN 1.855
        WHEN r.currency = 'ARS' THEN 0.0049
        WHEN r.currency = 'CLP' THEN 0.0076
        WHEN r.currency = 'CZK' THEN 0.329
        WHEN r.currency = 'HUF' THEN 0.0226
        WHEN r.currency = 'PEN' THEN 1.984
        WHEN r.currency = 'UYU' THEN 0.171
        ELSE 0
    END                                                         AS pref_rate,
    -- 汇率来源标识
    CASE
        WHEN r.public_fx_rate IS NOT NULL AND r.public_fx_rate > 0
            THEN 'PUB'
        WHEN r.follow_rate IS NOT NULL AND r.follow_rate > 0
            THEN 'FIN'
        WHEN r.rate IS NOT NULL AND r.rate > 0
            THEN 'RATE'
        WHEN r.currency IN ('TRY', 'COP', 'DKK', 'NOK', 'AED', 'ARS', 'CLP', 'CZK', 'HUF', 'PEN', 'UYU')
            THEN 'FALLBACK'
        ELSE 'NONE'
    END                                                         AS rate_src_cd,
    -- 展示/状态
    NVL(r.sort,                             0)                  AS sort_num,
    NVL(r.show_location,                    0)                  AS show_loc_cd,
    NVL(r.status,                           0)                  AS ccy_stat,
    -- 时间
    -- Reviewer Fix: 增加DATETIME字段NVL兜底，对齐零NULL策略
    NVL(r.system_update_time,              CAST('1970-01-01' AS DATETIME))  AS pub_rate_upd_time,
    NVL(r.update_by,                       '未知')                          AS upd_by,
    NVL(r.update_time,                     CAST('1970-01-01' AS DATETIME))  AS upd_time
FROM rate_latest r
;
