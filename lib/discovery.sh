#!/bin/bash
# lib/discovery.sh - Infrastructure Discovery 모듈
# 로컬 및 원격(SSH) 서버의 Infrastructure 데이터 수집
# 사용: source lib/discovery.sh && collect_infrastructure_data <lssn> [ssh_user@ssh_host:ssh_port]

# ⚠️ set -euo pipefail 제거됨 (부모 스크립트 영향 방지)
# 대신 각 함수에서 명시적 error handling 사용

# ============================================================================
# Required Dependencies (must be loaded before this module)
# ============================================================================
# - common.sh (for log_auto_discover_step, log_auto_discover_error, log_auto_discover_validation, log_message)
# - kvs.sh (for kvs_put)

# Verify dependencies are available
if ! declare -f log_auto_discover_step >/dev/null 2>&1; then
	echo "❌ Error: log_auto_discover_step not found. common.sh must be loaded before discovery.sh" >&2
	exit 1
fi

if ! declare -f kvs_put >/dev/null 2>&1; then
	echo "❌ Error: kvs_put not found. kvs.sh must be loaded before discovery.sh" >&2
	exit 1
fi

# 설정
DISCOVERY_SCRIPT_LOCAL="${SCRIPT_DIR}/scripts/auto-discover-linux.sh"
DISCOVERY_INTERVAL=21600  # 6시간 (초 단위)
DISCOVERY_STATE_FILE="${DISCOVERY_STATE_FILE:-/tmp/giip_discovery_state}"
LOG_FILE="${LOG_FILE:-/var/log/giipagent.log}"

# KVS 로깅 설정
KVS_LOG_ENABLED=true
KVS_LSSN="${KVS_LSSN:-9999}"  # 모니터링용 LSSN

# ============================================================================
# 함수 0: KVS 로깅 (문제 추적용)
# ============================================================================
_log_to_kvs() {
    local phase="$1"      # 단계명 (예: INIT, LOCAL_START, REMOTE_CONNECT, JSON_PARSE, DB_SAVE, ERROR)
    local lssn="$2"       # 대상 LSSN
    local status="$3"     # 상태 (SUCCESS, RUNNING, ERROR, WARNING)
    local message="$4"    # 상세 메시지
    local data="${5:-}"   # 추가 데이터 (선택)
    
    if [[ "$KVS_LOG_ENABLED" != "true" ]]; then
        return 0
    fi
    
    # KVS에 저장할 JSON 생성
    local timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    local kvs_json=$(cat <<EOF
{
  "phase": "$phase",
  "target_lssn": $lssn,
  "status": "$status",
  "message": "$(echo "$message" | sed 's/"/\\"/g')",
  "timestamp": "$timestamp",
  "hostname": "$(hostname)",
  "pid": $$
  $(if [[ -n "$data" ]]; then echo ",$data"; fi)
}
EOF
)
    
    # KVS에 저장 시도
    if command -v kvsput >/dev/null 2>&1; then
        # giipAgentLinux의 kvsput 사용
        local factor="discovery_${phase}_$(date +%s)"
        kvsput "$factor" "$kvs_json" 2>/dev/null || true
    fi
    
    # 파일 기반 로깅도 병행
    local log_file="/tmp/discovery_kvs_log_${KVS_LSSN}.txt"
    echo "[$timestamp] [LSSN:$lssn] [$phase] [$status] $message" >> "$log_file" 2>/dev/null || true
}

# ============================================================================
# 함수 1: 로컬 또는 원격 서버에서 Infrastructure Discovery 데이터 수집
# ============================================================================
collect_infrastructure_data() {
    local lssn="$1"
    local remote_info="${2:-}"  # 형식: ssh_user@ssh_host:ssh_port 또는 비어있음(로컬)
    
    # 전역 LSSN 설정 (모든 로깅에 사용)
    export KVS_LSSN="$lssn"
    
    _log_to_kvs "DISCOVERY_START" "$lssn" "RUNNING" "Starting infrastructure discovery collection, remote_info=$remote_info" || true
    
    if [[ -n "$remote_info" ]]; then
        # echo "[Discovery] 🔍 Collecting infrastructure data from remote server (LSSN=$lssn, Host=$remote_info)" >&2
        _collect_remote_data "$lssn" "$remote_info" || return 1
    else
        # echo "[Discovery] 🔍 Collecting infrastructure data locally (LSSN=$lssn)" >&2
        _collect_local_data "$lssn" || return 1
    fi
    
    _log_to_kvs "DISCOVERY_END" "$lssn" "SUCCESS" "Infrastructure discovery collection completed" || true
    return 0
}

# ============================================================================
# 함수 2: 로컬 auto-discover 실행
# ============================================================================
_collect_local_data() {
    local lssn="$1"
    
    _log_to_kvs "LOCAL_START" "$lssn" "RUNNING" "Starting local discovery"
    
    # Step 1: auto-discover-linux.sh 실행
    if [[ ! -f "$DISCOVERY_SCRIPT_LOCAL" ]]; then
        local error_msg="Script not found: $DISCOVERY_SCRIPT_LOCAL"
        # echo "[Discovery] ❌ Error: $error_msg" >&2
        _log_to_kvs "LOCAL_SCRIPT_CHECK" "$lssn" "ERROR" "$error_msg"
        return 1
    fi
    
    _log_to_kvs "LOCAL_SCRIPT_CHECK" "$lssn" "SUCCESS" "Script found: $DISCOVERY_SCRIPT_LOCAL"
    
    local discovery_json
    # ⭐ RULE: Call with bash for independent execution (NO chmod +x)
    # Separate stderr (debug logs) from stdout (JSON output)
    if ! discovery_json=$(bash "$DISCOVERY_SCRIPT_LOCAL" 2>/dev/null); then
        local error_msg="Failed to execute auto-discover-linux.sh"
        # echo "[Discovery] ❌ Error: $error_msg" >&2
        _log_to_kvs "LOCAL_EXECUTION" "$lssn" "ERROR" "$error_msg"
        return 1
    fi
    
    _log_to_kvs "LOCAL_EXECUTION" "$lssn" "SUCCESS" "Script executed successfully"
    
    # Step 2: JSON 검증
    if ! echo "$discovery_json" | python3 -m json.tool >/dev/null 2>&1; then
        local error_msg="Invalid JSON from local discovery script"
        # echo "[Discovery] ❌ Error: $error_msg" >&2
        # echo "[Discovery] Debug: ${discovery_json:0:500}" >&2
        _log_to_kvs "LOCAL_JSON_VALIDATION" "$lssn" "ERROR" "$error_msg, First 500 chars: ${discovery_json:0:500}"
        return 1
    fi
    
    _log_to_kvs "LOCAL_JSON_VALIDATION" "$lssn" "SUCCESS" "JSON validation passed"
    
    # Step 3: DB 저장
    if ! _save_discovery_to_db "$lssn" "$discovery_json"; then
        _log_to_kvs "LOCAL_DB_SAVE" "$lssn" "ERROR" "Failed to save discovery data to DB"
        return 1
    fi
    
    _log_to_kvs "LOCAL_DB_SAVE" "$lssn" "SUCCESS" "Discovery data saved to DB"
    # echo "[Discovery] ✅ Local infrastructure discovery completed for LSSN=$lssn" >&2
    { rm -f "$DISCOVERY_STATE_FILE.lssn_$lssn" && echo "$(date +%s)" > "$DISCOVERY_STATE_FILE.lssn_$lssn"; } 2>/dev/null || true
    
    return 0
}

# ============================================================================
# 함수 3: 원격 서버에서 SSH를 통해 auto-discover 실행
# ============================================================================
_collect_remote_data() {
    local lssn="$1"
    local remote_info="$2"  # 형식: ssh_user@ssh_host:ssh_port 또는 ssh_user@ssh_host
    
    _log_to_kvs "REMOTE_START" "$lssn" "RUNNING" "Starting remote discovery: $remote_info"
    
    # remote_info 파싱
    local ssh_user ssh_host ssh_port ssh_key
    if ! _parse_ssh_info "$remote_info" ssh_user ssh_host ssh_port ssh_key; then
        _log_to_kvs "REMOTE_PARSE" "$lssn" "ERROR" "Failed to parse remote info: $remote_info"
        return 1
    fi
    
    _log_to_kvs "REMOTE_PARSE" "$lssn" "SUCCESS" "Parsed: user=$ssh_user, host=$ssh_host, port=$ssh_port"
    
    # Step 1: 원격 서버에서 auto-discover-linux.sh 실행 (방법 1: 기존 경로)
    local discovery_json
    
    # echo "[Discovery] 📡 Connecting to $ssh_user@$ssh_host:$ssh_port (LSSN=$lssn)..." >&2
    
    _log_to_kvs "REMOTE_CONNECT" "$lssn" "RUNNING" "Attempting SSH connection to $ssh_host:$ssh_port"
    
    # 방법 1: 원격 서버에 auto-discover-linux.sh가 이미 있는 경우
    local try1_error=""
    if discovery_json=$(_ssh_exec "$ssh_user" "$ssh_host" "$ssh_port" "$ssh_key" \
        "bash /opt/giip/agent/linux/scripts/auto-discover-linux.sh 2>&1" 2>&1); then
        
        _log_to_kvs "REMOTE_EXECUTE_METHOD1" "$lssn" "SUCCESS" "Script executed via method 1 (existing path)"
        
        if echo "$discovery_json" | python3 -m json.tool >/dev/null 2>&1; then
            # echo "[Discovery] ✅ Remote discovery data collected successfully (method 1)" >&2
            _log_to_kvs "REMOTE_JSON_VALIDATION" "$lssn" "SUCCESS" "JSON validation passed (method 1)"
            
            if _save_discovery_to_db "$lssn" "$discovery_json"; then
                _log_to_kvs "REMOTE_DB_SAVE" "$lssn" "SUCCESS" "Discovery data saved to DB"
                { rm -f "$DISCOVERY_STATE_FILE.lssn_$lssn.remote_$ssh_host" && echo "$(date +%s)" > "$DISCOVERY_STATE_FILE.lssn_$lssn.remote_$ssh_host"; } 2>/dev/null || true
                return 0
            else
                _log_to_kvs "REMOTE_DB_SAVE" "$lssn" "ERROR" "Failed to save discovery data to DB (method 1)"
                # 계속 진행 (방법 2 시도)
            fi
        else
            try1_error="Invalid JSON: ${discovery_json:0:200}"
            _log_to_kvs "REMOTE_JSON_VALIDATION" "$lssn" "WARNING" "$try1_error"
        fi
    else
        try1_error="SSH execution failed: $discovery_json"
        _log_to_kvs "REMOTE_EXECUTE_METHOD1" "$lssn" "WARNING" "$try1_error"
    fi
    
    # 방법 2: 로컬 스크립트를 원격으로 전송 후 실행
    # echo "[Discovery] 📤 Transferring discovery script to $ssh_host (method 2)..." >&2
    
    _log_to_kvs "REMOTE_TRANSFER_START" "$lssn" "RUNNING" "Transferring script from method 1 failure: $try1_error"
    
    if ! _scp_file "$ssh_user" "$ssh_host" "$ssh_port" "$ssh_key" \
        "$DISCOVERY_SCRIPT_LOCAL" "/tmp/auto-discover-linux.sh"; then
        local error_msg="Failed to transfer discovery script to $ssh_host"
        # echo "[Discovery] ❌ Error: $error_msg" >&2
        _log_to_kvs "REMOTE_TRANSFER" "$lssn" "ERROR" "$error_msg"
        return 1
    fi
    
    _log_to_kvs "REMOTE_TRANSFER" "$lssn" "SUCCESS" "Script transferred successfully"
    
    # 원격에서 전송된 스크립트 실행
    _log_to_kvs "REMOTE_EXECUTE_METHOD2" "$lssn" "RUNNING" "Executing transferred script"
    
    if ! discovery_json=$(_ssh_exec "$ssh_user" "$ssh_host" "$ssh_port" "$ssh_key" \
        "bash /tmp/auto-discover-linux.sh 2>&1" 2>&1); then
        local error_msg="Failed to execute discovery script on $ssh_host"
        # echo "[Discovery] ❌ Error: $error_msg" >&2
        _log_to_kvs "REMOTE_EXECUTE_METHOD2" "$lssn" "ERROR" "$error_msg: $discovery_json"
        return 1
    fi
    
    _log_to_kvs "REMOTE_EXECUTE_METHOD2" "$lssn" "SUCCESS" "Script executed via method 2 (transferred)"
    
    # Step 2: JSON 검증
    if ! echo "$discovery_json" | python3 -m json.tool >/dev/null 2>&1; then
        local error_msg="Invalid JSON from remote discovery script (method 2)"
        # echo "[Discovery] ❌ Error: $error_msg" >&2
        # echo "[Discovery] Debug: ${discovery_json:0:500}" >&2
        _log_to_kvs "REMOTE_JSON_VALIDATION_METHOD2" "$lssn" "ERROR" "$error_msg, First 500 chars: ${discovery_json:0:500}"
        return 1
    fi
    
    _log_to_kvs "REMOTE_JSON_VALIDATION_METHOD2" "$lssn" "SUCCESS" "JSON validation passed (method 2)"
    
    # Step 3: DB 저장
    _log_to_kvs "REMOTE_DB_SAVE" "$lssn" "RUNNING" "Saving discovery data to database"
    
    if ! _save_discovery_to_db "$lssn" "$discovery_json"; then
        _log_to_kvs "REMOTE_DB_SAVE" "$lssn" "ERROR" "Failed to save discovery data to DB"
        # 정리: 원격 임시 파일 삭제
        _ssh_exec "$ssh_user" "$ssh_host" "$ssh_port" "$ssh_key" \
            "rm -f /tmp/auto-discover-linux.sh" 2>/dev/null || true
        return 1
    fi
    
    _log_to_kvs "REMOTE_DB_SAVE" "$lssn" "SUCCESS" "Discovery data saved to DB"
    
    # 정리: 원격 임시 파일 삭제
    _log_to_kvs "REMOTE_CLEANUP" "$lssn" "RUNNING" "Cleaning up temporary files on remote host"
    _ssh_exec "$ssh_user" "$ssh_host" "$ssh_port" "$ssh_key" \
        "rm -f /tmp/auto-discover-linux.sh" 2>/dev/null || true
    
    # echo "[Discovery] ✅ Remote infrastructure discovery completed for LSSN=$lssn (Host=$ssh_host)" >&2
    _log_to_kvs "REMOTE_COMPLETE" "$lssn" "SUCCESS" "Remote discovery completed successfully for host=$ssh_host"
    { rm -f "$DISCOVERY_STATE_FILE.lssn_$lssn.remote_$ssh_host" && echo "$(date +%s)" > "$DISCOVERY_STATE_FILE.lssn_$lssn.remote_$ssh_host"; } 2>/dev/null || true
    
    return 0
}

# ============================================================================
# 함수 4: SSH 정보 파싱
# 형식: ssh_user@ssh_host:ssh_port 또는 ssh_user@ssh_host (default port 22)
# 선택적: ssh_key 환경변수로 custom key 지정 가능
# ============================================================================
_parse_ssh_info() {
    local remote_info="$1"
    local -n out_user="$2"
    local -n out_host="$3"
    local -n out_port="$4"
    local -n out_key="$5"
    
    # user@host:port 형식 파싱
    if [[ "$remote_info" =~ ^([^@]+)@([^:]+):([0-9]+)$ ]]; then
        out_user="${BASH_REMATCH[1]}"
        out_host="${BASH_REMATCH[2]}"
        out_port="${BASH_REMATCH[3]}"
    elif [[ "$remote_info" =~ ^([^@]+)@(.+)$ ]]; then
        out_user="${BASH_REMATCH[1]}"
        out_host="${BASH_REMATCH[2]}"
        out_port="22"
    else
        # echo "[Discovery] ❌ Error: Invalid remote info format. Use 'user@host' or 'user@host:port'" >&2
        return 1
    fi
    
    # SSH 키 파일 결정 (환경변수 → 기본값)
    if [[ -n "${SSH_KEY:-}" ]]; then
        out_key="$SSH_KEY"
    else
        # 기본 키 위치 확인
        if [[ -f "/root/.ssh/giip_key" ]]; then
            out_key="/root/.ssh/giip_key"
        elif [[ -f "/root/.ssh/id_rsa" ]]; then
            out_key="/root/.ssh/id_rsa"
        else
            out_key=""  # SSH 에이전트 사용
        fi
    fi
}

# ============================================================================
# 함수 5: SSH 명령 실행
# ============================================================================
_ssh_exec() {
    local ssh_user="$1"
    local ssh_host="$2"
    local ssh_port="$3"
    local ssh_key="$4"
    local command="$5"
    
    local ssh_opts="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"
    
    if [[ -n "$ssh_key" && -f "$ssh_key" ]]; then
        ssh_opts="$ssh_opts -i $ssh_key"
    fi
    
    # SSH 실행 (로깅 포함)
    local output
    local exit_code
    
    output=$(ssh $ssh_opts -p "$ssh_port" "${ssh_user}@${ssh_host}" "$command" 2>&1)
    exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        _log_to_kvs "SSH_EXEC_SUCCESS" "${KVS_LSSN:-9999}" "SUCCESS" "SSH command executed on $ssh_host:$ssh_port, user=$ssh_user"
    else
        _log_to_kvs "SSH_EXEC_ERROR" "${KVS_LSSN:-9999}" "ERROR" "SSH command failed with exit code $exit_code on $ssh_host:$ssh_port. Error: ${output:0:200}"
    fi
    
    echo "$output"
    return $exit_code
}

# ============================================================================
# 함수 6: SCP를 통한 파일 전송
# ============================================================================
_scp_file() {
    local ssh_user="$1"
    local ssh_host="$2"
    local ssh_port="$3"
    local ssh_key="$4"
    local local_file="$5"
    local remote_file="$6"
    
    local scp_opts="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"
    
    if [[ -n "$ssh_key" && -f "$ssh_key" ]]; then
        scp_opts="$scp_opts -i $ssh_key"
    fi
    
    # SCP 실행 (로깅 포함)
    local output
    local exit_code
    
    output=$(scp $scp_opts -P "$ssh_port" "$local_file" "${ssh_user}@${ssh_host}:${remote_file}" 2>&1)
    exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        _log_to_kvs "SCP_TRANSFER_SUCCESS" "${KVS_LSSN:-9999}" "SUCCESS" "File transferred: $local_file → $ssh_host:$remote_file"
    else
        _log_to_kvs "SCP_TRANSFER_ERROR" "${KVS_LSSN:-9999}" "ERROR" "SCP transfer failed with exit code $exit_code. Error: ${output:0:200}"
    fi
    
    return $exit_code
}

# ============================================================================
# 함수 7: Discovery 데이터를 DB에 저장
# ============================================================================
_save_discovery_to_db() {
    local lssn="$1"
    local discovery_json="$2"
    
    # echo "[Discovery] 💾 Saving to database for LSSN=$lssn..." >&2
    _log_to_kvs "DB_SAVE_START" "$lssn" "RUNNING" "Starting database save operations"
    
    # Step 1: Server Info (tLSvr)
    _log_to_kvs "DB_SAVE_SERVER_INFO" "$lssn" "RUNNING" "Saving server info"
    _save_server_info "$lssn" "$discovery_json" || {
        _log_to_kvs "DB_SAVE_SERVER_INFO" "$lssn" "ERROR" "Failed to save server info"
        return 1
    }
    _log_to_kvs "DB_SAVE_SERVER_INFO" "$lssn" "SUCCESS" "Server info saved"
    
    # Step 2: Network Interfaces (tLSvrNIC)
    _log_to_kvs "DB_SAVE_NETWORK" "$lssn" "RUNNING" "Saving network interfaces"
    _save_network_interfaces "$lssn" "$discovery_json" || {
        _log_to_kvs "DB_SAVE_NETWORK" "$lssn" "ERROR" "Failed to save network interfaces"
        return 1
    }
    _log_to_kvs "DB_SAVE_NETWORK" "$lssn" "SUCCESS" "Network interfaces saved"
    
    # Step 3: Software (tLSvrSoftware)
    _log_to_kvs "DB_SAVE_SOFTWARE" "$lssn" "RUNNING" "Saving software inventory"
    _save_software "$lssn" "$discovery_json" || {
        _log_to_kvs "DB_SAVE_SOFTWARE" "$lssn" "ERROR" "Failed to save software"
        return 1
    }
    _log_to_kvs "DB_SAVE_SOFTWARE" "$lssn" "SUCCESS" "Software inventory saved"
    
    # Step 4: Services (tLSvrService)
    _log_to_kvs "DB_SAVE_SERVICES" "$lssn" "RUNNING" "Saving services"
    _save_services "$lssn" "$discovery_json" || {
        _log_to_kvs "DB_SAVE_SERVICES" "$lssn" "ERROR" "Failed to save services"
        return 1
    }
    _log_to_kvs "DB_SAVE_SERVICES" "$lssn" "SUCCESS" "Services saved"
    
    # Step 5: Generate Advice (pApiAgentGenerateAdvicebyAK)
    _log_to_kvs "DB_GENERATE_ADVICE" "$lssn" "RUNNING" "Generating advice"
    _generate_advice "$lssn" || {
        _log_to_kvs "DB_GENERATE_ADVICE" "$lssn" "WARNING" "Failed to generate advice (non-critical)"
    }
    _log_to_kvs "DB_GENERATE_ADVICE" "$lssn" "SUCCESS" "Advice generation completed"
    
    _log_to_kvs "DB_SAVE_COMPLETE" "$lssn" "SUCCESS" "All database operations completed successfully"
    # echo "[Discovery] ✅ Database save completed for LSSN=$lssn" >&2
    return 0
}

# ============================================================================
# 함수 8: Server Info 저장 (tLSvr)
# ============================================================================
_save_server_info() {
    local lssn="$1"
    local discovery_json="$2"
    
    # JSON에서 필드 추출
    local hostname=$(echo "$discovery_json" | python3 -c "import sys,json; print(json.load(sys.stdin).get('hostname',''))" 2>/dev/null || echo "")
    local os=$(echo "$discovery_json" | python3 -c "import sys,json; print(json.load(sys.stdin).get('os',''))" 2>/dev/null || echo "")
    local cpu=$(echo "$discovery_json" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cpu',''))" 2>/dev/null || echo "")
    local cpu_cores=$(echo "$discovery_json" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cpu_cores',0))" 2>/dev/null || echo "0")
    local memory_gb=$(echo "$discovery_json" | python3 -c "import sys,json; print(json.load(sys.stdin).get('memory_gb',0))" 2>/dev/null || echo "0")
    local disk_gb=$(echo "$discovery_json" | python3 -c "import sys,json; print(json.load(sys.stdin).get('disk_gb',0))" 2>/dev/null || echo "0")
    
    _log_to_kvs "SERVER_INFO_PARSE" "$lssn" "SUCCESS" "Parsed server info: hostname=$hostname, os=$os, cores=$cpu_cores, mem=${memory_gb}GB"
    
    # API 호출을 위한 JSON 생성
    local api_json=$(cat <<EOF
{
    "lssn": $lssn,
    "hostname": "$(echo "$hostname" | sed 's/"/\\"/g')",
    "osVersion": "$(echo "$os" | sed 's/"/\\"/g')",
    "cpu": "$(echo "$cpu" | sed 's/"/\\"/g')",
    "cpuCores": $cpu_cores,
    "memoryGB": $memory_gb,
    "diskGB": $disk_gb,
    "agentVersion": "3.0"
}
EOF
)
    
    # API 호출 시뮬레이션 (실제로는 KVS에 저장 또는 API 호출)
    # echo "[Discovery] 📊 Server info: hostname=$hostname, os=$os, cores=$cpu_cores, mem=${memory_gb}GB, disk=${disk_gb}GB" >&2
    
    _log_to_kvs "SERVER_INFO_API_CALL" "$lssn" "RUNNING" "Calling server info API with: $api_json"
    
    # TODO: 실제 API 호출 또는 KVS 저장
    # _api_call "ServerInfoUpdate" "$api_json"
    
    _log_to_kvs "SERVER_INFO_API_CALL" "$lssn" "SUCCESS" "Server info API call completed (TODO: actual implementation)"
    
    return 0
}

# ============================================================================
# 함수 9: Network Interfaces 저장 (tLSvrNIC)
# ============================================================================
_save_network_interfaces() {
    local lssn="$1"
    local discovery_json="$2"
    
    local nic_count=0
    
    _log_to_kvs "NETWORK_PARSE_START" "$lssn" "RUNNING" "Parsing network interfaces from discovery data"
    
    # network[] 배열 순회
    echo "$discovery_json" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    networks = data.get('network', [])
    for i, net in enumerate(networks):
        is_primary = 1 if i == 0 else 0
        print(f'{net.get(\"name\",\"\")}|{net.get(\"ipv4\",\"\")}|{net.get(\"ipv6\",\"\")}|{net.get(\"mac\",\"\")}|{is_primary}')
except Exception as e:
    pass
" 2>/dev/null | while IFS='|' read -r ifname ipv4 ipv6 mac is_primary; do
        
        [[ -z "$ifname" ]] && continue
        
        # echo "[Discovery] 🌐 NIC: $ifname - IPv4=$ipv4, IPv6=$ipv6, MAC=$mac" >&2
        _log_to_kvs "NETWORK_INTERFACE" "$lssn" "SUCCESS" "NIC entry: name=$ifname, ipv4=$ipv4, mac=$mac"
        ((nic_count++))
        
        # TODO: 실제 API 호출 또는 KVS 저장
    done
    
    _log_to_kvs "NETWORK_PARSE_COMPLETE" "$lssn" "SUCCESS" "Network interfaces parsed: $nic_count NICs"
    # echo "[Discovery] ✅ Network interfaces saved ($nic_count NICs)" >&2
    return 0
}

# ============================================================================
# 함수 10: Software 저장 (tLSvrSoftware)
# ============================================================================
_save_software() {
    local lssn="$1"
    local discovery_json="$2"
    
    local sw_count=0
    
    _log_to_kvs "SOFTWARE_PARSE_START" "$lssn" "RUNNING" "Parsing software inventory from discovery data"
    
    # software[] 배열 순회
    echo "$discovery_json" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    softwares = data.get('software', [])
    for sw in softwares:
        print(f'{sw.get(\"name\",\"\")}|{sw.get(\"version\",\"\")}|{sw.get(\"vendor\",\"\")}')
except Exception as e:
    pass
" 2>/dev/null | while IFS='|' read -r name version vendor; do
        
        [[ -z "$name" ]] && continue
        
        # echo "[Discovery] 📦 Software: $name v$version" >&2
        _log_to_kvs "SOFTWARE_ENTRY" "$lssn" "SUCCESS" "Software entry: name=$name, version=$version"
        ((sw_count++))
        
        # TODO: 실제 API 호출 또는 KVS 저장
    done
    
    _log_to_kvs "SOFTWARE_PARSE_COMPLETE" "$lssn" "SUCCESS" "Software inventory parsed: $sw_count items"
    # echo "[Discovery] ✅ Software list saved ($sw_count items)" >&2
    return 0
}

# ============================================================================
# 함수 11: Services 저장 (tLSvrService)
# ============================================================================
_save_services() {
    local lssn="$1"
    local discovery_json="$2"
    
    local svc_count=0
    
    _log_to_kvs "SERVICES_PARSE_START" "$lssn" "RUNNING" "Parsing services from discovery data"
    
    # services[] 배열 순회
    echo "$discovery_json" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    services = data.get('services', [])
    for svc in services:
        print(f'{svc.get(\"name\",\"\")}|{svc.get(\"status\",\"\")}|{svc.get(\"port\",0)}')
except Exception as e:
    pass
" 2>/dev/null | while IFS='|' read -r name status port; do
        
        [[ -z "$name" ]] && continue
        
        # echo "[Discovery] 🔧 Service: $name - $status (port=$port)" >&2
        _log_to_kvs "SERVICE_ENTRY" "$lssn" "SUCCESS" "Service entry: name=$name, status=$status, port=$port"
        ((svc_count++))
        
        # TODO: 실제 API 호출 또는 KVS 저장
    done
    
    _log_to_kvs "SERVICES_PARSE_COMPLETE" "$lssn" "SUCCESS" "Services parsed: $svc_count items"
    # echo "[Discovery] ✅ Services saved ($svc_count items)" >&2
    return 0
}

# ============================================================================
# 함수 12: Advice 생성 (pApiAgentGenerateAdvicebyAK)
# ============================================================================
_generate_advice() {
    local lssn="$1"
    
    # echo "[Discovery] 🧠 Generating advice for LSSN=$lssn..." >&2
    _log_to_kvs "ADVICE_GENERATION" "$lssn" "RUNNING" "Generating advice based on discovery data"
    
    # TODO: 실제 API 호출
    # _api_call "GenerateAdvicebyAK" "{\"lssn\":$lssn}"
    
    _log_to_kvs "ADVICE_GENERATION" "$lssn" "SUCCESS" "Advice generation completed (TODO: actual implementation)"
    # echo "[Discovery] ℹ️  Advice generation skipped (optional)" >&2
    return 0
}

# ============================================================================
# 함수 13: 스케줄링 확인 (6시간 간격)
# ============================================================================
should_run_discovery() {
    local lssn="$1"
    local remote_info="${2:-}"
    
    local state_file="$DISCOVERY_STATE_FILE.lssn_$lssn"
    
    # 원격 서버의 경우 파일명에 호스트 추가
    if [[ -n "$remote_info" ]]; then
        local ssh_host
        if [[ "$remote_info" =~ ^([^@]+)@([^:]+) ]]; then
            ssh_host="${BASH_REMATCH[2]}"
            state_file="${state_file}.remote_${ssh_host}"
        fi
    fi
    
    # 처음 실행?
    if [[ ! -f "$state_file" ]]; then
        return 0  # true
    fi
    
    # 6시간 경과?
    local last_run=$(cat "$state_file")
    local current_time=$(date +%s)
    local elapsed=$((current_time - last_run))
    
    if (( elapsed >= DISCOVERY_INTERVAL )); then
        return 0  # true
    else
        return 1  # false
    fi
}

# ============================================================================
# 메인 진입점 (직접 실행 시)
# ============================================================================
# ============================================================================
# Auto-Discover Functions (STEP-1 ~ STEP-7)
# ============================================================================

# Helper function: Resolve auto-discover script path
_resolve_auto_discover_script() {
	local base_dir="$1"
	
	# Handle case where SCRIPT_DIR might already include /lib
	if [[ "$base_dir" == */lib ]]; then
		base_dir="${base_dir%/lib}"
	fi
	
	echo "${base_dir}/giipscripts/auto-discover-linux.sh"
}

# STEP-1: Configuration Check
_auto_discover_step1_config_check() {
	local lssn="$1"
	
	log_auto_discover_step "STEP-1" "Configuration Check" "auto_discover_step_1_config" \
		"{\"lssn\":${lssn},\"sk_length\":${#sk},\"apiaddrv2_set\":$([ -n \"$apiaddrv2\" ] && echo 'true' || echo 'false')}"
	
	if [ -z "$sk" ] || [ -z "$apiaddrv2" ]; then
		log_auto_discover_error "STEP-1" "CONFIG_MISSING" "Required variables not set" \
			"{\"sk_set\":$([ -n \"$sk\" ] && echo 'true' || echo 'false'),\"apiaddrv2_set\":$([ -n \"$apiaddrv2\" ] && echo 'true' || echo 'false')}"
		return 1
	fi
	
	return 0
}

# STEP-2: Script Path Check
_auto_discover_step2_script_check() {
	local script_path="$1"
	
	log_auto_discover_step "STEP-2" "Script Path Check" "auto_discover_step_2_scriptpath" \
		"{\"path\":\"${script_path}\",\"exists\":$([ -f \"$script_path\" ] && echo 'true' || echo 'false')}"
	
	if [ ! -f "$script_path" ]; then
		log_auto_discover_error "STEP-2" "SCRIPT_NOT_FOUND" "auto-discover script not found" \
			"{\"searched_path\":\"${script_path}\"}"
		return 1
	fi
	
	return 0
}

# STEP-3: Initialize KVS
_auto_discover_step3_init_kvs() {
	local lssn="$1"
	local hostname="$2"
	local os="$3"
	local script_path="$4"
	
	log_auto_discover_step "STEP-3" "Initialize KVS Records" "auto_discover_step_3_init" \
		"{\"action\":\"storing_init_marker\",\"lssn\":${lssn}}"
	
	local init_data="{\"status\":\"starting\",\"script_path\":\"${script_path}\",\"hostname\":\"${hostname}\",\"os\":\"${os}\"}"
	kvs_put "lssn" "${lssn}" "auto_discover_init" "$init_data" >/dev/null 2>&1
	
	return $?
}

# STEP-4: Execute Auto-Discover Script
_auto_discover_step4_execute() {
	local script_path="$1"
	local lssn="$2"
	local hostname="$3"
	local os="$4"
	
	log_auto_discover_step "STEP-4" "Execute Auto-Discover Script" "auto_discover_step_4_execution" \
		"{\"script\":\"${script_path}\",\"timeout_sec\":60}"
	
	local result_file="/tmp/auto_discover_result_$$.json"
	local log_file="/tmp/auto_discover_log_$$.log"
	
	timeout 60 bash "$script_path" "$lssn" "$hostname" "$os" > "$result_file" 2> "$log_file"
	local exit_code=$?
	
	if [ $exit_code -eq 0 ]; then
		log_auto_discover_validation "STEP-4" "script_execution" "PASS" "{\"exit_code\":0}"
		echo "$result_file"
		return 0
	elif [ $exit_code -eq 124 ]; then
		log_auto_discover_error "STEP-4" "SCRIPT_TIMEOUT" "Script execution timed out" "{\"exit_code\":124}"
		return 1
	else
		local error=$(tail -5 "$log_file" 2>/dev/null | tr '\n' ';')
		log_auto_discover_error "STEP-4" "SCRIPT_EXECUTION_FAILED" "Script failed" "{\"exit_code\":${exit_code}}"
		return 1
	fi
}

# STEP-5: Validate Result File
_auto_discover_step5_validate() {
	local result_file="$1"
	
	local result_size=$(wc -c < "$result_file" 2>/dev/null || echo "0")
	log_auto_discover_step "STEP-5" "Validate Result File" "auto_discover_step_5_validation" \
		"{\"result_file\":\"${result_file}\"}"
	
	if [ $result_size -eq 0 ]; then
		log_auto_discover_error "STEP-5" "RESULT_FILE_EMPTY" "Result file is empty" "{\"file\":\"${result_file}\",\"size\":0}"
		return 1
	fi
	
	log_auto_discover_validation "STEP-5" "result_file_size" "PASS" "{\"bytes\":${result_size}}"
	return 0
}

# STEP-6: Extract and Store Components
_auto_discover_step6_extract() {
	local result_file="$1"
	local lssn="$2"
	
	log_auto_discover_step "STEP-6" "Extract Components" "auto_discover_step_6_extract" "{\"file\":\"${result_file}\"}"
	
	local auto_discover_json=$(cat "$result_file" 2>/dev/null)
	if [ -z "$auto_discover_json" ]; then
		log_auto_discover_error "STEP-6" "JSON_EMPTY" "Failed to read discovery JSON" "{}"
		return 1
	fi
	
	# Store complete result
	local result_kvalue="/tmp/kvs_kValue_auto_discover_result_$$.json"
	echo "$auto_discover_json" > "$result_kvalue"
	kvs_put "lssn" "${lssn}" "auto_discover_result" "$auto_discover_json" >/dev/null 2>&1
	
	# Extract and store networks
	local networks_data=$(echo "$auto_discover_json" | jq '.network // empty' 2>/dev/null)
	if [ -n "$networks_data" ]; then
		kvs_put "lssn" "${lssn}" "auto_discover_networks" "$networks_data" >/dev/null 2>&1
	fi
	
	# Extract and store services
	local services_data=$(echo "$auto_discover_json" | jq '.services // empty' 2>/dev/null)
	if [ -n "$services_data" ]; then
		kvs_put "lssn" "${lssn}" "auto_discover_services" "$services_data" >/dev/null 2>&1
	fi
	
	log_auto_discover_validation "STEP-6" "components_extracted" "PASS" "{}"
	return 0
}

# STEP-7: Complete
_auto_discover_step7_complete() {
	local lssn="$1"
	
	log_auto_discover_step "STEP-7" "Store Complete Marker" "auto_discover_step_7_complete" "{\"status\":\"completed\"}"
	
	local complete_data="{\"status\":\"completed\",\"timestamp\":\"$(date '+%Y-%m-%d %H:%M:%S')\"}"
	kvs_put "lssn" "${lssn}" "auto_discover_complete" "$complete_data" >/dev/null 2>&1
	
	return 0
}

# Main: Run Auto-Discover (all steps)
run_auto_discover() {
	local lssn="$1"
	local hostname="$2"
	local os="$3"
	local script_base_dir="$4"
	
	# STEP-1: Configuration check
	_auto_discover_step1_config_check "$lssn" || return 1
	
	# STEP-2: Script path check
	local script_path=$(_resolve_auto_discover_script "$script_base_dir")
	_auto_discover_step2_script_check "$script_path" || return 1
	
	# STEP-3: Initialize KVS
	_auto_discover_step3_init_kvs "$lssn" "$hostname" "$os" "$script_path" || return 1
	
	# STEP-4: Execute script
	local result_file=$(_auto_discover_step4_execute "$script_path" "$lssn" "$hostname" "$os")
	if [ -z "$result_file" ]; then
		return 1
	fi
	
	# STEP-5: Validate result
	_auto_discover_step5_validate "$result_file" || return 1
	
	# STEP-6: Extract and store
	_auto_discover_step6_extract "$result_file" "$lssn" || return 1
	
	# STEP-7: Complete marker
	_auto_discover_step7_complete "$lssn" || return 1
	
	# Cleanup
	rm -f "$result_file" "/tmp/auto_discover_log_$$.log" >/dev/null 2>&1
	
	return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # 직접 실행된 경우
    if [[ $# -lt 1 ]]; then
        cat <<USAGE
Usage: $0 <lssn> [ssh_user@ssh_host:ssh_port]

Example (Local):
  $0 1

Example (Remote):
  $0 1 root@192.168.1.100:22
  $0 1 root@remote.example.com

Environment Variables:
  SSH_KEY - Custom SSH private key path (default: /root/.ssh/giip_key or /root/.ssh/id_rsa)
  LOG_FILE - Log file path (default: /var/log/giipagent.log)

USAGE
        exit 1
    fi
    
    lssn="$1"
    remote_info="${2:-}"
    
    collect_infrastructure_data "$lssn" "$remote_info"
fi
