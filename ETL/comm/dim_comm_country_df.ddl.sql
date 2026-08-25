-- ============================================================
-- 数据域:   comm (公共域)
-- 业务过程: geo_ref (地理参考)
-- 表名:     dim_comm_country_df
-- 表类型:   维度表 (Dimension) - 日全量快照
-- 描述:     国家维度表，沉淀 ISO、UN、World Bank 及区域组织标识
-- 来源:     手工国家信息表 - 简版.csv
-- 调度周期: 日
-- ============================================================

CREATE TABLE IF NOT EXISTS dim_comm_country_df (
    cntry_cd            STRING      COMMENT '国家ISO 3166-1 alpha-2代码（自然键）',
    cntry_nm            STRING      COMMENT '国家中文名称',
    cntry_nm_en         STRING      COMMENT '国家英文名称',
    iso_alpha3_cd       STRING      COMMENT '国家ISO 3166-1 alpha-3代码',
    un_rgn              STRING      COMMENT '联合国大区',
    un_sub_rgn          STRING      COMMENT '联合国子区域',
    un_mid_rgn          STRING      COMMENT '联合国中间区域',
    wb_rgn              STRING      COMMENT '世界银行地区',
    wb_income_grp       STRING      COMMENT '世界银行FY2026收入分组',
    is_eu               BIGINT      COMMENT '是否欧盟成员：1-是，0-否',
    is_oecd             BIGINT      COMMENT '是否OECD成员：1-是，0-否',
    is_asean            BIGINT      COMMENT '是否东盟成员：1-是，0-否',
    is_gcc              BIGINT      COMMENT '是否海湾合作委员会成员：1-是，0-否'
)
COMMENT '国家维度表-日全量快照'
PARTITIONED BY (ds STRING COMMENT '分区日期 yyyyMMdd')
LIFECYCLE 36500;
