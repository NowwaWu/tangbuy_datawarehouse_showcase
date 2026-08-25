--MaxCompute SQL
--********************************************************************--
--author: 吴延俊
--create time: 2026-06-10 00:00:00
-- 数据域:   pay (支付结算域)
-- 业务过程: pay (支付)
-- 表名:     dwd_pay_pay_rcd_di
-- 表类型:   明细事实表 (DWD Detail) - 事务事实
-- 描述:     用户资金侧成功支付事务流水，区分余额支付、充值支付和三方渠道支付。
-- 粒度:     一行 = 一笔支付记录 (pay_payment.id)
-- 来源:
--   ods_mysql_tang_pay_pay_payment_ri          (支付记录, 驱动表)
--   ods_mysql_tang_pay_pay_transaction_ri      (交易账单, 判定资金支付账单成功)
--   ods_mysql_tang_pay_pay_recharge_record_ri  (充值记录, 标识充值支付)
--   ods_mysql_tang_pay_pay_payment_balance_ri  (余额支付扩展, 补充退款冻结金额)
-- 更新策略: 按支付发生时间 pay_time 取当日成功支付记录，INSERT OVERWRITE 写入当日分区
-- 调度周期: 日
-- 调度变量: ${bizdate} 格式 yyyyMMdd
-- 零NULL:   数值度量 → 0, ID → -99, 字符串枚举 → 'UNKNOWN', 时间保留 NULL
--********************************************************************--


WITH
-- -----------------------------------------------------------
-- CTE-1: 余额支付扩展按支付记录聚合，避免1:N膨胀
-- -----------------------------------------------------------
bal_ext AS (
    SELECT
        payment_id,
        CAST(SUM(NVL(refund_freeze, 0)) AS DECIMAL(18,4)) AS ref_frz_amt
    FROM demo_dw.ods_mysql_tang_pay_pay_payment_balance_ri
    GROUP BY payment_id
),

-- -----------------------------------------------------------
-- CTE-2: 成功充值记录，用于标识充值支付
-- -----------------------------------------------------------
rchg_succ AS (
    SELECT
        trade_no
    FROM demo_dw.ods_mysql_tang_pay_pay_recharge_record_ri
    WHERE status = 1
),

-- -----------------------------------------------------------
-- CTE-3: 资金侧成功支付事件
-- -----------------------------------------------------------
pay_base AS (
    SELECT
        p.id                                                      AS pay_rcd_id,
        t.id                                                      AS txn_id,
        t.transaction_no                                          AS txn_no,
        t.business_no                                             AS biz_no,
        p.trade_no                                                AS trade_no,
        p.serial_no                                               AS out_trade_no,
        p.prepay_no                                               AS prepay_no,
        COALESCE(p.user_id, t.user_id)                            AS usr_id,
        COALESCE(p.business_type, t.business_type)                AS biz_type_cd,
        t.record_type                                             AS rcd_type_cd,
        t.trade_type                                              AS trade_type_cd,
        CASE
            WHEN UPPER(NVL(p.pay_way, '')) = 'BALANCE' THEN 'BALANCE'
            WHEN r.trade_no IS NOT NULL THEN 'RECHG'
            WHEN p.pay_way IS NOT NULL THEN 'THIRD'
            ELSE 'UNKNOWN'
        END                                                       AS pay_src_cd,
        p.pay_way                                                 AS pay_mtd_cd,
        p.payment_type                                            AS paypal_pay_mtd_cd,
        p.currency                                                AS ccy,
        CAST(p.amount AS DECIMAL(18,4))                           AS ccy_amt,
        CAST(p.trade_amount AS DECIMAL(18,4))                     AS pay_amt,
        CAST(p.off_amount AS DECIMAL(18,4))                       AS pay_disc_amt,
        CAST(p.currency_off_amount AS DECIMAL(18,4))              AS pay_ccy_disc_amt,
        CAST(p.fee AS DECIMAL(18,4))                              AS pay_fee,
        CAST(p.fixed_loss AS DECIMAL(18,4))                       AS fixed_loss_amt,
        CAST(p.fx_rate AS DECIMAL(18,6))                          AS fx_rate,
        CAST(p.before_balance AS DECIMAL(18,4))                   AS bal_before_amt,
        CAST(p.balance AS DECIMAL(18,4))                          AS bal_after_amt,
        b.ref_frz_amt                                             AS ref_frz_amt,
        t.status                                                  AS txn_stat,
        p.status                                                  AS pay_stat,
        p.call_status                                             AS call_stat,
        p.quick_pay                                               AS quick_pay_cd,
        CASE WHEN UPPER(NVL(p.pay_way, '')) = 'BALANCE' THEN 1 ELSE 0 END AS is_bal_pay,
        CASE WHEN r.trade_no IS NOT NULL THEN 1 ELSE 0 END        AS is_rechg_pay,
        CASE WHEN t.status = 3 THEN 1 ELSE 0 END                  AS is_succ,
        COALESCE(
            CAST(p.trade_time AS DATETIME),
            CAST(p.notify_time AS DATETIME),
            CAST(t.update_time AS DATETIME),
            CAST(p.update_time AS DATETIME),
            CAST(p.create_time AS DATETIME)
        )                                                         AS pay_time,
        CAST(p.trade_time AS DATETIME)                            AS trade_time,
        CAST(p.notify_time AS DATETIME)                           AS ntfy_time,
        CAST(p.create_time AS DATETIME)                           AS crt_time,
        CAST(p.update_time AS DATETIME)                           AS upd_time,
        p.payer_id                                                AS payer_id,
        p.payer_account                                           AS payer_acct,
        p.remark                                                  AS rmk,
        p.memo                                                    AS memo
    FROM demo_dw.ods_mysql_tang_pay_pay_payment_ri p
    INNER JOIN demo_dw.ods_mysql_tang_pay_pay_transaction_ri t
      ON p.transaction_id = t.id
    LEFT JOIN rchg_succ r
      ON p.trade_no = r.trade_no
    LEFT JOIN bal_ext b
      ON p.id = b.payment_id
    WHERE t.record_type = 1
      AND t.status = 3
)

INSERT OVERWRITE TABLE demo_dw.dwd_pay_pay_rcd_di PARTITION (ds = '${bizdate}')
SELECT
    NVL(pay_rcd_id,                -99)                          AS pay_rcd_id,
    NVL(txn_id,                    -99)                          AS txn_id,
    NVL(txn_no,                  '-99')                          AS txn_no,
    NVL(biz_no,                  '-99')                          AS biz_no,
    NVL(trade_no,                '-99')                          AS trade_no,
    NVL(out_trade_no,            '-99')                          AS out_trade_no,
    NVL(prepay_no,               '-99')                          AS prepay_no,
    NVL(usr_id,                    -99)                          AS usr_id,
    NVL(biz_type_cd,                -1)                          AS biz_type_cd,
    NVL(rcd_type_cd,             -1)                          AS rcd_type_cd,
    NVL(trade_type_cd,              -1)                          AS trade_type_cd,
    NVL(pay_src_cd,          'UNKNOWN')                          AS pay_src_cd,
    UPPER(NVL(pay_mtd_cd,       'UNKNOWN'))                         AS pay_mtd_cd,
    UPPER(NVL(paypal_pay_mtd_cd,'UNKNOWN'))                         AS paypal_pay_mtd_cd,
    UPPER(NVL(ccy,           'UNKNOWN'))                         AS ccy,
    NVL(ccy_amt,                    0)                           AS ccy_amt,
    NVL(pay_amt,                    0)                           AS pay_amt,
    NVL(pay_disc_amt,               0)                           AS pay_disc_amt,
    NVL(pay_ccy_disc_amt,           0)                           AS pay_ccy_disc_amt,
    NVL(pay_fee,                    0)                           AS pay_fee,
    NVL(fixed_loss_amt,             0)                           AS fixed_loss_amt,
    NVL(fx_rate,                    0)                           AS fx_rate,
    NVL(bal_before_amt,             0)                           AS bal_before_amt,
    NVL(bal_after_amt,              0)                           AS bal_after_amt,
    NVL(ref_frz_amt,                0)                           AS ref_frz_amt,
    NVL(txn_stat,                  -1)                           AS txn_stat,
    NVL(pay_stat,                  -1)                           AS pay_stat,
    NVL(call_stat,                 -1)                           AS call_stat,
    NVL(quick_pay_cd,              -1)                           AS quick_pay_cd,
    NVL(is_bal_pay,                 0)                           AS is_bal_pay,
    NVL(is_rechg_pay,               0)                           AS is_rechg_pay,
    NVL(is_succ,                    0)                           AS is_succ,
    pay_time                                                     AS pay_time,
    trade_time                                                   AS trade_time,
    ntfy_time                                                    AS ntfy_time,
    crt_time                                                     AS crt_time,
    upd_time                                                     AS upd_time,
    NVL(payer_id,                '-99')                          AS payer_id,
    NVL(payer_acct,          'UNKNOWN')                          AS payer_acct,
    NVL(rmk,                       '')                           AS rmk,
    NVL(memo,                      '')                           AS memo
FROM pay_base
WHERE pay_time >= TO_DATE('${bizdate}', 'yyyymmdd')
  AND pay_time <  DATEADD(TO_DATE('${bizdate}', 'yyyymmdd'), 1, 'dd')
;
