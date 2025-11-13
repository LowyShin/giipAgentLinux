#!/bin/bash

# MySQL 성능 메트릭 수집 테스트 스크립트
# 용도: check_managed_databases.sh의 MySQL 성능 수집 부분만 단독 테스트
# 
# API 명세: docs/GATEWAY_API_SPECIFICATION.md
# 관련 함수: lib/check_managed_databases.sh
#
# 사용법:
#   1. API에서 자동 가져오기 (권장):
#      bash test-mysql-performance.sh
#
#   2. 수동 설정:
#      DB_HOST=호스트 DB_PORT=포트 DB_USER=유저 \
#      DB_PASSWORD=암호 DB_DATABASE=DB명 \
#      bash test-mysql-performance.sh

echo "======================================"
echo "MySQL Performance Metrics Test"
echo "======================================"
echo ""

# API에서 Managed DB 정보 가져오기 (check_managed_databases.sh에서 복사)
get_db_info_from_api() {
    local config_file="${1:-../giipAgent.cnf}"
    
    if [ ! -f "$config_file" ]; then
        echo "ERROR: Config file not found: $config_file" >&2
        return 1
    fi
    
    # giipAgent.cnf에서 설정 읽기
    source "$config_file"
    
    echo "🔍 Fetching managed database info from API..." >&2
    
    local temp_file=$(mktemp)
    local text="GatewayManagedDatabaseList lssn"
    local jsondata="{\"lssn\":${lssn}}"
    
    # API 호출 (check_managed_databases.sh와 동일)
    wget -O "$temp_file" --quiet \
        --post-data="text=${text}&token=${sk}&jsondata=${jsondata}" \
        --header="Content-Type: application/x-www-form-urlencoded" \
        "${apiaddrv2}?code=${apiaddrcode}" \
        --no-check-certificate 2>&1
    
    if [ ! -s "$temp_file" ]; then
        echo "ERROR: Failed to fetch from API" >&2
        rm -f "$temp_file"
        return 1
    fi
    
    # JSON 파싱하여 첫 번째 DB 정보 추출 (check_managed_databases.sh와 동일)
    python3 -c "
import json, sys
try:
    data = json.load(open('$temp_file'))
    if 'data' in data and isinstance(data['data'], list) and len(data['data']) > 0:
        db = data['data'][0]
        # db_* 필드명 사용 (API 응답 그대로)
        print(f\"{db.get('db_host','')}|{db.get('db_port','')}|{db.get('db_user','')}|{db.get('db_password','')}|{db.get('db_database','')}|{db.get('db_name','')}|{db.get('db_type','')}\")
    else:
        print('ERROR: No managed databases in response', file=sys.stderr)
        sys.exit(1)
except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
"
    local exit_code=$?
    rm -f "$temp_file"
    return $exit_code
}

# DB 정보 가져오기
if [ -z "$DB_HOST" ]; then
    echo "🌐 Fetching DB info from API (config: ${CONFIG_FILE:-../giipAgent.cnf})..."
    DB_INFO=$(get_db_info_from_api "${CONFIG_FILE:-../giipAgent.cnf}")
    
    if [[ "$DB_INFO" == ERROR:* ]]; then
        echo "❌ Failed to get DB info from API: $DB_INFO"
        echo ""
        echo "💡 You can also set DB credentials via environment variables:"
        echo "   DB_HOST=... DB_PORT=... DB_USER=... DB_PASSWORD=... DB_DATABASE=... bash $0"
        exit 1
    fi
    
    # 파싱
    IFS='|' read -r DB_HOST DB_PORT DB_USER DB_PASSWORD DB_DATABASE DB_NAME DB_TYPE <<< "$DB_INFO"
    
    echo "✅ Got DB info from API:"
    echo "   Name: $DB_NAME"
    echo "   Type: $DB_TYPE"
else
    echo "📝 Using environment variables for DB connection"
    DB_NAME="${DB_NAME:-manual-test}"
    DB_TYPE="${DB_TYPE:-MySQL}"
fi

echo ""
echo "📋 Connection Info:"
echo "   Host: $DB_HOST:$DB_PORT"
echo "   User: $DB_USER"
if [ -n "$DB_DATABASE" ]; then
    echo "   Database: $DB_DATABASE"
else
    echo "   Database: (none - will connect without -D option)"
fi
echo "   Password: ****** (hidden)"
echo ""

# MySQL 클라이언트 확인
if ! command -v mysql >/dev/null 2>&1; then
    echo "❌ MySQL client not installed!"
    exit 1
fi

echo "✅ MySQL client found: $(which mysql)"
echo ""

# 1. 기본 연결 테스트
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 1: Basic Connection Test"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

START_TIME=$(date +%s%3N)

# DB_DATABASE가 비어있으면 -D 옵션 제외
if [ -n "$DB_DATABASE" ]; then
    echo "[DEBUG] Running: mysql -h \"$DB_HOST\" -P \"$DB_PORT\" -u \"$DB_USER\" -p\"****\" -D \"$DB_DATABASE\" -e \"SELECT 1 AS test\""
    CONN_TEST=$(timeout 5 mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" -D "$DB_DATABASE" -e "SELECT 1 AS test" 2>&1)
else
    echo "[DEBUG] Running: mysql -h \"$DB_HOST\" -P \"$DB_PORT\" -u \"$DB_USER\" -p\"****\" -e \"SELECT 1 AS test\""
    CONN_TEST=$(timeout 5 mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" -e "SELECT 1 AS test" 2>&1)
fi

CONN_EXIT=$?
END_TIME=$(date +%s%3N)
RESPONSE_TIME=$((END_TIME - START_TIME))

if [ $CONN_EXIT -eq 0 ]; then
    echo "✅ Connection successful (${RESPONSE_TIME}ms)"
else
    echo "❌ Connection failed (exit code: $CONN_EXIT)"
    echo "Error: $CONN_TEST"
    exit 1
fi
echo ""

# 2. 성능 메트릭 수집 테스트
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 2: Performance Metrics Collection"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "[DEBUG] Running performance query..."

# DB_DATABASE가 비어있으면 -D 옵션 제외
if [ -n "$DB_DATABASE" ]; then
    PERF_DATA=$(timeout 5 mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" -D "$DB_DATABASE" -N -e "
	SELECT 
		CONCAT('{',
			'\"threads_connected\":', VARIABLE_VALUE, ',',
			'\"threads_running\":', (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME='Threads_running'), ',',
			'\"questions\":', (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME='Questions'), ',',
			'\"slow_queries\":', (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME='Slow_queries'), ',',
			'\"uptime\":', (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME='Uptime'),
		'}')
	FROM information_schema.GLOBAL_STATUS 
	WHERE VARIABLE_NAME='Threads_connected'
" 2>&1)
else
    PERF_DATA=$(timeout 5 mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" -N -e "
	SELECT 
		CONCAT('{',
			'\"threads_connected\":', VARIABLE_VALUE, ',',
			'\"threads_running\":', (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME='Threads_running'), ',',
			'\"questions\":', (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME='Questions'), ',',
			'\"slow_queries\":', (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME='Slow_queries'), ',',
			'\"uptime\":', (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME='Uptime'),
		'}')
	FROM information_schema.GLOBAL_STATUS 
	WHERE VARIABLE_NAME='Threads_connected'
" 2>&1)
fi

PERF_EXIT=$?

echo "[DEBUG] Query exit code: $PERF_EXIT"
echo "[DEBUG] Raw output:"
echo "$PERF_DATA"
echo ""

if [ $PERF_EXIT -eq 0 ]; then
    if [ -n "$PERF_DATA" ] && [[ "$PERF_DATA" == "{"* ]]; then
        echo "✅ Performance data collected successfully"
        echo ""
        echo "📊 Performance JSON:"
        echo "$PERF_DATA"
        echo ""
        
        # JSON 파싱 테스트
        if command -v python3 >/dev/null 2>&1; then
            echo "📈 Parsed Metrics:"
            echo "$PERF_DATA" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for key, value in data.items():
    print(f'   {key}: {value}')
"
        fi
    else
        echo "⚠️  Query succeeded but output format unexpected"
        echo "Expected: JSON starting with '{'"
        echo "Got: $PERF_DATA"
    fi
else
    echo "❌ Performance query failed (exit code: $PERF_EXIT)"
fi
echo ""

# 3. 개별 메트릭 쿼리 테스트
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 3: Individual Metrics Test"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

METRICS=("Threads_connected" "Threads_running" "Questions" "Slow_queries" "Uptime")

for metric in "${METRICS[@]}"; do
    if [ -n "$DB_DATABASE" ]; then
        VALUE=$(timeout 5 mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" -D "$DB_DATABASE" -N -e "
            SELECT VARIABLE_VALUE 
            FROM information_schema.GLOBAL_STATUS 
            WHERE VARIABLE_NAME='$metric'
        " 2>/dev/null)
    else
        VALUE=$(timeout 5 mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" -N -e "
            SELECT VARIABLE_VALUE 
            FROM information_schema.GLOBAL_STATUS 
            WHERE VARIABLE_NAME='$metric'
        " 2>/dev/null)
    fi
    
    if [ -n "$VALUE" ]; then
        echo "   ✅ $metric: $VALUE"
    else
        echo "   ❌ $metric: Failed to retrieve"
    fi
done

echo ""
echo "======================================"
echo "Test Complete"
echo "======================================"
