--MaxCompute SQL
--********************************************************************--
--author: 吴延俊
--create time: 2026-05-19 00:00:00
--********************************************************************--

WITH user_base AS (
    SELECT
        user_id,
        user_name,
        nick_name,
        avatar,
        email,
        phone,
        CASE
            WHEN gender = 0 THEN '男'
            WHEN gender = 1 THEN '女'
            ELSE '未知'
        END                                         AS gndr_cd,
        birthday                                    AS dob,
        language                                    AS lang,
        CASE WHEN status = 0 THEN 1 ELSE 0 END      AS usr_stat,
        lock_status                                 AS is_frz,
        risk                                        AS is_risk,
        del_flag                                    AS is_del,
        paid_free_enable                            AS is_pay_free_on,
        cast(paid_free_limit as decimal(18,4)) as pay_free_limit ,
        refuse_num                                  AS rjt_cnt,
        level                                       AS lvl_id,
        growth,
        integral,
        cast(balance as decimal(18,4))                                    AS bal_amt,
        cast(rebate as decimal(18,4))                                     AS rebate_amt,
        cast(freeze  as decimal(18,4))                                    AS frz_amt,
        cast(overdraft  as decimal(18,4))                                 AS ovdft_amt,
        register_country,
        province                                    AS prov,
        city,
        register_ip,
        storage_id                                  AS wh_id,
        CASE WHEN water_mark_state = 0 THEN 1 ELSE 0 END AS is_wm_on,
        cast(register_time as datetime)                              AS crt_time,
        cast(update_time as datetime)                                 AS upd_time
    FROM demo_dw.ods_mysql_tang_user_user_info_ri
),

member_level AS (
    SELECT
        id                                          AS lvl_id,
        level                                       AS lvl_nm,
        CAST(level AS BIGINT)                       AS lvl,
        growth                                      AS lvl_growth_req,
        coupon_nums                                 AS cpn_cnt,
        cast(fare_ratio as decimal(18,4))                                 AS fare_rate,
        return_exchange_nums                        AS rtn_exch_cnt,
        fine_photo_nums                             AS fine_photo_cnt,
        fast_response_nums                          AS fast_rsp_cnt,
        preview_package_nums                        AS prvw_pkg_cnt,
        cast(append_discount as decimal(18,4))                             AS append_disc,
        cast(insurance_discount as decimal(18,4))                          AS ins_disc
    FROM demo_dw.ods_mysql_tang_user_member_config_ri
),

user_ext AS (
    SELECT user_id, app_os, fcm_token AS fcm_tkn, app_version as app_ver, platform,  CASE WHEN agreement = 'true' THEN 1 ELSE 0 END as is_agreement_read,
           declaration AS is_declaration_ok
    FROM demo_dw.ods_mysql_tang_user_user_info_ext_ri
),

usr_pltf_rn AS (
    SELECT
        user_id,
        platform,
        ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY create_time ASC) AS rn
    FROM demo_dw.ods_mysql_tang_user_user_platform_ri
),
usr_pltf AS (
    SELECT  user_id,
            platform
    FROM    usr_pltf_rn
    WHERE   rn = 1
),

watermark AS (
    SELECT user_id,name as  wm_nm, background_image as wm_bg_img,is_use as  is_wm_on
    FROM demo_dw.ods_mysql_tang_user_user_watermark_info_ri

),

user_tags_agg AS (
    SELECT
        user_id,
        WM_CONCAT(',', name)                        AS usr_tag_list
    FROM demo_dw.ods_mysql_tang_user_user_tags_ri
    GROUP BY user_id
),

cps_info AS (
    SELECT  user_id
            ,promoter_id                                AS rcmd_pmt_id
            ,share_code                                 AS shr_cd
            ,CAST(commission_amount AS DECIMAL(18,4))   AS rcmd_cmsn_amt
    FROM    demo_dw.ods_mysql_tang_cps_b_share_detail_ri
    WHERE   del_flag = 0
),

pmt_acty_rn AS (
    SELECT  user_id
            ,whatsapp_dial_code        AS wa_dial_cd
            ,whatsapp_phone            AS wa_phn
            ,facebook_id               AS fb_id
            ,instagram_id              AS ig_id
            ,ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY update_time DESC) AS rn
    FROM    demo_dw.ods_mysql_tang_cps_proxy_promotion_activity_record_ri
),
pmt_acty AS (
    SELECT  user_id
            ,wa_dial_cd
            ,wa_phn
            ,fb_id
            ,ig_id
    FROM    pmt_acty_rn
    WHERE   rn = 1
),

cntry AS (
    SELECT  country_code,
            country_name,
            country_name_cn              AS cntry_nm
    FROM    demo_dw.ods_manual_country_code
),

ip_geo AS (
    SELECT  reg_ip,
            MAX(cntry_cd) AS cntry_cd,
            MAX(prov)     AS prov,
            MAX(city)     AS city
    FROM    demo_dw.dim_comm_ip_geo_df
    GROUP BY reg_ip
),

ebk_usrs AS (
    SELECT  DISTINCT email
    FROM    demo_dw.ods_supabase_auth_users_df
    WHERE   ds = '${bizdate}'
)

INSERT OVERWRITE TABLE demo_dw.dim_usr_info_df PARTITION (ds = '${bizdate}')
SELECT
    u.user_id                                                   AS usr_id,
    u.user_name                                                 AS usr_nm,
    u.nick_name                                                 AS nick,
    u.email                                                     AS email,
    u.phone                                                     AS phn,
    u.gndr_cd                                                   AS gndr_cd,
    u.dob                                                       AS dob,
    u.lang                                                      AS lang,
    u.avatar                                                    AS img,
    COALESCE(NULLIF(cntry.country_code, ''), g.cntry_cd)         AS cntry_cd,
    COALESCE(cntry.cntry_nm, cntry_ip.cntry_nm)                  AS cntry_nm,
    COALESCE(NULLIF(u.prov, ''), g.prov)                         AS prov,
    COALESCE(NULLIF(u.city, ''), g.city)                         AS city,
    u.register_ip                                               AS reg_ip,
    u.usr_stat                                                  AS usr_stat,
    u.is_frz                                                    AS is_frz,
    u.is_risk                                                   AS is_risk,
    u.is_del                                                    AS is_del,
    u.is_pay_free_on                                            AS is_pay_free_on,
    u.pay_free_limit                                            AS pay_free_limit,
    u.rjt_cnt                                                   AS rjt_cnt,
    u.lvl_id                                                    AS lvl_id,
    m.lvl_nm                                                    AS lvl_nm,
    m.lvl                                                       AS lvl,
    u.growth                                                    AS growth,
    u.integral                                                  AS integral,
    m.cpn_cnt                                                   AS cpn_cnt,
    m.fare_rate                                                 AS fare_rate,
    m.rtn_exch_cnt                                              AS rtn_exch_cnt,
    m.fine_photo_cnt                                            AS fine_photo_cnt,
    m.fast_rsp_cnt                                              AS fast_rsp_cnt,
    m.prvw_pkg_cnt                                              AS prvw_pkg_cnt,
    m.append_disc                                               AS append_disc,
    m.ins_disc                                                  AS ins_disc,
    u.bal_amt                                                   AS bal_amt,
    u.rebate_amt                                                AS rebate_amt,
    u.frz_amt                                                   AS frz_amt,
    u.ovdft_amt                                                 AS ovdft_amt,
    u.wh_id                                                     AS wh_id,
    e.app_os                                                    AS app_os,
    e.platform                                                  AS pltf_cd,
    COALESCE(p.platform, 'EMAIL')                               AS reg_pltf_cd,
    e.fcm_tkn                                                   AS fcm_tkn,
    e.app_ver                                                   AS app_ver,
    e.is_agreement_read                                         AS is_agreement_read,
    e.is_declaration_ok                                         AS is_declaration_ok,
    w.is_wm_on                                                  AS is_wm_on,
    w.wm_nm                                                     AS wm_nm,
    w.wm_bg_img                                                 AS wm_bg_img,
    t.usr_tag_list                                              AS usr_tag_list,
    c.rcmd_pmt_id                                               AS rcmd_pmt_id,
    c.shr_cd                                                    AS shr_cd,
    c.rcmd_cmsn_amt                                             AS rcmd_cmsn_amt,
    a.wa_dial_cd                                                AS wa_dial_cd,
    a.wa_phn                                                    AS wa_phn,
    a.fb_id                                                     AS fb_id,
    a.ig_id                                                     AS ig_id,
    CASE WHEN eu.email IS NOT NULL THEN 1 ELSE 0 END         AS is_ebk_usr,
    u.crt_time,
    u.upd_time
FROM user_base u
LEFT JOIN member_level m ON u.lvl_id = m.lvl_id
LEFT JOIN user_ext e ON u.user_id = e.user_id
LEFT JOIN usr_pltf p ON u.user_id = p.user_id
LEFT JOIN watermark w ON u.user_id = w.user_id
LEFT JOIN user_tags_agg t ON u.user_id = t.user_id
LEFT JOIN cps_info c ON u.user_id = c.user_id
LEFT JOIN pmt_acty a ON u.user_id = a.user_id
LEFT JOIN ip_geo g ON u.register_ip = g.reg_ip
LEFT JOIN cntry ON u.register_country = cntry.country_name
LEFT JOIN cntry cntry_ip ON g.cntry_cd = cntry_ip.country_code
LEFT JOIN ebk_usrs eu ON u.email = eu.email;
