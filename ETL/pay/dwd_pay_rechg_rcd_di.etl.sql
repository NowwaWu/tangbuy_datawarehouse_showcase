--MaxCompute SQL
--********************************************************************--
--author: 吴延俊
--create time: 2026-06-10 00:00:00
-- 数据域:   pay (支付结算域)
-- 业务过程: rechg (充值)
-- 表名:     dwd_pay_rechg_rcd_di
-- 表类型:   明细事实表 (DWD Detail) - 事务事实
-- 描述:     用户充值成功入账事务流水，以充值交易单号为粒度，保留支付方式、到账金额、手续费等资金字段。
-- 粒度:     一行 = 一笔成功充值记录 (pay_recharge_record.trade_no)
-- 来源:
--   ods_mysql_tang_pay_pay_recharge_record_ri   (充值记录, 驱动表)
--   ods_mysql_tang_pay_pay_payment_ri           (支付记录, 补充支付渠道/手续费/汇率)
--   ods_mysql_tang_pay_pay_transaction_ri       (交易账单, 补充账单类型/业务类型)
-- 更新策略: 按充值成功通知时间 notify_time 取当日成功记录，INSERT OVERWRITE 写入当日分区
-- 调度周期: 日
-- 调度变量: ${bizdate} 格式 yyyyMMdd
-- 零NULL:   数值度量 → 0, ID → -99, 字符串枚举 → 'UNKNOWN', 时间保留 NULL
--********************************************************************--


WITH
-- -----------------------------------------------------------
-- CTE-1: 支付记录补充字段 (trade_no 唯一)
-- -----------------------------------------------------------
pay_rcd AS (
    SELECT
        id,
        transaction_id,
        trade_no,
        serial_no,
        user_id,
        business_type,
        currency,
        fx_rate,
        fee,
        fixed_loss,
        pay_way,
        status,
        call_status,
        trade_time,
        notify_time,
        payer_account
    FROM demo_dw.ods_mysql_tang_pay_pay_payment_ri
),

-- -----------------------------------------------------------
-- CTE-2: 交易账单信息
-- -----------------------------------------------------------
txn AS (
    SELECT
        id,
        transaction_no,
        business_type,
        record_type,
        trade_type,
        user_id,
        status
    FROM demo_dw.ods_mysql_tang_pay_pay_transaction_ri
),

-- -----------------------------------------------------------
-- CTE-3: 成功充值事件，按充值通知时间归属分区
-- -----------------------------------------------------------
rchg_base AS (
    SELECT
        r.trade_no                                                AS rechg_no,
        p.id                                                      AS pay_rcd_id,
        t.id                                                      AS txn_id,
        t.transaction_no                                          AS txn_no,
        COALESCE(r.serial_no, p.serial_no)                        AS out_trade_no,
        COALESCE(r.user_id, t.user_id, p.user_id)                 AS usr_id,
        COALESCE(t.business_type, p.business_type)                AS biz_type_cd,
        t.record_type                                             AS rcd_type_cd,
        t.trade_type                                              AS trade_type_cd,
        COALESCE(r.pay_way, p.pay_way)                            AS pay_mtd_cd,
        r.payment_account                                         AS pay_acct,
        r.payer_id                                                AS payer_id,
        p.payer_account                                           AS payer_acct,
        p.currency                                                AS ccy,
        CAST(r.currency_amount AS DECIMAL(18,4))                  AS ccy_amt,
        CAST(r.amount AS DECIMAL(18,4))                           AS rechg_amt,
        CAST(r.trade_amount AS DECIMAL(18,4))                     AS rechg_actl_amt,
        CAST(r.withdraw_amount AS DECIMAL(18,4))                  AS wthd_amt,
        CAST(r.loss_amount AS DECIMAL(18,4))                      AS rechg_loss_amt,
        CAST(p.fee AS DECIMAL(18,4))                              AS pay_fee,
        CAST(p.fixed_loss AS DECIMAL(18,4))                       AS fixed_loss_amt,
        CAST(p.fx_rate AS DECIMAL(18,6))                          AS fx_rate,
        r.status                                                  AS rechg_stat,
        t.status                                                  AS txn_stat,
        p.status                                                  AS pay_stat,
        p.call_status                                             AS call_stat,
        CASE WHEN r.status = 1 THEN 1 ELSE 0 END                  AS is_succ,
        CAST(r.notify_time AS DATETIME)                           AS rechg_time,
        CAST(r.expire_time AS DATETIME)                           AS exp_time,
        CAST(r.create_time AS DATETIME)                           AS crt_time,
        CAST(p.trade_time AS DATETIME)                            AS pay_time,
        CAST(p.notify_time AS DATETIME)                           AS ntfy_time,
        r.remark                                                  AS rmk,
        r.version                                                 AS ver
    FROM demo_dw.ods_mysql_tang_pay_pay_recharge_record_ri r
    LEFT JOIN pay_rcd p
      ON r.trade_no = p.trade_no
    LEFT JOIN txn t
      ON p.transaction_id = t.id
    WHERE r.status = 1
      AND CAST(r.notify_time AS DATETIME) >= TO_DATE('${bizdate}', 'yyyymmdd')
      AND CAST(r.notify_time AS DATETIME) <  DATEADD(TO_DATE('${bizdate}', 'yyyymmdd'), 1, 'dd')
)

INSERT OVERWRITE TABLE demo_dw.dwd_pay_rechg_rcd_di PARTITION (ds = '${bizdate}')
SELECT
    NVL(rechg_no,                 '-99')                         AS rechg_no,
    NVL(pay_rcd_id,                -99)                          AS pay_rcd_id,
    NVL(txn_id,                    -99)                          AS txn_id,
    NVL(txn_no,                  '-99')                          AS txn_no,
    NVL(out_trade_no,            '-99')                          AS out_trade_no,
    NVL(usr_id,                    -99)                          AS usr_id,
    NVL(biz_type_cd,                -1)                          AS biz_type_cd,
    NVL(rcd_type_cd,             -1)                          AS rcd_type_cd,
    NVL(trade_type_cd,              -1)                          AS trade_type_cd,
    UPPER(NVL(pay_mtd_cd,       'UNKNOWN'))                         AS pay_mtd_cd,
    NVL(pay_acct,             'UNKNOWN')                         AS pay_acct,
    NVL(payer_id,                '-99')                          AS payer_id,
    NVL(payer_acct,          'UNKNOWN')                          AS payer_acct,
    UPPER(NVL(ccy,           'UNKNOWN'))                         AS ccy,
    NVL(ccy_amt,                    0)                           AS ccy_amt,
    NVL(rechg_amt,                   0)                           AS rechg_amt,
    NVL(rechg_actl_amt,              0)                           AS rechg_actl_amt,
    NVL(wthd_amt,                   0)                           AS wthd_amt,
    NVL(rechg_loss_amt,              0)                           AS rechg_loss_amt,
    NVL(pay_fee,                    0)                           AS pay_fee,
    NVL(fixed_loss_amt,             0)                           AS fixed_loss_amt,
    NVL(fx_rate,                    0)                           AS fx_rate,
    NVL(rechg_stat,                 -1)                           AS rechg_stat,
    NVL(txn_stat,                  -1)                           AS txn_stat,
    NVL(pay_stat,                  -1)                           AS pay_stat,
    NVL(call_stat,                 -1)                           AS call_stat,
    NVL(is_succ,                    0)                           AS is_succ,
    rechg_time                                                    AS rechg_time,
    exp_time                                                     AS exp_time,
    crt_time                                                     AS crt_time,
    pay_time                                                     AS pay_time,
    ntfy_time                                                    AS ntfy_time,
    NVL(rmk,                       '')                           AS rmk,
    NVL(ver,                        0)                           AS ver
FROM rchg_base
;
