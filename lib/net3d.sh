#!/bin/bash
# lib/net3d.sh - Net3D Network Topology Data Collection Module
# Version: 1.1
# Date: 2025-12-28
# Purpose: Collects netstat/ss data for Net3D visualization (every 5 minutes)
# Usage: source lib/net3d.sh && collect_net3d_data <lssn>

# ============================================================================
# ⭐ UTF-8 환경 강제 설정 (source되는 라이브러리도 필요!)
# ============================================================================
# 목적: 일본어/한글 로케일 환경에서 Python 인라인 코드 파싱 에러 방지
# 이슈: CentOS 7.4 일본어 환경에서 멀티바이트 문자 깨짐 문제 해결
# 날짜: 2025-12-28
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8


# ============================================================================
# Required Dependencies
# ============================================================================
# - common.sh (for log_message)
# - kvs.sh (for kvs_put)

if ! declare -f log_message >/dev/null 2>&1; then
	echo "❌ Error: log_message not found. common.sh must be loaded first" >&2
	exit 1
fi

if ! declare -f kvs_put >/dev/null 2>&1; then
	echo "❌ Error: kvs_put not found. kvs.sh must be loaded first" >&2
	exit 1
fi

# Load server_info module for IP collection
# Use SCRIPT_DIR to locate server_info.sh relative to the current script location
# Current script is at giipAgentLinux/lib/net3d.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/server_info.sh" ]]; then
    source "${SCRIPT_DIR}/server_info.sh"
    log_message "INFO" "[Net3D] server_info.sh module loaded successfully"
else
    log_message "WARN" "[Net3D] server_info.sh not found. Server IP collection will be skipped."
fi

# Configuration
NET3D_INTERVAL=300  # 5 minutes
NET3D_STATE_FILE="${NET3D_STATE_FILE:-/tmp/giip_net3d_state}"

# ============================================================================
# Main Function: Collect and Upload Net3D Data
# ============================================================================
collect_net3d_data() {
    local lssn="$1"
    
    # 1. Check interval
    if ! should_run_net3d "$lssn"; then
        return 0
    fi
    
    log_message "INFO" "[Net3D] Starting network topology data collection for LSSN=$lssn"
    
    # Detect Python
    local python_cmd=""
    if command -v python3 >/dev/null 2>&1; then
        python_cmd="python3"
    elif command -v python >/dev/null 2>&1; then
        python_cmd="python"
    else
        log_message "ERROR" "[Net3D] Python not found. Cannot parse network data."
        return 1
    fi

    # 2. Collect Data
    local net_json="{}"
    local source_cmd=""
    
    # 🔍 [NEW] ENRICHMENT: Local Database Session Check (MSSQL, MySQL, PostgreSQL)
    local sql_session_map="{}"
    sql_session_map=$($python_cmd -c "
import sys, json, subprocess, hashlib

def get_mssql_sessions():
    sessions = {}
    try:
        import pyodbc
        # Try local connection with Trusted_Connection (requires Kerberos/Domain on Linux, but kept for parity)
        conn_str = 'DRIVER={ODBC Driver 17 for SQL Server};SERVER=localhost;DATABASE=master;Trusted_Connection=yes;Connection Timeout=3;'
        conn = pyodbc.connect(conn_str)
        cursor = conn.cursor()
        cursor.execute('''
            SELECT c.client_net_address, c.client_tcp_port, CONVERT(NVARCHAR(64), r.query_hash, 1) as query_hash,
                   CONVERT(NVARCHAR(130), r.sql_handle, 1) as sql_handle, c.local_tcp_port
            FROM sys.dm_exec_connections c JOIN sys.dm_exec_requests r ON c.session_id = r.session_id
        ''')
        for row in cursor.fetchall():
            key = f'{row.client_net_address.strip()}:{row.client_tcp_port}'
            sessions[key] = {'hash': row.query_hash, 'sql_handle': row.sql_handle, 'localPort': int(row.local_tcp_port)}
        conn.close()
    except: pass
    return sessions

def get_mysql_sessions():
    sessions = {}
    try:
        # Requires mysql client and appropriate permissions (e.g. via /root/.my.cnf)
        cmd = ['mysql', '-sN', '-e', 'SELECT host, info FROM information_schema.processlist WHERE command != \"Sleep\" AND host IS NOT NULL']
        output = subprocess.check_output(cmd, stderr=subprocess.STDOUT, timeout=3).decode('utf-8')
        for line in output.splitlines():
            if '\t' in line:
                host_str, sql = line.split('\t', 1)
                if ':' in host_str:
                    ip, port = host_str.rsplit(':', 1)
                    qhash = '0x' + hashlib.md5(sql.encode('utf-8')).hexdigest() if sql else ''
                    sessions[f'{ip}:{port}'] = {'hash': qhash, 'localPort': 3306}
    except: pass
    return sessions

def get_pg_sessions():
    sessions = {}
    try:
        # Requires psql client and appropriate permissions
        cmd = ['psql', '-tA', '-F', '\t', '-c', \"SELECT client_addr, client_port, query FROM pg_stat_activity WHERE state = 'active' AND client_addr IS NOT NULL\"]
        output = subprocess.check_output(cmd, stderr=subprocess.STDOUT, timeout=3).decode('utf-8')
        for line in output.splitlines():
            parts = line.split('\t')
            if len(parts) >= 3:
                ip, port, sql = parts[0], parts[1], parts[2]
                qhash = '0x' + hashlib.md5(sql.encode('utf-8')).hexdigest() if sql else ''
                sessions[f'{ip}:{port}'] = {'hash': qhash, 'localPort': 5432}
    except: pass
    return sessions

all_sessions = {}
all_sessions.update(get_mssql_sessions())
all_sessions.update(get_mysql_sessions())
all_sessions.update(get_pg_sessions())
print(json.dumps(all_sessions))
" 2>/dev/null)

    # Try ss first (faster, modern)
    if command -v ss >/dev/null 2>&1; then
        source_cmd="ss"
        net_json=$(_collect_with_ss "$lssn" "$python_cmd")
        
        # Check if we got any connections
        # We count occurrences of "local_ip" to estimate connection count
        local conn_count=$(echo "$net_json" | grep -o "\"local_ip\"" | wc -l)
        
        if [ "$conn_count" -eq 0 ]; then
             log_message "WARN" "[Net3D] 'ss' command yielded 0 connections. Attempting fallback to 'netstat'."
             net_json="" # Clear to trigger fallback
        fi
    fi
    
    # Fallback to netstat if ss was skipped, missing, or returned 0 connections
    if [ -z "$net_json" ]; then
        if command -v netstat >/dev/null 2>&1; then
            source_cmd="netstat"
            net_json=$(_collect_with_netstat "$lssn" "$python_cmd")
        else
            # Only log warning if we didn't try ss or ss was also missing
            if [ "$source_cmd" != "ss" ]; then
                log_message "WARN" "[Net3D] Neither 'ss' nor 'netstat' found. Skipping."
                return 1
            fi
            # If ss was tried (and emptiness caused fallthrough) but netstat missing
            log_message "WARN" "[Net3D] 'ss' returned 0 connections and 'netstat' is not available."
            return 1
        fi
    fi

    # 3. Upload Network Data to KVS (netstat factor)
    if kvs_put "lssn" "${lssn}" "netstat" "$net_json"; then
        log_message "INFO" "[Net3D] Successfully uploaded netstat data"
        echo "$(date +%s)" > "${NET3D_STATE_FILE}_${lssn}"
    else
        log_message "ERROR" "[Net3D] Failed to upload netstat data"
        return 1
    fi

    # 4. Upload DB Connection Data to KVS (db_connections factor)
    # [NEW] Separation of concerns: DB data goes to its own factor as per global standards
    if [ "$sql_session_map" != "{}" ]; then
        local db_json=""
        db_json=$($python_cmd -c "
import sys, json
try:
    session_map = json.loads(sys.argv[1])
    db_conns = []
    for key, s in session_map.items():
        ip, port = key.rsplit(':', 1)
        db_conns.append({
            'client_net_address': ip,
            'remote_port': int(port),
            'local_port': s.get('localPort'),
            'query_hash': s.get('hash', ''),
            'sql_handle': s.get('sql_handle', ''),
            'status': 'active'
        })
    print(json.dumps(db_conns))
except Exception as e:
    print('[]')
" "$sql_session_map")

        if [ "$db_json" != "[]" ]; then
            if kvs_put "lssn" "${lssn}" "db_connections" "$db_json"; then
                log_message "INFO" "[Net3D] Successfully uploaded db_connections data"
            else
                log_message "ERROR" "[Net3D] Failed to upload db_connections data"
            fi
        fi
    fi
    
    # 5. Upload Server IP Information (if module available)
    if declare -f collect_server_ips >/dev/null 2>&1; then
        local server_ips_json=$(collect_server_ips "$lssn")
        
        # Validate JSON
        if echo "$server_ips_json" | grep -q '"error"'; then
            log_message "WARN" "[Net3D] Server IP collection failed: $server_ips_json"
        else
            local ips_len=${#server_ips_json}
            if [[ "$ips_len" -gt 10 ]]; then
                if kvs_put "lssn" "${lssn}" "server_ips" "$server_ips_json"; then
                    log_message "INFO" "[Net3D] Successfully uploaded server IP data (${ips_len} bytes)"
                else
                    log_message "ERROR" "[Net3D] Failed to upload server IP data"
                fi
            fi
        fi
    else
        log_message "DEBUG" "[Net3D] Server IP collection module not loaded, skipping"
    fi
    
    return 0
}

# ============================================================================
# Helper: Check if it's time to run
# ============================================================================
should_run_net3d() {
    local lssn="$1"
    local state_file="${NET3D_STATE_FILE}_${lssn}"
    
    if [ ! -f "$state_file" ]; then
        return 0 # Run if first time
    fi
    
    local last_run=$(cat "$state_file")
    local current_time=$(date +%s)
    local elapsed=$((current_time - last_run))
    
    if (( elapsed >= NET3D_INTERVAL )); then
        return 0
    else
        return 1
    fi
}

# ============================================================================
# Helper: Collect using 'ss' command (External Python Script)
# ============================================================================
_collect_with_ss() {
    local lssn="$1"
    local python_cmd="$2"
    
    # Get script directory
    local SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local PARSE_SCRIPT="$SCRIPT_DIR/parse_ss.py"
    
    if [ ! -f "$PARSE_SCRIPT" ]; then
        echo '{"connections": [], "error": "parse_ss.py not found"}'
        return 1
    fi
    
    # Parse ss output using external Python script
    local result=$(ss -ntap 2>/dev/null | $python_cmd "$PARSE_SCRIPT" "$lssn")
    
    # Add timestamp, CPU, and Memory usage (Python script leaves it empty)
    local cpu=$(get_cpu_usage)
    local mem=$(get_mem_usage)
    echo "$result" | $python_cmd -c "import sys, json; data = json.load(sys.stdin); data['timestamp'] = '$(date +%s)'; data['cpu_usage'] = $cpu; data['mem_usage'] = $mem; print(json.dumps(data))"
}

# ============================================================================
# Helper: Collect using 'netstat' command (External Python Script)
# ============================================================================
_collect_with_netstat() {
    local lssn="$1"
    local python_cmd="$2"
    
    # Get script directory
    local SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local PARSE_SCRIPT="$SCRIPT_DIR/parse_netstat.py"
    
    if [ ! -f "$PARSE_SCRIPT" ]; then
        echo '{"connections": [], "error": "parse_netstat.py not found"}'
        return 1
    fi
    
    # Parse netstat output using external Python script
    local result=$(netstat -antp 2>/dev/null | $python_cmd "$PARSE_SCRIPT" "$lssn")
    
    # Add timestamp, CPU, and Memory usage (Python script leaves it empty)
    local cpu=$(get_cpu_usage)
    local mem=$(get_mem_usage)
    echo "$result" | $python_cmd -c "import sys, json; data = json.load(sys.stdin); data['timestamp'] = '$(date +%s)'; data['cpu_usage'] = $cpu; data['mem_usage'] = $mem; print(json.dumps(data))"
}
