#!/bin/bash
#
# Gateway Server Auto Setup Script
# Version: 1.0
# 
# Description:
#   Gateway 서버를 자동으로 설정하는 스크립트
#   CQE를 통해 자동 배포되어 실행됩니다
#   
# What it does:
#   1. giipAgentLinux 레포지토리 클론 (또는 업데이트)
#   2. giipAgent.cnf 설정 파일 생성
#   3. giipAgentGateway_servers.csv 서버 목록 생성 (API에서 가져옴)
#   4. Cron 작업 등록 (5분마다 실행)
#   5. SSH 키 디렉토리 생성
#   6. 로그 디렉토리 생성
#   
# Variables (replaced by CQE):
#   {{SK}} - Security Key
#   {{LSSN}} - Server LSSN
#   {{APIADDR}} - API v1 Address
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

# 설치 디렉토리 설정
INSTALL_DIR="/opt/giipAgentLinux"
CONFIG_FILE="$INSTALL_DIR/giipAgent.cnf"
SERVERLIST_FILE="$INSTALL_DIR/giipAgentGateway_servers.csv"
SSH_KEY_DIR="$INSTALL_DIR/ssh_keys"
LOG_FILE="/var/log/giipAgentGateway.log"

log_info "===== Gateway Server Auto Setup Started ====="
log_info "Install Directory: $INSTALL_DIR"

# 1. 설치 디렉토리 생성
log_info "Creating install directory..."
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# 2. giipAgentLinux 레포지토리 클론 또는 업데이트
if [ ! -d "$INSTALL_DIR/.git" ]; then
    log_info "Cloning giipAgentLinux repository..."
    
    # Git 설치 확인
    if ! command -v git &> /dev/null; then
        log_error "Git is not installed. Installing git..."
        
        # OS 감지 및 Git 설치
        if [ -f /etc/debian_version ]; then
            apt-get update && apt-get install -y git
        elif [ -f /etc/redhat-release ]; then
            yum install -y git
        else
            log_error "Unsupported OS. Please install git manually."
            exit 1
        fi
    fi
    
    git clone https://github.com/LowyShin/giipAgentLinux.git "$INSTALL_DIR"
    log_success "Repository cloned successfully"
else
    log_info "Repository already exists. Pulling latest changes..."
    git pull origin real
    log_success "Repository updated"
fi

# 3. Config 파일 생성 (환경변수에서 읽음)
log_info "Creating Gateway configuration file..."
cat > "$CONFIG_FILE" <<'EOF'
# Gateway Agent Configuration (Auto-generated)
# Generated at: $(date '+%Y-%m-%d %H:%M:%S')

# Authentication
sk="{{SK}}"
lssn={{LSSN}}

# API Endpoints
apiaddr="{{APIADDR}}"
apiaddrv2="{{APIADDRV2}}"

# Gateway Settings
giipagentdelay="300"
serverlist_file="$(echo "$SERVERLIST_FILE")"

# Logging
log_file="$LOG_FILE"
log_level="INFO"
EOF

log_success "Config file created: $CONFIG_FILE"

# 4. 서버 목록 파일 초기화 (API에서 가져옴)
log_info "Fetching remote server list from API..."

# jq 설치 확인
if ! command -v jq &> /dev/null; then
    log_info "Installing jq..."
    if [ -f /etc/debian_version ]; then
        apt-get update && apt-get install -y jq
    elif [ -f /etc/redhat-release ]; then
        yum install -y jq
    fi
fi

# API에서 서버 목록 가져오기
SERVERLIST_RESPONSE=$(curl -s -X POST "{{APIADDRV2}}" \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    --data-urlencode 'text=GatewayExportServerList gateway_lssn' \
    --data-urlencode "token={{SK}}" \
    --data-urlencode "jsondata={\"gateway_lssn\":{{LSSN}}}")

# 응답 확인
if echo "$SERVERLIST_RESPONSE" | jq -e '.data[0].RstVal == 200' > /dev/null 2>&1; then
    # CSV 라인 추출
    echo "$SERVERLIST_RESPONSE" | jq -r '.data[].csv_line' > "$SERVERLIST_FILE"
    
    if [ -s "$SERVERLIST_FILE" ]; then
        log_success "Server list created: $SERVERLIST_FILE"
        SERVER_COUNT=$(cat "$SERVERLIST_FILE" | grep -v "^#" | wc -l)
        log_info "Total servers: $SERVER_COUNT"
        
        # 서버 목록 출력 (처음 5개만)
        log_info "Server list (first 5):"
        head -5 "$SERVERLIST_FILE"
    else
        log_error "Server list is empty"
    fi
else
    log_error "Failed to fetch server list from API"
    
    # 빈 서버 목록 파일 생성
    cat > "$SERVERLIST_FILE" <<'EOF'
# hostname,lssn,ssh_host,ssh_user,ssh_port,ssh_key_path,os_info,enabled
# No remote servers configured yet
# Add servers via web UI at /admin/gateway
EOF
    log_info "Created empty server list file"
fi

# 5. giipAgentGateway.sh 실행 권한 부여
log_info "Setting execute permissions..."
chmod +x "$INSTALL_DIR/giipAgentGateway.sh"
chmod +x "$INSTALL_DIR/giipscripts/"*.sh

# 6. Cron 등록 (5분마다 실행)
log_info "Registering cron job..."
CRON_LINE="*/5 * * * * cd $INSTALL_DIR && bash giipAgentGateway.sh >> $LOG_FILE 2>&1"

# 기존 cron 작업 제거 후 추가
(crontab -l 2>/dev/null | grep -v "giipAgentGateway.sh"; echo "$CRON_LINE") | crontab -

log_success "Cron job registered (runs every 5 minutes)"

# 7. 로그 디렉토리 및 파일 생성
log_info "Creating log directory..."
mkdir -p /var/log/giip
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"

log_success "Log file created: $LOG_FILE"

# 8. SSH 키 디렉토리 생성
log_info "Creating SSH key directory..."
mkdir -p "$SSH_KEY_DIR"
chmod 700 "$SSH_KEY_DIR"

log_success "SSH key directory created: $SSH_KEY_DIR"

# 9. 설치 정보 출력
log_success "===== Gateway Server Auto Setup Completed ====="
echo ""
echo "📋 Setup Summary:"
echo "  - Gateway LSSN: {{LSSN}}"
echo "  - Config File: $CONFIG_FILE"
echo "  - Server List: $SERVERLIST_FILE"
echo "  - Log File: $LOG_FILE"
echo "  - SSH Keys: $SSH_KEY_DIR"
echo "  - Remote Servers: $SERVER_COUNT"
echo ""
echo "🔧 Next Steps:"
echo "  1. Add remote servers via web UI (/admin/gateway)"
echo "  2. Configure SSH keys in $SSH_KEY_DIR"
echo "  3. Monitor logs: tail -f $LOG_FILE"
echo ""

# 10. 결과를 KVS로 전송
log_info "Uploading setup result to KVS..."

RESULT_JSON=$(cat <<EOF
{
  "status": "success",
  "gateway_lssn": {{LSSN}},
  "config_file": "$CONFIG_FILE",
  "serverlist_file": "$SERVERLIST_FILE",
  "remote_servers": $SERVER_COUNT,
  "setup_time": "$(date '+%Y-%m-%d %H:%M:%S')",
  "install_dir": "$INSTALL_DIR",
  "log_file": "$LOG_FILE"
}
EOF
)

# KVS에 결과 업로드
TMP_RESULT="/tmp/gateway_setup_result_{{LSSN}}.json"
echo "$RESULT_JSON" > "$TMP_RESULT"

if [ -f "$INSTALL_DIR/giipscripts/kvsput.sh" ]; then
    bash "$INSTALL_DIR/giipscripts/kvsput.sh" "$TMP_RESULT" "gateway_setup"
    log_success "Setup result uploaded to KVS"
else
    log_error "kvsput.sh not found, skipping KVS upload"
fi

rm -f "$TMP_RESULT"

# 11. 즉시 한 번 실행 (테스트)
log_info "Running Gateway agent once for testing..."
cd "$INSTALL_DIR"
bash giipAgentGateway.sh

log_success "Gateway agent test run completed"
log_info "Gateway setup completed successfully!"

exit 0
