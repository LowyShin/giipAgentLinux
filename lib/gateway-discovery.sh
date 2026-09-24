#!/bin/bash
# gateway-discovery.sh - Gateway 서버에서 원격 서버들의 Infrastructure Discovery 수행
# 위치: giipAgentLinux/lib/gateway-discovery.sh
# 용도: Gateway 에이전트가 주기적으로 실행하여 모든 원격 서버의 데이터 수집

set -euo pipefail

# Discovery 모듈 로드
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/discovery.sh"

# ============================================================================
# 함수 1: tLSvr에서 Gateway 산하의 모든 원격 서버 조회
# ============================================================================
get_remote_servers() {
    local gateway_lssn="$1"
    
    # TODO: DB에서 조회
    # SQL: SELECT LSsn, gateway_ssh_host, gateway_ssh_port, gateway_ssh_user
    #      FROM tLSvr
    #      WHERE gateway_lssn = @gateway_lssn AND is_gateway = 0 AND lsDeldt IS NULL
    
    # 임시: 환경변수 또는 파일에서 읽기
    # 형식: "LSSN|SSH_USER|SSH_HOST|SSH_PORT"
    
    # DB 연결 불가 시 캐시 파일 사용
    local cache_file="/tmp/giip_gateway_servers_${gateway_lssn}.txt"
    
    if [[ -f "$cache_file" ]]; then
        cat "$cache_file"
    else
        echo "[GatewayDiscovery] ⚠️  No cache file: $cache_file" >&2
        return 1
    fi
}

# ============================================================================
# 함수 2: 각 원격 서버별 Discovery 실행
# ============================================================================
run_gateway_discovery() {
    local gateway_lssn="$1"
    
    echo "[GatewayDiscovery] 🚀 Starting gateway discovery for gateway LSSN=$gateway_lssn" >&2
    
    # 원격 서버 목록 조회
    if ! servers=$(get_remote_servers "$gateway_lssn"); then
        echo "[GatewayDiscovery] ⚠️  Failed to get remote servers list" >&2
        return 1
    fi
    
    local total=0
    local success=0
    local failed=0
    
    # 각 서버별 처리
    echo "$servers" | while IFS='|' read -r lssn ssh_user ssh_host ssh_port; do
        
        # 빈 줄 무시
        [[ -z "$lssn" ]] && continue
        
        # 형식 검증
        if [[ ! "$lssn" =~ ^[0-9]+$ ]]; then
            echo "[GatewayDiscovery] ⚠️  Invalid LSSN: $lssn" >&2
            continue
        fi
        
        ((total++))
        
        # Discovery 실행
        local remote_info="${ssh_user}@${ssh_host}:${ssh_port}"
        
        echo "[GatewayDiscovery] 📡 Processing LSSN=$lssn ($remote_info)..." >&2
        
        if collect_infrastructure_data "$lssn" "$remote_info"; then
            echo "[GatewayDiscovery] ✅ Success: LSSN=$lssn" >&2
            ((success++))
        else
            echo "[GatewayDiscovery] ❌ Failed: LSSN=$lssn" >&2
            ((failed++))
        fi
        
    done
    
    echo "[GatewayDiscovery] 📊 Summary: Total=$total, Success=$success, Failed=$failed" >&2
    
    if (( failed > 0 )); then
        return 1
    fi
    
    return 0
}

# ============================================================================
# 메인 진입점
# ============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -lt 1 ]]; then
        echo "Usage: $0 <gateway_lssn>"
        echo ""
        echo "Example:"
        echo "  $0 1"
        exit 1
    fi
    
    gateway_lssn="$1"
    run_gateway_discovery "$gateway_lssn"
fi
