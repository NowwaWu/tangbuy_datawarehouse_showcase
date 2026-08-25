CREATE TABLE demo_dw.`dim_itm_category_df` (
  `parent_ctgy_id` BIGINT COMMENT '当前类目父类目ID',
  `ctgy_lvl` BIGINT COMMENT '当前类目层级: 1-一级, 2-二级, 3-三级, 4-四级',
  `is_leaf` BIGINT COMMENT '是否叶子类目: 0-否, 1-是',
  `lvl1_ctgy_id` BIGINT COMMENT '一级类目ID',
  `lvl1_ctgy_nm` STRING COMMENT '一级类目中文名称',
  `lvl2_ctgy_id` BIGINT COMMENT '二级补齐类目ID',
  `lvl2_ctgy_nm` STRING COMMENT '二级补齐类目中文名称',
  `lvl3_ctgy_id` BIGINT COMMENT '三级补齐类目ID',
  `lvl3_ctgy_nm` STRING COMMENT '三级补齐类目中文名称',
  `lvl4_ctgy_id` BIGINT COMMENT '四级补齐类目ID（当前类目ID）',
  `lvl4_ctgy_nm` STRING COMMENT '四级补齐类目中文名称（当前类目名称）',
  `dcl_cn_nm` STRING COMMENT '当前类目申报中文名称',
  `dcl_en_nm` STRING COMMENT '当前类目申报英文名称',
  `cstm_hs_cd` STRING COMMENT '当前类目海关HS编码，未知填-99'
)
COMMENT '商品类目维度表-四级类目展开日全量快照'
PARTITIONED BY (
  `ds` STRING NOT NULL COMMENT '分区日期 yyyyMMdd'
)
STORED AS AliOrc
LIFECYCLE 36500;
