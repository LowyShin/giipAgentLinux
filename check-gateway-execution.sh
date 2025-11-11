# Gateway 실행 로그 확인 스크립트
# 서버에서 실행: bash check-gateway-execution.sh

echo "===== Gateway 실행 로그 확인 ====="
echo ""

# 최근 로그 파일 찾기
LOGDIR="/home/giip/giipAgent/logs"
if [ -d "$LOGDIR" ]; then
    echo "📂 로그 디렉토리: $LOGDIR"
    echo ""
    
    # 최근 로그 파일
    LATEST_LOG=$(ls -t $LOGDIR/giipAgent*.log 2>/dev/null | head -1)
    
    if [ -n "$LATEST_LOG" ]; then
        echo "📄 최근 로그 파일: $LATEST_LOG"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "최근 20줄:"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        tail -20 "$LATEST_LOG"
    else
        echo "⚠️ 로그 파일을 찾을 수 없습니다"
    fi
else
    echo "⚠️ 로그 디렉토리가 없습니다: $LOGDIR"
fi

echo ""
echo "===== Gateway 서버 목록 조회 테스트 ====="
echo ""

# 임시로 API 호출해서 서버 목록 확인
TEMP_FILE="/tmp/gateway_test_$$.json"

# giipAgent.cnf에서 설정 읽기
if [ -f "/home/giip/giipAgent/giipAgent.cnf" ]; then
    source /home/giip/giipAgent/giipAgent.cnf
    
    echo "🔍 API 호출 중..."
    echo "LSSN: $lssn"
    echo "API: $apiaddrv2"
    echo ""
    
    API_URL="${apiaddrv2}?code=${apiaddrcode}"
    TEXT="GatewayRemoteServerListForAgent lssn"
    JSONDATA="{\"lssn\":${lssn}}"
    
    wget -O "$TEMP_FILE" \
        --post-data="text=${TEXT}&token=${sk}&jsondata=${JSONDATA}" \
        --header="Content-Type: application/x-www-form-urlencoded" \
        "$API_URL" \
        --no-check-certificate -q 2>&1
    
    if [ -s "$TEMP_FILE" ]; then
        echo "✅ API 응답 받음"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "응답 내용:"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        cat "$TEMP_FILE" | python3 -m json.tool 2>/dev/null || cat "$TEMP_FILE"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        
        # 서버 개수 확인
        SERVER_COUNT=$(grep -o '{[^}]*}' "$TEMP_FILE" | wc -l)
        echo "📊 서버 개수: $SERVER_COUNT"
        
        # 각 서버 정보 파싱
        if [ $SERVER_COUNT -gt 0 ]; then
            echo ""
            echo "서버 목록:"
            grep -o '{[^}]*}' "$TEMP_FILE" | while read -r server_json; do
                hostname=$(echo "$server_json" | grep -o '"hostname"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
                lssn=$(echo "$server_json" | grep -o '"lssn"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:\s*\([0-9]*\).*/\1/')
                ssh_host=$(echo "$server_json" | grep -o '"ssh_host"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
                enabled=$(echo "$server_json" | grep -o '"enabled"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:\s*\([0-9]*\).*/\1/')
                
                if [ -n "$hostname" ]; then
                    echo "  - $hostname (LSSN: $lssn, SSH: $ssh_host, Enabled: $enabled)"
                fi
            done
        fi
        
        rm -f "$TEMP_FILE"
    else
        echo "❌ API 응답 없음"
        rm -f "$TEMP_FILE"
    fi
else
    echo "❌ 설정 파일을 찾을 수 없습니다: /home/giip/giipAgent/giipAgent.cnf"
fi

echo ""
echo "===== 완료 ====="
