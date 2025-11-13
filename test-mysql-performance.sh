#!/bin/bash

# MySQL 성능 메트릭 수집 테스트 스크립트
# 용도: check_managed_databases.sh의 MySQL 성능 수집 부분만 단독 테스트

echo "======================================"
echo "MySQL Performance Metrics Test"
echo "======================================"
echo ""

# API에서 Managed DB 정보 가져오기
get_db_info_from_api() {
    local config_file="${1:-../giipAgent.cnf}"
    
    if [ ! -f "$config_file" ]; then
        echo "❌ Config file not found: $config_file"
        return 1
    fi
    
    # giipAgent.cnf에서 설정 읽기
    source "$config_file"
    
    echo "🔍 Fetching managed database info from API..."
    
    # API 호출
    local api_response=$(curl -s -X POST "$APIURI" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        --data-urlencode "text=pApiGatewayManagedDatabaseListForAgentbySK" \
        --data-urlencode "token=$SK" \
        --data-urlencode "jsondata={\"lssn\":$LSSN}")
    
    if [ -z "$api_response" ]; then
        echo "❌ API response is empty"
        return 1
    fi
    
    # JSON 파싱하여 첫 번째 DB 정보 추출
    echo "$api_response" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    if 'managed_databases' in data and len(data['managed_databases']) > 0:
        db = data['managed_databases'][0]
        print(f\"{db['db_host']}|{db['db_port']}|{db['db_user']}|{db['db_password']}|{db['db_database']}|{db['db_name']}|{db['db_type']}\")
    else:
        print('ERROR: No managed databases found')
        sys.exit(1)
except Exception as e:
    print(f'ERROR: {e}')
    sys.exit(1)
"
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
echo "   Database: $DB_DATABASE"
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
CONN_TEST=$(timeout 5 mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASSWORD" -D"$DB_DATABASE" -e "SELECT 1 AS test" 2>&1)
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

PERF_DATA=$(timeout 5 mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASSWORD" -D"$DB_DATABASE" -N -e "
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
    VALUE=$(timeout 5 mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASSWORD" -D"$DB_DATABASE" -N -e "
        SELECT VARIABLE_VALUE 
        FROM information_schema.GLOBAL_STATUS 
        WHERE VARIABLE_NAME='$metric'
    " 2>/dev/null)
    
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
