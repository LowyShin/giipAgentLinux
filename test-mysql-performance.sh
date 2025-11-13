#!/bin/bash

# MySQL 성능 메트릭 수집 테스트 스크립트
# 용도: check_managed_databases.sh의 MySQL 성능 수집 부분만 단독 테스트

echo "======================================"
echo "MySQL Performance Metrics Test"
echo "======================================"
echo ""

# 테스트용 DB 정보 (p-cnsldb01m)
DB_HOST="10.254.250.94"
DB_PORT="43306"
DB_USER="giip"
DB_PASSWORD="qwer1234"
DB_DATABASE="cnsl"

echo "📋 Connection Info:"
echo "   Host: $DB_HOST:$DB_PORT"
echo "   User: $DB_USER"
echo "   Database: $DB_DATABASE"
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
