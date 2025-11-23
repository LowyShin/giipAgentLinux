#!/bin/bash
# giipAgent3-gateway-integration.sh
# giipAgent3.sh에서 Gateway Discovery를 통합하는 방법
# 이 파일은 참고용 예제입니다. 실제 giipAgent3.sh에 통합되어야 합니다.

# ============================================================================
# Section 1: giipAgent3.sh 상단 - 라이브러리 로드
# ============================================================================

# 기존 코드:
# source ./lib/kvs.sh
# source ./lib/gateway.sh

# 추가할 코드:
# source ./lib/discovery.sh           # Infrastructure Discovery (로컬 및 원격)
# source ./lib/gateway-discovery.sh   # Gateway Discovery (모든 원격 서버)

# 완전한 라이브러리 로드 섹션:
cat <<'EXAMPLE_LIBS'
#!/bin/bash
# giipAgent3.sh - 라이브러리 로드 섹션

# 기본 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 라이브러리 로드
source ./lib/kvs.sh
source ./lib/gateway.sh
source ./lib/discovery.sh           # ✅ NEW: Infrastructure Discovery
source ./lib/gateway-discovery.sh   # ✅ NEW: Gateway Discovery
source ./lib/logging.sh

# 환경 변수 설정
export LOG_FILE="/var/log/giipagent.log"
export SSH_KEY="/root/.ssh/giip_key"
export DISCOVERY_INTERVAL=21600     # 6시간

EXAMPLE_LIBS

# ============================================================================
# Section 2: Normal 에이전트 모드 (로컬 서버)
# ============================================================================

cat <<'EXAMPLE_NORMAL_MODE'
# giipAgent3.sh - Normal 모드 메인 루프

run_normal_agent() {
    local lssn="${LSN:-1}"
    
    echo "[Agent3] Starting normal mode for LSSN=$lssn" >&2
    
    while true; do
        # 기존 작업
        process_queue "$lssn"
        
        # ========== NEW: Infrastructure Discovery ==========
        if should_run_discovery "$lssn"; then
            echo "[Agent3] 🔍 Running infrastructure discovery..." >&2
            
            if collect_infrastructure_data "$lssn"; then
                echo "[Agent3] ✅ Infrastructure discovery succeeded" >&2
            else
                echo "[Agent3] ⚠️  Infrastructure discovery failed (will retry later)" >&2
            fi
        fi
        # ====================================================
        
        # 주기적 작업
        check_heartbeat "$lssn"
        sleep 60
        
    done
}

EXAMPLE_NORMAL_MODE

# ============================================================================
# Section 3: Gateway 에이전트 모드 (원격 서버 관리)
# ============================================================================

cat <<'EXAMPLE_GATEWAY_MODE'
# giipAgent3.sh - Gateway 모드 메인 루프

run_gateway_agent() {
    local gateway_lssn="${LSN:-100}"
    
    echo "[Agent3] Starting gateway mode for LSSN=$gateway_lssn" >&2
    
    # 캐시 파일 경로
    local cache_file="/tmp/giip_gateway_servers_${gateway_lssn}.txt"
    
    # 첫 시작 시 캐시 파일 없으면 경고
    if [[ ! -f "$cache_file" ]]; then
        echo "[Agent3] ⚠️  Cache file not found: $cache_file" >&2
        echo "[Agent3] 📝 Create cache file with format: LSSN|SSH_USER|SSH_HOST|SSH_PORT" >&2
    fi
    
    while true; do
        # 기존 작업
        check_gateway_queue "$gateway_lssn"
        manage_remote_servers "$gateway_lssn"
        
        # ========== NEW: Gateway Discovery ==========
        if should_run_discovery "gateway_$gateway_lssn"; then
            echo "[Agent3] 🚀 Running gateway discovery..." >&2
            
            if run_gateway_discovery "$gateway_lssn"; then
                echo "[Agent3] ✅ Gateway discovery succeeded" >&2
            else
                echo "[Agent3] ⚠️  Gateway discovery completed with errors" >&2
            fi
        fi
        # ============================================
        
        sleep 120
        
    done
}

EXAMPLE_GATEWAY_MODE

# ============================================================================
# Section 4: 캐시 파일 설정 스크립트
# ============================================================================

cat <<'EXAMPLE_SETUP_CACHE'
#!/bin/bash
# setup-gateway-cache.sh - Gateway 캐시 파일 생성 도구

# 사용법:
#   bash setup-gateway-cache.sh <gateway_lssn> <config_file>
#
# 예제:
#   bash setup-gateway-cache.sh 100 /root/gateway_servers.txt
#

setup_gateway_cache() {
    local gateway_lssn="$1"
    local config_file="${2:-}"
    
    if [[ -z "$gateway_lssn" ]]; then
        echo "Usage: $0 <gateway_lssn> [config_file]"
        echo ""
        echo "Config file format:"
        echo "  # Comment"
        echo "  lssn|ssh_user|ssh_host|ssh_port"
        echo "  2|root|192.168.1.100|22"
        echo "  3|admin|remote.example.com|2222"
        exit 1
    fi
    
    local cache_file="/tmp/giip_gateway_servers_${gateway_lssn}.txt"
    
    # 옵션 1: 파일에서 읽기
    if [[ -n "$config_file" && -f "$config_file" ]]; then
        # 주석 제거
        grep -v "^#" "$config_file" | grep -v "^$" > "$cache_file"
        echo "[Setup] ✅ Cache file created from $config_file"
    fi
    
    # 옵션 2: 대화형 입력
    if [[ ! -f "$cache_file" ]] || [[ -z "$(cat "$cache_file")" ]]; then
        echo "[Setup] Creating cache file interactively..."
        echo ""
        
        while true; do
            echo "Enter remote server info (or 'done' to finish):"
            echo "Format: lssn|ssh_user|ssh_host|ssh_port"
            read -p "> " server_info
            
            if [[ "$server_info" == "done" ]]; then
                break
            fi
            
            if [[ "$server_info" =~ ^[0-9]+\|[^|]+\|[^|]+\|[0-9]+$ ]]; then
                echo "$server_info" >> "$cache_file"
                echo "[Setup] ✅ Added: $server_info"
            else
                echo "[Setup] ❌ Invalid format. Try again."
            fi
        done
    fi
    
    # 최종 확인
    if [[ -f "$cache_file" ]]; then
        echo ""
        echo "[Setup] ✅ Cache file created: $cache_file"
        echo "[Setup] Content:"
        cat "$cache_file" | sed 's/^/  /'
        chmod 600 "$cache_file"
    else
        echo "[Setup] ❌ Failed to create cache file"
        return 1
    fi
}

setup_gateway_cache "$@"

EXAMPLE_SETUP_CACHE

# ============================================================================
# Section 5: SSH 키 설정 스크립트
# ============================================================================

cat <<'EXAMPLE_SSH_SETUP'
#!/bin/bash
# setup-ssh-keys.sh - SSH 키 설정 도구

setup_ssh_keys() {
    local target_hosts="${1:-}"
    
    if [[ -z "$target_hosts" ]]; then
        echo "Usage: $0 '<host1> <host2> ...'"
        echo ""
        echo "Example:"
        echo "  $0 '192.168.1.100 192.168.1.101 remote.example.com'"
        exit 1
    fi
    
    local key_file="/root/.ssh/giip_key"
    
    # 1. SSH 키 생성
    if [[ ! -f "$key_file" ]]; then
        echo "[SSH Setup] 🔑 Generating SSH key..."
        ssh-keygen -t rsa -N "" -f "$key_file" -C "giip-gateway"
        chmod 600 "$key_file"
        echo "[SSH Setup] ✅ SSH key created"
    else
        echo "[SSH Setup] ✅ SSH key already exists"
    fi
    
    # 2. 각 호스트에 공개 키 전달
    for host in $target_hosts; do
        echo "[SSH Setup] 📤 Installing key on $host..."
        
        if ssh-copy-id -i "$key_file.pub" "root@$host" >/dev/null 2>&1; then
            echo "[SSH Setup] ✅ Key installed on $host"
        else
            echo "[SSH Setup] ⚠️  Failed to install key on $host"
        fi
    done
    
    # 3. 연결 테스트
    echo ""
    echo "[SSH Setup] Testing connections..."
    
    for host in $target_hosts; do
        if ssh -i "$key_file" -o StrictHostKeyChecking=no \
            "root@$host" "hostname" >/dev/null 2>&1; then
            echo "[SSH Setup] ✅ $host: Connection successful"
        else
            echo "[SSH Setup] ❌ $host: Connection failed"
        fi
    done
}

setup_ssh_keys "$@"

EXAMPLE_SSH_SETUP

# ============================================================================
# Section 6: 통합 테스트 스크립트
# ============================================================================

cat <<'EXAMPLE_INTEGRATION_TEST'
#!/bin/bash
# test-integration.sh - 전체 통합 테스트

test_integration() {
    echo "============================================"
    echo "Gateway Discovery Integration Test"
    echo "============================================"
    echo ""
    
    # 1. 라이브러리 로드 확인
    echo "[Test] Loading libraries..."
    if ! source ./lib/discovery.sh 2>/dev/null; then
        echo "❌ Failed to load lib/discovery.sh"
        return 1
    fi
    if ! source ./lib/gateway-discovery.sh 2>/dev/null; then
        echo "❌ Failed to load lib/gateway-discovery.sh"
        return 1
    fi
    echo "✅ Libraries loaded"
    echo ""
    
    # 2. 로컬 discovery 테스트
    echo "[Test] Testing local discovery..."
    if collect_infrastructure_data 999; then
        echo "✅ Local discovery successful"
    else
        echo "⚠️  Local discovery returned error (may be expected)"
    fi
    echo ""
    
    # 3. SSH 파싱 테스트
    echo "[Test] Testing SSH parsing..."
    if bash -c "
        source ./lib/discovery.sh
        _parse_ssh_info 'root@192.168.1.100:22' u h p k
        [[ \$u == 'root' && \$h == '192.168.1.100' && \$p == '22' ]]
    " 2>/dev/null; then
        echo "✅ SSH parsing works"
    else
        echo "❌ SSH parsing failed"
        return 1
    fi
    echo ""
    
    # 4. 캐시 파일 테스트
    echo "[Test] Creating test cache file..."
    local cache_file="/tmp/test_gateway_cache.txt"
    cat > "$cache_file" <<EOF
1|root|localhost|22
EOF
    
    if [[ -f "$cache_file" ]]; then
        echo "✅ Cache file created"
    else
        echo "❌ Cache file creation failed"
        return 1
    fi
    echo ""
    
    echo "============================================"
    echo "✅ All integration tests passed!"
    echo "============================================"
    echo ""
    echo "Next steps:"
    echo "  1. Run: bash test-gateway-discovery.sh"
    echo "  2. Setup SSH keys: bash setup-ssh-keys.sh '192.168.1.100 192.168.1.101'"
    echo "  3. Setup cache: bash setup-gateway-cache.sh 100 /root/servers.txt"
    echo "  4. Integrate into giipAgent3.sh"
}

test_integration "$@"

EXAMPLE_INTEGRATION_TEST

# ============================================================================
# Section 7: 실제 적용 체크리스트
# ============================================================================

cat <<'CHECKLIST'

✅ Gateway Discovery 모듈 적용 체크리스트

📋 Phase 1: 준비 (1-2시간)
  [ ] lib/discovery.sh 파일 확인
  [ ] lib/gateway-discovery.sh 파일 확인
  [ ] SSH 키 생성: ssh-keygen -t rsa -N "" -f /root/.ssh/giip_key
  [ ] 원격 서버들에 공개 키 등록: ssh-copy-id -i /root/.ssh/giip_key root@<host>
  [ ] 테스트 스크립트 실행: bash test-gateway-discovery.sh

📋 Phase 2: 라이브러리 로드 (30분)
  [ ] giipAgent3.sh 상단에 라이브러리 로드 추가:
      source ./lib/discovery.sh
      source ./lib/gateway-discovery.sh
  [ ] 환경 변수 설정 확인

📋 Phase 3: Normal 모드 통합 (1시간)
  [ ] Normal 모드 메인 루프에 discovery 호출 추가
  [ ] should_run_discovery 체크 로직 추가
  [ ] 로그 출력 확인

📋 Phase 4: Gateway 모드 통합 (1시간)
  [ ] Gateway 모드 메인 루프에 gateway-discovery 호출 추가
  [ ] 캐시 파일 생성: /tmp/giip_gateway_servers_<lssn>.txt
  [ ] 로그 출력 확인

📋 Phase 5: 테스트 (2시간)
  [ ] 로컬 서버 discovery 수집 확인
  [ ] 원격 서버 1개 로 discovery 수집 확인
  [ ] 모든 원격 서버 gateway discovery 수집 확인
  [ ] 6시간 스케줄링 동작 확인 (또는 강제 재실행)

📋 Phase 6: 프로덕션 (1시간)
  [ ] 에러 처리 및 재시도 로직 검토
  [ ] 로그 로테이션 설정
  [ ] 모니터링 알림 설정
  [ ] 성능 모니터링

CHECKLIST

echo ""
echo "✅ Gateway Discovery 모듈 구현 완료!"
echo ""
echo "생성된 파일:"
echo "  - lib/discovery.sh (Infrastructure Discovery 로컬/원격)"
echo "  - lib/gateway-discovery.sh (Gateway 다중 서버 처리)"
echo "  - test-gateway-discovery.sh (통합 테스트)"
echo "  - docs/GATEWAY_DISCOVERY_INTEGRATION.md (상세 가이드)"
echo ""
echo "다음 단계: bash test-gateway-discovery.sh"
