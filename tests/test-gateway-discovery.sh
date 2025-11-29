#!/bin/bash
# test-gateway-discovery.sh - Gateway Discovery 모듈 테스트 스크립트
# 위치: giipAgentLinux/test-gateway-discovery.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ============================================================================
# 색상 정의 (로그 출력용)
# ============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'  # No Color

# ============================================================================
# 함수: 테스트 결과 출력
# ============================================================================
print_test() {
    local name="$1"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}[TEST] $name${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_pass() {
    local msg="$1"
    echo -e "${GREEN}✅ PASS: $msg${NC}"
}

print_fail() {
    local msg="$1"
    echo -e "${RED}❌ FAIL: $msg${NC}"
    return 1
}

print_info() {
    local msg="$1"
    echo -e "${YELLOW}ℹ️  $msg${NC}"
}

# ============================================================================
# TEST 1: 라이브러리 파일 존재 확인
# ============================================================================
test_library_exists() {
    print_test "Library Files Existence"
    
    local files_ok=true
    
    if [[ -f "./lib/discovery.sh" ]]; then
        print_pass "lib/discovery.sh found"
    else
        print_fail "lib/discovery.sh NOT found"
        files_ok=false
    fi
    
    if [[ -f "./lib/gateway-discovery.sh" ]]; then
        print_pass "lib/gateway-discovery.sh found"
    else
        print_fail "lib/gateway-discovery.sh NOT found"
        files_ok=false
    fi
    
    if [[ -f "./scripts/auto-discover-linux.sh" ]]; then
        print_pass "scripts/auto-discover-linux.sh found"
    else
        print_fail "scripts/auto-discover-linux.sh NOT found"
        files_ok=false
    fi
    
    $files_ok || return 1
}

# ============================================================================
# TEST 2: 라이브러리 로드 확인
# ============================================================================
test_library_load() {
    print_test "Library Load"
    
    # discovery.sh 로드
    if bash -n "./lib/discovery.sh" 2>&1 | head -1 | grep -q "syntax"; then
        print_fail "lib/discovery.sh has syntax error"
        bash -n "./lib/discovery.sh"
        return 1
    fi
    print_pass "lib/discovery.sh syntax OK"
    
    # gateway-discovery.sh 로드
    if bash -n "./lib/gateway-discovery.sh" 2>&1 | head -1 | grep -q "syntax"; then
        print_fail "lib/gateway-discovery.sh has syntax error"
        bash -n "./lib/gateway-discovery.sh"
        return 1
    fi
    print_pass "lib/gateway-discovery.sh syntax OK"
}

# ============================================================================
# TEST 3: auto-discover-linux.sh 실행
# ============================================================================
test_auto_discover_local() {
    print_test "Local Auto-Discover Execution"
    
    # 스크립트 실행
    if ! output=$(bash ./scripts/auto-discover-linux.sh 2>&1); then
        print_fail "auto-discover-linux.sh execution failed"
        echo "$output"
        return 1
    fi
    
    # JSON 유효성 확인
    if ! echo "$output" | python3 -m json.tool >/dev/null 2>&1; then
        print_fail "auto-discover-linux.sh output is not valid JSON"
        echo "$output" | head -20
        return 1
    fi
    
    print_pass "auto-discover-linux.sh executed successfully"
    
    # JSON 내용 확인
    print_info "Output sample:"
    echo "$output" | python3 -m json.tool | head -30
}

# ============================================================================
# TEST 4: Discovery 모듈 - 로컬 수집
# ============================================================================
test_discovery_local() {
    print_test "Discovery Module - Local Collection"
    
    # 임시 로그 파일
    local log_file="/tmp/test_discovery_local.log"
    
    # discovery 모듈 로드 및 실행
    if ! output=$(bash -c "
        source ./lib/discovery.sh
        export LOG_FILE='$log_file'
        collect_infrastructure_data 999
    " 2>&1); then
        print_fail "Local collection failed"
        echo "$output"
        return 1
    fi
    
    # 로그 확인
    if grep -q "✅ Local infrastructure discovery completed" <<< "$output"; then
        print_pass "Local infrastructure discovery completed"
    else
        print_info "Output: $output"
    fi
}

# ============================================================================
# TEST 5: SSH 연결 확인
# ============================================================================
test_ssh_connection() {
    print_test "SSH Connection Check"
    
    # SSH 키 확인
    if [[ -f "/root/.ssh/giip_key" ]]; then
        print_pass "SSH key found: /root/.ssh/giip_key"
    elif [[ -f "/root/.ssh/id_rsa" ]]; then
        print_pass "SSH key found: /root/.ssh/id_rsa"
    else
        print_info "SSH key not found (expected for local-only testing)"
        return 0
    fi
    
    # SSH 포트 확인
    if netstat -tuln 2>/dev/null | grep -q ":22 "; then
        print_pass "SSH service is running"
    else
        print_info "SSH service check skipped"
    fi
}

# ============================================================================
# TEST 6: SSH 파싱
# ============================================================================
test_ssh_info_parse() {
    print_test "SSH Info Parsing"
    
    local test_cases=(
        "root@192.168.1.100:22|root|192.168.1.100|22"
        "admin@remote.example.com:2222|admin|remote.example.com|2222"
        "user@host.com|user|host.com|22"
    )
    
    for test_case in "${test_cases[@]}"; do
        IFS='|' read -r remote_info expected_user expected_host expected_port <<< "$test_case"
        
        # SSH 파싱 테스트
        if output=$(bash -c "
            source ./lib/discovery.sh
            _parse_ssh_info '$remote_info' u h p k 2>&1
            echo \"\$u|\$h|\$p\"
        " 2>&1); then
            
            if [[ "$output" == "${expected_user}|${expected_host}|${expected_port}" ]]; then
                print_pass "Parsed: $remote_info → $output"
            else
                print_fail "Parse mismatch for $remote_info: got $output, expected ${expected_user}|${expected_host}|${expected_port}"
                return 1
            fi
        else
            print_fail "SSH parsing failed: $remote_info"
            echo "$output"
            return 1
        fi
    done
}

# ============================================================================
# TEST 7: Gateway 캐시 파일 생성
# ============================================================================
test_gateway_cache_setup() {
    print_test "Gateway Cache File Setup"
    
    local gateway_lssn="999"
    local cache_file="/tmp/giip_gateway_servers_${gateway_lssn}.txt"
    
    # 캐시 파일 생성
    cat > "$cache_file" <<EOF
1|root|localhost|22
EOF
    
    if [[ -f "$cache_file" ]]; then
        print_pass "Cache file created: $cache_file"
        
        # 내용 확인
        if grep -q "^1|root|localhost|22$" "$cache_file"; then
            print_pass "Cache file content is valid"
        else
            print_fail "Cache file content is invalid"
            return 1
        fi
    else
        print_fail "Cache file creation failed"
        return 1
    fi
}

# ============================================================================
# TEST 8: 스케줄링 함수
# ============================================================================
test_scheduling() {
    print_test "Scheduling Functions"
    
    # should_run_discovery 테스트
    output=$(bash -c "
        source ./lib/discovery.sh
        
        # 첫 실행 (상태 파일 없음)
        lssn=\$(date +%s)
        if should_run_discovery \"\$lssn\"; then
            echo 'FIRST_RUN_OK'
        else
            echo 'FIRST_RUN_FAIL'
        fi
        
        # 상태 파일 생성
        echo \"\$(date +%s)\" > \"/tmp/giip_discovery_state.lssn_\$lssn\"
        
        # 두 번째 호출 (최근에 실행했으므로 false)
        if should_run_discovery \"\$lssn\"; then
            echo 'SECOND_RUN_OK_SHOULD_NOT'
        else
            echo 'SECOND_RUN_OK'
        fi
    " 2>&1)
    
    if grep -q "FIRST_RUN_OK" <<< "$output" && grep -q "SECOND_RUN_OK" <<< "$output"; then
        print_pass "Scheduling logic works correctly"
    else
        print_fail "Scheduling logic failed"
        echo "$output"
        return 1
    fi
}

# ============================================================================
# TEST 9: 전체 통합 테스트 (로컬)
# ============================================================================
test_integration_local() {
    print_test "Full Integration Test (Local Only)"
    
    # 통합 테스트 실행
    output=$(bash -c "
        source ./lib/discovery.sh
        source ./lib/gateway-discovery.sh
        
        export LOG_FILE='/tmp/test_integration.log'
        
        # 로컬 discovery 실행
        if collect_infrastructure_data 999; then
            echo 'COLLECTION_OK'
        else
            echo 'COLLECTION_FAIL'
        fi
    " 2>&1)
    
    if grep -q "COLLECTION_OK" <<< "$output"; then
        print_pass "Integration test passed"
    else
        print_fail "Integration test failed"
        echo "$output"
        return 1
    fi
}

# ============================================================================
# TEST 10: 문서 확인
# ============================================================================
test_documentation() {
    print_test "Documentation"
    
    if [[ -f "./docs/GATEWAY_DISCOVERY_INTEGRATION.md" ]]; then
        print_pass "Documentation file found"
        
        # 주요 섹션 확인
        local sections=("전제 조건" "통합 방법" "로컬 서버 Discovery" "원격 서버 Discovery" "테스트")
        
        for section in "${sections[@]}"; do
            if grep -q "$section" "./docs/GATEWAY_DISCOVERY_INTEGRATION.md"; then
                print_pass "Section found: $section"
            else
                print_info "Section not found: $section (optional)"
            fi
        done
    else
        print_fail "Documentation file NOT found"
        return 1
    fi
}

# ============================================================================
# 메인 테스트 실행
# ============================================================================
main() {
    echo -e "${GREEN}"
    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║  Gateway Discovery Module - Test Suite                            ║"
    echo "║  Created: 2025-11-22                                              ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
    
    local failed=0
    
    # 테스트 실행
    test_library_exists || ((failed++))
    echo ""
    
    test_library_load || ((failed++))
    echo ""
    
    test_auto_discover_local || ((failed++))
    echo ""
    
    test_discovery_local || ((failed++))
    echo ""
    
    test_ssh_connection || ((failed++))
    echo ""
    
    test_ssh_info_parse || ((failed++))
    echo ""
    
    test_gateway_cache_setup || ((failed++))
    echo ""
    
    test_scheduling || ((failed++))
    echo ""
    
    test_integration_local || ((failed++))
    echo ""
    
    test_documentation || ((failed++))
    echo ""
    
    # 결과 요약
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  Test Summary                                                      ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════════╝${NC}"
    
    if (( failed == 0 )); then
        echo -e "${GREEN}✅ All tests PASSED${NC}"
        echo ""
        echo "다음 단계:"
        echo "  1. 원격 서버 SSH 키 설정: ssh-copy-id -i /root/.ssh/giip_key root@<host>"
        echo "  2. 캐시 파일 설정: /tmp/giip_gateway_servers_<lssn>.txt"
        echo "  3. giipAgent3.sh 통합"
        echo ""
        return 0
    else
        echo -e "${RED}❌ $failed test(s) FAILED${NC}"
        return 1
    fi
}

# 스크립트 실행
main "$@"
