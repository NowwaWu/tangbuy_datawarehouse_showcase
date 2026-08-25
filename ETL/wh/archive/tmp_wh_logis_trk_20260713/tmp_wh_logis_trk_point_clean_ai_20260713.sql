--MaxCompute SQL
-- 本地归档：20260713 物流轨迹临时分析，仅供历史复现，不作为生产调度节点。
-- 脱敏清洗轨迹明细：不落原始 description，固定读取 ds='20260713'

DROP TABLE IF EXISTS demo_dw.tmp_wh_logis_trk_point_clean_ai_20260713;

CREATE TABLE demo_dw.tmp_wh_logis_trk_point_clean_ai_20260713
(
    express_no                  STRING          COMMENT '物流单号',
    exprs_nm                    STRING          COMMENT '承运商',
    line_nm                     STRING          COMMENT '物流线路',
    rcv_cntry                   STRING          COMMENT '目的国家',
    pkg_stat_nm                 STRING          COMMENT '源包裹状态名称，不作为可靠物流终态',
    position                    STRING          COMMENT '轨迹地点',
    description_masked          STRING          COMMENT '清洗并脱敏后的轨迹描述',
    event_time                  DATETIME        COMMENT '统一转换后的轨迹发生时间',
    invalid_event_time          BIGINT          COMMENT '轨迹时间无效标识：1无效或为空，0有效',
    create_time                 TIMESTAMP       COMMENT '轨迹创建时间',
    event_seq                   BIGINT          COMMENT '单票轨迹节点顺序',
    prev_event_time             DATETIME        COMMENT '上一节点轨迹发生时间',
    next_event_time             DATETIME        COMMENT '下一节点轨迹发生时间',
    prev_description_masked     STRING          COMMENT '上一节点脱敏描述',
    next_description_masked     STRING          COMMENT '下一节点脱敏描述',
    gap_hours                   DECIMAL(18,2)   COMMENT '与上一原始节点的间隔小时数',
    ds                          STRING          COMMENT '快照日期'
)
COMMENT '物流轨迹AI分析脱敏清洗明细-20260713'
LIFECYCLE 30;

-- 先规范空白，再按邮箱、电话、明显姓名和详细地址依次脱敏
WITH
with_src AS
(
    SELECT  express_no,
            exprs_nm,
            line_nm,
            rcv_cntry,
            pkg_stat_nm,
            position,
            description AS description_raw,
            IF(
                description IS NULL,
                NULL,
                TRIM(REGEXP_REPLACE(REGEXP_REPLACE(description, '[[:space:]]+', ' '), ' +', ' '))
            ) AS description_clean,
            change_time,
            create_time,
            ds
    FROM demo_dw.tmp_wh_logis_trk_point
    WHERE ds = '20260713'
),
-- 联系方式脱敏：邮箱、国际电话及含分隔符的长电话号码
with_contact_mask AS
(
    SELECT  express_no,
            exprs_nm,
            line_nm,
            rcv_cntry,
            pkg_stat_nm,
            position,
            description_raw,
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(
                        description_clean,
                        '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}',
                        '[EMAIL]'
                    ),
                    '\\+[0-9][0-9() .-]{6,}[0-9]',
                    '[PHONE]'
                ),
                '([0-9][ .()-]?){9,14}[0-9]',
                '[PHONE]'
            ) AS description_contact_masked,
            change_time,
            create_time,
            ds
    FROM with_src
),
-- 明显姓名脱敏：保留签收/收件语义，只替换标签后的姓名实体
with_name_mask AS
(
    SELECT  express_no,
            exprs_nm,
            line_nm,
            rcv_cntry,
            pkg_stat_nm,
            position,
            description_raw,
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(
                        REGEXP_REPLACE(
                            REGEXP_REPLACE(
                                REGEXP_REPLACE(
                                    REGEXP_REPLACE(
                                        REGEXP_REPLACE(
                                            REGEXP_REPLACE(
                                                REGEXP_REPLACE(
                                                    description_contact_masked,
                                                    '(?i)signed[ ]+for[ ]+by[ ]+[A-Za-z][A-Za-z .''-]{1,40}',
                                                    'signed for by [NAME]'
                                                ),
                                                '(?i)signed[ ]+by[ ]+[A-Za-z][A-Za-z .''-]{1,40}',
                                                'signed by [NAME]'
                                            ),
                                            '(?i)received[ ]+by[ ]+[A-Za-z][A-Za-z .''-]{1,40}',
                                            'received by [NAME]'
                                        ),
                                        '(?i)recipient[ ]*[:：-][ ]*[A-Za-z][A-Za-z .''-]{1,40}',
                                        'recipient: [NAME]'
                                    ),
                                    '(?i)consignee[ ]*[:：-][ ]*[A-Za-z][A-Za-z .''-]{1,40}',
                                    'consignee: [NAME]'
                                ),
                                '(?i)receiver[ ]*[:：-][ ]*[A-Za-z][A-Za-z .''-]{1,40}',
                                'receiver: [NAME]'
                            ),
                            '签收人[ ]*[:：-]?[ ]*[一-龥·]{2,10}',
                            '签收人：[NAME]'
                        ),
                        '收件人[ ]*[:：-]?[ ]*[一-龥·]{2,10}',
                        '收件人：[NAME]'
                    ),
                    '联系人[ ]*[:：-]?[ ]*[一-龥·]{2,10}',
                    '联系人：[NAME]'
                ),
                '姓名[ ]*[:：-]?[ ]*[一-龥·]{2,10}',
                '姓名：[NAME]'
            ) AS description_name_masked,
            change_time,
            create_time,
            ds
    FROM with_contact_mask
),
-- 地址脱敏：处理地址标签、常见英文门牌街道和中文门牌地址
with_addr_mask AS
(
    SELECT  express_no,
            exprs_nm,
            line_nm,
            rcv_cntry,
            pkg_stat_nm,
            position,
            description_raw,
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(
                        REGEXP_REPLACE(
                            REGEXP_REPLACE(
                                description_name_masked,
                                '(?i)delivery[ ]+address[ ]*[:：-]?[ ]*[^,;，；]{3,100}',
                                'delivery address: [ADDRESS]'
                            ),
                            '(?i)address[ ]*[:：-]?[ ]*[^,;，；]{3,100}',
                            'address: [ADDRESS]'
                        ),
                        '详细地址[ ]*[:：-]?[ ]*[^,;，；]{3,100}',
                        '详细地址：[ADDRESS]'
                    ),
                    '(?i)[0-9]{1,6}[ ]+[A-Za-z0-9 .''-]{2,60}[ ]+(street|st|road|rd|avenue|ave|lane|ln|drive|dr|boulevard|blvd|way|court|ct)([ ,.;]|$)',
                    '[ADDRESS]'
                ),
                '[一-龥]{2,}(省|市|区|县|镇|街道|路|街|巷|弄)[一-龥A-Za-z0-9-]{0,30}[0-9一二三四五六七八九十百]+号',
                '[ADDRESS]'
            ) AS description_masked,
            change_time,
            create_time,
            ds
    FROM with_name_mask
),
-- 时间仅在 ISDATE 校验通过后转换，失败节点保留
with_time AS
(
    SELECT  express_no,
            exprs_nm,
            line_nm,
            rcv_cntry,
            pkg_stat_nm,
            position,
            description_raw,
            description_masked,
            IF(
                change_time IS NOT NULL
                AND TRIM(change_time) <> ''
                AND ISDATE(TRIM(change_time), 'yyyy-mm-dd hh:mi:ss'),
                TO_DATE(TRIM(change_time), 'yyyy-mm-dd hh:mi:ss'),
                NULL
            ) AS event_time,
            IF(
                change_time IS NULL
                OR TRIM(change_time) = ''
                OR NOT ISDATE(TRIM(change_time), 'yyyy-mm-dd hh:mi:ss'),
                1, 0
            ) AS invalid_event_time,
            change_time,
            create_time,
            ds,
            ROW_NUMBER() OVER
            (
                PARTITION BY express_no, change_time, position, description_raw
                ORDER BY create_time, exprs_nm, line_nm, rcv_cntry, pkg_stat_nm
            ) AS exact_dup_rn
    FROM with_addr_mask
),
-- 对完全重复节点只保留一条
with_dedup AS
(
    SELECT  express_no,
            exprs_nm,
            line_nm,
            rcv_cntry,
            pkg_stat_nm,
            position,
            description_masked,
            event_time,
            invalid_event_time,
            create_time,
            ds
    FROM with_time
    WHERE exact_dup_rn = 1
),
-- 无效时间排在有效轨迹之后，其他字段仅作为稳定排序键
with_neighbor AS
(
    SELECT  express_no,
            exprs_nm,
            line_nm,
            rcv_cntry,
            pkg_stat_nm,
            position,
            description_masked,
            event_time,
            invalid_event_time,
            create_time,
            ROW_NUMBER() OVER
            (
                PARTITION BY express_no
                ORDER BY invalid_event_time, event_time, create_time, position, description_masked
            ) AS event_seq,
            LAG(event_time) OVER
            (
                PARTITION BY express_no
                ORDER BY invalid_event_time, event_time, create_time, position, description_masked
            ) AS prev_event_time,
            LEAD(event_time) OVER
            (
                PARTITION BY express_no
                ORDER BY invalid_event_time, event_time, create_time, position, description_masked
            ) AS next_event_time,
            LAG(description_masked) OVER
            (
                PARTITION BY express_no
                ORDER BY invalid_event_time, event_time, create_time, position, description_masked
            ) AS prev_description_masked,
            LEAD(description_masked) OVER
            (
                PARTITION BY express_no
                ORDER BY invalid_event_time, event_time, create_time, position, description_masked
            ) AS next_description_masked,
            ds
    FROM with_dedup
)

INSERT OVERWRITE TABLE demo_dw.tmp_wh_logis_trk_point_clean_ai_20260713
SELECT  express_no,
        exprs_nm,
        line_nm,
        rcv_cntry,
        pkg_stat_nm,
        position,
        description_masked,
        event_time,
        invalid_event_time,
        create_time,
        event_seq,
        prev_event_time,
        next_event_time,
        prev_description_masked,
        next_description_masked,
        IF(
            event_time IS NOT NULL AND prev_event_time IS NOT NULL,
            CAST(DATEDIFF(event_time, prev_event_time, 'ss') / 3600.0 AS DECIMAL(18,2)),
            NULL
        ) AS gap_hours,
        ds
FROM with_neighbor;
