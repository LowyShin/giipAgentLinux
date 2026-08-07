#!/bin/bash
#===============================================================================
# MS SQL Server Performance Diagnostics Module (Query Store based)
#
# Description:
#   Query Store에서 회귀 쿼리(최근 구간 vs 기준 구간 평균 지연 비교)와 대기 유형 상위
#   목록을, ring buffer에서 실제 CPU%를 수집한다. Query Store가 꺼져 있거나 접근 권한이
#   없으면 상태만 기록하고 절대 자동으로 켜지 않는다(고객 DB 설정 변경 금지).
#
# Version: 1.0.0
# Date: 2026-08-07
# Related: giip-issue #921
#
# Usage:
#   source lib/db_perf_diag_mssql.sh
#   result=$(collect_mssql_perf_diag "host" "port" "user" "password" "database")
#
# Returns (always valid JSON, never fails hard):
#   {
#     "query_store_status": "READ_WRITE" | "READ_ONLY" | "OFF" | "NOT_AVAILABLE" | "error",
#     "regressions": [ { "query_id":.., "avg_dur_recent_ms":.., "avg_dur_baseline_ms":.., "exec_count":.., "query_text":".." }, ... ],
#     "wait_stats": [ { "wait_category":"..", "total_wait_ms":.. }, ... ],
#     "real_cpu_percent": <int> | null
#   }
#===============================================================================

collect_mssql_perf_diag() {
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local host="$1"
    local port="$2"
    local user="$3"
    local password="$4"
    local database="${5:-master}"

    if [ -z "$host" ] || [ -z "$port" ] || [ -z "$user" ] || [ -z "$password" ]; then
        echo '{"query_store_status":"error","reason":"missing_connection_params","regressions":[],"wait_stats":[],"real_cpu_percent":null}'
        return 1
    fi

    if ! command -v sqlcmd &>/dev/null; then
        echo '{"query_store_status":"error","reason":"sqlcmd_not_installed","regressions":[],"wait_stats":[],"real_cpu_percent":null}'
        return 1
    fi

    # ------------------------------------------------------------------
    # 1. Query Store availability check (READ-ONLY — never mutate settings)
    # ------------------------------------------------------------------
    local qs_state
    qs_state=$(timeout 5 sqlcmd -S "$host,$port" -U "$user" -P "$password" -d "$database" -h -1 -W -Q \
        "SET NOCOUNT ON; SELECT ISNULL(actual_state_desc,'NOT_AVAILABLE') FROM sys.database_query_store_options;" 2>/dev/null | tr -d '\r\n ')
    [ -z "$qs_state" ] && qs_state="NOT_AVAILABLE"

    local qs_regressions="[]"
    local qs_waits="[]"

    if [ "$qs_state" = "READ_WRITE" ] || [ "$qs_state" = "READ_ONLY" ]; then
        # --------------------------------------------------------------
        # 2. Regressed queries: recent 30min avg duration vs prior 24h baseline,
        #    only queries that got at least 2x slower and now average > 100ms.
        # --------------------------------------------------------------
        local regress_query="
SET NOCOUNT ON;
;WITH recent AS (
    SELECT p.query_id, AVG(rs.avg_duration) AS avg_dur_recent, SUM(rs.count_executions) AS exec_recent
    FROM sys.query_store_runtime_stats rs
    JOIN sys.query_store_plan p ON rs.plan_id = p.plan_id
    JOIN sys.query_store_runtime_stats_interval rsi ON rs.runtime_stats_interval_id = rsi.runtime_stats_interval_id
    WHERE rsi.start_time >= DATEADD(MINUTE, -30, GETUTCDATE())
    GROUP BY p.query_id
),
baseline AS (
    SELECT p.query_id, AVG(rs.avg_duration) AS avg_dur_baseline
    FROM sys.query_store_runtime_stats rs
    JOIN sys.query_store_plan p ON rs.plan_id = p.plan_id
    JOIN sys.query_store_runtime_stats_interval rsi ON rs.runtime_stats_interval_id = rsi.runtime_stats_interval_id
    WHERE rsi.start_time >= DATEADD(HOUR, -25, GETUTCDATE()) AND rsi.start_time < DATEADD(MINUTE, -30, GETUTCDATE())
    GROUP BY p.query_id
)
SELECT TOP 5
    r.query_id,
    CAST(r.avg_dur_recent AS BIGINT) AS avg_dur_recent,
    CAST(ISNULL(b.avg_dur_baseline,0) AS BIGINT) AS avg_dur_baseline,
    r.exec_recent,
    ISNULL(SUBSTRING(qt.query_sql_text, 1, 500), '') AS query_text
FROM recent r
LEFT JOIN baseline b ON r.query_id = b.query_id
JOIN sys.query_store_query q ON r.query_id = q.query_id
JOIN sys.query_store_query_text qt ON q.query_text_id = qt.query_text_id
WHERE r.avg_dur_recent > 100000
  AND r.avg_dur_recent > ISNULL(b.avg_dur_baseline,0) * 2
ORDER BY r.avg_dur_recent DESC;
"
        local regress_result
        regress_result=$(timeout 10 sqlcmd -S "$host,$port" -U "$user" -P "$password" -d "$database" -h -1 -s $'\t' -W -Q "$regress_query" 2>/dev/null | grep -v "^[[:space:]]*$")
        if [ -n "$regress_result" ]; then
            local parsed
            parsed=$(echo "$regress_result" | python3 "${SCRIPT_DIR}/parse_qs_regressions.py" 2>/dev/null)
            [ -n "$parsed" ] && qs_regressions="$parsed"
        fi

        # --------------------------------------------------------------
        # 3. Top wait categories (last 30 min)
        # --------------------------------------------------------------
        local wait_query="
SET NOCOUNT ON;
SELECT TOP 5
    ws.wait_category_desc,
    CAST(SUM(ws.total_query_wait_time_ms) AS BIGINT) AS total_wait_ms
FROM sys.query_store_wait_stats ws
JOIN sys.query_store_runtime_stats_interval rsi ON ws.runtime_stats_interval_id = rsi.runtime_stats_interval_id
WHERE rsi.start_time >= DATEADD(MINUTE, -30, GETUTCDATE())
GROUP BY ws.wait_category_desc
ORDER BY total_wait_ms DESC;
"
        local wait_result
        wait_result=$(timeout 10 sqlcmd -S "$host,$port" -U "$user" -P "$password" -d "$database" -h -1 -s $'\t' -W -Q "$wait_query" 2>/dev/null | grep -v "^[[:space:]]*$")
        if [ -n "$wait_result" ]; then
            local parsed_w
            parsed_w=$(echo "$wait_result" | python3 "${SCRIPT_DIR}/parse_qs_waits.py" 2>/dev/null)
            [ -n "$parsed_w" ] && qs_waits="$parsed_w"
        fi
    fi

    # ------------------------------------------------------------------
    # 4. Real CPU% via ring buffer (independent of Query Store state)
    # ------------------------------------------------------------------
    local cpu_query="
SET NOCOUNT ON;
SELECT TOP 1 CAST(SQLProcessUtilization AS INT)
FROM (
    SELECT
        record.value('(./Record/@id)[1]', 'int') AS record_id,
        record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int') AS SQLProcessUtilization
    FROM (
        SELECT CONVERT(xml, record) AS record
        FROM sys.dm_os_ring_buffers
        WHERE ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR'
        AND record LIKE '%<SystemHealth>%'
    ) AS x
) AS y
ORDER BY record_id DESC;
"
    local cpu_pct
    cpu_pct=$(timeout 5 sqlcmd -S "$host,$port" -U "$user" -P "$password" -d "$database" -h -1 -W -Q "$cpu_query" 2>/dev/null | tr -d '\r\n ')
    if ! [[ "$cpu_pct" =~ ^[0-9]+$ ]]; then
        cpu_pct="null"
    fi

    # ------------------------------------------------------------------
    # Assemble final JSON via jq (safe against quoting/escaping issues)
    # ------------------------------------------------------------------
    if command -v jq &>/dev/null; then
        jq -n --arg qs "$qs_state" --argjson regressions "$qs_regressions" --argjson waits "$qs_waits" --argjson cpu "$cpu_pct" \
            '{query_store_status:$qs, regressions:$regressions, wait_stats:$waits, real_cpu_percent:$cpu}' 2>/dev/null
    else
        # Fallback: manual assembly (jq is a hard dependency elsewhere in this repo, but degrade gracefully)
        echo "{\"query_store_status\":\"${qs_state}\",\"regressions\":${qs_regressions},\"wait_stats\":${qs_waits},\"real_cpu_percent\":${cpu_pct}}"
    fi

    return 0
}

export -f collect_mssql_perf_diag
