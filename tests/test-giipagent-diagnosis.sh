#!/bin/bash
#
# SYNOPSIS:
#   giipAgent2.sh 진단 스크립트
#
# USAGE:
#   bash test-giipagent-diagnosis.sh
#
# DESCRIPTION:
#   giipAgent2.sh 실행 시 발생하는 문제를 진단하고 상세 정보를 KVS에 저장
#   - API 응답 상세 분석
#   - Queue 처리 과정 추적
#   - 에러 발생 시 상세 컨텍스트 저장
#
# OUTPUT:
#   - KVS에 진단 데이터 저장 (kFactor=giipagent)
#   - 로그 파일: log/diagnosis_YYYYMMDD.log
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/log/diagnosis_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "${SCRIPT_DIR}/log"

# ANSI 색상 코드
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${2:-$NC}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"
}

log "========================================" "$BLUE"
log "giipAgent2.sh 진단 스크립트 시작" "$BLUE"
log "========================================" "$BLUE"

# Load config
CFG_PATH="${SCRIPT_DIR}/../giipAgent.cnf"
if [ ! -f "$CFG_PATH" ]; then
    log "❌ Config not found: $CFG_PATH" "$RED"
    exit 1
fi

log "✓ Config loaded: $CFG_PATH" "$GREEN"
source "$CFG_PATH"

# Verify required variables
if [ -z "$sk" ] || [ -z "$lssn" ] || [ -z "$apiaddrv2" ]; then
    log "❌ Missing config: sk, lssn, or apiaddrv2" "$RED"
    exit 1
fi

log "✓ LSSN: $lssn" "$GREEN"
log "✓ API: ${apiaddrv2%%\?*}" "$GREEN"

# Check kvsput.sh
KVSPUT="${SCRIPT_DIR}/giipscripts/kvsput.sh"
if [ ! -f "$KVSPUT" ]; then
    log "❌ kvsput.sh not found: $KVSPUT" "$RED"
    exit 1
fi
log "✓ kvsput.sh found" "$GREEN"

# Save diagnostic start event
TMP_JSON="/tmp/giip_diagnosis_$$.json"

cat > "$TMP_JSON" <<EOF
{
  "event_type": "diagnosis_start",
  "timestamp": "$(date '+%Y-%m-%d %H:%M:%S')",
  "lssn": ${lssn},
  "hostname": "$(hostname)",
  "mode": "diagnosis",
  "version": "2.00",
  "details": {
    "test_id": "diagnosis_$$",
    "purpose": "Detailed queue check and API response analysis",
    "script_version": "1.0"
  }
}
EOF

log "" "$NC"
log "📤 Sending diagnosis_start event..." "$YELLOW"
if bash "$KVSPUT" "$TMP_JSON" "giipagent" >> "$LOG_FILE" 2>&1; then
    log "✅ diagnosis_start saved to KVS" "$GREEN"
else
    log "⚠️  Failed to save diagnosis_start" "$YELLOW"
fi
rm -f "$TMP_JSON"

# ============================================================================
# Test 1: API Endpoint Check
# ============================================================================
log "" "$NC"
log "========================================" "$BLUE"
log "Test 1: API Endpoint Check" "$BLUE"
log "========================================" "$BLUE"

API_URL="${apiaddrv2}"
if [ -n "$apiaddrcode" ]; then
    API_URL="${API_URL}?code=${apiaddrcode}"
fi

log "API URL: ${API_URL%%\?*}?code=***" "$NC"

# Test API with simple command
TEST_CMD="CQEQueueGet ${lssn} $(hostname) $(uname -s) op"
log "Test Command: $TEST_CMD" "$NC"

cat > "$TMP_JSON" <<EOF
{
  "event_type": "api_test",
  "timestamp": "$(date '+%Y-%m-%d %H:%M:%S')",
  "lssn": ${lssn},
  "hostname": "$(hostname)",
  "mode": "diagnosis",
  "version": "2.00",
  "details": {
    "test_command": "$TEST_CMD",
    "api_endpoint": "${apiaddrv2}"
  }
}
EOF

# Call API
RESPONSE_FILE="/tmp/giip_api_response_$$.txt"
HTTP_CODE=$(curl -s -w "%{http_code}" -o "$RESPONSE_FILE" \
    --max-time 30 \
    --connect-timeout 10 \
    -X POST "$API_URL" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "text=$TEST_CMD" \
    --data-urlencode "token=$sk" 2>&1 | tail -1)

log "HTTP Status: $HTTP_CODE" "$NC"

if [ "$HTTP_CODE" = "200" ]; then
    log "✅ API connection successful" "$GREEN"
    
    # Parse response
    RESPONSE=$(cat "$RESPONSE_FILE")
    log "" "$NC"
    log "API Response:" "$NC"
    echo "$RESPONSE" | tee -a "$LOG_FILE"
    log "" "$NC"
    
    # Check if response is valid JSON
    if echo "$RESPONSE" | jq empty 2>/dev/null; then
        log "✅ Response is valid JSON" "$GREEN"
        
        # Extract RstVal
        RSTVAL=$(echo "$RESPONSE" | jq -r '.data[0].RstVal // "null"')
        RSTMSG=$(echo "$RESPONSE" | jq -r '.data[0].RstMsg // "null"')
        SCRIPT=$(echo "$RESPONSE" | jq -r '.data[0].Script // "null"')
        
        log "RstVal: $RSTVAL" "$NC"
        log "RstMsg: $RSTMSG" "$NC"
        log "Script length: ${#SCRIPT} chars" "$NC"
        
        # Save detailed API response to KVS
        cat > "$TMP_JSON" <<EOF
{
  "event_type": "api_response_analysis",
  "timestamp": "$(date '+%Y-%m-%d %H:%M:%S')",
  "lssn": ${lssn},
  "hostname": "$(hostname)",
  "mode": "diagnosis",
  "version": "2.00",
  "details": {
    "http_code": ${HTTP_CODE},
    "rstval": ${RSTVAL},
    "rstmsg": "${RSTMSG}",
    "has_script": $([ "$SCRIPT" != "null" ] && [ ${#SCRIPT} -gt 0 ] && echo "true" || echo "false"),
    "script_length": ${#SCRIPT},
    "response_valid_json": true
  }
}
EOF
        
        log "" "$NC"
        log "📤 Saving API response analysis..." "$YELLOW"
        bash "$KVSPUT" "$TMP_JSON" "giipagent" >> "$LOG_FILE" 2>&1
        
        # Analyze Script field
        if [ "$SCRIPT" != "null" ] && [ ${#SCRIPT} -gt 0 ]; then
            log "" "$NC"
            log "📜 Script content received:" "$YELLOW"
            echo "$SCRIPT" | head -20 | tee -a "$LOG_FILE"
            
            # Save script to file
            SCRIPT_FILE="/tmp/giip_queue_script_$$.sh"
            echo "$SCRIPT" > "$SCRIPT_FILE"
            log "" "$NC"
            log "✓ Script saved to: $SCRIPT_FILE" "$GREEN"
            
            # Analyze script
            SCRIPT_LINES=$(echo "$SCRIPT" | wc -l)
            HAS_EXPECT=$(echo "$SCRIPT" | grep -c 'expect=' || true)
            
            cat > "$TMP_JSON" <<EOF
{
  "event_type": "script_analysis",
  "timestamp": "$(date '+%Y-%m-%d %H:%M:%S')",
  "lssn": ${lssn},
  "hostname": "$(hostname)",
  "mode": "diagnosis",
  "version": "2.00",
  "details": {
    "script_lines": ${SCRIPT_LINES},
    "has_expect": $([ $HAS_EXPECT -ge 1 ] && echo "true" || echo "false"),
    "script_type": "$([ $HAS_EXPECT -ge 1 ] && echo "expect" || echo "bash")",
    "script_file": "$SCRIPT_FILE"
  }
}
EOF
            
            log "📤 Saving script analysis..." "$YELLOW"
            bash "$KVSPUT" "$TMP_JSON" "giipagent" >> "$LOG_FILE" 2>&1
            
        else
            log "ℹ️  No script in response (queue empty)" "$YELLOW"
        fi
        
    else
        log "❌ Response is NOT valid JSON" "$RED"
        log "Raw response:" "$NC"
        cat "$RESPONSE_FILE" | tee -a "$LOG_FILE"
        
        # Save error to KVS
        cat > "$TMP_JSON" <<EOF
{
  "event_type": "api_error",
  "timestamp": "$(date '+%Y-%m-%d %H:%M:%S')",
  "lssn": ${lssn},
  "hostname": "$(hostname)",
  "mode": "diagnosis",
  "version": "2.00",
  "details": {
    "error_type": "invalid_json_response",
    "http_code": ${HTTP_CODE},
    "response_preview": "$(cat "$RESPONSE_FILE" | head -c 200)",
    "context": "queue_check"
  }
}
EOF
        
        log "📤 Saving error to KVS..." "$YELLOW"
        bash "$KVSPUT" "$TMP_JSON" "giipagent" >> "$LOG_FILE" 2>&1
    fi
else
    log "❌ API connection failed: HTTP $HTTP_CODE" "$RED"
    log "Response:" "$NC"
    cat "$RESPONSE_FILE" | tee -a "$LOG_FILE"
    
    # Save error to KVS
    cat > "$TMP_JSON" <<EOF
{
  "event_type": "api_error",
  "timestamp": "$(date '+%Y-%m-%d %H:%M:%S')",
  "lssn": ${lssn},
  "hostname": "$(hostname)",
  "mode": "diagnosis",
  "version": "2.00",
  "details": {
    "error_type": "http_error",
    "http_code": ${HTTP_CODE},
    "response": "$(cat "$RESPONSE_FILE" | head -c 200)",
    "context": "api_connection"
  }
}
EOF
    
    log "📤 Saving error to KVS..." "$YELLOW"
    bash "$KVSPUT" "$TMP_JSON" "giipagent" >> "$LOG_FILE" 2>&1
fi

rm -f "$RESPONSE_FILE"

# ============================================================================
# Test 2: Environment Information
# ============================================================================
log "" "$NC"
log "========================================" "$BLUE"
log "Test 2: Environment Information" "$BLUE"
log "========================================" "$BLUE"

OS_INFO=$(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '"' || uname -s)
CURL_VERSION=$(curl --version | head -1 || echo "not installed")
JQ_VERSION=$(jq --version 2>/dev/null || echo "not installed")
BASH_VERSION=$(bash --version | head -1 || echo "unknown")

log "OS: $OS_INFO" "$NC"
log "Curl: $CURL_VERSION" "$NC"
log "Jq: $JQ_VERSION" "$NC"
log "Bash: $BASH_VERSION" "$NC"

cat > "$TMP_JSON" <<EOF
{
  "event_type": "environment_info",
  "timestamp": "$(date '+%Y-%m-%d %H:%M:%S')",
  "lssn": ${lssn},
  "hostname": "$(hostname)",
  "mode": "diagnosis",
  "version": "2.00",
  "details": {
    "os": "$OS_INFO",
    "curl": "$CURL_VERSION",
    "jq": "$JQ_VERSION",
    "bash": "$BASH_VERSION",
    "pwd": "$(pwd)",
    "user": "$(whoami)"
  }
}
EOF

log "" "$NC"
log "📤 Saving environment info..." "$YELLOW"
bash "$KVSPUT" "$TMP_JSON" "giipagent" >> "$LOG_FILE" 2>&1

# ============================================================================
# Test 3: giipAgent2.sh Execution Test
# ============================================================================
log "" "$NC"
log "========================================" "$BLUE"
log "Test 3: giipAgent2.sh Execution" "$BLUE"
log "========================================" "$BLUE"

AGENT_SCRIPT="${SCRIPT_DIR}/giipAgent2.sh"
if [ -f "$AGENT_SCRIPT" ]; then
    log "✓ giipAgent2.sh found" "$GREEN"
    log "" "$NC"
    log "🚀 Running giipAgent2.sh..." "$YELLOW"
    log "   (Output will be captured in agent log)" "$NC"
    
    AGENT_START=$(date +%s)
    bash "$AGENT_SCRIPT" 2>&1 | tee -a "$LOG_FILE"
    AGENT_EXIT=$?
    AGENT_END=$(date +%s)
    AGENT_DURATION=$((AGENT_END - AGENT_START))
    
    log "" "$NC"
    if [ $AGENT_EXIT -eq 0 ]; then
        log "✅ giipAgent2.sh completed successfully (${AGENT_DURATION}s)" "$GREEN"
    else
        log "⚠️  giipAgent2.sh exited with code $AGENT_EXIT (${AGENT_DURATION}s)" "$YELLOW"
    fi
    
    # Save execution result
    cat > "$TMP_JSON" <<EOF
{
  "event_type": "agent_execution_test",
  "timestamp": "$(date '+%Y-%m-%d %H:%M:%S')",
  "lssn": ${lssn},
  "hostname": "$(hostname)",
  "mode": "diagnosis",
  "version": "2.00",
  "details": {
    "exit_code": ${AGENT_EXIT},
    "duration_seconds": ${AGENT_DURATION},
    "success": $([ $AGENT_EXIT -eq 0 ] && echo "true" || echo "false")
  }
}
EOF
    
    log "📤 Saving execution result..." "$YELLOW"
    bash "$KVSPUT" "$TMP_JSON" "giipagent" >> "$LOG_FILE" 2>&1
else
    log "❌ giipAgent2.sh not found: $AGENT_SCRIPT" "$RED"
fi

# ============================================================================
# Diagnosis Complete
# ============================================================================
log "" "$NC"
log "========================================" "$BLUE"
log "진단 완료" "$BLUE"
log "========================================" "$BLUE"

cat > "$TMP_JSON" <<EOF
{
  "event_type": "diagnosis_complete",
  "timestamp": "$(date '+%Y-%m-%d %H:%M:%S')",
  "lssn": ${lssn},
  "hostname": "$(hostname)",
  "mode": "diagnosis",
  "version": "2.00",
  "details": {
    "log_file": "$LOG_FILE",
    "total_duration_seconds": $(($(date +%s) - $(stat -c %Y "$LOG_FILE" 2>/dev/null || echo 0)))
  }
}
EOF

log "📤 Saving diagnosis_complete..." "$YELLOW"
bash "$KVSPUT" "$TMP_JSON" "giipagent" >> "$LOG_FILE" 2>&1
rm -f "$TMP_JSON"

log "" "$NC"
log "✅ 진단 완료!" "$GREEN"
log "📝 로그 파일: $LOG_FILE" "$NC"
log "" "$NC"
log "다음 명령어로 KVS 데이터를 확인하세요:" "$YELLOW"
log "  pwsh ./giipdb/mgmt/query-kvs-giipagent.ps1 -Lssn \"$lssn\" -Top 20" "$NC"
log "" "$NC"
