-- MySQL / Aurora MySQL equivalent of SQL Server's
-- SELECT host_name, login_name, status, cpu_time, reads, writes, logical_reads, start_time, command, query_text
--
-- Notes:
-- - Requires performance_schema to be enabled.
-- - TIMER_WAIT is in picoseconds. We convert to milliseconds to approximate SQL Server's cpu_time (ms).
-- - PROCESSLIST_TIME is used as a fallback (seconds since statement started), converted to ms where appropriate.
-- - reads/writes/logical_reads are best-effort using events_statements_current fields (ROWS_EXAMINED / ROWS_SENT).
-- - start_time is approximated as NOW() - INTERVAL PROCESSLIST_TIME SECOND.
--
SELECT
  @@hostname AS sql_server,
  t.THREAD_ID AS spid,
  COALESCE(t.PROCESSLIST_HOST, '') AS host_name,
  COALESCE(t.PROCESSLIST_USER, '') AS login_name,
  COALESCE(t.PROCESSLIST_STATE, '') AS status,
  -- cpu_time in milliseconds: prefer TIMER_WAIT (picoseconds -> ms), fallback to PROCESSLIST_TIME*1000
  CASE WHEN COALESCE(t.PROCESSLIST_COMMAND, '') = 'Binlog Dump GTID' THEN 0
    ELSE IFNULL(CAST(es.TIMER_WAIT AS DECIMAL(20,3)) / 1000000, CAST(t.PROCESSLIST_TIME AS SIGNED) * 1000)
  END AS cpu_time,
  IFNULL(es.ROWS_EXAMINED, 0) AS reads_count,
  IFNULL(es.ROWS_SENT, 0) AS writes_count,
  IFNULL(es.ROWS_EXAMINED, 0) AS logical_reads_count,
  -- approximate start time using PROCESSLIST_TIME (seconds ago)
  CASE WHEN t.PROCESSLIST_TIME IS NOT NULL THEN (NOW() - INTERVAL t.PROCESSLIST_TIME SECOND) ELSE NULL END AS start_time,
  COALESCE(t.PROCESSLIST_COMMAND, '') AS command,
  -- prefer the full SQL text from events_statements_current; fallback to PROCESSLIST_INFO
  -- escape CR/LF and tabs in the SQL text so the client returns a single-line field
  REPLACE(REPLACE(REPLACE(COALESCE(es.SQL_TEXT, t.PROCESSLIST_INFO), '\r', '\\r'), '\n', '\\n'), '\t', ' ') AS query_text
FROM performance_schema.threads t
LEFT JOIN performance_schema.events_statements_current es ON es.THREAD_ID = t.THREAD_ID
-- only user threads
WHERE COALESCE(t.PROCESSLIST_USER, '') <> ''
ORDER BY cpu_time DESC
LIMIT 20
;
