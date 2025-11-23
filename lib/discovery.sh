#!/bin/bash
# lib/discovery.sh - Infrastructure Discovery 모듈
# 로컬 및 원격(SSH) 서버의 Infrastructure 데이터 수집
# 사용: source lib/discovery.sh && collect_infrastructure_data <lssn> [ssh_user@ssh_host:ssh_port]

set -euo pipefail

# 설정
DISCOVERY_SCRIPT_LOCAL="$(dirname "$0")/../giipscripts/auto-discover-linux.sh"
DISCOVERY_INTERVAL=21600  # 6시간 (초 단위)
DISCOVERY_STATE_FILE="${DISCOVERY_STATE_FILE:-/tmp/giip_discovery_state}"
LOG_FILE="${LOG_FILE:-/var/log/giipagent.log}"

# ============================================================================
# 함수 1: 로컬 또는 원격 서버에서 Infrastructure Discovery 데이터 수집
# ============================================================================
collect_infrastructure_data() {
    local lssn="$1"
    local remote_info="${2:-}"  # 형식: ssh_user@ssh_host:ssh_port 또는 비어있음(로컬)
    
    if [[ -n "$remote_info" ]]; then
        echo "[Discovery] 🔍 Collecting infrastructure data from remote server (LSSN=$lssn, Host=$remote_info)" >&2
        _collect_remote_data "$lssn" "$remote_info"
    else
        echo "[Discovery] 🔍 Collecting infrastructure data locally (LSSN=$lssn)" >&2
        _collect_local_data "$lssn"
    fi
}

# ============================================================================
# 함수 2: 로컬 auto-discover 실행
# ============================================================================
_collect_local_data() {
    local lssn="$1"
    
    # Step 1: auto-discover-linux.sh 실행
    if [[ ! -f "$DISCOVERY_SCRIPT_LOCAL" ]]; then
        echo "[Discovery] ❌ Error: $DISCOVERY_SCRIPT_LOCAL not found" >&2
        return 1
    fi
    
    local discovery_json
    if ! discovery_json=$("$DISCOVERY_SCRIPT_LOCAL" 2>/dev/null); then
        echo "[Discovery] ❌ Error: Failed to collect local discovery data" >&2
        return 1
    fi
    
    # Step 2: JSON 검증
    if ! echo "$discovery_json" | python3 -m json.tool >/dev/null 2>&1; then
        echo "[Discovery] ❌ Error: Invalid JSON from local discovery script" >&2
        echo "[Discovery] Debug: $discovery_json" >&2
        return 1
    fi
    
    # Step 3: DB 저장
    _save_discovery_to_db "$lssn" "$discovery_json" || return 1
    
    echo "[Discovery] ✅ Local infrastructure discovery completed for LSSN=$lssn" >&2
    echo "$(date +%s)" > "$DISCOVERY_STATE_FILE.lssn_$lssn"
    
    return 0
}

# ============================================================================
# 함수 3: 원격 서버에서 SSH를 통해 auto-discover 실행
# ============================================================================
_collect_remote_data() {
    local lssn="$1"
    local remote_info="$2"  # 형식: ssh_user@ssh_host:ssh_port 또는 ssh_user@ssh_host
    
    # remote_info 파싱
    local ssh_user ssh_host ssh_port ssh_key
    _parse_ssh_info "$remote_info" ssh_user ssh_host ssh_port ssh_key
    
    # Step 1: 원격 서버에서 auto-discover-linux.sh 실행
    # (리모트 서버의 스크립트 위치를 확인하거나 온디맨드로 전송)
    local discovery_json
    
    echo "[Discovery] 📡 Connecting to $ssh_user@$ssh_host:$ssh_port (LSSN=$lssn)..." >&2
    
    # 방법 1: 원격 서버에 auto-discover-linux.sh가 이미 있는 경우
    if discovery_json=$(_ssh_exec "$ssh_user" "$ssh_host" "$ssh_port" "$ssh_key" \
        "bash /opt/giip/agent/linux/giipscripts/auto-discover-linux.sh 2>/dev/null" 2>/dev/null); then
        
        if echo "$discovery_json" | python3 -m json.tool >/dev/null 2>&1; then
            echo "[Discovery] ✅ Remote discovery data collected successfully" >&2
            _save_discovery_to_db "$lssn" "$discovery_json" || return 1
            echo "$(date +%s)" > "$DISCOVERY_STATE_FILE.lssn_$lssn.remote_$ssh_host"
            return 0
        fi
    fi
    
    # 방법 2: 로컬 스크립트를 원격으로 전송 후 실행
    echo "[Discovery] 📤 Transferring discovery script to $ssh_host..." >&2
    
    if ! _scp_file "$ssh_user" "$ssh_host" "$ssh_port" "$ssh_key" \
        "$DISCOVERY_SCRIPT_LOCAL" "/tmp/auto-discover-linux.sh"; then
        echo "[Discovery] ❌ Error: Failed to transfer discovery script to $ssh_host" >&2
        return 1
    fi
    
    # 원격에서 전송된 스크립트 실행
    if ! discovery_json=$(_ssh_exec "$ssh_user" "$ssh_host" "$ssh_port" "$ssh_key" \
        "bash /tmp/auto-discover-linux.sh 2>/dev/null" 2>/dev/null); then
        echo "[Discovery] ❌ Error: Failed to execute discovery script on $ssh_host" >&2
        return 1
    fi
    
    # Step 2: JSON 검증
    if ! echo "$discovery_json" | python3 -m json.tool >/dev/null 2>&1; then
        echo "[Discovery] ❌ Error: Invalid JSON from remote discovery script" >&2
        echo "[Discovery] Debug: $discovery_json" >&2
        return 1
    fi
    
    # Step 3: DB 저장
    if ! _save_discovery_to_db "$lssn" "$discovery_json"; then
        # 정리: 원격 임시 파일 삭제
        _ssh_exec "$ssh_user" "$ssh_host" "$ssh_port" "$ssh_key" \
            "rm -f /tmp/auto-discover-linux.sh" 2>/dev/null || true
        return 1
    fi
    
    # 정리: 원격 임시 파일 삭제
    _ssh_exec "$ssh_user" "$ssh_host" "$ssh_port" "$ssh_key" \
        "rm -f /tmp/auto-discover-linux.sh" 2>/dev/null || true
    
    echo "[Discovery] ✅ Remote infrastructure discovery completed for LSSN=$lssn (Host=$ssh_host)" >&2
    echo "$(date +%s)" > "$DISCOVERY_STATE_FILE.lssn_$lssn.remote_$ssh_host"
    
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
        echo "[Discovery] ❌ Error: Invalid remote info format. Use 'user@host' or 'user@host:port'" >&2
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
    
    # SSH 실행
    ssh $ssh_opts -p "$ssh_port" "${ssh_user}@${ssh_host}" "$command"
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
    
    # SCP 실행
    scp $scp_opts -P "$ssh_port" "$local_file" "${ssh_user}@${ssh_host}:${remote_file}"
}

# ============================================================================
# 함수 7: Discovery 데이터를 DB에 저장
# ============================================================================
_save_discovery_to_db() {
    local lssn="$1"
    local discovery_json="$2"
    
    echo "[Discovery] 💾 Saving to database for LSSN=$lssn..." >&2
    
    # Step 1: Server Info (tLSvr)
    _save_server_info "$lssn" "$discovery_json" || return 1
    
    # Step 2: Network Interfaces (tLSvrNIC)
    _save_network_interfaces "$lssn" "$discovery_json" || return 1
    
    # Step 3: Software (tLSvrSoftware)
    _save_software "$lssn" "$discovery_json" || return 1
    
    # Step 4: Services (tLSvrService)
    _save_services "$lssn" "$discovery_json" || return 1
    
    # Step 5: Generate Advice (pApiAgentGenerateAdvicebyAK)
    _generate_advice "$lssn" || return 0  # 비필수
    
    echo "[Discovery] ✅ Database save completed for LSSN=$lssn" >&2
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
    echo "[Discovery] 📊 Server info: hostname=$hostname, os=$os, cores=$cpu_cores, mem=${memory_gb}GB, disk=${disk_gb}GB" >&2
    
    # TODO: 실제 API 호출 또는 KVS 저장
    # _api_call "ServerInfoUpdate" "$api_json"
    
    return 0
}

# ============================================================================
# 함수 9: Network Interfaces 저장 (tLSvrNIC)
# ============================================================================
_save_network_interfaces() {
    local lssn="$1"
    local discovery_json="$2"
    
    local nic_count=0
    
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
        
        echo "[Discovery] 🌐 NIC: $ifname - IPv4=$ipv4, IPv6=$ipv6, MAC=$mac" >&2
        ((nic_count++))
        
        # TODO: 실제 API 호출 또는 KVS 저장
    done
    
    echo "[Discovery] ✅ Network interfaces saved ($nic_count NICs)" >&2
    return 0
}

# ============================================================================
# 함수 10: Software 저장 (tLSvrSoftware)
# ============================================================================
_save_software() {
    local lssn="$1"
    local discovery_json="$2"
    
    local sw_count=0
    
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
        
        echo "[Discovery] 📦 Software: $name v$version" >&2
        ((sw_count++))
        
        # TODO: 실제 API 호출 또는 KVS 저장
    done
    
    echo "[Discovery] ✅ Software list saved ($sw_count items)" >&2
    return 0
}

# ============================================================================
# 함수 11: Services 저장 (tLSvrService)
# ============================================================================
_save_services() {
    local lssn="$1"
    local discovery_json="$2"
    
    local svc_count=0
    
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
        
        echo "[Discovery] 🔧 Service: $name - $status (port=$port)" >&2
        ((svc_count++))
        
        # TODO: 실제 API 호출 또는 KVS 저장
    done
    
    echo "[Discovery] ✅ Services saved ($svc_count items)" >&2
    return 0
}

# ============================================================================
# 함수 12: Advice 생성 (pApiAgentGenerateAdvicebyAK)
# ============================================================================
_generate_advice() {
    local lssn="$1"
    
    echo "[Discovery] 🧠 Generating advice for LSSN=$lssn..." >&2
    
    # TODO: 실제 API 호출
    # _api_call "GenerateAdvicebyAK" "{\"lssn\":$lssn}"
    
    echo "[Discovery] ℹ️  Advice generation skipped (optional)" >&2
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
