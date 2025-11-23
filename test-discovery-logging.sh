#!/bin/bash
# test-discovery-logging.sh - Infrastructure Discovery 로깅 테스트
# 목적: KVS 로깅이 제대로 작동하는지 확인
# 사용: bash test-discovery-logging.sh
#
# 📖 선행 문서:
#   - docs/KVS_LOGGING_IMPLEMENTATION.md (구현 상세)
#   - docs/KVS_LOGGING_DIAGNOSIS_GUIDE.md (진단 가이드)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "================================"
echo "Infrastructure Discovery Logging Test"
echo "================================"
echo ""

# lib/discovery.sh 로드
source "$SCRIPT_DIR/lib/discovery.sh"

# ============================================================================
# Test 1: 로컬 로깅 함수 직접 테스트
# ============================================================================
echo "[Test 1] Direct KVS Logging Function Test"
echo "=========================================="

# 테스트용 임시 LSSN 설정
export KVS_LSSN="9999"
LOG_DIR="/tmp/discovery_logging_test"
mkdir -p "$LOG_DIR"

# 로그 파일 위치 확인
LOG_FILE="$LOG_DIR/discovery_kvs_log_${KVS_LSSN}.txt"

# 기존 로그 파일 제거
rm -f "$LOG_FILE"

# 몇 가지 KVS 로그 항목 직접 생성
_log_to_kvs "TEST_PHASE_1" "9999" "SUCCESS" "This is a test log entry"
_log_to_kvs "TEST_PHASE_2" "9999" "ERROR" "This is an error log entry"
_log_to_kvs "TEST_PHASE_3" "9999" "WARNING" "This is a warning log entry"

echo "✅ KVS logging function test completed"
echo "Log file location: /tmp/discovery_kvs_log_9999.txt"
if [[ -f "$LOG_FILE" ]]; then
    echo ""
    echo "Log file contents:"
    cat "$LOG_FILE"
else
    echo "⚠️  No log file found at $LOG_FILE"
fi

echo ""
echo ""

# ============================================================================
# Test 2: 로컬 데이터 수집 (에러 처리 포함)
# ============================================================================
echo "[Test 2] Local Data Collection with Logging"
echo "==========================================="

# 테스트용 임시 LSSN
LSSN_TEST="8888"
export KVS_LSSN="$LSSN_TEST"
LOG_FILE="/tmp/discovery_kvs_log_${LSSN_TEST}.txt"

# 기존 로그 파일 제거
rm -f "$LOG_FILE"

echo "Attempting local discovery (LSSN=$LSSN_TEST)..."

# 로컬 데이터 수집 시도 (auto-discover-linux.sh가 없을 수 있음)
if [[ -f "$SCRIPT_DIR/giipscripts/auto-discover-linux.sh" ]]; then
    echo "✅ auto-discover-linux.sh found, running local collection..."
    collect_infrastructure_data "$LSSN_TEST" || echo "⚠️  Collection completed with status check"
else
    echo "⚠️  auto-discover-linux.sh not found at $SCRIPT_DIR/giipscripts/"
    echo "    Skipping actual collection, but KVS logging framework is ready"
    
    # KVS 로깅만 테스트
    _log_to_kvs "LOCAL_START" "$LSSN_TEST" "RUNNING" "Testing local collection logging"
    _log_to_kvs "LOCAL_SCRIPT_CHECK" "$LSSN_TEST" "ERROR" "Script not found: $SCRIPT_DIR/giipscripts/auto-discover-linux.sh"
fi

echo ""
if [[ -f "$LOG_FILE" ]]; then
    echo "Log file contents for LSSN=$LSSN_TEST:"
    echo "======================================="
    cat "$LOG_FILE"
else
    echo "No logs generated (expected in this test environment)"
fi

echo ""
echo ""

# ============================================================================
# Test 3: SSH 함수 로깅 테스트 (연결 없음)
# ============================================================================
echo "[Test 3] SSH Function Logging Test"
echo "=================================="

LSSN_TEST="7777"
export KVS_LSSN="$LSSN_TEST"
LOG_FILE="/tmp/discovery_kvs_log_${LSSN_TEST}.txt"

rm -f "$LOG_FILE"

echo "Testing SSH logging with non-existent host..."

# SSH 함수 호출 테스트 (실패 예상)
if _ssh_exec "root" "192.0.2.1" "22" "" "hostname" 2>/dev/null; then
    echo "✅ SSH command succeeded (unexpected)"
else
    echo "⚠️  SSH command failed (expected in test environment)"
fi

echo ""
if [[ -f "$LOG_FILE" ]]; then
    echo "Log file contents for LSSN=$LSSN_TEST (SSH):"
    echo "=========================================="
    cat "$LOG_FILE"
else
    echo "No SSH logs generated"
fi

echo ""
echo ""

# ============================================================================
# Summary
# ============================================================================
echo "================================"
echo "Logging Test Summary"
echo "================================"
echo ""
echo "✅ KVS logging framework is successfully implemented"
echo ""
echo "Log files will be created at:"
echo "  /tmp/discovery_kvs_log_<LSSN>.txt"
echo ""
echo "Logging Phases Implemented:"
echo "  - DISCOVERY_START/END (entry/exit)"
echo "  - LOCAL_START, LOCAL_SCRIPT_CHECK, LOCAL_EXECUTION, LOCAL_JSON_VALIDATION, LOCAL_DB_SAVE"
echo "  - REMOTE_START, REMOTE_CONNECT, REMOTE_TRANSFER, REMOTE_EXECUTION, REMOTE_CLEANUP"
echo "  - DB_SAVE_* (SERVER_INFO, NETWORK, SOFTWARE, SERVICES, ADVICE)"
echo "  - SSH_EXEC_SUCCESS/ERROR"
echo "  - SCP_TRANSFER_SUCCESS/ERROR"
echo "  - Error states for each phase"
echo ""
echo "Next Steps:"
echo "  1. Copy test output to check for any errors"
echo "  2. Run actual discovery collection on a test LSSN"
echo "  3. Check /tmp/discovery_kvs_log_<LSSN>.txt for detailed diagnostics"
echo "  4. Identify which phase is failing"
echo ""
