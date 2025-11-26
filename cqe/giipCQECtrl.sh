#!/bin/bash
#
# giipCQECtrl.sh - CQE 제어 유틸리티
#
# 사용법:
#   ./giipCQECtrl.sh list              # 스케줄 목록 조회
#   ./giipCQECtrl.sh status <lssn>     # 서버 상태 조회
#   ./giipCQECtrl.sh execute <mslsn>   # 즉시 실행
#   ./giipCQECtrl.sh result <lssn>     # 실행 결과 조회
#   ./giipCQECtrl.sh logs <lssn>       # 로그 조회

set -euo pipefail

MYPATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CNFFILE="$MYPATH/giipAgent.cnf"

# 설정 로드
if [ -f "$CNFFILE" ]; then
    SK=$(grep -E "^sk=" "$CNFFILE" 2>/dev/null | cut -d'"' -f2)
    
    # v2 API 우선 사용
    APIADDRV2=$(grep -E "^apiaddrv2=" "$CNFFILE" 2>/dev/null | cut -d'"' -f2)
    APIADDRCODE=$(grep -E "^apiaddrcode=" "$CNFFILE" 2>/dev/null | cut -d'"' -f2)
    
    # v1 API (fallback)
    APIADDR_V1=$(grep -E "^apiaddr=" "$CNFFILE" 2>/dev/null | cut -d'"' -f2)
    
    if [ -n "$APIADDRV2" ]; then
        APIADDR="$APIADDRV2"
        APICODE="$APIADDRCODE"
        API_VERSION="v2"
    else
        APIADDR=${APIADDR_V1:-https://giipasp.azurewebsites.net}
        APICODE=""
        API_VERSION="v1"
    fi
else
    echo "❌ Config file not found: $CNFFILE"
    exit 1
fi

# ========================================
# 함수들
# ========================================

# API 호출 헬퍼 함수
call_api() {
    local text=$1
    local jsondata=${2:-{}}
    
    if [ "$API_VERSION" = "v2" ]; then
        curl -sS -X POST "$APIADDR?code=$APICODE" \
            -H 'Content-Type: application/x-www-form-urlencoded' \
            --data-urlencode "text=$text" \
            --data-urlencode "sk=$SK" \
            --data-urlencode "jsondata=$jsondata"
    else
        curl -sS -X POST "$APIADDR" \
            -H 'Content-Type: application/x-www-form-urlencoded' \
            --data-urlencode "text=$text" \
            --data-urlencode "sk=$SK" \
            --data-urlencode "jsondata=$jsondata"
    fi
}

# 스케줄 목록 조회
list_schedules() {
    echo "📋 CQE Schedule List ($API_VERSION)"
    echo "===================="
    
    call_api "CQEScheduleList" "{}" | jq -C '.'
}

# 서버 상태 조회
check_status() {
    local lssn=$1
    echo "🔍 CQE Status for server lssn=$lssn ($API_VERSION)"
    echo "===================================="
    
    call_api "CQEServerStatus" "{\"lssn\":$lssn}" | jq -C '.'
}

# 즉시 실행
execute_now() {
    local mslsn=$1
    echo "🚀 Executing script immediately (mslsn=$mslsn) ($API_VERSION)"
    echo "=============================================="
    
    call_api "CQERunActivate" "{\"mslsn\":$mslsn}" | jq -C '.'
}

# 실행 결과 조회
show_results() {
    local lssn=$1
    echo "📊 CQE Execution Results for lssn=$lssn ($API_VERSION)"
    echo "========================================"
    
    call_api "KVSList" "{\"ktype\":\"lssn\",\"kkey\":\"$lssn\",\"kfactor\":\"cqeresult\",\"limit\":10}" | jq -C '.'
}

# 로그 조회
show_logs() {
    local lssn=$1
    local logfile="/var/log/giip/cqe_$(date +%Y%m%d).log"
    
    echo "📄 CQE Logs for lssn=$lssn"
    echo "=========================="
    
    if [ -f "$logfile" ]; then
        grep "lssn=$lssn" "$logfile" | tail -20
    else
        echo "⚠️  Log file not found: $logfile"
    fi
}

# 도움말
show_help() {
    cat <<EOF
🔧 GIIP CQE Control Utility

Usage:
  $0 <command> [arguments]

Commands:
  list                    스케줄 목록 조회
  status <lssn>          서버 상태 조회
  execute <mslsn>        즉시 실행
  result <lssn>          실행 결과 조회 (최근 10개)
  logs <lssn>            로그 조회
  help                   도움말

Examples:
  $0 list
  $0 status 71028
  $0 execute 12345
  $0 result 71028
  $0 logs 71028

Configuration:
  Config file: $CNFFILE
  API Version: $API_VERSION
  API Endpoint: $APIADDR
  Secret Key: ${SK:0:10}...

EOF
}

# ========================================
# 메인
# ========================================

COMMAND=${1:-help}

case "$COMMAND" in
    list)
        list_schedules
        ;;
    status)
        if [ $# -lt 2 ]; then
            echo "❌ Usage: $0 status <lssn>"
            exit 1
        fi
        check_status "$2"
        ;;
    execute)
        if [ $# -lt 2 ]; then
            echo "❌ Usage: $0 execute <mslsn>"
            exit 1
        fi
        execute_now "$2"
        ;;
    result)
        if [ $# -lt 2 ]; then
            echo "❌ Usage: $0 result <lssn>"
            exit 1
        fi
        show_results "$2"
        ;;
    logs)
        if [ $# -lt 2 ]; then
            echo "❌ Usage: $0 logs <lssn>"
            exit 1
        fi
        show_logs "$2"
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo "❌ Unknown command: $COMMAND"
        echo ""
        show_help
        exit 1
        ;;
esac
