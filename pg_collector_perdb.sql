-- +----------------------------------------------------------------------------+
-- |  pg_collector_perdb.sql : per-database inspection sections                 |
-- |  Included once for each database by the main script (loop file)            |
-- +----------------------------------------------------------------------------+


\qecho <br>
\qecho <hr>
SELECT 'db-' || current_database() AS dbanchor \gset
SELECT current_database() AS curdb \gset
\qecho <a name=:dbanchor></a>
\qecho <h1>Database: :DBNAME</h1>
\qecho <br>

-- +----------------------------------------------------------------------------+
-- |      - Database-level Observations                        -              |
-- +----------------------------------------------------------------------------+
SELECT 'dbobs_' || current_database() AS dbobsanchor \gset
\qecho <a name=:dbobsanchor></a>
\qecho <font size="+1" face="Arial,Helvetica,Geneva,sans-serif" color="#16191f"><b>数据库级观察项（:DBNAME ）</b></font><hr align="left" width="460">
\qecho <br>
---------------------------------
-- Check for duplicate indexes --
---------------------------------
select count(*) > 0 obsrv_duplicate_indexes
from
(
SELECT pg_size_pretty(sum(pg_relation_size(idx))::bigint) as size,
       (array_agg(idx))[1] as idx1, (array_agg(idx))[2] as idx2,
       (array_agg(idx))[3] as idx3, (array_agg(idx))[4] as idx4
FROM (
    SELECT indexrelid::regclass as idx, (indrelid::text ||E'
'|| indclass::text ||E'
'|| indkey::text ||E'
'|| coalesce(indexprs::text,'')||E'
' || coalesce(indpred::text,'')) as key
    FROM pg_index) sub
GROUP BY key HAVING count(*)>1
ORDER BY sum(pg_relation_size(idx)) DESC) AS t \gset

\if :obsrv_duplicate_indexes
    \qecho &#8594; 该数据库存在重复索引，请查看以下章节 <a class=link href=#db-:curdb-Duplicate_indexes>Duplicate indexes</a> .<br>
\else
\endif
--------------------------------------------------
-- Check for Index Bloat --
--------------------------------------------------
SELECT count(*) > 0 obsrv_index_bloat
FROM (
    SELECT
        schemaname, relname, indexrelname,
        pg_size_pretty(pg_relation_size(i.indexrelid)) as index_size,
        pg_size_pretty(pg_relation_size(i.indrelid)) as table_size
    FROM pg_index i
    JOIN pg_stat_all_indexes s ON i.indexrelid = s.indexrelid
    WHERE pg_relation_size(i.indexrelid) > pg_relation_size(i.indrelid) * 0.5
) AS bloat \gset

\if :obsrv_index_bloat
    \qecho &#8594; 该数据库存在索引膨胀（索引大小超过表的 50%），请查看以下章节 <a class=link href=#db-:curdb-Fragmentation>Fragmentation</a> .<br>
\else
\endif
-------------------------------
-- Check for Invalid Indexes --
-------------------------------
select count(*) > 0  obsrv_invalid_indxes_count from pg_index WHERE pg_index.indisvalid = false \gset

\if :obsrv_invalid_indxes_count
    \qecho &#8594; 该数据库存在无效索引，请查看以下章节 <a class=link href=#db-:curdb-invalid_indexes>Invalid indexes</a> .<br>
\else
\endif
------------------------------------------
-- Check for Unused_Indexes --
------------------------------------------
select count(*) > 0 obsrv_unused_indexes
FROM pg_catalog.pg_stat_all_indexes ai , pg_index i
WHERE ai.indexrelid=i.indexrelid
and ai.idx_scan = 0
and ai.schemaname not in ('pg_catalog','pg_toast') \gset

 \if :obsrv_unused_indexes
    \qecho &#8594; 该数据库存在未使用索引，请查看以下章节 <a class=link href=#db-:curdb-Unused_Indexes>Unused Indexes</a> .<br>
 \else
 \endif
------------------------------------------
-- Check for Low remaining sequences --
------------------------------------------
SELECT count(1) as obsrv_less_remaining_sequences FROM (SELECT
    schemaname as Schema,
    sequencename as Sequence_Name,
    data_type::regtype as Data_Type,
    last_value as Current_Value,
    max_value as Max_Value,
    min_value as Min_Value,
    increment_by as Increment_By,
    CASE
        WHEN max_value = 9223372036854775807 THEN 'No Limit'
        ELSE round(((max_value - last_value)::numeric / (max_value - min_value)::numeric * 100), 2)::text || '%'
    END as Remaining_Percentage,
    CASE
        WHEN max_value = 9223372036854775807 THEN 'No Action Needed'
        WHEN ((max_value - last_value)::numeric / (max_value - min_value)::numeric * 100) < 1
        THEN 'CRITICAL: Less than 1% remaining'
        WHEN ((max_value - last_value)::numeric / (max_value - min_value)::numeric * 100) < 5
        THEN 'WARNING: Less than 5% remaining'
        WHEN ((max_value - last_value)::numeric / (max_value - min_value)::numeric * 100) < 10
        THEN 'NOTICE: Less than 10% remaining'
        ELSE 'OK'
    END as Status
FROM pg_sequences) seq WHERE status not in ('OK', 'No Action Needed') \gset

\if :obsrv_less_remaining_sequences
    \qecho &#8594; 该数据库存在剩余值不足 10% 的序列，请查看以下章节 <a class=link href=#db-:curdb-sequences>sequences</a> .<br>
\else
\endif
------------------------------------------------------------------------------------------------------
-- Check for tables that have more than 20% dead rows --
------------------------------------------------------------------------------------------------------
select count(*) > 0 obsrv_tables_more_than_20pct_dead_rows from pg_stat_all_tables where n_dead_tup::float/nullif(n_live_tup+n_dead_tup,0) >.2 and (n_live_tup > 1000 or n_dead_tup > 1000)   \gset
\if :obsrv_tables_more_than_20pct_dead_rows
    \qecho &#8594; 该数据库存在死元组超过 20% 的表，请查看以下章节 <a class=link href=#db-:curdb-vacuum_Statistics>Vacuum & Statistics</a> .<br>
\else
\endif
---------------------------------------------------------------------------------
-- Check for tables that have autovacuum_enabled=off|false on the table level  --
---------------------------------------------------------------------------------
select count(*) > 0 obsrv_tables_autovacuum_enabled_off from pg_class where reloptions::text like '%autovacuum_enabled=off%' or pg_class.reloptions::text like '%autovacuum_enabled=false%'    \gset
\if :obsrv_tables_autovacuum_enabled_off
    \qecho &#8594; 该数据库存在表级已禁用 autovacuum（autovacuum_enabled=off|false）的表，请查看以下章节 <a class=link href=#db-:curdb-vacuum_Statistics>Vacuum & Statistics</a> .<br>
\else
\endif
------------------------------------------
-- Check for Foreign Keys without index --
------------------------------------------
select count(*) > 0 obsrv_fk_without_index
FROM pg_constraint c
WHERE c.contype = 'f'
AND NOT EXISTS (
    SELECT 1 FROM pg_index i
    WHERE i.indrelid = c.conrelid
    AND (c.conkey <@ i.indkey::int2[])
) \gset

 \if :obsrv_fk_without_index
    \qecho &#8594; 该数据库存在无索引支持的外键，请查看以下章节 <a class=link href=#db-:curdb-FK_without_index>FK without index</a> .<br>
 \else
 \endif
------------------------------------------
-- Check for Unlogged tables            --
------------------------------------------
select count(*) > 0 obsrv_unlogged_tables
FROM pg_class WHERE relpersistence = 'u' and relkind in ('r','p') \gset

 \if :obsrv_unlogged_tables
    \qecho &#8594; 该数据库存在 unlogged 表（崩溃后数据会丢失），请查看以下章节 <a class=link href=#db-:curdb-unlogged_tables>unlogged tables</a> .<br>
 \else
 \endif
\qecho <br>
\qecho <center>[<a class="noLink" href="#top">Top</a>]</center><p>
-- +----------------------------------------------------------------------------+
-- |      - Extensions                                       -                  |
-- +----------------------------------------------------------------------------+
\qecho <a name="Extensions"></a>
\qecho <font size="+2" face="Arial,Helvetica,Geneva,sans-serif" color="#16191f"><b>扩展插件</b></font><hr align="left" width="460">
\qecho <br>
\qecho <details open>
\qecho <br>
\qecho <h3>已安装扩展插件 :  </h3>
SELECT e.extname AS "Extension Name", e.extversion AS "Version", n.nspname AS "Schema",pg_get_userbyid(e.extowner)  as Owner,  c.description AS "Description" , e.extrelocatable as "relocatable to another schema", e.extconfig ,e.extcondition
FROM pg_catalog.pg_extension e LEFT JOIN pg_catalog.pg_namespace n ON n.oid = e.extnamespace LEFT JOIN pg_catalog.pg_description c ON c.objoid = e.oid AND c.classoid = 'pg_catalog.pg_extension'::pg_catalog.regclass
ORDER BY 1;
\qecho <h3>pgaudit 配置和用户级配置 </h3>
SELECT name as "parameter_name", setting from pg_settings where name like 'pgaudit.%';
\qecho <br>
select usename as user_name,useconfig as user_config FROM pg_user where useconfig::text like '%pgaudit.%';
\qecho </details>
\qecho <br>

\qecho <center>[<a class="noLink" href=#db-:curdb>Chapter Top</a>]</center><p>
-- +----------------------------------------------------------------------------+
-- |      - TOP10 Table Ages                                     -                  |
-- +----------------------------------------------------------------------------+
\qecho <a name="Top10 Table Ages"></a>
\qecho <font size="+2" face="Arial,Helvetica,Geneva,sans-serif" color="#16191f"><b>Top10 表年龄</b></font><hr align="left" width="460">
\qecho <br>
\qecho <details open>
SELECT c.oid::regclass as relation_name,
        greatest(age(c.relfrozenxid),age(t.relfrozenxid)) as age,
        pg_size_pretty(pg_table_size(c.oid)) as table_size,
        c.relkind
FROM pg_class c
LEFT JOIN pg_class t ON c.reltoastrelid = t.oid
WHERE c.relkind in ('r', 't','m')
order by 2 desc limit 10;
\qecho </details>
\qecho <center>[<a class="noLink" href=#db-:curdb>Chapter Top</a>]</center><p>
-- +----------------------------------------------------------------------------+
-- |      - TOP20 Table Size                                       -                  |
-- +----------------------------------------------------------------------------+
\qecho <a name="Top20 Table Size"></a>
\qecho <font size="+2" face="Arial,Helvetica,Geneva,sans-serif" color="#16191f"><b>Top20 表大小</b></font><hr align="left" width="460">
\qecho <br>
\qecho <h3>按大小排序的 Top20 表（当前数据库）</h3>
\qecho <br>
\qecho <h3> 注意：</h3>
\qecho <h4> - 如果表从未被 vacuum 或 analyze 过，ROW_ESTIMATE 列（pg_class.reltuples）的值为 -1，表示行数未知。 </h4>
\qecho <details open>
SELECT *, pg_size_pretty(total_bytes) AS TOTAL_PRETTY
    , pg_size_pretty(index_bytes) AS INDEX_PRETTY
    , pg_size_pretty(toast_bytes) AS TOAST_PRETTY
    , pg_size_pretty(table_bytes) AS TABLE_PRETTY
  FROM (
  SELECT *, total_bytes-index_bytes-COALESCE(toast_bytes,0) AS TABLE_BYTES FROM (
      SELECT c.oid,nspname AS table_schema, relname AS TABLE_NAME
              , c.reltuples::bigint AS ROW_ESTIMATE
              , pg_total_relation_size(c.oid) AS TOTAL_BYTES
              , pg_indexes_size(c.oid) AS INDEX_BYTES
              , pg_total_relation_size(reltoastrelid) AS TOAST_BYTES
          FROM pg_class c
          LEFT JOIN pg_namespace n ON n.oid = c.relnamespace
          WHERE relkind = 'r'
  ) a
) a
order by 5 desc
LIMIT 20;
\qecho </details>

\qecho <center>[<a class="noLink" href=#db-:curdb>Chapter Top</a>]</center><p>

-- +----------------------------------------------------------------------------+
-- |      - TOP20 Index Size                                       -                  |
-- +----------------------------------------------------------------------------+
\qecho <a name="Top20 Index Size"></a>
\qecho <font size="+2" face="Arial,Helvetica,Geneva,sans-serif" color="#16191f"><b>Top20 索引大小</b></font><hr align="left" width="460">
\qecho <br>

\qecho <h3>按大小排序的 Top20 索引（当前数据库）</h3>
\qecho <br>
\qecho <details open>
SELECT
schemaname as schema_name,relname as "Table",
indexrelname AS indexname,
pg_relation_size(indexrelid),
pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_catalog.pg_statio_all_indexes  ORDER BY 4 desc limit 20;
\qecho </details>

\qecho <center>[<a class="noLink" href=#db-:curdb>Chapter Top</a>]</center><p>

-- +----------------------------------------------------------------------------+
-- |      - Table  Statistics                              -                  |
-- +----------------------------------------------------------------------------+
\qecho <a name=db-:curdb-vacuum_Statistics></a>
\qecho <font size="+2" face="Arial,Helvetica,Geneva,sans-serif" color="#16191f"><b>表统计信息</b></font><hr align="left" width="460">
--Which tables are currently eligible for autovacuum based on curret parameters
\qecho <h3>待 VACUUM </h3>
\qecho <br>
\qecho <details open>
WITH vbt AS (SELECT setting AS autovacuum_vacuum_threshold FROM pg_settings WHERE name = 'autovacuum_vacuum_threshold')
    , vsf AS (SELECT setting AS autovacuum_vacuum_scale_factor FROM pg_settings WHERE name = 'autovacuum_vacuum_scale_factor')
    , fma AS (SELECT setting AS autovacuum_freeze_max_age FROM pg_settings WHERE name = 'autovacuum_freeze_max_age')
    , sto AS (select opt_oid, split_part(setting, '=', 1) as param, split_part(setting, '=', 2) as value from (select oid opt_oid, unnest(reloptions) setting from pg_class) opt)
SELECT
    '"'||ns.nspname||'"."'||c.relname||'"' as relation
    , pg_size_pretty(pg_table_size(c.oid)) as table_size
    , age(relfrozenxid) as xid_age
    , coalesce(cfma.value::float, autovacuum_freeze_max_age::float) autovacuum_freeze_max_age
    , (coalesce(cvbt.value::float, autovacuum_vacuum_threshold::float) + coalesce(cvsf.value::float,autovacuum_vacuum_scale_factor::float) * c.reltuples) as autovacuum_vacuum_tuples
    , n_dead_tup as dead_tuples
FROM pg_class c join pg_namespace ns on ns.oid = c.relnamespace
join pg_stat_all_tables stat on stat.relid = c.oid
join vbt on (1=1) join vsf on (1=1) join fma on (1=1)
left join sto cvbt on cvbt.param = 'autovacuum_vacuum_threshold' and c.oid = cvbt.opt_oid
left join sto cvsf on cvsf.param = 'autovacuum_vacuum_scale_factor' and c.oid = cvsf.opt_oid
left join sto cfma on cfma.param = 'autovacuum_freeze_max_age' and c.oid = cfma.opt_oid
WHERE c.relkind = 'r' and nspname <> 'pg_catalog'
and (
    age(relfrozenxid) >= coalesce(cfma.value::float, autovacuum_freeze_max_age::float)
    or
    coalesce(cvbt.value::float, autovacuum_vacuum_threshold::float) + coalesce(cvsf.value::float,autovacuum_vacuum_scale_factor::float) * c.reltuples <= n_dead_tup
   -- or 1 = 1
)
ORDER BY age(relfrozenxid) DESC LIMIT 20;
\qecho </details>
\qecho <br>
-- check if the statistics collector is enabled (track_counts is on)
\qecho <h3>TOP20 检查统计信息收集器是否启用（track_counts 为 on） </h3>
\qecho <br>
\qecho <details open>
SELECT name, setting FROM pg_settings WHERE name='track_counts';
\qecho </details>
\qecho <br>
-- to check the number of dead rows for the top 20 table
\qecho <h3>按死元组数量排序的 Top20 表</h3>
\qecho <br>
\qecho <details open>
select schemaname as schema_name,relname AS table_name,n_live_tup, n_tup_upd, n_tup_del, n_dead_tup, last_vacuum, last_autovacuum, last_analyze, last_autoanalyze  from pg_stat_all_tables order by n_dead_tup desc limit 20;
\qecho </details>
\qecho <br>
\qecho <h3>死元组超过 20% 的 Top20 表 </h3>
\qecho <br>
\qecho <details open>
select schemaname,relname , last_vacuum,last_autovacuum,n_live_tup,n_dead_tup , trunc((n_dead_tup::numeric/nullif(n_live_tup+n_dead_tup,0))* 100,2) as "n_dead_tup_%" from pg_stat_all_tables  where n_dead_tup::float/nullif(n_live_tup+n_dead_tup,0) >.2 order by n_live_tup desc limit 20;
\qecho </details>
\qecho <br>

\qecho <h3>未执行 auto analyze/auto vacuum/vacuum/analyze 的 Top20 表（按 n_dead_tup 排序） </h3>
\qecho <br>
\qecho <details open>
\qecho <br>
select relname,schemaname,n_dead_tup,last_vacuum,vacuum_count,last_autovacuum,autovacuum_count,last_autoanalyze,autoanalyze_count,last_analyze,analyze_count from pg_stat_all_tables  where  autoanalyze_count = 0 and autovacuum_count  = 0 and analyze_count = 0 and vacuum_count=0 order by n_dead_tup desc limit 20;  
\qecho </details>
\qecho <br>
\qecho <h3>已禁用 autovacuum（autovacuum_enabled=off|false）的表（表级别） </h3>
\qecho <br>
\qecho <details open>
select relname as table_name , pg_namespace.nspname as schema_name ,reloptions from pg_class  ,pg_namespace  where (pg_class.reloptions::text like '%autovacuum_enabled=off%'  or  pg_class.reloptions::text like '%autovacuum_enabled=false%' ) and pg_class.relnamespace = pg_namespace.oid ;
\qecho </details>
\qecho <br>\qecho <h3>已设置特定表级参数的表 </h3>
\qecho <br>
\qecho <details open>
select relname as table_name , pg_namespace.nspname as schema_name ,reloptions from pg_class ,pg_namespace  where pg_class.reloptions is not null and pg_class.relnamespace = pg_namespace.oid ;
\qecho </details>

\qecho <center>[<a class="noLink" href=#db-:curdb>Chapter Top</a>]</center><p>
-- +----------------------------------------------------------------------------+
-- |      - Table Access Profile                             -                  |
-- +----------------------------------------------------------------------------+
\qecho <a name="table_Access_Profile"></a>
\qecho <font size="+2" face="Arial,Helvetica,Geneva,sans-serif" color="#16191f"><b>表访问概况</b></font><hr align="left" width="460">
\qecho <br>
\qecho <details open> 
with table_size_info as 
(SELECT
schemaname as schema_name,relname as "Table",
pg_relation_size(relid) relation_size,
relid,
pg_size_pretty(pg_relation_size(relid)) AS "table_size",
pg_size_pretty(pg_total_relation_size(relid)) AS "TABLE size + indexes",
pg_size_pretty(pg_total_relation_size(relid) - pg_relation_size(relid)) as "indexes size"
FROM pg_catalog.pg_statio_all_tables ORDER BY 1,3  desc)
Select
b.schema_name,
a.relname as "Table_Name",
b.table_size as "Table_Size",
a.seq_scan  total_fts_scan ,
a.seq_tup_read total_fts_num_rows_reads,
a.seq_tup_read/NULLIF(a.seq_scan,0)  fts_rows_per_read ,
a.idx_scan total_idx_scan,
a.idx_tup_fetch total_Idx_num_rows_read ,
a.idx_tup_fetch/NULLIF(a.idx_scan,0)  idx_rows_per_read,
trunc((idx_scan::numeric/NULLIF((idx_scan::numeric+seq_scan::numeric),0)) * 100,2) as "IDX_scan_%",
trunc((seq_scan::numeric/NULLIF((idx_scan::numeric+seq_scan::numeric),0)) * 100,2) as "FTS_scan_%",
case when seq_scan>idx_scan then 'FTS' else 'IDX' end access_profile,
a.n_live_tup,
a.n_dead_tup,
trunc((n_dead_tup::numeric/NULLIF(n_live_tup::numeric,0)) * 100,2) as "dead_tup_%",
a.n_tup_ins,
a.n_tup_upd, 
a.n_tup_del,
trunc((n_tup_ins::numeric/NULLIF((n_tup_ins::numeric+n_tup_upd::numeric+n_tup_del::numeric),0)) * 100,2) as "tup_ins_%",
trunc((n_tup_upd::numeric/NULLIF((n_tup_ins::numeric+n_tup_upd::numeric+n_tup_del::numeric),0)) * 100,2) as "tup_upd_%",
trunc((n_tup_del::numeric/NULLIF((n_tup_ins::numeric+n_tup_upd::numeric+n_tup_del::numeric),0)) * 100,2) as "tup_del_%" 
from pg_stat_all_tables  a ,  table_size_info  b
where a.relid=b.relid 
and schema_name not in ('pg_catalog')
order  by b.relation_size  desc limit 20;
\qecho </details>
\qecho <br>
\qecho <h3> 主表大小超过 1GB 且全表扫描多于索引扫描的表TOP20</h3>
\qecho <br>
\qecho <details open>
with table_size_info as 
(SELECT
schemaname as schema_name,relname as "Table",
pg_relation_size(relid) relation_size,
relid,
pg_size_pretty(pg_relation_size(relid)) AS "table_size",
pg_size_pretty(pg_total_relation_size(relid)) AS "TABLE size + indexes",
pg_size_pretty(pg_total_relation_size(relid) - pg_relation_size(relid)) as "indexes size"
FROM pg_catalog.pg_statio_all_tables ORDER BY 1,3  desc)
Select
b.schema_name,
a.relname as "Table_Name",
b.table_size as "Table_Size",
a.seq_scan  total_fts_scan ,
a.seq_tup_read total_fts_num_rows_reads,
a.seq_tup_read/NULLIF(a.seq_scan,0)  fts_rows_per_read ,
a.idx_scan total_idx_scan,
a.idx_tup_fetch total_Idx_num_rows_read ,
a.idx_tup_fetch/NULLIF(a.idx_scan,0)  idx_rows_per_read,
trunc((idx_scan::numeric/NULLIF((idx_scan::numeric+seq_scan::numeric),0)) * 100,2) as "IDX_scan_%",
trunc((seq_scan::numeric/NULLIF((idx_scan::numeric+seq_scan::numeric),0)) * 100,2) as "FTS_scan_%",
case when seq_scan>idx_scan then 'FTS' else 'IDX' end access_profile,
a.n_live_tup,
a.n_dead_tup,
trunc((n_dead_tup::numeric/NULLIF(n_live_tup::numeric,0)) * 100,2) as "dead_tup_%",
a.n_tup_ins,
a.n_tup_upd, 
a.n_tup_del,
trunc((n_tup_ins::numeric/NULLIF((n_tup_ins::numeric+n_tup_upd::numeric+n_tup_del::numeric),0)) * 100,2) as "tup_ins_%",
trunc((n_tup_upd::numeric/NULLIF((n_tup_ins::numeric+n_tup_upd::numeric+n_tup_del::numeric),0)) * 100,2) as "tup_upd_%",
trunc((n_tup_del::numeric/NULLIF((n_tup_ins::numeric+n_tup_upd::numeric+n_tup_del::numeric),0)) * 100,2) as "tup_del_%" 
from pg_stat_all_tables  a ,  table_size_info  b
where a.relid=b.relid 
and schema_name not in ('pg_catalog', 'pg_toast')
and seq_scan>idx_scan
and b.relation_size > 1073741824
order by b.relation_size desc LIMIT 20;
\qecho </details>
\qecho <br>
\qecho <h4> pg_statio_all_tables 视图  </h4>
\qecho <h4> 总物理读（从磁盘读取的块） = heap_blks_read + idx_blks_read + toast_blks_read + tidx_blks_read  </h4>
\qecho <h4> 总逻辑读（缓冲命中或从内存读取）  = heap_blks_hits + idx_blks_hits + toast_blks_hits + tidx_blks_hits  </h4>
\qecho <br>
\qecho <h3> 按总物理读排序的 Top20 表 </h3>
\qecho <br> 
\qecho <details open>
select
s2.* , 
coalesce(trunc((s2.total_physical_reads::numeric/NULLIF((s2.total_physical_reads::numeric+s2.total_logical_reads::numeric),0)) * 100,2),0)  as physical_reads_percent,
coalesce(trunc((s2.total_logical_reads::numeric/NULLIF((s2.total_physical_reads::numeric+s2.total_logical_reads::numeric),0)) * 100,2),0)  as logical_reads_percent
from 
(
select 
s.* ,
s.table_disk_blocks_read+
s.indexes_disk_blocks_read+
s.TOAST_table_disk_blocks_read+
s.TOAST_indexes_disk_blocks_read as total_physical_reads,

s.table_buffer_hits+
s.indexes_buffer_hits+
s.TOAST_table_buffer_hits+
s.TOAST_indexes_buffer_hits as total_logical_reads 
from
(
select
schemaname as schema_name,
relname as table_name,
coalesce(heap_blks_read,0) table_disk_blocks_read ,
coalesce(heap_blks_hit,0)  table_buffer_hits ,
coalesce(idx_blks_read,0) indexes_disk_blocks_read ,
coalesce(idx_blks_hit,0)   indexes_buffer_hits ,
coalesce(toast_blks_read,0) TOAST_table_disk_blocks_read ,
coalesce(toast_blks_hit,0)  TOAST_table_buffer_hits ,
coalesce(tidx_blks_read,0)  TOAST_indexes_disk_blocks_read ,
coalesce(tidx_blks_hit,0)   TOAST_indexes_buffer_hits 
from pg_statio_all_tables 
where schemaname not in ('pg_toast','pg_catalog','information_schema')
 ) as s

) as s2
order by s2.total_physical_reads  desc limit 20 ;
\qecho </details>
\qecho <br> 
\qecho <h3> 按总物理读比例排序的 Top20 表  </h3>
\qecho <br> 
\qecho <details open>
select 
s2.* , 
coalesce(trunc((s2.total_physical_reads::numeric/NULLIF((s2.total_physical_reads::numeric+s2.total_logical_reads::numeric),0)) * 100,2),0)  as physical_reads_percent,
coalesce(trunc((s2.total_logical_reads::numeric/NULLIF((s2.total_physical_reads::numeric+s2.total_logical_reads::numeric),0)) * 100,2),0)  as logical_reads_percent
from 
(
select 
s.* ,
s.table_disk_blocks_read+
s.indexes_disk_blocks_read+
s.TOAST_table_disk_blocks_read+
s.TOAST_indexes_disk_blocks_read as total_physical_reads,

s.table_buffer_hits+
s.indexes_buffer_hits+
s.TOAST_table_buffer_hits+
s.TOAST_indexes_buffer_hits as total_logical_reads 
from
(
select
schemaname as schema_name,
relname as table_name,
coalesce(heap_blks_read,0) table_disk_blocks_read ,
coalesce(heap_blks_hit,0)  table_buffer_hits ,
coalesce(idx_blks_read,0) indexes_disk_blocks_read ,
coalesce(idx_blks_hit,0)   indexes_buffer_hits ,
coalesce(toast_blks_read,0) TOAST_table_disk_blocks_read ,
coalesce(toast_blks_hit,0)  TOAST_table_buffer_hits ,
coalesce(tidx_blks_read,0)  TOAST_indexes_disk_blocks_read ,
coalesce(tidx_blks_hit,0)   TOAST_indexes_buffer_hits 
from pg_statio_all_tables
where schemaname not in ('pg_toast','pg_catalog','information_schema')  
) as s

) as s2 
order by physical_reads_percent  desc limit 20  ;
\qecho </details>

\qecho <center>[<a class="noLink" href=#db-:curdb>Chapter Top</a>]</center><p>

-- +----------------------------------------------------------------------------+
-- |      - Index Access Profile                             -                  |
-- +----------------------------------------------------------------------------+
\qecho <a name="Index_Access_Profile"></a>
\qecho <font size="+2" face="Arial,Helvetica,Geneva,sans-serif" color="#16191f"><b>索引访问概况</b></font><hr align="left" width="460">
\qecho <br>
\qecho <details open>
with index_size_info as 
(
SELECT
schemaname,relname as "Table",
indexrelname AS indexname,
indexrelid,
pg_relation_size(indexrelid) index_size_byte,
pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_catalog.pg_statio_all_indexes  ORDER BY 1,4 desc) 
Select a.schemaname, 
a.relname as "Table_Name",
a.indexrelname AS indexname,
b.index_size,
a.idx_scan,
a.idx_tup_read,
a.idx_tup_fetch
from pg_stat_all_indexes a ,  index_size_info b
where a.idx_scan >0  
and a.indexrelid=b.indexrelid
and a.schemaname not in ('pg_catalog')
order by b.index_size_byte desc,a.idx_scan asc limit 20;
\qecho </details>
\qecho <br> 
\qecho <h3> 按物理读排序的 Top20 索引 </h3>
\qecho <br> 
\qecho <details open>
select
schemaname        as schema_name  ,
relname            as table_name     ,
indexrelname    as index_name,
coalesce(idx_blks_read,0)   as indexe_disk_blocks_read,
coalesce(idx_blks_hit,0)    as indexe_buffer_hits    ,
coalesce(trunc((coalesce(idx_blks_read,0)
/ 
NULLIF(
coalesce(idx_blks_read,0)
+coalesce(idx_blks_hit,0)
,0) ) * 100,2),0) as physical_reads_percent ,
coalesce(trunc((coalesce(idx_blks_hit,0)
/ 
NULLIF(
coalesce(idx_blks_read,0)
+coalesce(idx_blks_hit,0)
,0) ) * 100,2),0) as logical_reads_percent
from 
pg_statio_all_indexes 
where schemaname not in ('pg_toast','pg_catalog','information_schema')
order by indexe_disk_blocks_read desc limit 20 ;
\qecho </details>
\qecho <br>
\qecho <h3> 按物理读比例排序的 Top20 索引  </h3>
\qecho <br> 
\qecho <details open>
select
schemaname        as schema_name  ,
relname            as table_name     ,
indexrelname    as index_name,
coalesce(idx_blks_read,0)   as indexe_disk_blocks_read,
coalesce(idx_blks_hit,0)    as indexe_buffer_hits    ,
coalesce(trunc((coalesce(idx_blks_read,0)
/ 
NULLIF(
coalesce(idx_blks_read,0)
+coalesce(idx_blks_hit,0)
,0) ) * 100,2),0) as physical_reads_percent ,
coalesce(trunc((coalesce(idx_blks_hit,0)
/ 
NULLIF(
coalesce(idx_blks_read,0)
+coalesce(idx_blks_hit,0)
,0) ) * 100,2),0) as logical_reads_percent
from 
pg_statio_all_indexes 
where schemaname not in ('pg_toast','pg_catalog','information_schema')
order by physical_reads_percent desc limit 20 ;
\qecho </details>

\qecho <center>[<a class="noLink" href=#db-:curdb>Chapter Top</a>]</center><p>
-- +----------------------------------------------------------------------------+
-- |      - Fragmentation (Bloat)                                -                  |
-- +----------------------------------------------------------------------------+   
\qecho <a name=db-:curdb-Fragmentation></a>
\qecho <font size="+2" face="Arial,Helvetica,Geneva,sans-serif" color="#16191f"><b>碎片化（膨胀）</b></font><hr align="left" width="460">
-- Show database bloat
\qecho <br>
\qecho <h3>按表浪费空间排序的 Top20 表和索引膨胀 [碎片化] </h3>
\qecho <br>
\qecho <details open>
SELECT
  schemaname, tablename, /*reltuples::bigint, relpages::bigint, otta,*/
  ROUND((CASE WHEN otta=0 THEN 0.0 ELSE sml.relpages::FLOAT/otta END)::NUMERIC,1) AS "table_bloat_ratio",
  CASE WHEN relpages < otta THEN 0 ELSE bs*(sml.relpages-otta)::BIGINT END AS wastedbytes,
  pg_size_pretty(CASE WHEN relpages < otta THEN 0 ELSE bs*(sml.relpages-otta)::BIGINT END) AS table_wasted_size,
  iname AS Index_nam, /*ituples::bigint, ipages::bigint, iotta,*/
  ROUND((CASE WHEN iotta=0 OR ipages=0 THEN 0.0 ELSE ipages::FLOAT/iotta END)::NUMERIC,1) AS "Index_bloat_ratio",
  CASE WHEN ipages < iotta THEN 0 ELSE bs*(ipages-iotta) END AS wastedibytes,
  pg_size_pretty(CASE WHEN ipages < iotta THEN 0 ELSE bs*(ipages-iotta) ::BIGINT END) AS Index_wasted_size
FROM (
  SELECT
    schemaname, tablename, cc.reltuples, cc.relpages, bs,
    CEIL((cc.reltuples*((datahdr+ma-
      (CASE WHEN datahdr%ma=0 THEN ma ELSE datahdr%ma END))+nullhdr2+4))/(bs-20::FLOAT)) AS otta,
    COALESCE(c2.relname,'?') AS iname, COALESCE(c2.reltuples,0) AS ituples, COALESCE(c2.relpages,0) AS ipages,
    COALESCE(CEIL((c2.reltuples*(datahdr-12))/(bs-20::FLOAT)),0) AS iotta -- very rough approximation, assumes all cols
  FROM (
    SELECT
      ma,bs,schemaname,tablename,
      (datawidth+(hdr+ma-(CASE WHEN hdr%ma=0 THEN ma ELSE hdr%ma END)))::NUMERIC AS datahdr,
      (maxfracsum*(nullhdr+ma-(CASE WHEN nullhdr%ma=0 THEN ma ELSE nullhdr%ma END))) AS nullhdr2
    FROM (
      SELECT
        schemaname, tablename, hdr, ma, bs,
        SUM((1-null_frac)*avg_width) AS datawidth,
        MAX(null_frac) AS maxfracsum,
        hdr+(
          SELECT 1+COUNT(*)/8
          FROM pg_stats s2
          WHERE null_frac<>0 AND s2.schemaname = s.schemaname AND s2.tablename = s.tablename
        ) AS nullhdr
      FROM pg_stats s, (
        SELECT
          (SELECT current_setting('block_size')::NUMERIC) AS bs,
          CASE WHEN SUBSTRING(v,12,3) IN ('8.0','8.1','8.2') THEN 27 ELSE 23 END AS hdr,
          CASE WHEN v ~ 'mingw32' THEN 8 ELSE 4 END AS ma
        FROM (SELECT version() AS v) AS foo
      ) AS constants
      GROUP BY 1,2,3,4,5
    ) AS foo
  ) AS rs
  JOIN pg_class cc ON cc.relname = rs.tablename
  JOIN pg_namespace nn ON cc.relnamespace = nn.oid AND nn.nspname = rs.schemaname AND nn.nspname <> 'information_schema'
  LEFT JOIN pg_index i ON indrelid = cc.oid
  LEFT JOIN pg_class c2 ON c2.oid = i.indexrelid
) AS sml
ORDER BY wastedbytes DESC limit 20; 
\qecho </details>

\qecho <br>
\qecho <h3>按表浪费比例排序的 Top20 表和索引膨胀 [碎片化] </h3>
\qecho <br>
\qecho <details open>
SELECT
  schemaname, tablename, /*reltuples::bigint, relpages::bigint, otta,*/
  ROUND((CASE WHEN otta=0 THEN 0.0 ELSE sml.relpages::FLOAT/otta END)::NUMERIC,1) AS "table_bloat_ratio",
  CASE WHEN relpages < otta THEN 0 ELSE bs*(sml.relpages-otta)::BIGINT END AS wastedbytes,
  pg_size_pretty(CASE WHEN relpages < otta THEN 0 ELSE bs*(sml.relpages-otta)::BIGINT END) AS table_wasted_size,
  iname AS Index_nam, /*ituples::bigint, ipages::bigint, iotta,*/
  ROUND((CASE WHEN iotta=0 OR ipages=0 THEN 0.0 ELSE ipages::FLOAT/iotta END)::NUMERIC,1) AS "Index_bloat_ratio",
  CASE WHEN ipages < iotta THEN 0 ELSE bs*(ipages-iotta) END AS wastedibytes,
  pg_size_pretty(CASE WHEN ipages < iotta THEN 0 ELSE bs*(ipages-iotta) ::BIGINT END) AS Index_wasted_size
FROM (
  SELECT
    schemaname, tablename, cc.reltuples, cc.relpages, bs,
    CEIL((cc.reltuples*((datahdr+ma-
      (CASE WHEN datahdr%ma=0 THEN ma ELSE datahdr%ma END))+nullhdr2+4))/(bs-20::FLOAT)) AS otta,
    COALESCE(c2.relname,'?') AS iname, COALESCE(c2.reltuples,0) AS ituples, COALESCE(c2.relpages,0) AS ipages,
    COALESCE(CEIL((c2.reltuples*(datahdr-12))/(bs-20::FLOAT)),0) AS iotta -- very rough approximation, assumes all cols
  FROM (
    SELECT
      ma,bs,schemaname,tablename,
      (datawidth+(hdr+ma-(CASE WHEN hdr%ma=0 THEN ma ELSE hdr%ma END)))::NUMERIC AS datahdr,
      (maxfracsum*(nullhdr+ma-(CASE WHEN nullhdr%ma=0 THEN ma ELSE nullhdr%ma END))) AS nullhdr2
    FROM (
      SELECT
        schemaname, tablename, hdr, ma, bs,
        SUM((1-null_frac)*avg_width) AS datawidth,
        MAX(null_frac) AS maxfracsum,
        hdr+(
          SELECT 1+COUNT(*)/8
          FROM pg_stats s2
          WHERE null_frac<>0 AND s2.schemaname = s.schemaname AND s2.tablename = s.tablename
        ) AS nullhdr
      FROM pg_stats s, (
        SELECT
          (SELECT current_setting('block_size')::NUMERIC) AS bs,
          CASE WHEN SUBSTRING(v,12,3) IN ('8.0','8.1','8.2') THEN 27 ELSE 23 END AS hdr,
          CASE WHEN v ~ 'mingw32' THEN 8 ELSE 4 END AS ma
        FROM (SELECT version() AS v) AS foo
      ) AS constants
      GROUP BY 1,2,3,4,5
    ) AS foo
  ) AS rs
  JOIN pg_class cc ON cc.relname = rs.tablename
  JOIN pg_namespace nn ON cc.relnamespace = nn.oid AND nn.nspname = rs.schemaname AND nn.nspname <> 'information_schema'
  LEFT JOIN pg_index i ON indrelid = cc.oid
  LEFT JOIN pg_class c2 ON c2.oid = i.indexrelid
) AS sml
ORDER BY 4 desc limit 20; 
\qecho </details>

\qecho <br>
\qecho <h3>按索引浪费比例排序的 Top20 表和索引膨胀 [碎片化] </h3>
\qecho <br>
\qecho <details open>
SELECT
  schemaname, tablename, /*reltuples::bigint, relpages::bigint, otta,*/
  ROUND((CASE WHEN otta=0 THEN 0.0 ELSE sml.relpages::FLOAT/otta END)::NUMERIC,1) AS "table_bloat_ratio",
  CASE WHEN relpages < otta THEN 0 ELSE bs*(sml.relpages-otta)::BIGINT END AS wastedbytes,
  pg_size_pretty(CASE WHEN relpages < otta THEN 0 ELSE bs*(sml.relpages-otta)::BIGINT END) AS table_wasted_size,
  iname AS Index_nam, /*ituples::bigint, ipages::bigint, iotta,*/
  ROUND((CASE WHEN iotta=0 OR ipages=0 THEN 0.0 ELSE ipages::FLOAT/iotta END)::NUMERIC,1) AS "Index_bloat_ratio",
  CASE WHEN ipages < iotta THEN 0 ELSE bs*(ipages-iotta) END AS wastedibytes,
  pg_size_pretty(CASE WHEN ipages < iotta THEN 0 ELSE bs*(ipages-iotta) ::BIGINT END) AS Index_wasted_size
FROM (
  SELECT
    schemaname, tablename, cc.reltuples, cc.relpages, bs,
    CEIL((cc.reltuples*((datahdr+ma-
      (CASE WHEN datahdr%ma=0 THEN ma ELSE datahdr%ma END))+nullhdr2+4))/(bs-20::FLOAT)) AS otta,
    COALESCE(c2.relname,'?') AS iname, COALESCE(c2.reltuples,0) AS ituples, COALESCE(c2.relpages,0) AS ipages,
    COALESCE(CEIL((c2.reltuples*(datahdr-12))/(bs-20::FLOAT)),0) AS iotta -- very rough approximation, assumes all cols
  FROM (
    SELECT
      ma,bs,schemaname,tablename,
      (datawidth+(hdr+ma-(CASE WHEN hdr%ma=0 THEN ma ELSE hdr%ma END)))::NUMERIC AS datahdr,
      (maxfracsum*(nullhdr+ma-(CASE WHEN nullhdr%ma=0 THEN ma ELSE nullhdr%ma END))) AS nullhdr2
    FROM (
      SELECT
        schemaname, tablename, hdr, ma, bs,
        SUM((1-null_frac)*avg_width) AS datawidth,
        MAX(null_frac) AS maxfracsum,
        hdr+(
          SELECT 1+COUNT(*)/8
          FROM pg_stats s2
          WHERE null_frac<>0 AND s2.schemaname = s.schemaname AND s2.tablename = s.tablename
        ) AS nullhdr
      FROM pg_stats s, (
        SELECT
          (SELECT current_setting('block_size')::NUMERIC) AS bs,
          CASE WHEN SUBSTRING(v,12,3) IN ('8.0','8.1','8.2') THEN 27 ELSE 23 END AS hdr,
          CASE WHEN v ~ 'mingw32' THEN 8 ELSE 4 END AS ma
        FROM (SELECT version() AS v) AS foo
      ) AS constants
      GROUP BY 1,2,3,4,5
    ) AS foo
  ) AS rs
  JOIN pg_class cc ON cc.relname = rs.tablename
  JOIN pg_namespace nn ON cc.relnamespace = nn.oid AND nn.nspname = rs.schemaname AND nn.nspname <> 'information_schema'
  LEFT JOIN pg_index i ON indrelid = cc.oid
  LEFT JOIN pg_class c2 ON c2.oid = i.indexrelid
) AS sml
ORDER BY 8 desc limit 20; 
\qecho </details>

\qecho <center>[<a class="noLink" href=#db-:curdb>Chapter Top</a>]</center><p>

-- +----------------------------------------------------------------------------+
-- |      - Unused Indexes                                 -                  |
-- +----------------------------------------------------------------------------+
\qecho <a name=db-:curdb-Unused_Indexes></a>
\qecho <font size="+2" face="Arial,Helvetica,Geneva,sans-serif" color="#16191f"><b>未使用的索引TOP20</b></font><hr align="left" width="460">
\qecho <br>
\qecho <details open>
SELECT ai.schemaname,ai.relname AS tablename,ai.indexrelid  as index_oid ,
ai.indexrelname AS indexname,i.indisunique ,
ai.idx_scan ,
pg_relation_size(ai.indexrelid) as index_size,
pg_size_pretty(pg_relation_size(ai.indexrelid)) AS pretty_index_size
FROM pg_catalog.pg_stat_all_indexes ai , pg_index i
WHERE ai.indexrelid=i.indexrelid
and ai.idx_scan = 0 
and ai.schemaname not in ('pg_catalog','pg_toast')
order by index_size desc LIMIT 20;
\qecho </details>

\qecho <center>[<a class="noLink" href=#db-:curdb>Chapter Top</a>]</center><p>

-- +----------------------------------------------------------------------------+
-- |      - FK without index                                 -                  |
-- +----------------------------------------------------------------------------+ 
\qecho <a name=db-:curdb-FK_without_index></a>
\qecho <font size="+2" face="Arial,Helvetica,Geneva,sans-serif" color="#16191f"><b>外键无索引</b></font><hr align="left" width="460">

\qecho <br>
\qecho <details open>
SELECT c.conrelid::regclass AS "table",
       /* list of key column names in order */
       string_agg(a.attname, ',' ORDER BY x.n) AS columns,
       pg_catalog.pg_size_pretty(
          pg_catalog.pg_relation_size(c.conrelid)
       ) AS size,
       c.conname AS constraint,
       c.confrelid::regclass AS referenced_table
FROM pg_catalog.pg_constraint c
   /* enumerated key column numbers per foreign key */
   CROSS JOIN LATERAL
      unnest(c.conkey) WITH ORDINALITY AS x(attnum, n)
   /* name for each key column */
   JOIN pg_catalog.pg_attribute a
      ON a.attnum = x.attnum
         AND a.attrelid = c.conrelid
WHERE NOT EXISTS
        /* is there a matching index for the constraint? */
        (SELECT 1 FROM pg_catalog.pg_index i
         WHERE i.indrelid = c.conrelid
           /* the first index columns must be the same as the
              key columns, but order doesn't matter */
           AND (i.indkey::smallint[])[0:cardinality(c.conkey)-1]
               OPERATOR(pg_catalog.@>) c.conkey)
  AND c.contype = 'f'
GROUP BY c.conrelid, c.conname, c.confrelid
ORDER BY pg_catalog.pg_relation_size(c.conrelid) DESC;
\qecho </details>

\qecho <center>[<a class="noLink" href=#db-:curdb>Chapter Top</a>]</center><p>

-- +----------------------------------------------------------------------------+
-- |      - Invalid indexes                                  -                  |
-- +----------------------------------------------------------------------------+
\qecho <a name=db-:curdb-invalid_indexes></a>
\qecho <font size="+2" face="Arial,Helvetica,Geneva,sans-serif" color="#16191f"><b>失效索引</b></font><hr align="left" width="460">
\qecho <br>
\qecho <details open>

with table_info as 
(SELECT pg_index.indrelid , pg_class.oid, pg_class.relname as table_name 
from   pg_class , pg_index
where pg_index.indrelid = pg_class.oid )
SELECT distinct pg_index.indexrelid as INDX_ID,pg_class.relname as index_name ,table_info.table_name,pg_namespace.nspname as schema_name  , pg_class.relowner as owner_id , pg_index.indisvalid as indx_is_valid
FROM pg_class , pg_index ,pg_namespace , table_info
WHERE pg_index.indisvalid = false 
AND pg_index.indexrelid = pg_class.oid
and pg_class.relnamespace = pg_namespace.oid
and pg_index.indrelid = table_info.oid;
\qecho </details>

\qecho <center>[<a class="noLink" href=#db-:curdb>Chapter Top</a>]</center><p>

-- +----------------------------------------------------------------------------+
-- |      - Duplicate indexes                               -                  |
-- +----------------------------------------------------------------------------+ 
\qecho <a name=db-:curdb-Duplicate_indexes></a>
\qecho <font size="+2" face="Arial,Helvetica,Geneva,sans-serif" color="#16191f"><b>重复索引</b></font><hr align="left" width="460">
\qecho <br>
\qecho <br>
\qecho <details open>
SELECT pg_size_pretty(sum(pg_relation_size(idx))::bigint) as size,
       (array_agg(idx))[1] as idx1, (array_agg(idx))[2] as idx2,
       (array_agg(idx))[3] as idx3, (array_agg(idx))[4] as idx4
FROM (
    SELECT indexrelid::regclass as idx, (indrelid::text ||E'\n'|| indclass::text ||E'\n'|| indkey::text ||E'\n'||
                                         coalesce(indexprs::text,'')||E'\n' || coalesce(indpred::text,'')) as key
    FROM pg_index) sub
GROUP BY key HAVING count(*)>1
ORDER BY sum(pg_relation_size(idx)) DESC LIMIT 20;
\qecho </details>

\qecho <center>[<a class="noLink" href=#db-:curdb>Chapter Top</a>]</center><p>

-- +----------------------------------------------------------------------------+
-- |      - Unlogged tables                                  -                  |
-- +----------------------------------------------------------------------------+
\qecho <a name=db-:curdb-unlogged_tables></a>
\qecho <font size="+2" face="Arial,Helvetica,Geneva,sans-serif" color="#16191f"><b>Unlogged 表</b></font><hr align="left" width="460">
\qecho <br>
\qecho <details open>

select relname as table_name, relpersistence FROM pg_class WHERE relpersistence = 'u';
\qecho </details>

\qecho <center>[<a class="noLink" href=#db-:curdb>Chapter Top</a>]</center><p>

-- +----------------------------------------------------------------------------+
-- |      - Temp tables                                  -                  |
-- +----------------------------------------------------------------------------+
\qecho <a name="Temp_tables"></a>
\qecho <font size="+2" face="Arial,Helvetica,Geneva,sans-serif" color="#16191f"><b>临时表</b></font><hr align="left" width="460">

\qecho <br>
\qecho <details open>
\qecho <h3>参数</h3>

select 
name as parameter_name,setting,unit, short_desc  
FROM pg_catalog.pg_settings 
WHERE name in ('temp_buffers','temp_tablespaces','temp_file_limit','log_temp_files') order by name;
\qecho <br>

\qecho <h3>临时表统计信息</h3>
\qecho <h4>注意：每个数据库中查询创建的临时文件数量及查询写入临时文件的数据总量(累计) </h4>
\qecho <br>
select datname as database_name,temp_bytes/1024/1024/1024 temp_size_GB ,temp_files  from  pg_stat_database
where  temp_bytes + temp_files > 0
and datname is not null  
order by 2  desc;

\qecho <br>
SELECT
n.nspname as SchemaName
,c.relname as RelationName
,CASE c.relkind
WHEN 'r' THEN 'table'
WHEN 'v' THEN 'view'
WHEN 'i' THEN 'index'
WHEN 'S' THEN 'sequence'
WHEN 's' THEN 'special'
END as RelationType
,pg_catalog.pg_get_userbyid(c.relowner) as RelationOwner
,pg_size_pretty(pg_relation_size(n.nspname ||'.'|| c.relname)) as RelationSize
FROM pg_catalog.pg_class c
LEFT JOIN pg_catalog.pg_namespace n
ON n.oid = c.relnamespace
WHERE c.relkind IN ('r','s')
AND (n.nspname !~ '^pg_toast' and nspname like 'pg_temp%')
ORDER BY pg_relation_size(n.nspname ||'.'|| c.relname) DESC LIMIT 20;
\qecho </details>

\qecho <center>[<a class="noLink" href=#db-:curdb>Chapter Top</a>]</center><p>

-- +----------------------------------------------------------------------------+
-- |      - Large objects                                    -                  |
-- +----------------------------------------------------------------------------+ 
\qecho <a name="Large_objects"></a>
\qecho <font size="+2" face="Arial,Helvetica,Geneva,sans-serif" color="#16191f"><b>大对象</b></font><hr align="left" width="460">
\qecho <br>
\qecho <details open>
\qecho <br>

\qecho <h3>各用户大对象数量统计（当前数据库） </h3>
select pg_get_userbyid(lomowner) as user_name ,count (*) as number_of_lo from pg_largeobject_metadata 
group by 1  order by 2 desc LIMIT 20;

\qecho <br>
\qecho <h3>pg_largeobject_metadata 表大小（当前数据库）</h3>
\dt+ pg_largeobject_metadata;

\qecho </details>

\qecho <center>[<a class="noLink" href=#db-:curdb>Chapter Top</a>]</center><p>

-- +----------------------------------------------------------------------------+
-- |      - Partition tables                                 -                  |
-- +----------------------------------------------------------------------------+ 
\qecho <a name="Partition_tables"></a>
\qecho <font size="+2" face="Arial,Helvetica,Geneva,sans-serif" color="#16191f"><b>分区表</b></font><hr align="left" width="460">

\qecho <br>
\qecho <details open>
\qecho <h3>子分区数TOP20的分区表</h3>
SELECT
    parent.oid                        AS parent_table_oid,
    parent.relname                    AS parent_table_name,
    count(child.oid)                  AS partition_count
FROM pg_inherits
    JOIN pg_class parent            ON pg_inherits.inhparent = parent.oid
    JOIN pg_class child             ON pg_inherits.inhrelid   = child.oid 
    group by 1,2
    order by 3 desc limit 20;
\qecho <br>
\qecho </details>

\qecho <center>[<a class="noLink" href=#db-:curdb>Chapter Top</a>]</center><p>

-- +----------------------------------------------------------------------------+
-- |      - Sequences                                          -                  |
-- +----------------------------------------------------------------------------+ 
\qecho <a name=db-:curdb-sequences></a>
\qecho <font size="+2" face="Arial,Helvetica,Geneva,sans-serif" color="#16191f"><b>序列</b></font><hr align="left" width="460">
\qecho <br>
\qecho <details open>
\qecho <h3>剩余值不足 10%的序列</h3>
SELECT * FROM (SELECT 
    schemaname as Schema,
    sequencename as Sequence_Name,
    data_type::regtype as Data_Type,
    last_value as Current_Value,
    max_value as Max_Value,
    min_value as Min_Value,
    increment_by as Increment_By,
    cycle,
    cache_size,
    max_value - last_value as remaining_values,
    CASE 
        WHEN max_value = 9223372036854775807 THEN 'No Limit'
        ELSE round(((max_value - last_value)::numeric / (max_value - min_value)::numeric * 100), 2)::text || '%'
    END as Remaining_Percentage,
    CASE 
        WHEN max_value = 9223372036854775807 THEN 'No Action Needed'
        WHEN ((max_value - last_value)::numeric / (max_value - min_value)::numeric * 100) < 1 
        THEN '1-CRITICAL: Less than 1% remaining'
        WHEN ((max_value - last_value)::numeric / (max_value - min_value)::numeric * 100) < 5 
        THEN '2-WARNING: Less than 5% remaining'
        WHEN ((max_value - last_value)::numeric / (max_value - min_value)::numeric * 100) < 10 
        THEN '3-NOTICE: Less than 10% remaining'
        ELSE 'OK'
    END as Status
FROM pg_sequences) seq WHERE status not in ('OK', 'No Action Needed') Order by status;
\qecho </details>
\qecho <center>[<a class="noLink" href=#db-:curdb>Chapter Top</a>]</center><p>

-- +----------------------------------------------------------------------------+
-- |      - Functions statistics                             -                  |
-- +----------------------------------------------------------------------------+
\qecho <a name="functions_statistics"></a>
\qecho <font size="+2" face="Arial,Helvetica,Geneva,sans-serif" color="#16191f"><b>函数统计</b></font><hr align="left" width="460">
\qecho <br>
----The pg_stat_user_functions view will contain one row for each tracked function, showing statistics about executions of that function. 
\qecho <details open>
SELECT name,setting from pg_settings where name ='track_functions';
\qecho <br>
-- 检查函数总耗时top
\qecho <h3>总耗时TOP20的函数</h3>
select
schemaname||'.'||funcname func_name, calls, total_time,
round((total_time/calls)::numeric,2) as mean_time, self_time
from pg_catalog.pg_stat_user_functions
order by total_time desc limit 20;

\qecho </details>
\qecho <center>[<a class="noLink" href=#db-:curdb>Chapter Top</a>]</center><p>

-- +----------------------------------------------------------------------------+
-- |      - Triggers                                         -                  |
-- +----------------------------------------------------------------------------+
\qecho <a name="triggers"></a>
\qecho <font size="+2" face="Arial,Helvetica,Geneva,sans-serif" color="#16191f"><b>触发器</b></font><hr align="left" width="460">
\qecho <br>
\qecho <details open>
\qecho <h3>用户创建（非内部生成）且被禁用的触发器</h3>
SELECT
    n.nspname AS schema_name,
    c.relname AS table_name,
    t.tgname  AS trigger_name,
    t.tgenabled
FROM pg_trigger t
JOIN pg_class c
    ON c.oid = t.tgrelid
JOIN pg_namespace n
    ON n.oid = c.relnamespace
WHERE t.tgisinternal = false
and t.tgenabled='D'
ORDER BY n.nspname, c.relname, t.tgname;
\qecho </details>
\qecho <center>[<a class="noLink" href=#db-:curdb>Chapter Top</a>]</center><p>
