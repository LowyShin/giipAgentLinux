#!/bin/bash
#
# giipCQE.sh - GIIP Command Queue Execution Agent v2.0
# 
# 개선 사항:
# - 실행 결과 자동 수집 및 tKVS 저장
# - 타임아웃 제어
# - 에러 처리 및 재시도
# - 보안 검증
# - 상세 로깅
#
# 사용법 (설치 위치에 관계없이 동작):
#   bash giipCQE.sh              # 정상 실행 (Cron에서 주로 사용)
#   bash giipCQE.sh --test       # 테스트 모드
#   bash giipCQE.sh --once       # 한 번만 실행
#
# 실행 예시:
#   # 스크립트 위치에서 실행
#   cd /path/to/giipAgentLinux/cqe
#   bash giipCQE.sh --test
#
#   # 또는 레포지토리 루트에서 실행
#   cd /path/to/giipAgentLinux
#   bash cqe/giipCQE.sh --test
#
# Cron 설정 (설치 위치별로 커스터마이징 필요):
#   # 예시 1: /home/shinh/giipAgentLinux 에 설치된 경우
#   */5 * * * * cd /home/shinh/giipAgentLinux && bash cqe/giipCQE.sh >> /tmp/giip_cqe_logs/cqe_cron.log 2>&1
#
#   # 예시 2: /opt/giip/agent 에 설치된 경우
#   */5 * * * * cd /opt/giip/agent && bash cqe/giipCQE.sh >> /tmp/giip_cqe_logs/cqe_cron.log 2>&1
#
# 설정 파일 위치: giipAgentLinux 부모 디렉토리의 giipAgent.cnf (레포지토리 루트 기준)
# 로그 위치: /tmp/giip_cqe_logs/cqe_YYYYMMDD.log (일시적, giipAgent3.sh에서 관리)

set -euo pipefail

# ========================================
# 설정
# ========================================
SCRIPT_VERSION="2.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 설정 파일: 레포지토리 루트의 부모 디렉토리에 위치 (다른 에이전트와 동일)
# ${SCRIPT_DIR}은 cqe 디렉토리이므로 ../로 한 단계 위에서 찾음
CNFFILE="${SCRIPT_DIR}/../giipAgent.cnf"

# 로그 디렉토리: /tmp/ (일시적 로그, giipAgent3.sh에서 관리)
LOGDIR="/tmp/giip_cqe_logs"
mkdir -p "$LOGDIR" 2>/dev/null || LOGDIR="/tmp"

LOGFILE="$LOGDIR/cqe_$(date +%Y%m%d).log"
TMPDIR="/tmp/giip_cqe_$$"
TMP_SCRIPT="$TMPDIR/exec_script.sh"
TMP_OUTPUT="$TMPDIR/output.txt"
TMP_ERROR="$TMPDIR/error.txt"
TMP_RESULT="$TMPDIR/result.json"

# 실행 모드
TEST_MODE=${1:-}
RUN_ONCE=false

if [ "$TEST_MODE" = "--test" ]; then
    echo "🧪 Test mode enabled"
    TEST_MODE=true
elif [ "$TEST_MODE" = "--once" ]; then
    echo "🔂 Run once mode"
    RUN_ONCE=true
    TEST_MODE=false
else
    TEST_MODE=false
fi

# 타임아웃 (초)
SCRIPT_TIMEOUT=300
MAX_RETRIES=3
RETRY_DELAY=5

# 로그 디렉토리 생성
mkdir -p "$LOGDIR"
mkdir -p "$TMPDIR"

# ========================================
# 로깅 함수
# ========================================
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ❌ ERROR: $*" | tee -a "$LOGFILE" >&2
}

log_success() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $*" | tee -a "$LOGFILE"
}

log_warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  WARNING: $*" | tee -a "$LOGFILE"
}

# ========================================
# 설정 파일 로드
# ========================================
load_config() {
    if [ ! -f "$CNFFILE" ]; then
        log_error "Config file not found: $CNFFILE"
        exit 1
    fi
    
    # 설정 읽기
    SK=$(grep -E "^sk=" "$CNFFILE" 2>/dev/null | cut -d'"' -f2)
    LSSN=$(grep -E "^lssn=" "$CNFFILE" 2>/dev/null | cut -d'"' -f2)
    
    # v2 API 우선 사용
    APIADDRV2=$(grep -E "^apiaddrv2=" "$CNFFILE" 2>/dev/null | cut -d'"' -f2)
    
    # v1 API (fallback)
    APIADDR=$(grep -E "^apiaddr=" "$CNFFILE" 2>/dev/null | cut -d'"' -f2)
    
    # Delay (초 단위)
    DELAY=$(grep -E "^giipagentdelay=" "$CNFFILE" 2>/dev/null | cut -d'"' -f2)
    
    # 기본값 설정
    if [ -n "$APIADDRV2" ]; then
        APIADDR="$APIADDRV2"
        API_VERSION="v2"
        log "✓ Using API v2: $APIADDR"
    else
        APIADDR=${APIADDR:-https://giipasp.azurewebsites.net}
        API_VERSION="v1"
        log "⚠️  Using API v1 (legacy): $APIADDR"
    fi
    
    DELAY=${DELAY:-60}
    
    if [ -z "$SK" ] || [ -z "$LSSN" ]; then
        log_error "Invalid config: sk or lssn not found"
        exit 1
    fi
    
    log "✓ Config loaded: lssn=$LSSN, api=$APIADDR (${API_VERSION}), delay=${DELAY}s"
}

# ========================================
# 시스템 정보 수집
# ========================================
get_system_info() {
    HOSTNAME=$(hostname)
    
    # OS 정보 (상세 버전 포함)
    OS_SIMPLE=""
    OS_VERSION=""
    OS_DETAIL=""
    
    if [ -f /etc/os-release ]; then
        # PRETTY_NAME: "Ubuntu 20.04.6 LTS"
        OS_SIMPLE=$(grep '^NAME=' /etc/os-release | cut -d'"' -f2)
        OS_VERSION=$(grep '^VERSION_ID=' /etc/os-release | cut -d'"' -f2)
        OS_PRETTY=$(grep '^PRETTY_NAME=' /etc/os-release | cut -d'"' -f2)
        
        # Ubuntu/Debian 추가 정보
        if [ -f /etc/lsb-release ]; then
            OS_CODENAME=$(grep CODENAME /etc/lsb-release | cut -d'=' -f2)
        fi
    elif [ -f /etc/redhat-release ]; then
        # CentOS/RHEL: "CentOS Linux release 7.9.2009 (Core)"
        OS_PRETTY=$(cat /etc/redhat-release)
        OS_SIMPLE=$(echo "$OS_PRETTY" | cut -d' ' -f1-2)
        OS_VERSION=$(echo "$OS_PRETTY" | grep -oP '\d+\.\d+')
    else
        OS_SIMPLE=$(uname -s)
        OS_VERSION=$(uname -r)
    fi
    
    # 커널 정보
    KERNEL_VERSION=$(uname -r)
    ARCH=$(uname -m)
    
    # 상세 OS 정보 구성
    if [ -n "$OS_PRETTY" ]; then
        OS_DETAIL="$OS_PRETTY"
    elif [ -n "$OS_SIMPLE" ] && [ -n "$OS_VERSION" ]; then
        OS_DETAIL="$OS_SIMPLE $OS_VERSION"
    else
        OS_DETAIL="$OS_SIMPLE"
    fi
    
    # URL 인코딩 (공백 처리)
    OS=$(echo "$OS_DETAIL" | sed 's/ /%20/g')
}

# ========================================
# 큐 가져오기
# ========================================
fetch_queue() {
    log "📥 Fetching queue from server ($API_VERSION)..."
    
    local url="$APIADDR"
    local response
    
    # JSON 데이터 구성 (pApiCQEQueueGetbySk SP 파라미터와 일치)
    # SP 파라미터: @sk, @lsSn, @hostname, @os, @op
    # os: URL 인코딩된 상세 버전 (예: Ubuntu%2020.04.6%20LTS)
    local json_data
    json_data=$(jq -n \
        --arg lssn "$LSSN" \
        --arg hostname "$HOSTNAME" \
        --arg os "$OS_DETAIL" \
        --arg op "op" \
        '{lssn:$lssn,hostname:$hostname,os:$os,op:$op}' \
        | tr -d '\n ')
    
    log "DEBUG: OS=$OS, KERNEL=$KERNEL_VERSION, ARCH=$ARCH"
    log "DEBUG: json_data=$json_data"
    
    if [ "$API_VERSION" = "v2" ]; then
        # v2 API: POST
        response=$(curl -sS -X POST "$url" \
            -H 'Content-Type: application/x-www-form-urlencoded' \
            --data-urlencode 'text=CQEQueueGet' \
            --data-urlencode "sk=$SK" \
            --data-urlencode "jsondata=$json_data" \
            2>&1)
    else
        # v1 API: Legacy format
        response=$(curl -sS -X POST "$url" \
            -H 'Content-Type: application/x-www-form-urlencoded' \
            --data-urlencode 'text=CQEQueueGet' \
            --data-urlencode "sk=$SK" \
            --data-urlencode "jsondata=$json_data" \
            2>&1)
    fi
    
    echo "$response"
}

# ========================================
# 스크립트 보안 검증
# ========================================
validate_script() {
    local script_file=$1
    
    # 위험한 패턴 체크
    local dangerous_patterns=(
        "rm -rf /"
        "rm -rf /*"
        "dd if=/dev/zero"
        ":(){ :|:& };:"
        "mkfs"
        "format"
        "> /dev/sda"
        "curl.*|.*sh"
        "wget.*|.*sh"
    )
    
    for pattern in "${dangerous_patterns[@]}"; do
        if grep -qF "$pattern" "$script_file" 2>/dev/null; then
            log_error "Dangerous pattern detected: $pattern"
            return 1
        fi
    done
    
    return 0
}

# ========================================
# 스크립트 실행
# ========================================
execute_script() {
    local script_body=$1
    local mslsn=$2
    local mssn=$3
    local script_name=${4:-"unknown"}
    
    log "🚀 Executing script: $script_name (mslsn=$mslsn, mssn=$mssn)"
    
    # 스크립트 파일 생성
    echo "$script_body" > "$TMP_SCRIPT"
    chmod +x "$TMP_SCRIPT"
    
    # 보안 검증
    if ! validate_script "$TMP_SCRIPT"; then
        log_error "Script validation failed - BLOCKED"
        save_result "$mslsn" "$mssn" "$script_name" "validation_failed" 99 "" "Security validation failed"
        return 1
    fi
    
    # dos2unix 변환 (있으면)
    if command -v dos2unix >/dev/null 2>&1; then
        dos2unix "$TMP_SCRIPT" 2>/dev/null || true
    fi
    
    # 실행 시작 시간
    local start_time
    start_time=$(date '+%Y-%m-%d %H:%M:%S')
    local start_epoch
    start_epoch=$(date +%s)
    
    # 타임아웃과 함께 실행
    local exit_code=0
    if timeout "$SCRIPT_TIMEOUT" bash "$TMP_SCRIPT" > "$TMP_OUTPUT" 2> "$TMP_ERROR"; then
        exit_code=0
        log_success "Script completed successfully"
    else
        exit_code=$?
        if [ $exit_code -eq 124 ]; then
            log_error "Script timed out after ${SCRIPT_TIMEOUT}s"
        else
            log_error "Script failed with exit code: $exit_code"
        fi
    fi
    
    # 실행 종료 시간
    local end_time
    end_time=$(date '+%Y-%m-%d %H:%M:%S')
    local end_epoch
    end_epoch=$(date +%s)
    local duration=$((end_epoch - start_epoch))
    
    # 출력 읽기
    local stdout=""
    local stderr=""
    
    if [ -f "$TMP_OUTPUT" ]; then
        stdout=$(cat "$TMP_OUTPUT" | head -c 10000)  # 최대 10KB
    fi
    
    if [ -f "$TMP_ERROR" ]; then
        stderr=$(cat "$TMP_ERROR" | head -c 5000)   # 최대 5KB
    fi
    
    # 상태 판단
    local status
    if [ $exit_code -eq 0 ]; then
        status="success"
    elif [ $exit_code -eq 124 ]; then
        status="timeout"
    else
        status="failed"
    fi
    
    log "📊 Result: status=$status, exit_code=$exit_code, duration=${duration}s"
    
    # 결과 저장
    save_result "$mslsn" "$mssn" "$script_name" "$status" "$exit_code" "$stdout" "$stderr" "$start_time" "$end_time" "$duration"
    
    return $exit_code
}

# ========================================
# 결과 저장 (tKVS)
# ========================================
save_result() {
    local mslsn=$1
    local mssn=$2
    local script_name=$3
    local status=$4
    local exit_code=$5
    local stdout=$6
    local stderr=${7:-}
    local start_time=${8:-}
    local end_time=${9:-}
    local duration=${10:-0}
    
    log "💾 Saving result to tKVS..."
    
    # JSON 생성 (jq 사용)
    if command -v jq >/dev/null 2>&1; then
        jq -n \
            --arg mslsn "$mslsn" \
            --arg mssn "$mssn" \
            --arg lssn "$LSSN" \
            --arg script_name "$script_name" \
            --arg status "$status" \
            --arg exit_code "$exit_code" \
            --arg stdout "$stdout" \
            --arg stderr "$stderr" \
            --arg start_time "$start_time" \
            --arg end_time "$end_time" \
            --arg duration "$duration" \
            --arg hostname "$HOSTNAME" \
            --arg os "$OS" \
            --arg agent_version "$SCRIPT_VERSION" \
            '{
                mslsn: $mslsn,
                mssn: $mssn,
                lssn: $lssn,
                script_name: $script_name,
                status: $status,
                exit_code: ($exit_code | tonumber),
                stdout: $stdout,
                stderr: $stderr,
                start_time: $start_time,
                end_time: $end_time,
                duration_seconds: ($duration | tonumber),
                hostname: $hostname,
                os: $os,
                agent_version: $agent_version,
                timestamp: (now | strftime("%Y-%m-%d %H:%M:%S"))
            }' > "$TMP_RESULT"
    else
        # jq 없으면 수동으로 JSON 생성
        cat > "$TMP_RESULT" <<EOF
{
  "mslsn": "$mslsn",
  "mssn": "$mssn",
  "lssn": "$LSSN",
  "script_name": "$script_name",
  "status": "$status",
  "exit_code": $exit_code,
  "stdout": $(echo "$stdout" | jq -Rs .),
  "stderr": $(echo "$stderr" | jq -Rs .),
  "start_time": "$start_time",
  "end_time": "$end_time",
  "duration_seconds": $duration,
  "hostname": "$HOSTNAME",
  "os": "$OS",
  "agent_version": "$SCRIPT_VERSION"
}
EOF
    fi
    
    # kvsput.sh로 업로드
    local kvsput_script="$MYPATH/../giipAgentAdmLinux/giip-sysscript/kvsput.sh"
    
    if [ -f "$kvsput_script" ]; then
        if sh "$kvsput_script" "$TMP_RESULT" "cqeresult" >> "$LOGFILE" 2>&1; then
            log_success "Result saved to tKVS (kfactor=cqeresult)"
        else
            log_error "Failed to save result to tKVS"
        fi
    else
        log_warn "kvsput.sh not found: $kvsput_script"
        log_warn "Result file saved locally: $TMP_RESULT"
        # 로컬에 백업
        cp "$TMP_RESULT" "$LOGDIR/cqe_result_$(date +%Y%m%d%H%M%S).json"
    fi
}

# ========================================
# 정리
# ========================================
cleanup() {
    rm -rf "$TMPDIR" 2>/dev/null || true
}

trap cleanup EXIT

# ========================================
# 메인 루프
# ========================================
main() {
    log "========================================="
    log "GIIP CQE Agent v$SCRIPT_VERSION Started"
    log "========================================="
    
    # 설정 로드
    load_config
    
    # 시스템 정보
    get_system_info
    log "System: $HOSTNAME ($OS)"
    
    # 중복 실행 체크
    local pid_file="/tmp/giipCQE_${LSSN}.pid"
    if [ -f "$pid_file" ]; then
        local old_pid
        old_pid=$(cat "$pid_file")
        if ps -p "$old_pid" > /dev/null 2>&1; then
            log_warn "CQE Agent already running (PID: $old_pid)"
            if [ "$RUN_ONCE" = false ] && [ "$TEST_MODE" = false ]; then
                exit 0
            fi
        fi
    fi
    echo $$ > "$pid_file"
    
    # 메인 루프
    local loop_count=0
    while true; do
        loop_count=$((loop_count + 1))
        log "--- Loop #$loop_count ---"
        
        # 큐 가져오기
        local response
        response=$(fetch_queue)
        
        # 디버그 (테스트 모드)
        if [ "$TEST_MODE" = true ]; then
            log "📋 Raw Response: $response"
        fi
        
        # JSON 파싱
        if echo "$response" | jq -e '.' >/dev/null 2>&1; then
            local rst_val
            rst_val=$(echo "$response" | jq -r '.RstVal // "404"')
            
            if [ "$rst_val" = "200" ]; then
                # 스크립트 실행
                local ms_body
                local mslsn
                local mssn
                local script_name
                
                ms_body=$(echo "$response" | jq -r '.ms_body // ""')
                mslsn=$(echo "$response" | jq -r '.mslsn // "0"')
                mssn=$(echo "$response" | jq -r '.mssn // "0"')
                script_name="script_${mssn}"
                
                if [ -n "$ms_body" ] && [ "$ms_body" != "null" ]; then
                    execute_script "$ms_body" "$mslsn" "$mssn" "$script_name"
                else
                    log_warn "Empty script body received"
                fi
            elif [ "$rst_val" = "404" ]; then
                log "ℹ️  No queue available"
            else
                log_warn "Unexpected response: RstVal=$rst_val"
            fi
        else
            log_error "Invalid JSON response"
            if [ "$TEST_MODE" = true ]; then
                log "Raw response: $response"
            fi
        fi
        
        # 한 번만 실행 모드
        if [ "$RUN_ONCE" = true ]; then
            log "Run once mode - exiting"
            break
        fi
        
        # 대기
        log "💤 Sleeping ${DELAY}s..."
        sleep "$DELAY"
    done
    
    log "========================================="
    log "GIIP CQE Agent Stopped"
    log "========================================="
}

# 실행
main
