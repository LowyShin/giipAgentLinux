#!/bin/bash
# Test script for check_managed_databases.sh
# Purpose: Manually test managed database health check functionality

# Initialize paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
CONFIG_FILE="$SCRIPT_DIR/../giipAgent.cnf"

# Load common.sh first (for load_config)
if [ ! -f "${LIB_DIR}/common.sh" ]; then
    echo "❌ Library not found: ${LIB_DIR}/common.sh"
    exit 1
fi

source "${LIB_DIR}/common.sh"

# Load configuration
load_config "../giipAgent.cnf"
if [ $? -ne 0 ]; then
    echo "❌ Failed to load configuration"
    exit 1
fi

# Load kvs.sh (for save_execution_log)
if [ ! -f "${LIB_DIR}/kvs.sh" ]; then
    echo "❌ Library not found: ${LIB_DIR}/kvs.sh"
    exit 1
fi

source "${LIB_DIR}/kvs.sh"

# Set LogFileName variable (required by check_managed_databases.sh)
export LogFileName="log/test-managed-db-check_$(date +%Y%m%d).log"
mkdir -p log

# Validate required variables
if [ -z "$lssn" ] || [ -z "$sk" ] || [ -z "$apiaddrv2" ] || [ -z "$apiaddrcode" ]; then
    echo "❌ Missing required config variables:"
    echo "   lssn: ${lssn:-NOT SET}"
    echo "   sk: ${sk:-NOT SET}"
    echo "   apiaddrv2: ${apiaddrv2:-NOT SET}"
    echo "   apiaddrcode: ${apiaddrcode:-NOT SET}"
    exit 1
fi

echo "========================================="
echo "🧪 Testing Managed Database Health Check"
echo "========================================="
echo "Config:"
echo "  LSSN: $lssn"
echo "  API: $apiaddrv2"
echo "  Script Dir: $SCRIPT_DIR"
echo "  Log File: $LogFileName"
echo "========================================="

# Load the check_managed_databases function
if [ ! -f "$SCRIPT_DIR/lib/check_managed_databases.sh" ]; then
    echo "❌ Module not found: $SCRIPT_DIR/lib/check_managed_databases.sh"
    exit 1
fi

source "$SCRIPT_DIR/lib/check_managed_databases.sh"

# ========================================
# STEP 1: Fetch managed database list from API
# ========================================
echo ""
echo "========================================="
echo "📋 STEP 1: Fetching Managed Database List"
echo "========================================="

db_list_file=$(mktemp)
local text="GatewayManagedDatabaseList lssn"
local jsondata="{\"lssn\":${lssn}}"

wget -O "$db_list_file" --quiet \
    --post-data="text=${text}&token=${sk}&jsondata=${jsondata}" \
    --header="Content-Type: application/x-www-form-urlencoded" \
    "${apiaddrv2}?code=${apiaddrcode}" \
    --no-check-certificate 2>&1

if [ ! -f "$db_list_file" ] || [ ! -s "$db_list_file" ]; then
    echo "❌ Failed to fetch database list from API"
    rm -f "$db_list_file"
    exit 1
fi

echo "✅ Database list fetched successfully"
echo ""

# Parse JSON - Extract "data" array using Python (same as check_managed_databases.sh)
db_list=$(python3 -c "
import json, sys
try:
    data = json.load(open('$db_list_file'))
    if 'data' in data and isinstance(data['data'], list):
        for item in data['data']:
            print(json.dumps(item))
except Exception as e:
    print(f'Error parsing JSON: {e}', file=sys.stderr)
    sys.exit(1)
")

if [ -z "$db_list" ]; then
    echo "⚠️  No databases found or failed to parse response"
    rm -f "$db_list_file"
    exit 1
fi

# Parse and display database info
echo "========================================="
echo "🗄️  Registered Databases"
echo "========================================="

db_count=$(echo "$db_list" | wc -l)
echo "Total databases: $db_count"
echo ""

# Display each database
echo "$db_list" | while read db_json; do
    if [ -z "$db_json" ]; then
        continue
    fi
    
    mdb_id=$(echo "$db_json" | python3 -c "import json, sys; print(json.load(sys.stdin).get('mdb_id', 'N/A'))")
    db_name=$(echo "$db_json" | python3 -c "import json, sys; print(json.load(sys.stdin).get('db_name', 'N/A'))")
    db_type=$(echo "$db_json" | python3 -c "import json, sys; print(json.load(sys.stdin).get('db_type', 'N/A'))")
    db_host=$(echo "$db_json" | python3 -c "import json, sys; print(json.load(sys.stdin).get('db_host', 'N/A'))")
    db_port=$(echo "$db_json" | python3 -c "import json, sys; print(json.load(sys.stdin).get('db_port', 'N/A'))")
    db_user=$(echo "$db_json" | python3 -c "import json, sys; print(json.load(sys.stdin).get('db_user', 'N/A'))")
    last_check=$(echo "$db_json" | python3 -c "import json, sys; print(json.load(sys.stdin).get('last_check_dt', 'never'))")
    status=$(echo "$db_json" | python3 -c "import json, sys; print(json.load(sys.stdin).get('status', 'unknown'))")
    
    echo "[$mdb_id] $db_name ($db_type)"
    echo "  Host: $db_host:$db_port"
    echo "  User: $db_user"
    echo "  Status: $status"
    echo "  Last Check: $last_check"
    echo ""
done

echo "========================================="
echo ""

# ========================================
# STEP 2: Test database connections
# ========================================
echo "========================================="
echo "🔌 STEP 2: Testing Database Connections"
echo "========================================="
echo ""

# Test each database connection
echo "$db_list" | while read db_json; do
    if [ -z "$db_json" ]; then
        continue
    fi
    
    mdb_id=$(echo "$db_json" | python3 -c "import json, sys; print(json.load(sys.stdin).get('mdb_id', ''))")
    db_name=$(echo "$db_json" | python3 -c "import json, sys; print(json.load(sys.stdin).get('db_name', ''))")
    db_type=$(echo "$db_json" | python3 -c "import json, sys; print(json.load(sys.stdin).get('db_type', ''))")
    db_host=$(echo "$db_json" | python3 -c "import json, sys; print(json.load(sys.stdin).get('db_host', ''))")
    db_port=$(echo "$db_json" | python3 -c "import json, sys; print(json.load(sys.stdin).get('db_port', ''))")
    db_user=$(echo "$db_json" | python3 -c "import json, sys; print(json.load(sys.stdin).get('db_user', ''))")
    db_password=$(echo "$db_json" | python3 -c "import json, sys; print(json.load(sys.stdin).get('db_password', ''))")
    
    echo "Testing [$mdb_id] $db_name ($db_type)..."
    echo "  Host: $db_host:$db_port"
    
    case "$db_type" in
        "mysql"|"MySQL")
            if command -v mysql &> /dev/null; then
                echo "  Testing MySQL connection..."
                mysql -h"$db_host" -P"$db_port" -u"$db_user" -p"$db_password" -e "SELECT VERSION() as version, NOW() as current_time, @@global.read_only as read_only;" 2>&1 | head -5
                
                if [ $? -eq 0 ]; then
                    echo "  ✅ MySQL connection successful"
                    
                    # Get performance metrics
                    echo "  📊 Performance Metrics:"
                    mysql -h"$db_host" -P"$db_port" -u"$db_user" -p"$db_password" -e "
                        SELECT 
                            CONCAT('    CPU Load: ', ROUND(100 * (SELECT COUNT(*) FROM information_schema.processlist WHERE state != 'Sleep') / (SELECT @@max_connections), 2), '%') as cpu_metric
                        UNION ALL
                        SELECT CONCAT('    Active Sessions: ', COUNT(*)) FROM information_schema.processlist WHERE state != 'Sleep'
                        UNION ALL
                        SELECT CONCAT('    Total Connections: ', COUNT(*)) FROM information_schema.processlist
                        UNION ALL
                        SELECT CONCAT('    DB Size: ', ROUND(SUM(data_length + index_length) / 1024 / 1024, 2), ' MB') FROM information_schema.tables WHERE table_schema = '$db_name';
                    " 2>&1 | grep -v "cpu_metric" | sed 's/|//g'
                else
                    echo "  ❌ MySQL connection failed"
                fi
            else
                echo "  ⚠️  mysql client not installed"
            fi
            ;;
            
        "postgresql"|"PostgreSQL")
            if command -v psql &> /dev/null; then
                echo "  Testing PostgreSQL connection..."
                PGPASSWORD="$db_password" psql -h "$db_host" -p "$db_port" -U "$db_user" -d "$db_name" -c "SELECT version(), now();" 2>&1 | head -5
                
                if [ $? -eq 0 ]; then
                    echo "  ✅ PostgreSQL connection successful"
                    
                    # Get performance metrics
                    echo "  📊 Performance Metrics:"
                    PGPASSWORD="$db_password" psql -h "$db_host" -p "$db_port" -U "$db_user" -d "$db_name" -t -c "
                        SELECT '    Active Sessions: ' || count(*) FROM pg_stat_activity WHERE state = 'active';
                        SELECT '    Total Connections: ' || count(*) FROM pg_stat_activity;
                        SELECT '    DB Size: ' || pg_size_pretty(pg_database_size('$db_name'));
                    " 2>&1 | grep -v "^$"
                else
                    echo "  ❌ PostgreSQL connection failed"
                fi
            else
                echo "  ⚠️  psql client not installed"
            fi
            ;;
            
        "mssql"|"MSSQL"|"sqlserver")
            if python3 -c "import pyodbc" 2>/dev/null; then
                echo "  Testing MSSQL connection..."
                python3 << EOF
import pyodbc
try:
    conn = pyodbc.connect(
        f"DRIVER={{ODBC Driver 17 for SQL Server}};SERVER=$db_host,$db_port;DATABASE=$db_name;UID=$db_user;PWD=$db_password",
        timeout=10
    )
    cursor = conn.cursor()
    cursor.execute("SELECT @@VERSION, GETDATE()")
    row = cursor.fetchone()
    print(f"  ✅ MSSQL connection successful")
    print(f"  Version: {row[0].split('\\n')[0][:80]}")
    print(f"  Current Time: {row[1]}")
    
    # Get performance metrics
    print("  📊 Performance Metrics:")
    cursor.execute("""
        SELECT '    CPU Usage: ' + CAST(AVG(cpu_percent) AS VARCHAR) + '%' FROM sys.dm_os_ring_buffers
        UNION ALL
        SELECT '    Active Sessions: ' + CAST(COUNT(*) AS VARCHAR) FROM sys.dm_exec_sessions WHERE status = 'running'
        UNION ALL
        SELECT '    Total Connections: ' + CAST(COUNT(*) AS VARCHAR) FROM sys.dm_exec_sessions
    """)
    for row in cursor:
        print(row[0])
    
    conn.close()
except Exception as e:
    print(f"  ❌ MSSQL connection failed: {e}")
EOF
            else
                echo "  ⚠️  pyodbc not installed"
            fi
            ;;
            
        *)
            echo "  ⚠️  Unsupported database type: $db_type"
            ;;
    esac
    
    echo ""
done

rm -f "$db_list_file"

echo "========================================="
echo ""

# ========================================
# STEP 3: Run check_managed_databases()
# ========================================
echo "========================================="
echo "🔄 STEP 3: Running Health Check & API Update"
echo "========================================="
echo ""

check_managed_databases

EXIT_CODE=$?

echo ""
echo "========================================="
echo "📊 Final Results Summary"
echo "========================================="

# Show log file contents
if [ -f "$LogFileName" ]; then
    echo ""
    echo "📄 Log File Contents:"
    echo "----------------------------------------"
    cat "$LogFileName"
    echo "----------------------------------------"
fi

echo ""
if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ Test completed successfully"
else
    echo "❌ Test failed with exit code: $EXIT_CODE"
fi
echo "========================================="

exit $EXIT_CODE
