#!/bin/bash
#
# Refresh Gateway Server List
# Version: 1.0
# 
# Description:
#   Gateway 서버의 원격 서버 목록을 API에서 다시 가져와 갱신합니다
#   웹 UI에서 서버를 추가/제거할 때 자동으로 실행됩니다
#
# Variables (replaced by CQE):
#   {{SK}} - Security Key
#   {{LSSN}} - Gateway Server LSSN
#   {{APIADDRV2}} - API v2 Address
#

set -e

# 로그 함수
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" >&2
}

log_success() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $1"
}

# 설정
INSTALL_DIR="/opt/giipAgentLinux"
CONFIG_FILE="$INSTALL_DIR/giipAgent.cnf"
SERVERLIST_FILE="$INSTALL_DIR/giipAgentGateway_servers.csv"

log_info "===== Refreshing Gateway Server List ====="

# Config 파일 존재 확인
if [ ! -f "$CONFIG_FILE" ]; then
    log_error "Config file not found: $CONFIG_FILE"
    log_error "Please run setup_gateway_auto.sh first"
    exit 1
fi

# Config 파일에서 인증 정보 읽기
SK=$(grep 'sk=' "$CONFIG_FILE" | cut -d'"' -f2)
LSSN=$(grep 'lssn=' "$CONFIG_FILE" | cut -d'=' -f2)
APIADDRV2=$(grep 'apiaddrv2=' "$CONFIG_FILE" | cut -d'"' -f2)

# 변수 확인
if [ -z "$SK" ] || [ -z "$LSSN" ] || [ -z "$APIADDRV2" ]; then
    log_error "Missing configuration in $CONFIG_FILE"
    log_error "SK=$SK, LSSN=$LSSN, APIADDRV2=$APIADDRV2"
    exit 1
fi

log_info "Gateway LSSN: $LSSN"

# 서버 목록 백업
if [ -f "$SERVERLIST_FILE" ]; then
    BACKUP_FILE="${SERVERLIST_FILE}.bak.$(date '+%Y%m%d_%H%M%S')"
    cp "$SERVERLIST_FILE" "$BACKUP_FILE"
    log_info "Backup created: $BACKUP_FILE"
    
    # 이전 서버 수
    OLD_SERVER_COUNT=$(cat "$SERVERLIST_FILE" | grep -v "^#" | grep -v "^$" | wc -l)
    log_info "Previous server count: $OLD_SERVER_COUNT"
fi

# API에서 최신 서버 목록 가져오기
log_info "Fetching latest server list from API..."

SERVERLIST_RESPONSE=$(curl -s -X POST "$APIADDRV2" \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    --data-urlencode 'text=GatewayExportServerList gateway_lssn' \
    --data-urlencode "token=$SK" \
    --data-urlencode "jsondata={\"gateway_lssn\":$LSSN}" \
    --connect-timeout 10 \
    --max-time 30)

# 응답 확인
if echo "$SERVERLIST_RESPONSE" | jq -e '.data[0].RstVal == 200' > /dev/null 2>&1; then
    # CSV 라인 추출하여 임시 파일에 저장
    TMP_FILE="${SERVERLIST_FILE}.new"
    echo "$SERVERLIST_RESPONSE" | jq -r '.data[].csv_line' > "$TMP_FILE"
    
    # 파일 검증
    if [ -s "$TMP_FILE" ]; then
        # 새 서버 수
        NEW_SERVER_COUNT=$(cat "$TMP_FILE" | grep -v "^#" | grep -v "^$" | wc -l)
        
        # 서버 목록 교체
        mv "$TMP_FILE" "$SERVERLIST_FILE"
        log_success "Server list updated successfully"
        
        # 변경 사항 로그
        log_info "Server count changed: $OLD_SERVER_COUNT → $NEW_SERVER_COUNT"
        
        # 서버 목록 출력 (처음 10개)
        log_info "Current servers (first 10):"
        head -10 "$SERVERLIST_FILE" | while read line; do
            log_info "  $line"
        done
        
        # 변경 사항 상세 정보
        if [ "$NEW_SERVER_COUNT" -gt "$OLD_SERVER_COUNT" ]; then
            ADDED=$((NEW_SERVER_COUNT - OLD_SERVER_COUNT))
            log_info "✅ $ADDED server(s) added"
        elif [ "$NEW_SERVER_COUNT" -lt "$OLD_SERVER_COUNT" ]; then
            REMOVED=$((OLD_SERVER_COUNT - NEW_SERVER_COUNT))
            log_info "❌ $REMOVED server(s) removed"
        else
            log_info "ℹ️ No change in server count"
        fi
        
    else
        log_error "Server list is empty"
        
        # 백업 복원
        if [ -f "$BACKUP_FILE" ]; then
            cp "$BACKUP_FILE" "$SERVERLIST_FILE"
            log_info "Restored from backup: $BACKUP_FILE"
        fi
        
        exit 1
    fi
else
    log_error "Failed to fetch server list from API"
    
    # 에러 메시지 출력
    RSTVAL=$(echo "$SERVERLIST_RESPONSE" | jq -r '.data[0].RstVal' 2>/dev/null || echo "unknown")
    RSTMSG=$(echo "$SERVERLIST_RESPONSE" | jq -r '.data[0].RstMsg' 2>/dev/null || echo "No error message")
    
    log_error "API Error: RstVal=$RSTVAL, Msg=$RSTMSG"
    
    # 백업 복원
    if [ -f "$BACKUP_FILE" ]; then
        cp "$BACKUP_FILE" "$SERVERLIST_FILE"
        log_info "Restored from backup: $BACKUP_FILE"
    fi
    
    exit 1
fi

# 결과를 KVS로 전송
log_info "Uploading refresh result to KVS..."

RESULT_JSON=$(cat <<EOF
{
  "status": "success",
  "gateway_lssn": $LSSN,
  "old_server_count": $OLD_SERVER_COUNT,
  "new_server_count": $NEW_SERVER_COUNT,
  "refresh_time": "$(date '+%Y-%m-%d %H:%M:%S')",
  "serverlist_file": "$SERVERLIST_FILE"
}
EOF
)

TMP_RESULT="/tmp/gateway_refresh_result_${LSSN}.json"
echo "$RESULT_JSON" > "$TMP_RESULT"

if [ -f "$INSTALL_DIR/giipscripts/kvsput.sh" ]; then
    bash "$INSTALL_DIR/giipscripts/kvsput.sh" "$TMP_RESULT" "gateway_refresh"
    log_success "Refresh result uploaded to KVS"
else
    log_error "kvsput.sh not found, skipping KVS upload"
fi

rm -f "$TMP_RESULT"

# 백업 파일 정리 (7일 이상 된 백업 삭제)
log_info "Cleaning up old backups..."
find "$(dirname "$SERVERLIST_FILE")" -name "giipAgentGateway_servers.csv.bak.*" -mtime +7 -delete

log_success "===== Refresh Completed ====="
log_info "Total servers: $NEW_SERVER_COUNT"

exit 0
