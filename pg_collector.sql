-- +-------------------------------------------------------------------------------------------------+
-- |  -- Script Name: pg_collector.sql                                                               |
-- |  -- Author : Mohamed Ali                                                                        |
-- |  -- Create Date : 16 SEPT 2019                                                                  |
-- |  -- Modifier: specter shoe                                                                               |
-- |  -- Modify Date : 29 OCT 2026                                                                   |
-- |  -- Description : Script to collect PostgreSQL Database Information and generate HTML Report    |
-- |  -- NEW : Add risk assessment and remove some check item,and inspect all databases    |
-- |  -- version : V 3.2.001                                                                             |
-- |  -- Changelog : https://github.com/awslabs/pg-collector/blob/main/CHANGELOG.md                  |
-- | Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.                              |
-- | SPDX-License-Identifier: MIT-0                                                                  |
-- +-------------------------------------------------------------------------------------------------+
\pset format html
\set filename :DBNAME-`date +%Y-%m-%d_%H%M%S`

-- +----------------------------------------------------------------------------+
-- |  Generate per-database loop command file.                                  |
-- |  MUST run before the report \o below, because \o truncates on open.        |
-- +----------------------------------------------------------------------------+
-- 设置目录
\set collector_dir ./
\pset format unaligned
\t on
\o /tmp/pg_collector_loop.sql
-- 通过增加条件来限制只检查或者不检查指定的数据库
SELECT cmd FROM (
  SELECT 1 ord, datname, format('\c %I', datname) cmd
  FROM pg_database WHERE datallowconn AND NOT datistemplate  -- AND datname IN ('shoedb','tpcc')
  UNION ALL
  SELECT 2, datname, format('\i %s/pg_collector_perdb.sql', :'collector_dir')
  FROM pg_database WHERE datallowconn AND NOT datistemplate  -- AND datname IN ('shoedb','tpcc')
) x ORDER BY datname, ord;

-- Generate database-name navigation rows (one link per database)
\o /tmp/pg_collector_dbnav.sql
WITH dbs AS (
  SELECT datname, (row_number() OVER (ORDER BY datname) - 1) / 4 AS grp
  FROM pg_database WHERE datallowconn AND NOT datistemplate  -- AND datname IN ('shoedb','tpcc')
)
SELECT '\qecho <tr>' || E'\n' ||
  string_agg('\qecho <td nowrap align="center" width="25%"><a class="link" href="#db-' || datname || '">' || datname || '</a></td>', E'\n' ORDER BY datname) ||
  E'\n' || '\qecho </tr>'
FROM dbs GROUP BY grp ORDER BY grp;
\o
\o
\t off
\pset format html
\o /tmp/pg_collector_:filename.html
\pset footer  off
\qecho <style type='text/css'> 
\qecho body { 
\qecho font:10pt Arial,Helvetica,sans-serif;
\qecho color:Black Russian; background:white; } 
\qecho p { 
\qecho font:10pt Arial,sans-serif;
\qecho color:Black Russian; background:white; } 
\qecho table,tr,td { 
\qecho font:10pt Arial,Helvetica,sans-serif; 
\qecho text-align:center; 
\qecho color:Black Russian; background:white; 
\qecho padding:0px 0px 0px 0px; margin:0px 0px 0px 0px; } 
\qecho th { 
\qecho font:bold 10pt Arial,Helvetica,sans-serif; 
\qecho color:#16191f; 
\qecho background:#e59003; 
\qecho padding:0px 0px 0px 0px;} 
\qecho h1 { 
\qecho font:bold 16pt Arial,Helvetica,Geneva,sans-serif; 
\qecho color:#16191f; 
\qecho background-color:#e59003; 
\qecho border-bottom:1px solid #e59003;
\qecho margin-top:0pt; margin-bottom:0pt; padding:0px 0px 0px 0px;} 
\qecho h2 {
\qecho font:bold 10pt Arial,Helvetica,Geneva,sans-serif;
\qecho color:#16191f; 
\qecho background-color:White; 
\qecho margin-top:4pt; margin-bottom:0pt;}
\qecho h3 {
\qecho font:bold 10pt Arial,Helvetica,Geneva,sans-serif;
\qecho color:#16191f;
\qecho background-color:White;
\qecho margin-top:4pt; margin-bottom:0pt;} 
\qecho a {
\qecho font:10pt Arial,Helvetica,sans-serif;
\qecho color:#663300;
\qecho background:#ffffff;
\qecho margin-top:0pt; margin-bottom:0pt;}
\qecho a[name] { display: block; scroll-margin-top: 20px; }
\qecho .threshold-critical { 
\qecho font:bold 10pt Arial,Helvetica,sans-serif; 
\qecho color:red; } 
\qecho .threshold-warning { 
\qecho font:bold 10pt Arial,Helvetica,sans-serif; 
\qecho color:orange; } 
\qecho .threshold-ok { 
\qecho font:bold 10pt Arial,Helvetica,sans-serif; 
\qecho color:green; } 
\qecho </style> 
\qecho <h1 align="center" style="background-color:#e59003" >PG COLLECTOR  V3.2.001</h1>
\qecho <font size="+1" face="Arial,Helvetica,Geneva,sans-serif" color="#16191f"><a href="https://github.com/awslabs/pg-collector" target="_blank">如需了解 PG Collector 的更多信息，请访问项目 GitHub 仓库</a></font><hr align="left" >
-- +----------------------------------------------------------------------------+
-- |      - 风险项与处理方法                                                   -  |
-- +----------------------------------------------------------------------------+
\qecho <font size="+2" face="Arial,Helvetica,Geneva,sans-serif" color="#16191f"><b>风险项与处理方法</b></font><hr align="left" width="460">

------------------------------------
-- 版本与功能兼容性检测 (兼容不同 PG 版本) --
------------------------------------
SELECT current_setting('server_version_num')::int >= 130000 AS is_pg_13_plus \gset
SELECT current_setting('server_version_num')::int >= 150000 AS is_pg_15_plus \gset
SELECT count(*) > 0 AS is_pg_stat_statements_enabled FROM pg_catalog.pg_extension WHERE extname = 'pg_stat_statements' \gset
SELECT false AS isauroralimitless \gset

------------------------------------
-- 检查数据库连接数是否过高(最大连接数的80%） --
------------------------------------
SELECT count(*) > (SELECT setting::int * 0.8 FROM pg_settings WHERE name = 'max_connections') obsrv_high_connections
FROM pg_stat_activity \gset


------------------------------------
-- 检查事务ID回卷风险（数据库年龄大于10亿）--
------------------------------------
SELECT max(age(datfrozenxid))  > 2^30 obsrv_txid_wrap FROM pg_database \gset

------------------------------------
-- 检查复制延迟（任意阶段延迟1分钟）--
------------------------------------
SELECT count(*) > 0 obsrv_replication_lag
FROM pg_stat_replication
WHERE state = 'streaming' 
AND (
write_lag > interval '1 minute' 
or flush_lag > interval '1 minute' 
or replay_lag > interval '1 minute') \gset

  
------------------------------------
-- 检查长事务（1小时） --
------------------------------------
SELECT count(*) > 0 obsrv_long_transactions
FROM pg_stat_activity
WHERE pid <> pg_backend_pid()
AND state <> 'idle'
AND xact_start < now() - interval '1 hour' \gset

------------------------------------
-- 检查空闲事务（30分钟） --
------------------------------------
SELECT count(*) > 0 obsrv_idle_in_transaction
FROM pg_stat_activity
WHERE state = 'idle in transaction'
AND state_change < now() - interval '30 minutes' \gset

------------------------------------
-- 检查阻塞会话 --
------------------------------------
SELECT count(*) > 0 obsrv_blocked_sessions
FROM pg_stat_activity
WHERE cardinality(pg_blocking_pids(pid)) > 0 \gset

------------------------------------
-- 检查缓存命中率（<95%） --
------------------------------------
SELECT coalesce(round((sum(blks_hit)::numeric / nullif(sum(blks_hit) + sum(blks_read), 0)) * 100, 2) < 95, false) obsrv_low_cache_hit
FROM pg_stat_database \gset

------------------------------------
-- 检查当前Temp文件使用（>1GB） --
------------------------------------
SELECT coalesce(sum(size) > 1073741824, false) obsrv_high_temp_usage
FROM pg_ls_tmpdir() \gset

------------------------------------
-- 检查持久化参数(fsync/full_page_writes) --
------------------------------------
SELECT count(*) > 0 obsrv_durability_settings_off
FROM pg_settings
WHERE (name = 'fsync' AND setting != 'on')
   OR (name = 'full_page_writes' AND setting != 'on') \gset

\qecho <table border="1" cellspacing="0" cellpadding="5" style="width:100%">
\qecho <tr>
\qecho <th>风险项</th>
\qecho <th>描述</th>
\qecho <th>处理方法</th>
\qecho </tr>

\if :obsrv_high_connections
\qecho <tr>
\qecho <td class="threshold-critical"><a class="link" href="#sessions_info">数据库连接数过高</a></td>
\qecho <td>连接数超过最大限制的80%，可能导致新连接被拒绝</td>
\qecho <td>1. 检查并优化应用程序连接池配置<br>2. 最大连接数配置是否合理<br>3. 关闭空闲连接</td>
\qecho </tr>
\else
\endif


\if :obsrv_txid_wrap
\qecho <tr>
\qecho <td class="threshold-critical"><a class="link" href="#Transaction_ID_TXID(Wraparound)">事务ID回卷风险</a></td>
\qecho <td>事务ID接近最大值，可能导致数据库不可用</td>
\qecho <td>1. 执行VACUUM FREEZE<br>2. 监控txid_current()值<br>3. 确保自动VACUUM正常运行</td>
\qecho </tr>
\else
\endif


\if :obsrv_replication_lag
\qecho <tr>
\qecho <td class="threshold-critical"><a class="link" href="#Replication">复制延迟</a></td>
\qecho <td>主从复制延迟过大，影响数据一致性</td>
\qecho <td>1. 检查网络连接<br>2. 优化复制配置<br>3. 监控复制状态</td>
\qecho </tr>
\else
\endif

\if :obsrv_long_transactions
\qecho <tr>
\qecho <td class="threshold-warning"><a class="link" href="#sessions_info">长事务</a></td>
\qecho <td>存在运行超过1小时的事务，可能阻塞VACUUM并持有锁资源</td>
\qecho <td>1. 终止不必要的长事务<br>2. 优化事务逻辑<br>3. 监控pg_stat_activity</td>
\qecho </tr>
\else
\endif

\if :obsrv_idle_in_transaction
\qecho <tr>
\qecho <td class="threshold-warning"><a class="link" href="#sessions_info">空闲事务堆积</a></td>
\qecho <td>存在idle in transaction超过30分钟的会话，会阻碍vacuum推进并持有锁</td>
\qecho <td>1. 设置idle_in_transaction_session_timeout<br>2. 检查应用事务提交逻辑<br>3. 终止异常会话</td>
\qecho </tr>
\else
\endif

\if :obsrv_blocked_sessions
\qecho <tr>
\qecho <td class="threshold-critical"><a class="link" href="#LOCK">阻塞会话</a></td>
\qecho <td>存在被其他会话阻塞的会话，可能影响业务正常运行</td>
\qecho <td>1. 通过pg_blocking_pids定位阻塞源<br>2. 评估是否终止阻塞会话<br>3. 优化锁竞争SQL</td>
\qecho </tr>
\else
\endif

\if :obsrv_low_cache_hit
\qecho <tr>
\qecho <td class="threshold-warning"><a class="link" href="#Memory setting and cache read hit">缓存命中率过低</a></td>
\qecho <td>全库缓存命中率低于95%，可能存在大量磁盘读</td>
\qecho <td>1. 评估shared_buffers参数<br>2. 优化热点数据访问SQL<br>3. 检查全表扫描</td>
\qecho </tr>
\else
\endif

\if :obsrv_high_temp_usage
\qecho <tr>
\qecho <td class="threshold-warning"><a class="link" href="#Temp files">当前Temp文件使用过高</a></td>
\qecho <td>当前temp文件写入超过1GB，存在大量落盘的排序或哈希操作</td>
\qecho <td>1. 调大work_mem<br>2. 优化大排序SQL</td>
\qecho </tr>
\else
\endif

\if :obsrv_durability_settings_off
\qecho <tr>
\qecho <td class="threshold-critical"><a class="link" href="#parameters">持久化参数已关闭</a></td>
\qecho <td>fsync或full_page_writes被关闭，宕机可能导致数据损坏或丢失</td>
\qecho <td>1. 恢复fsync=on与full_page_writes=on<br>2. 仅批量初始化数据时临时关闭<br>3. 排查参数修改来源</td>
\qecho </tr>
\else
\endif
\qecho </table>
\qecho <br>

-- +----------------------------------------------------------------------------+
-- |      - observations                                                     -  |
-- +----------------------------------------------------------------------------+
\qecho <font size="+2" face="Arial,Helvetica,Geneva,sans-serif" color="#16191f"><b>观察项</b></font><hr align="left" width="460">
--------------------------------------------------
-- Check for database connections not using SSL --
--------------------------------------------------
SELECT count(*) > 0 obsrv_unsecured_conn_count
FROM pg_stat_activity a JOIN pg_stat_ssl s ON a.pid = s.pid and s.ssl = false \gset

\if :obsrv_unsecured_conn_count
    \qecho &#8594; 数据库存在未使用 SSL 加密的连接，可能暴露敏感数据。请查看SSL配置章节 <a class="link" href="#ssl">SSL</a> .<br>
\else
\endif
--------------------------------------------------
-- Check for Orphaned prepared transactions     --
--------------------------------------------------
SELECT count(*) > 0 obsrv_orphaned_preptxn_count
FROM pg_prepared_xacts WHERE now()-prepared >= interval '5' minute \gset

\if :obsrv_orphaned_preptxn_count
    \qecho &#8594; 数据库存在孤立的预备事务，可能导致阻塞和影响vacuum清理，甚至事务ID回卷。请查看以下章节 <a class="link" href="#Orphaned_prepared_transactions">Orphaned prepared transactions</a> .<br>
\else
\endif
------------------------------------
-- Check for autovacuum parameter --
------------------------------------
select count(*) > 0 obsrv_autovacuum_parameter_disabled
FROM pg_settings WHERE name = 'autovacuum' and setting != 'on'   \gset


 \if :obsrv_autovacuum_parameter_disabled
     \qecho &#8594; autovacuum 参数已禁用，数据库将不会自动进行vacuum清理。请查看以下章节 <a class="link" href="#parameters">DB parameters</a> .<br>
 \else
 \endif

--------------------------------------
-- Check for track_counts parameter --
--------------------------------------
select count(*) > 0 obsrv_track_counts_parameter_disabled
FROM pg_settings WHERE name = 'track_counts' and setting != 'on'   \gset


 \if :obsrv_track_counts_parameter_disabled
     \qecho &#8594; track_counts 参数已禁用，数据库将不会记录查询统计信息。请查看以下章节 <a class="link" href="#parameters">DB parameters</a> .<br>
 \else
 \endif

----------------------------------------------
-- Check for enable_indexonlyscan parameter --
----------------------------------------------
select count(*) > 0 obsrv_enable_indexonlyscan_parameter_disabled
FROM pg_settings WHERE name = 'enable_indexonlyscan' and setting != 'on'   \gset


 \if :obsrv_enable_indexonlyscan_parameter_disabled
     \qecho &#8594; enable_indexonlyscan 参数已禁用，数据库将不会使用indexonlyscan。请查看以下章节 <a class="link" href="#parameters">DB parameters</a> .<br>
 \else
 \endif

------------------------------------------
-- Check for enable_indexscan parameter --
------------------------------------------
select count(*) > 0 obsrv_enable_indexscan_parameter_disabled
FROM pg_settings WHERE name = 'enable_indexscan' and setting != 'on'   \gset


 \if :obsrv_enable_indexscan_parameter_disabled
     \qecho &#8594; enable_indexscan 参数已禁用，数据库将不会使用索引扫描。请查看以下章节 <a class="link" href="#parameters">DB parameters</a> .<br>
 \else
 \endif

------------------------------------------
-- Check for Inactive Replication Slots --
------------------------------------------
SELECT count(*) > 0 obsrv_inactive_rep_slots
FROM pg_replication_slots WHERE active='f' \gset


 \if :obsrv_inactive_rep_slots
     \qecho &#8594; 数据库存在非活动复制槽，可能导致WAL堆积，以及事务ID回卷。请查看以下章节 <a class="link" href="#Replication">Replication</a> .<br>
 \else
 \endif

--------------------------------------------------
-- 检查XID 年龄较高的活动逻辑复制槽（超3亿）   --
--------------------------------------------------
SELECT count(*) > 0 as obsrv_active_logical_slots_lag
FROM pg_replication_slots
WHERE active = true 
  AND slot_type = 'logical'
  AND age(catalog_xmin) >= 300000000 \gset
\if :obsrv_active_logical_slots_lag
    \qecho &#8594; 数据库存在年龄较高（catalog_xmin年龄>3亿）的活动逻辑复制槽，可能存在潜在延迟，建议排查原因，比如网络资源等。请查看以下章节 <a class="link" href="#Replication">Replication</a> .<br>
\else
\endif

-----------------------------------------------
-- Check for log_statement Excessive Logging --
-----------------------------------------------
SELECT count(*) > 0 obsrv_excessive_logging_logstatement 
FROM pg_settings
WHERE name = 'log_statement' and setting IN ('all', 'mod') \gset

\if :obsrv_excessive_logging_logstatement
     \qecho &#8594; log_statement 参数设置为 all 或 mod，可能导致数据库日志文件大小增加。请查看以下章节 <a class="link" href="#parameters">DB parameters</a> .<br>
\else
\endif

------------------------------------------------------------
-- Check for log_min_duration_statement Excessive Logging --
------------------------------------------------------------
SELECT count(*) > 0 obsrv_excessive_logging_logsmindurstmt
FROM pg_settings
WHERE name = 'log_min_duration_statement' and setting IN ('0') \gset

-- 根据用户编辑历史模式，为log_min_duration_statement参数添加详细说明
\if :obsrv_excessive_logging_logsmindurstmt
     \qecho &#8594; log_min_duration_statement 参数设置为 0，会记录所有SQL语句。请查看以下章节 <a class="link" href="#parameters">DB parameters</a> .<br>
\else
\endif

--------------------------------------------
-- Check for synchronous_commit parameter --
--------------------------------------------
select count(*) > 0 obsrv_synchronous_commit_parameter_disabled
FROM pg_settings WHERE name = 'synchronous_commit' and setting = 'off'   \gset


\if :obsrv_synchronous_commit_parameter_disabled
     \qecho &#8594; synchronous_commit 参数已禁用，崩溃时可能导致数据丢失。请查看以下章节 <a class="link" href="#parameters">DB parameters</a> .<br>
\else
\endif

---------------------------------
-- Check for Invalid databases --
---------------------------------
select count(*) > 0 obsrv_invalid_databases
FROM pg_database WHERE datconnlimit = '-2'  \gset


\if :obsrv_invalid_databases
     \qecho &#8594; 存在无效数据库。请查看以下章节 <a class="link" href="#DB_INFO">DB INFO</a> .<br>
\else
\endif

------------------------------------------
-- Check for Critical XID Age --
------------------------------------------
SELECT count(*) > 0 obsrv_critical_xid_age
FROM (
    SELECT max(age(datfrozenxid)) as oldest_xid 
    FROM pg_database
    HAVING max(age(datfrozenxid)) >= 300000000
) AS t \gset

\if :obsrv_critical_xid_age
     \qecho &#8594; 检测到数据库年龄超过3亿。请查看以下章节 <a class="link" href="#Transaction_ID_TXID(Wraparound)">Transaction ID TXID (Wraparound)</a>
\endif

---------------------------------------------------------------------------------
-- Check for autovacuum freeze max age                                         --
---------------------------------------------------------------------------------
select count(*) > 0 obsrv_autovacuum_freeze_max_age FROM pg_settings WHERE name = 'autovacuum_freeze_max_age' and setting::bigint > 200000000   \gset

\if :obsrv_autovacuum_freeze_max_age
  \qecho &#8594; autovacuum_freeze_max_age 参数设置为大于 2 亿的值。请查看以下章节 <a class="link" href="#Transaction_ID_TXID(Wraparound)">Transaction ID TXID (Wraparound)</a>
\else
\endif

---------------------------------------------------------------------------------
-- Check for logical replication spills                                        --
---------------------------------------------------------------------------------
\if :is_pg_15_plus
select count(*) > 0 obsrv_logical_replication_spills from pg_stat_replication_slots where spill_count > 0 and spill_bytes > 0 \gset
\else
SELECT false obsrv_logical_replication_spills \gset
\endif

\if :obsrv_logical_replication_spills
     \qecho &#8594; 数据库存在逻辑复制溢出（会导致磁盘空间消耗增加），可能存在消费慢或断开的逻辑复制。请查看以下章节 <a class="link" href="#Replication">Replication</a> .<br>
\else
\endif

------------------------------------------
-- Check for password_encryption = md5  --
------------------------------------------
select count(*) > 0 obsrv_password_encryption_md5
FROM pg_settings WHERE name = 'password_encryption' and setting = 'md5' \gset

 \if :obsrv_password_encryption_md5
     \qecho &#8594; password_encryption 参数设置为md5,存在一定安全风险。请查看以下章节 <a class="link" href="#parameters">parameters</a> .<br>
 \else
 \endif

------------------------------------------
-- Check for log_checkpoints disabled   --
------------------------------------------
select count(*) > 0 obsrv_log_checkpoints_disabled
FROM pg_settings WHERE name = 'log_checkpoints' and setting != 'on' \gset

 \if :obsrv_log_checkpoints_disabled
     \qecho &#8594; log_checkpoints 参数已禁用，检查点信息将不会记录到日志中。请查看以下章节 <a class="link" href="#parameters">parameters</a> .<br>
 \else
 \endif

---------------------------------
--Check for slow queries (5 seconds)           --
---------------------------------
\if :is_pg_stat_statements_enabled
\if :is_pg_13_plus
SELECT count(*) > 0 obsrv_slow_queries
FROM pg_stat_statements
WHERE mean_exec_time > 5000 \gset
\else
SELECT count(*) > 0 obsrv_slow_queries
FROM pg_stat_statements
WHERE mean_time > 5000 \gset
\endif
\else
SELECT false obsrv_slow_queries \gset
\endif

 \if :obsrv_slow_queries
     \qecho &#8594; 存在执行时间超过5秒的SQL语句，影响系统性能。请查看以下章节 <a class="link" href="#TOP SQL">TOP SQL</a> .<br>
 \else
 \endif


\qecho <br>

\qecho <br>
\qecho <br>
\qecho <a name="DB_INFO"></a>
\qecho <font size="+2" face="Arial,Helvetica,Geneva,sans-serif" color="#16191f"><b>数据库信息</b></font><hr align="left" width="150">
\qecho <br>
\qecho 巡检连接方式：:HOST
\qecho <br>
\set QUIET 1
select 'PG-'||current_setting('server_version') as server_version \gset
select case when pg_is_in_recovery() then 'Standby/Reader DB (Read Only)' else 'Primary/writer DB (Read write)' end as standby_mode \gset
\unset QUIET
\qecho :server_version
\qecho :standby_mode
\qecho <br>
\qecho <br>
select  now () as "Date" ,pg_postmaster_start_time() as "DB_START_DATE", EXTRACT(DAY FROM (current_timestamp - pg_postmaster_start_time()))  as "UP_DAYS"  ,current_database() as "DB_connected" ,current_user USER_NAME,(SELECT setting FROM pg_settings WHERE name = 'port') as "DB_PORT",version()  as "DB_Version" , setting AS block_size FROM pg_settings WHERE name = 'block_size';
\qecho <br>
\qecho <br>
SELECT
    d.datname                                       AS "Name",
    pg_catalog.pg_get_userbyid(d.datdba)            AS "Owner",
    pg_catalog.pg_encoding_to_char(d.encoding)      AS "Encoding",
    d.datcollate                                    AS "Collate",
    d.datctype                                      AS "Ctype",
    pg_catalog.array_to_string(d.datacl, E'\n')     AS "Access privileges",
    CASE
        WHEN pg_catalog.has_database_privilege(d.datname, 'CONNECT')
            THEN pg_catalog.pg_size_pretty(pg_catalog.pg_database_size(d.datname))
        ELSE 'No Access'
    END                                             AS "Size",
    t.spcname                                       AS "Tablespace",
    d.datistemplate                                 AS "Is Template",
    d.datallowconn                                  AS "Allow Connections",
    d.datconnlimit                                  AS "Connection Limit",
    d.datlastsysoid                                 AS "Last Sys OID",
    age(d.datfrozenxid)                             AS "Frozen XID Age",
    d.datminmxid                                    AS "Min MXID"
FROM pg_catalog.pg_database d
JOIN pg_catalog.pg_tablespace t
    ON d.dattablespace = t.oid
ORDER BY 1;

\qecho <br>
\qecho <table width="90%" border="1">
\qecho <tr><th colspan="4"><div align="center"><font color="#16191f"><b>信息</b></font></div></th></tr>
\qecho <tr><th colspan="4" bgcolor="#cfe2f3"><div align="left"><b>Instance level &#183; 实例级信息</b></div></th></tr>
\qecho <tr>
\qecho <td nowrap align="center" width="25%"><a class="link" href="#DB_INFO">数据库信息 DB INFO</a></td>
\qecho <td nowrap align="center" width="25%"><a class="link" href="#Transaction_ID_TXID(Wraparound)">事务ID回卷 Transaction ID TXID (Wraparound)</a></td>
\qecho <td nowrap align="center" width="25%"><a class="link" href="#Replication">复制 Replication</a></td>
\qecho <td nowrap align="center" width="25%"><a class="link" href="#vacuum_Statistics">VACUUM与统计信息 Vacuum & Statistics</a></td>
\qecho </tr>
\qecho <tr>
\qecho <td nowrap align="center" width="25%"><a class="link" href="#Memory setting and cache read hit">内存与缓存命中率 Memory setting</a></td>
\qecho <td nowrap align="center" width="25%"><a class="link" href="#TOP SQL">TOP SQL</a></td>
\qecho <td nowrap align="center" width="25%"><a class="link" href="#Users_Roles_Info">用户与角色信息 Users & Roles Info</a></td>
\qecho <td nowrap align="center" width="25%"><a class="link" href="#Tablespaces_Info">表空间信息 Tablespaces Info</a></td>
\qecho </tr>
\qecho <tr>
\qecho <td nowrap align="center" width="25%"><a class="link" href="#sessions_info">连接与会话 Sessions/Connections Info</a></td>
\qecho <td nowrap align="center" width="25%"><a class="link" href="#ssl">ssl</a></td>
\qecho <td nowrap align="center" width="25%"><a class="link" href="#background_processes">后台进程 Background processes</a></td>
\qecho <td nowrap align="center" width="25%"><a class="link" href="#pg_hba.conf">pg_hba.conf</a></td>
\qecho </tr>
\qecho <tr>
\qecho <td nowrap align="center" width="25%"><a class="link" href="#DB_Load">数据库负载 DB Load</a></td>
\qecho <td nowrap align="center" width="25%"><a class="link" href="#default_access_privileges">默认访问权限 Default access privileges</a></td>
\qecho <td nowrap align="center" width="25%"><a class="link" href="#parameters">常用参数</a></td>
\qecho <td nowrap align="center" width="25%"><a class="link" href="#Temp files">临时文件 Temp files</a></td>
\qecho </tr>
\qecho <tr><th colspan="4" bgcolor="#fff2cc"><div align="left"><b>Database level &#183; 库级信息</b></div></th></tr>
\i /tmp/pg_collector_dbnav.sql
\qecho </table>
\qecho <br>
\qecho <br>

-- +----------------------------------------------------------------------------+
-- |      - Tablespaces_Info                                 -                  |
-- +----------------------------------------------------------------------------+
\qecho <a name="Tablespaces_Info"></a>
\qecho <font size="+2" face="Arial,Helvetica,Geneva,sans-serif" color="#16191f"><b>表空间信息</b></font><hr align="left" width="460">
\qecho <br>
\qecho <details open>
SELECT spcname as Tablespace_Name,
  pg_catalog.pg_get_userbyid(spcowner) as Owner,
CASE
WHEN 
pg_tablespace_location(oid)=''
AND     spcname='pg_default'
THEN
current_setting('data_directory')||'/base/'
WHEN 
pg_tablespace_location(oid)=''
AND     spcname='pg_global'
THEN
current_setting('data_directory')||'/global/'
ELSE
pg_tablespace_location(oid)
END
AS      location          ,
spcacl,spcoptions
FROM pg_catalog.pg_tablespace
ORDER BY 1;
\qecho </details>

\qecho <center>[<a class="noLink" href="#top">Top</a>]</center><p>

-- +----------------------------------------------------------------------------+
-- |      - Users_Roles_Info                                 -                  |
-- +----------------------------------------------------------------------------+
\qecho <a name="Users_Roles_Info"></a>
\qecho <font size="+2" face="Arial,Helvetica,Geneva,sans-serif" color="#16191f"><b>用户与角色信息</b></font><hr align="left" width="460">
\qecho <br>
\qecho <details open>
\qecho <h3>用户信息</h3>
SELECT r.rolname, r.rolsuper, r.rolinherit,
  r.rolcreaterole, r.rolcreatedb, r.rolcanlogin,
  r.rolconnlimit, r.rolvaliduntil,
  ARRAY(SELECT b.rolname
        FROM pg_catalog.pg_auth_members m
        JOIN pg_catalog.pg_roles b ON (m.roleid = b.oid)
        WHERE m.member = r.oid) as memberof
, r.rolreplication
, r.rolbypassrls
FROM pg_catalog.pg_roles r
WHERE r.rolname !~ '^pg_'
ORDER BY 1;

\qecho <br>
-- list of per database role settings (settings set at the role level)
\qecho <h3>用户每个库单独设置参数设置</h3>
SELECT rolname AS "Role", datname AS "Database",
pg_catalog.array_to_string(setconfig, E'\n') AS "Settings"
FROM pg_catalog.pg_db_role_setting s
LEFT JOIN pg_catalog.pg_database d ON d.oid = setdatabase
LEFT JOIN pg_catalog.pg_roles r ON r.oid = setrole
ORDER BY 1, 2;

\qecho <br>
\qecho </details>

\qecho <center>[<a class="noLink" href="#top">Top</a>]</center><p>

-- +----------------------------------------------------------------------------+
-- |      - default_access_privileges                        -                  |
-- +----------------------------------------------------------------------------+
\qecho <a name="default_access_privileges"></a>
\qecho <font size="+2" face="Arial,Helvetica,Geneva,sans-serif" color="#16191f"><b>默认访问权限 Default access privileges</b></font><hr align="left" width="460">
\qecho <br>
\qecho <details open>
SELECT pg_catalog.pg_get_userbyid(d.defaclrole) AS "Owner",
  n.nspname AS "Schema",
  CASE d.defaclobjtype WHEN 'r' THEN 'table' WHEN 'S' THEN 'sequence' WHEN 'f' THEN 'function' WHEN 'T' THEN 'type' WHEN 'n' THEN 'schema' ELSE 'unknown' END AS "Type", 
pg_catalog.array_to_string(d.defaclacl, E'\n') AS "Access privileges"
FROM pg_catalog.pg_default_acl d
     LEFT JOIN pg_catalog.pg_namespace n ON n.oid = d.defaclnamespace
ORDER BY 1, 2, 3;
\qecho </details>

\qecho <center>[<a class="noLink" href="#top">Top</a>]</center><p>

-- +----------------------------------------------------------------------------+
-- |      - pg_hba.conf                                   -                     |
-- +----------------------------------------------------------------------------+
\qecho <a name="pg_hba.conf"></a>
\qecho <font size="+2" face="Arial,Helvetica,Geneva,sans-serif" color="#16191f"><b>pg_hba.conf</b></font><hr align="left" width="460">

\qecho <br>
\qecho <details open>
\qecho <h4>注意：此视图 pg_hba_file_rules 报告的是文件的当前内容，而非服务器上次加载的内容 </h4>
select * from pg_hba_file_rules;
\qecho </details>

\qecho <center>[<a class="noLink" href="#top">Top</a>]</center><p>

-- +----------------------------------------------------------------------------+
-- |      - Vacuum & Statistics                              -                  |
-- +----------------------------------------------------------------------------+
\qecho <a name="vacuum_Statistics"></a>
\qecho <font size="+2" face="Arial,Helvetica,Geneva,sans-serif" color="#16191f"><b>VACUUM 与统计信息</b></font><hr align="left" width="460">
\qecho <br>
\qecho <h3>自动清理参数</h3>
\qecho <br>
\qecho <details open>
SELECT name,setting,unit,context,source,sourcefile,pending_restart from pg_settings where name like '%vacuum%' or name ='maintenance_work_mem' order by 1;
\qecho <br>
\qecho </details>
\qecho <br>
\qecho <h3>当前运行的 autovacuum 和 vacuum 进程</h3>
\qecho <br>
\qecho <details open>
SELECT datname,usename,state,query,
now() - pg_stat_activity.query_start AS duration, 
wait_event from pg_stat_activity where query ~ '^autovacuum:' or query ~* '\A\s*vacuum\M' order by 5;
\qecho <br>
\qecho </details>
\qecho <br>

--  Whenever VACUUM is running, the pg_stat_progress_vacuum view will contain one row for each backend (including autovacuum worker processes) that is currently vacuuming (vacuum porgress)
\qecho <h3>VACUUM 进度</h3>
\qecho <br>
\qecho <details open>
SELECT p.pid, now() - a.xact_start AS duration, coalesce(wait_event_type ||'.'|| wait_event, 'f') AS waiting, CASE WHEN a.query ~ '^autovacuum.*to prevent wraparound' THEN 'wraparound' WHEN a.query ~ '^vacuum' THEN 'user' ELSE 'regular' END AS mode, p.datname AS database, p.relid::regclass AS table, p.phase, pg_size_pretty(p.heap_blks_total * current_setting('block_size')::int) AS table_size, pg_size_pretty(pg_total_relation_size(relid)) AS total_size, pg_size_pretty(p.heap_blks_scanned * current_setting('block_size')::int) AS scanned, pg_size_pretty(p.heap_blks_vacuumed * current_setting('block_size')::int) AS vacuumed, round(100.0 * p.heap_blks_scanned / p.heap_blks_total, 1) AS scanned_pct, round(100.0 * p.heap_blks_vacuumed / p.heap_blks_total, 1) AS vacuumed_pct, p.index_vacuum_count, round(100.0 * p.num_dead_tuples / p.max_dead_tuples,1) AS dead_pct FROM pg_stat_progress_vacuum p JOIN pg_stat_activity a using (pid) ORDER BY now() - a.xact_start DESC;
\qecho </details>
\qecho <br>
\qecho <h3>每日 autovacuum 进度</h3>
\qecho <br>
\qecho <h3> 注意</h3>
\qecho <h4> 如果日期列的值为 NULL，则表示表计数列中对应的值是 autovacuum 未清理的表数量。 </h4>
\qecho <br>
\qecho <details open>
select to_char(last_autovacuum, 'YYYY-MM-DD') as date , count(*) as table_count from pg_stat_all_tables   group by to_char(last_autovacuum, 'YYYY-MM-DD') order by 1;
\qecho </details>
\qecho <br>
\qecho <h3>每日 autoanalyze 进度</h3>
\qecho <br>
\qecho <h3> 注意</h3>
\qecho <h4> 如果日期列的值为 NULL，则表示表计数列中对应的值是 autoanalyze 未分析的表数量。 </h4>
\qecho <br>
\qecho <details open>
select to_char(last_autoanalyze, 'YYYY-MM-DD') as date , count(*) as table_count from pg_stat_all_tables   group by to_char(last_autoanalyze, 'YYYY-MM-DD') order by 1;
\qecho </details>
\qecho <br>

\qecho <center>[<a class="noLink" href="#top">Top</a>]</center><p>

-- +----------------------------------------------------------------------------+
-- |      - Transaction ID TXID(Wraparound)                  -                  |
-- +----------------------------------------------------------------------------+
\qecho <a name="Transaction_ID_TXID(Wraparound)"></a>
\qecho <font size="+2" face="Arial,Helvetica,Geneva,sans-serif" color="#16191f"><b>事务 ID TXID（回卷）</b></font><hr align="left" width="460">
\qecho <br>
\qecho <details open>

\qecho <h3>每个数据库的最旧 xid</h3>

SELECT datname database_name ,age(datfrozenxid) oldest_xid_per_DB 
FROM pg_database order by 2 limit 20;

\qecho <h3>触发紧急自动vacuum进度(percent_towards_emergency_autovac) 与 触发事务ID回卷进度(percent_towards_wraparound)</h3>

WITH max_age AS ( SELECT 2^31-1000000 as max_old_xid , setting AS 
autovacuum_freeze_max_age FROM pg_catalog.pg_settings 
WHERE name = 'autovacuum_freeze_max_age' ) , 
per_database_stats AS ( SELECT datname , m.max_old_xid::int , 
m.autovacuum_freeze_max_age::int , age(d.datfrozenxid) AS oldest_current_xid 
FROM pg_catalog.pg_database d JOIN max_age m ON (true) WHERE d.datallowconn ) 
SELECT max(oldest_current_xid) AS oldest_current_xid , 
max(ROUND(100*(oldest_current_xid/max_old_xid::float))) AS percent_towards_wraparound
 , max(ROUND(100*(oldest_current_xid/autovacuum_freeze_max_age::float))) AS percent_towards_emergency_autovac 
 FROM per_database_stats ;

\qecho <h3>持有的最大 XID</h3>
SELECT
(SELECT max(age(backend_xmin)) FROM pg_stat_activity) as oldest_running_xact,
(SELECT max(age(transaction)) FROM pg_prepared_xacts) as oldest_prepared_xact,
(SELECT max(age(xmin)) FROM pg_replication_slots) as oldest_replication_slot,
(SELECT max(age(backend_xmin))FROM pg_stat_replication)as oldest_replica_xact;

\qecho </details>

\qecho <center>[<a class="noLink" href="#top">Top</a>]</center><p>


-- +----------------------------------------------------------------------------+
-- |      - Replication                                       -                  |
-- +----------------------------------------------------------------------------+
\qecho <a name="Replication"></a>
\qecho <font size="+2" face="Arial,Helvetica,Geneva,sans-serif" color="#16191f"><b>复制 Replication</b></font><hr align="left" width="460">
\qecho <h3>复制参数</h3>
select 
name as parameter_name,setting,unit,short_desc  
FROM pg_catalog.pg_settings 
WHERE name in ('wal_level','max_wal_senders','max_replication_slots',
'max_worker_processes','max_logical_replication_workers','wal_receiver_timeout',
'max_sync_workers_per_subscription','wal_receiver_status_interval','wal_retrieve_retry_interval' ) ;

\qecho <h3>复制槽信息</h3>
select *,age(xmin) age_xmin,age(catalog_xmin) age_catalog_xmin,coalesce(round(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) / 1024 / 1024 , 2),0) AS Lag_MB_behind  
from pg_replication_slots 
order by age(xmin) desc;

\qecho <h3>当前复制相关XID 年龄状态</h3>
SELECT 
        (SELECT max(nullif(age(backend_xmin),2147483647)) FROM pg_stat_replication) as maxage_backend_xmin,
        (SELECT max(nullif(age(xmin),2147483647)) FROM pg_replication_slots where slot_type = 'physical') as maxage_phy_slots_xmin,
        (SELECT max(nullif(age(catalog_xmin),2147483647)) FROM pg_replication_slots where slot_type = 'physical') as maxage_phy_slots_catalogxmin;
\qecho <center>[<a class="noLink" href="#top">Top</a>]</center><p>

-- +----------------------------------------------------------------------------+
-- |      - Orphaned prepared transactions                   -                  |
-- +----------------------------------------------------------------------------+
\qecho <a name="Orphaned_prepared_transactions"></a>
\qecho <font size="+2" face="Arial,Helvetica,Geneva,sans-serif" color="#16191f"><b>孤立的预备事务</b></font><hr align="left" width="460">
SELECT transaction,gid, prepared,now()-prepared as prepared_duration, owner, database, age(transaction) AS ag_xmin 
FROM pg_prepared_xacts
ORDER BY age(transaction) DESC;

\qecho <center>[<a class="noLink" href="#top">Top</a>]</center><p>
-- +----------------------------------------------------------------------------+
-- |      - Memory setting and cache read hit                -                  |
-- +----------------------------------------------------------------------------+
\qecho <a name="Memory setting and cache read hit"></a>
\qecho <font size="+2" face="Arial,Helvetica,Geneva,sans-serif" color="#16191f"><b>内存配置与缓存命中率</b></font><hr align="left" width="460">
\qecho <br>
\qecho <details open>
(
select name as parameter_name , setting , unit, pg_size_pretty((setting::BIGINT*1024)::BIGINT)   
from pg_settings where name in ('work_mem','maintenance_work_mem')
)
UNION ALL
(
select name as parameter_name, setting , unit , pg_size_pretty((((setting::BIGINT)*8)*1024)::BIGINT)  
from pg_settings where name in ('shared_buffers','wal_buffers','effective_cache_size','temp_buffers')
) 
UNION ALL
select name as parameter_name,setting,'/' as unit,'/' as  pg_size_pretty FROM pg_catalog.pg_settings WHERE name in ('huge_pages' ) 
order by 4  desc;
\qecho <br>
\qecho <h3>整个实例的缓存命中率</h3>
select 
round((sum(blks_hit)::numeric / (sum(blks_hit) + sum(blks_read)::numeric))*100,2) as cache_read_hit_percentage
from pg_stat_database ;
\qecho <br>
\qecho <h3>每个数据库的缓存命中率</h3>
select datname as database_name, 
round((blks_hit::numeric / (blks_hit + blks_read)::numeric)*100,2) as cache_read_hit_percentage
from pg_stat_database 
where blks_hit + blks_read > 0
and datname is not null 
order by 2 desc;
\qecho </details>
\qecho <br>

\qecho <center>[<a class="noLink" href="#top">Top</a>]</center><p>

-- +----------------------------------------------------------------------------+
-- |      - sessions_info                                                     - |
-- +----------------------------------------------------------------------------+
\qecho <a name="sessions_info"></a>
\qecho <font size="+2" face="Arial,Helvetica,Geneva,sans-serif" color="#16191f"><b>会话/连接信息</b></font><hr align="left" width="460">
\qecho <br>
\qecho <h3>连接利用率</h3>
\qecho <br>
\qecho <details open>
with
settings as (SELECT setting::float AS "max_connections" FROM pg_settings WHERE name = 'max_connections'),
connections as (select sum (numbackends)::float total_connections from pg_stat_database)
select   settings.max_connections AS "Max_connections" ,total_connections as "Total_connections",ROUND((100*(connections.Total_connections/settings.max_connections))::numeric,2) as "Connections utilization %" from  settings, connections;
\qecho </details>
\qecho <br>

\qecho <h3> 数据库/用户名/状态/连接数</h3>
\qecho <br>
\qecho <details open>
select datname as "Database_Name" ,usename as "User_Name",state as status,count(*) as "Connections_count" FROM pg_stat_activity where datname is not null group by datname ,usename,state order by 4 desc;
\qecho </details>
\qecho <br>

\qecho <h3>活动会话</h3>
\qecho <br>
\qecho <details open>
/* active_session_monitor*/ select * from
(
    SELECT
usename,pid, now() - pg_stat_activity.xact_start AS xact_duration ,now() - pg_stat_activity.query_start AS query_duration,
substr(query,1,50) as query,state,wait_event
FROM pg_stat_activity
) as s where (xact_duration is not null  or query_duration is not null ) and state!='idle' and query not like '%active_session_monitor%'
order by xact_duration desc, query_duration desc;
\qecho </details>

\qecho <center>[<a class="noLink" href="#top">Top</a>]</center><p>

-- +----------------------------------------------------------------------------+
-- |      - LOCK                                             -                  |
-- +----------------------------------------------------------------------------+
\qecho <a name="LOCK"></a>
\qecho <font size="+2" face="Arial,Helvetica,Geneva,sans-serif" color="#16191f"><b>锁</b></font><hr align="left" width="460">
\qecho <br>
\qecho <br>
\qecho <h3>锁</h3>
\qecho <details open>
\qecho <br>
\qecho <h3>未授予的锁请求数量</h3>
SELECT coalesce(count(*),0) as "not_granted_lock" FROM pg_locks WHERE NOT GRANTED;
\qecho <br>
\qecho <h3>被阻塞会话数量</h3>
select count(*) from pg_stat_activity where cardinality(pg_blocking_pids(pid)) > 0 ;
\qecho <br>
\qecho <h3>锁模式</h3>
SELECT mode as lock_mode ,locktype, count(*) FROM pg_locks group by mode,locktype;
\qecho <br>
\qecho </details>

\qecho <center>[<a class="noLink" href="#top">Top</a>]</center><p>

-- +----------------------------------------------------------------------------+
-- |      - DB_Load                                          -                  |
-- +----------------------------------------------------------------------------+
\qecho <a name="DB_Load"></a>
\qecho <font size="+2" face="Arial,Helvetica,Geneva,sans-serif" color="#16191f"><b>数据库负载</b></font><hr align="left" width="460">
\qecho <br>

\qecho <h3>等待事件</h3>
\qecho <details open>
\qecho <h3>等待事件/会话数</h3>
SELECT coalesce(wait_event,'CPU') as wait_event , count(*) FROM pg_stat_activity group by wait_event order by 2 desc;
\qecho <br>
\qecho <h3>等待事件/SQL内容top20</h3>
SELECT  coalesce(wait_event,'CPU') as wait_event, substr(query,1,150) as query,count(*) FROM pg_stat_activity   group by  query,wait_event order by 3 desc limit 20;
\qecho <br>
\qecho <h3>pg_stat_bgwriter 视图</h3>
select * from pg_stat_bgwriter;
\qecho <br>
\qecho <h3>pg_stat_archiver 视图</h3>
select * from pg_stat_archiver;
\qecho <br>
\qecho <h3>pg_stat_database 视图</h3>
select * from pg_stat_database ;
\qecho <br>
\qecho </details>

\qecho <center>[<a class="noLink" href="#top">Top</a>]</center><p>

-- +----------------------------------------------------------------------------+
-- |      - Temp files                                          -                  |
-- +----------------------------------------------------------------------------+
\qecho <a name="Temp files"></a>
\qecho <font size="+2" face="Arial,Helvetica,Geneva,sans-serif" color="#16191f"><b>Temp文件</b></font><hr align="left" width="460"> 
\qecho <br>

\qecho <details open>
\qecho <h3>当前临时文件使用情况</h3>
SELECT name,size,modification FROM pg_ls_tmpdir() order by size desc limit 20;

\qecho <br>
\qecho </details>
\qecho <center>[<a class="noLink" href="#top">Top</a>]</center><p>

-- +----------------------------------------------------------------------------+
-- |      - TOP SQL                                          -                  |
-- +----------------------------------------------------------------------------+
\qecho <a name="TOP SQL"></a>
\qecho <font size="+2" face="Arial,Helvetica,Geneva,sans-serif" color="#16191f"><b>TOP SQL</b></font><hr align="left" width="460">
\qecho <br>
select count(*) > 0 is_pg_stat_statements_enabled FROM pg_catalog.pg_extension where extname = 'pg_stat_statements' \gset
\if :is_pg_stat_statements_enabled
SELECT (string_to_array(extversion, '.')::int[] >= array[1,9]) AS v_pgstatextv19 FROM pg_extension WHERE extname = 'pg_stat_statements' \gset
\qecho <h3> pg_stat_statements 已安装版本 </h3>
\qecho <br>
\qecho <details open>
SELECT e.extname AS "Extension Name", e.extversion AS "Version", n.nspname AS "Schema",pg_get_userbyid(e.extowner)  as Owner, c.description AS "Description" , e.extrelocatable as "relocatable to another schema", e.extconfig ,e.extcondition
 FROM pg_catalog.pg_extension e LEFT JOIN pg_catalog.pg_namespace n ON n.oid = e.extnamespace LEFT JOIN pg_catalog.pg_description c ON c.objoid = e.oid AND c.classoid = 'pg_catalog.pg_extension'::pg_catalog.regclass
 where e.extname = 'pg_stat_statements';
\qecho <br>
\qecho <h3>参数值： </h3>
-- pg_stat_statements extension configuration 
select name as parameter_name, setting  from pg_settings where name in ('pg_stat_statements.track','pg_stat_statements.track_utility','pg_stat_statements.save'
,'pg_stat_statements.max','shared_preload_libraries');
\qecho </details>
\qecho <br>

\qecho <h3> 按 total_time 排序的 TOP20 SQL </h3>
\qecho <br>
\qecho <details open>
--Top SQL order by total_time
\if :v_pgstatextv19
select queryid,substring(query,1,60) as query , calls, 
round(total_exec_time::numeric, 2) as total_time_Msec, 
round((total_exec_time::numeric/1000), 2) as total_time_sec,
round(mean_exec_time::numeric,2) as avg_time_Msec,
round((mean_exec_time::numeric/1000),2) as avg_time_sec,
round(stddev_exec_time::numeric, 2) as standard_deviation_time_Msec, 
round((stddev_exec_time::numeric/1000), 2) as standard_deviation_time_sec, 
round(rows::numeric/calls,2) rows_per_exec,
round((100 * total_exec_time / sum(total_exec_time) over ())::numeric, 4) as percent
from pg_stat_statements 
order by total_time_Msec desc limit 20;
\else
select queryid,substring(query,1,60) as query , calls,
round(total_time::numeric, 2) as total_time_Msec, 
round((total_time::numeric/1000), 2) as total_time_sec,
round(mean_time::numeric,2) as avg_time_Msec,
round((mean_time::numeric/1000),2) as avg_time_sec,
round(stddev_time::numeric, 2) as standard_deviation_time_Msec, 
round((stddev_time::numeric/1000), 2) as standard_deviation_time_sec, 
round(rows::numeric/calls,2) rows_per_exec,
round((100 * total_time / sum(total_time) over ())::numeric, 4) as percent
from pg_stat_statements 
order by total_time_Msec desc limit 20;
\endif
\qecho </details>

\qecho <br>
\qecho <h3> 按 avg_time 排序的 TOP20 SQL </h3>
\qecho <br>
\qecho <details open>
--Top SQL order by avg_time
\if :v_pgstatextv19
select queryid,substring(query,1,60) as query , calls,
round(total_exec_time::numeric, 2) as total_time_Msec, 
round((total_exec_time::numeric/1000), 2) as total_time_sec,
round(mean_exec_time::numeric,2) as avg_time_Msec,
round((mean_exec_time::numeric/1000),2) as avg_time_sec,
round(stddev_exec_time::numeric, 2) as standard_deviation_time_Msec, 
round((stddev_exec_time::numeric/1000), 2) as standard_deviation_time_sec, 
round(rows::numeric/calls,2) rows_per_exec,
round((100 * total_exec_time / sum(total_exec_time) over ())::numeric, 4) as percent
from pg_stat_statements 
order by avg_time_Msec desc limit 20;
\else
select queryid,substring(query,1,60) as query , calls,
round(total_time::numeric, 2) as total_time_Msec, 
round((total_time::numeric/1000), 2) as total_time_sec,
round(mean_time::numeric,2) as avg_time_Msec,
round((mean_time::numeric/1000),2) as avg_time_sec,
round(stddev_time::numeric, 2) as standard_deviation_time_Msec, 
round((stddev_time::numeric/1000), 2) as standard_deviation_time_sec, 
round(rows::numeric/calls,2) rows_per_exec,
round((100 * total_time / sum(total_time) over ())::numeric, 4) as percent
from pg_stat_statements 
order by avg_time_Msec desc limit 20;
\endif
\qecho </details>

\qecho <br>
\qecho <h3> 按占总数据库时间百分比排序的 TOP20 SQL</h3>
\qecho <br>
\qecho <details open>
--Top SQL order by percent of total DB time
\if :v_pgstatextv19
select queryid,substring(query,1,60) as query , calls, 
round(total_exec_time::numeric, 2) as total_time_Msec, 
round((total_exec_time::numeric/1000), 2) as total_time_sec,
round(mean_exec_time::numeric,2) as avg_time_Msec,
round((mean_exec_time::numeric/1000),2) as avg_time_sec,
round(stddev_exec_time::numeric, 2) as standard_deviation_time_Msec, 
round((stddev_exec_time::numeric/1000), 2) as standard_deviation_time_sec, 
round(rows::numeric/calls,2) rows_per_exec,
round((100 * total_exec_time / sum(total_exec_time) over ())::numeric, 4) as percent
from pg_stat_statements 
order by percent desc limit 20;
\else
select queryid,substring(query,1,60) as query , calls, 
round(total_time::numeric, 2) as total_time_Msec, 
round((total_time::numeric/1000), 2) as total_time_sec,
round(mean_time::numeric,2) as avg_time_Msec,
round((mean_time::numeric/1000),2) as avg_time_sec,
round(stddev_time::numeric, 2) as standard_deviation_time_Msec, 
round((stddev_time::numeric/1000), 2) as standard_deviation_time_sec, 
round(rows::numeric/calls,2) rows_per_exec,
round((100 * total_time / sum(total_time) over ())::numeric, 4) as percent
from pg_stat_statements 
order by percent desc limit 20;
\endif
\qecho </details>

\qecho <br>
\qecho <h3> 按执行次数（CALLs）排序的 TOP20 SQL </h3>
\qecho <br>
\qecho <details open>
--Top SQL order by number of execution (CALLs)  
\if :v_pgstatextv19  
select queryid,substring(query,1,60) as query , calls,
round(total_exec_time::numeric, 2) as total_time_Msec, 
round((total_exec_time::numeric/1000), 2) as total_time_sec,
round(mean_exec_time::numeric,2) as avg_time_Msec,
round((mean_exec_time::numeric/1000),2) as avg_time_sec,
round(stddev_exec_time::numeric, 2) as standard_deviation_time_Msec, 
round((stddev_exec_time::numeric/1000), 2) as standard_deviation_time_sec, 
round(rows::numeric/calls,2) rows_per_exec,
round((100 * total_exec_time / sum(total_exec_time) over ())::numeric, 4) as percent
from pg_stat_statements 
order by calls desc limit 20;
\else
select queryid,substring(query,1,60) as query , calls,
round(total_time::numeric, 2) as total_time_Msec, 
round((total_time::numeric/1000), 2) as total_time_sec,
round(mean_time::numeric,2) as avg_time_Msec,
round((mean_time::numeric/1000),2) as avg_time_sec,
round(stddev_time::numeric, 2) as standard_deviation_time_Msec, 
round((stddev_time::numeric/1000), 2) as standard_deviation_time_sec, 
round(rows::numeric/calls,2) rows_per_exec,
round((100 * total_time / sum(total_time) over ())::numeric, 4) as percent
from pg_stat_statements 
order by calls desc limit 20;
\endif
\qecho </details>

\qecho <br>
\qecho <h3> 按 shared blocks read（物理读）排序的 TOP20 SQL </h3>
\qecho <br>
\qecho <details open>
--Top SQL order by shared blocks read (physical reads) 
\if :v_pgstatextv19 
select queryid, substring(query,1,60) as query , calls,
round(total_exec_time::numeric, 2) as total_time_Msec, 
round((total_exec_time::numeric/1000), 2) as total_time_sec,
round(mean_exec_time::numeric,2) as avg_time_Msec,
round((mean_exec_time::numeric/1000),2) as avg_time_sec,
round(stddev_exec_time::numeric, 2) as standard_deviation_time_Msec, 
round((stddev_exec_time::numeric/1000), 2) as standard_deviation_time_sec, 
round(rows::numeric/calls,2) rows_per_exec,
round((100 * total_exec_time / sum(total_exec_time) over ())::numeric, 4) as percent,
shared_blks_read
from pg_stat_statements 
order by shared_blks_read desc limit 20;
\else
select queryid, substring(query,1,60) as query , calls,
round(total_time::numeric, 2) as total_time_Msec, 
round((total_time::numeric/1000), 2) as total_time_sec,
round(mean_time::numeric,2) as avg_time_Msec,
round((mean_time::numeric/1000),2) as avg_time_sec,
round(stddev_time::numeric, 2) as standard_deviation_time_Msec, 
round((stddev_time::numeric/1000), 2) as standard_deviation_time_sec, 
round(rows::numeric/calls,2) rows_per_exec,
round((100 * total_time / sum(total_time) over ())::numeric, 4) as percent,
shared_blks_read
from pg_stat_statements 
order by shared_blks_read desc limit 20;
\endif
\qecho </details>
\else
    \if yes
        \qecho pg_stat_statements 扩展未安装
    \endif
\endif

\qecho <center>[<a class="noLink" href="#top">Top</a>]</center><p>

-- +----------------------------------------------------------------------------+
-- |      - background_processes                                   -            |
-- +----------------------------------------------------------------------------+
\qecho <a name="background_processes"></a>
\qecho <font size="+2" face="Arial,Helvetica,Geneva,sans-serif" color="#16191f"><b>后台进程</b></font><hr align="left" width="460">
\qecho <br>
\qecho <details open>
\qecho <h3>Postgres 后台进程数量</h3>

SELECT  pid , backend_type as  "Background processes Type" , backend_start as "start time" FROM pg_stat_activity where datname is null order by 3 ;
\qecho </details>

\qecho <center>[<a class="noLink" href="#top">Top</a>]</center><p>

-- +----------------------------------------------------------------------------+
-- |      - ssl   -                                                             |
-- +----------------------------------------------------------------------------+
\qecho <a name="ssl"></a>
\qecho <font size="+2" face="Arial,Helvetica,Geneva,sans-serif" color="#16191f"><b>SSL</b></font><hr align="left" width="460">
\qecho <br>

\qecho <h3>SSL 配置参数与设置</h3>
select name as "Parameter_Name" , setting as value,short_desc  from pg_settings where name like '%ssl%';
\qecho <br>

\qecho <h3>SSL 连接汇总：按 SSL 状态和版本的连接总数 </h3>
\qecho <h4> 注意：ssl=f 表示未使用 SSL 加密的连接总数。 </h4>
select ssl ,version as ssl_version , count (*) as "Connection_count" FROM pg_stat_ssl group by ssl,version ;
\qecho <br>

\qecho <center>[<a class="noLink" href="#top">Top</a>]</center><p>

-- +----------------------------------------------------------------------------+
-- |      - parameters                                       -                  |
-- +----------------------------------------------------------------------------+
\qecho <a name="parameters"></a>
\qecho <font size="+2" face="Arial,Helvetica,Geneva,sans-serif" color="#16191f"><b>常用参数</b></font><hr align="left" width="460">
\qecho <br>
\qecho <details open>
\qecho <h3>复制参数</h3>
select 
name as parameter_name,setting,unit,short_desc  
FROM pg_catalog.pg_settings 
WHERE name in ('effective_io_concurrency',
'random_page_cost',
'seq_page_cost',
'statement_timeout',
'idle_in_transaction_session_timeout',
'search_path',
'log_min_duration_statement',
'password_encryption',
'log_checkpoints',
'max_connections',
'fsync',
'full_page_writes',
'enable_indexonlyscan',
'enable_indexscan',
'log_statement',
'log_min_duration_statement',
'synchronous_commit' ) order by name;
\qecho </details>

\qecho <center>[<a class="noLink" href="#top">Top</a>]</center><p>

-- +----------------------------------------------------------------------------+
-- |  Per-Database Details: switch to each database and include perdb sections  |
-- |  NOTE: \o of the report stays open; per-db blocks append to the same file. |
-- +----------------------------------------------------------------------------+
\qecho <br>
\qecho <h1>各数据库详情</h1>
\i /tmp/pg_collector_loop.sql
