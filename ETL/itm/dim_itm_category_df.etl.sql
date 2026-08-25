--MaxCompute SQL
--********************************************************************--
--author: 吴延俊
--create time: 2026-05-19 00:00:00
-- 数据域:   itm (商品域)
-- 业务过程: ctgy_mgr (类目管理)
-- 表名:     dim_itm_category_df
-- 表类型:   维度表 (Dimension) - 日全量快照
-- 描述:     商品HS类目维度表，按一级/二级/三级/四级类目展开并补齐到四级
-- 来源:     ods_mysql_tang_resource_r_hs_code_ri
-- ETL方式:  INSERT OVERWRITE 按日分区全量覆盖
-- 调度变量: ${bizdate} 格式 yyyyMMdd
--********************************************************************--

WITH base_raw AS (
    SELECT  cid AS ctgy_id
            ,cn_name AS ctgy_nm
            ,parent_id AS parent_ctgy_id
            ,dec_cn_name AS dcl_cn_nm
            ,dec_en_name AS dcl_en_nm
            ,NVL(hs_code,'-99') AS cstm_hs_cd
    FROM    demo_dw.ods_mysql_tang_resource_r_hs_code_ri
)
,child_cnt AS (
    SELECT  parent_ctgy_id AS ctgy_id
            ,COUNT(1) AS child_cnt
    FROM    base_raw
    WHERE   parent_ctgy_id <> 0
    GROUP BY parent_ctgy_id
)
,base_ctgy AS (
    SELECT  a.ctgy_id
            ,a.ctgy_nm
            ,a.parent_ctgy_id
            ,NVL(b.child_cnt,0) AS child_cnt
            ,a.dcl_cn_nm
            ,a.dcl_en_nm
            ,a.cstm_hs_cd
    FROM    base_raw a
    LEFT JOIN child_cnt b
    ON      a.ctgy_id = b.ctgy_id
)
,lvl1_ctgy AS (
    SELECT  ctgy_id
            ,ctgy_nm
            ,parent_ctgy_id
            ,child_cnt
            ,dcl_cn_nm
            ,dcl_en_nm
            ,cstm_hs_cd
    FROM    base_ctgy
    WHERE   parent_ctgy_id IN (0,999999999)
)
,lvl2_ctgy AS (
    SELECT  a.ctgy_id
            ,a.ctgy_nm
            ,a.parent_ctgy_id
            ,a.child_cnt
            ,a.dcl_cn_nm
            ,a.dcl_en_nm
            ,a.cstm_hs_cd
            ,b.ctgy_id AS lvl1_ctgy_id
            ,b.ctgy_nm AS lvl1_ctgy_nm
    FROM    base_ctgy a
    JOIN    lvl1_ctgy b
    ON      a.parent_ctgy_id = b.ctgy_id
)
,lvl3_ctgy AS (
    SELECT  a.ctgy_id
            ,a.ctgy_nm
            ,a.parent_ctgy_id
            ,a.child_cnt
            ,a.dcl_cn_nm
            ,a.dcl_en_nm
            ,a.cstm_hs_cd
            ,b.lvl1_ctgy_id
            ,b.lvl1_ctgy_nm
            ,b.ctgy_id AS lvl2_ctgy_id
            ,b.ctgy_nm AS lvl2_ctgy_nm
    FROM    base_ctgy a
    JOIN    lvl2_ctgy b
    ON      a.parent_ctgy_id = b.ctgy_id
)
,lvl4_ctgy AS (
    SELECT  a.ctgy_id
            ,a.ctgy_nm
            ,a.parent_ctgy_id
            ,a.child_cnt
            ,a.dcl_cn_nm
            ,a.dcl_en_nm
            ,a.cstm_hs_cd
            ,b.lvl1_ctgy_id
            ,b.lvl1_ctgy_nm
            ,b.lvl2_ctgy_id
            ,b.lvl2_ctgy_nm
            ,b.ctgy_id AS lvl3_ctgy_id
            ,b.ctgy_nm AS lvl3_ctgy_nm
    FROM    base_ctgy a
    JOIN    lvl3_ctgy b
    ON      a.parent_ctgy_id = b.ctgy_id
)

INSERT OVERWRITE TABLE demo_dw.dim_itm_category_df PARTITION (ds = '${bizdate}')
SELECT  parent_ctgy_id
        ,1 AS ctgy_lvl
        ,CASE WHEN child_cnt > 0 THEN 0 ELSE 1 END AS is_leaf
        ,ctgy_id AS lvl1_ctgy_id
        ,ctgy_nm AS lvl1_ctgy_nm
        ,ctgy_id AS lvl2_ctgy_id
        ,ctgy_nm AS lvl2_ctgy_nm
        ,ctgy_id AS lvl3_ctgy_id
        ,ctgy_nm AS lvl3_ctgy_nm
        ,ctgy_id AS lvl4_ctgy_id
        ,ctgy_nm AS lvl4_ctgy_nm
        ,dcl_cn_nm
        ,dcl_en_nm
        ,cstm_hs_cd
FROM    lvl1_ctgy

UNION ALL

SELECT  parent_ctgy_id
        ,2 AS ctgy_lvl
        ,CASE WHEN child_cnt > 0 THEN 0 ELSE 1 END AS is_leaf
        ,lvl1_ctgy_id
        ,lvl1_ctgy_nm
        ,ctgy_id AS lvl2_ctgy_id
        ,ctgy_nm AS lvl2_ctgy_nm
        ,ctgy_id AS lvl3_ctgy_id
        ,ctgy_nm AS lvl3_ctgy_nm
        ,ctgy_id AS lvl4_ctgy_id
        ,ctgy_nm AS lvl4_ctgy_nm
        ,dcl_cn_nm
        ,dcl_en_nm
        ,cstm_hs_cd
FROM    lvl2_ctgy

UNION ALL

SELECT  parent_ctgy_id
        ,3 AS ctgy_lvl
        ,CASE WHEN child_cnt > 0 THEN 0 ELSE 1 END AS is_leaf
        ,lvl1_ctgy_id
        ,lvl1_ctgy_nm
        ,lvl2_ctgy_id
        ,lvl2_ctgy_nm
        ,ctgy_id AS lvl3_ctgy_id
        ,ctgy_nm AS lvl3_ctgy_nm
        ,ctgy_id AS lvl4_ctgy_id
        ,ctgy_nm AS lvl4_ctgy_nm
        ,dcl_cn_nm
        ,dcl_en_nm
        ,cstm_hs_cd
FROM    lvl3_ctgy

UNION ALL

SELECT  parent_ctgy_id
        ,4 AS ctgy_lvl
        ,CASE WHEN child_cnt > 0 THEN 0 ELSE 1 END AS is_leaf
        ,lvl1_ctgy_id
        ,lvl1_ctgy_nm
        ,lvl2_ctgy_id
        ,lvl2_ctgy_nm
        ,lvl3_ctgy_id
        ,lvl3_ctgy_nm
        ,ctgy_id AS lvl4_ctgy_id
        ,ctgy_nm AS lvl4_ctgy_nm
        ,dcl_cn_nm
        ,dcl_en_nm
        ,cstm_hs_cd
FROM    lvl4_ctgy
;
