#!/bin/bash
# giipAgent Ver. 3.0 (Refactored)
sv="3.00"
# Written by Lowy Shin at 20140922
# Updated to modular architecture at 2025-01-10
# Supported OS : MacOS, CentOS, Ubuntu, Some Linux
# 20251104 Lowy, Add Gateway mode support with auto-dependency installation
# 20250110 Lowy, Refactor to modular architecture (lib/*.sh)

# Usable giip variables =========
# {{today}} : Replace today to "YYYYMMDD"

# ============================================================================
# Initialize Script Paths
# ============================================================================

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="${SCRIPT_DIR}/lib"

# ============================================================================
# Load Library Modules
# ============================================================================

# Load common functions (config, logging, error handling)
if [ -f "${LIB_DIR}/common.sh" ]; then
	. "${LIB_DIR}/common.sh"
else
	echo "❌ Error: common.sh not found in ${LIB_DIR}"
	exit 1
fi

# Load KVS logging functions
if [ -f "${LIB_DIR}/kvs.sh" ]; then
	. "${LIB_DIR}/kvs.sh"
else
	echo "❌ Error: kvs.sh not found in ${LIB_DIR}"
	exit 1
fi

# ============================================================================
# Load Configuration
# ============================================================================

load_config "../giipAgent.cnf"
if [ $? -ne 0 ]; then
	echo "❌ Failed to load configuration"
	exit 1
fi

# 🔴 [로깅 포인트 #5.1] Agent 시작
echo "[giipAgent3.sh] 🟢 [5.1] Agent 시작: version=${sv}, timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')"

# ============================================================================
# Fetch Server Configuration from DB (is_gateway auto-detection)
# ============================================================================

# Detect OS first (needed for API call)
os=$(detect_os)

# Get hostname
hn=$(hostname)

# Fetch server config from DB
echo "🔍 Fetching server configuration from DB..."
config_tmpfile="giipTmpConfig.json"
api_url=$(build_api_url "${apiaddrv2}" "${apiaddrcode}")

# ✅ giipapi 규칙: text에는 파라미터명만, jsondata에 실제 값
config_text="LSvrGetConfig lssn hostname"
config_jsondata="{\"lssn\":${lssn},\"hostname\":\"${hn}\"}"

wget -O "$config_tmpfile" \
	--post-data="text=${config_text}&token=${sk}&jsondata=${config_jsondata}" \
	--header="Content-Type: application/x-www-form-urlencoded" \
	"${api_url}" \
	--no-check-certificate -q 2>&1

if [ -f "$config_tmpfile" ]; then
	# Log API response to KVS for debugging
	api_response=$(cat "$config_tmpfile")
	kvs_put "lssn" "${lssn}" "api_lsvrgetconfig_response" "{\"api_url\":\"${api_url}\",\"response\":${api_response}}"
	
	# Extract is_gateway value from JSON response
	# giipapisk response format: {"data":[{"is_gateway":true,"RstVal":"200",...}],...}
	# Multiple fallback methods to ensure robust parsing
	
	is_gateway_from_db=""
	
	# Method 1: Try jq (most reliable)
	if command -v jq >/dev/null 2>&1; then
		is_gateway_from_db=$(jq -r '.data[0].is_gateway // .is_gateway // empty' "$config_tmpfile" 2>/dev/null)
		echo "[DEBUG] Method 1 (jq): is_gateway_from_db='${is_gateway_from_db}'" >&2
	fi
	
	# Method 2: If jq failed or not available, try sed/grep on normalized text
	if [ -z "$is_gateway_from_db" ]; then
		# Normalize: remove all newlines and carriage returns
		normalized=$(tr -d '\n\r' < "$config_tmpfile")
		
		# Extract: find "is_gateway":true or "is_gateway":false or "is_gateway":1 or "is_gateway":0
		is_gateway_from_db=$(echo "$normalized" | sed -n 's/.*"is_gateway"\s*:\s*\([^,}]*\).*/\1/p' | head -1 | tr -d ' ')
		echo "[DEBUG] Method 2 (sed/grep normalized): is_gateway_from_db='${is_gateway_from_db}'" >&2
	fi
	
	# Method 3: If still empty, try grep with literal search
	if [ -z "$is_gateway_from_db" ]; then
		# Look for exact patterns
		if grep -q '"is_gateway"\s*:\s*true' "$config_tmpfile" 2>/dev/null; then
			is_gateway_from_db="true"
		elif grep -q '"is_gateway"\s*:\s*false' "$config_tmpfile" 2>/dev/null; then
			is_gateway_from_db="false"
		elif grep -q '"is_gateway"\s*:\s*1' "$config_tmpfile" 2>/dev/null; then
			is_gateway_from_db="1"
		elif grep -q '"is_gateway"\s*:\s*0' "$config_tmpfile" 2>/dev/null; then
			is_gateway_from_db="0"
		fi
		echo "[DEBUG] Method 3 (grep patterns): is_gateway_from_db='${is_gateway_from_db}'" >&2
	fi
	
	# Convert true/false to 1/0
	case "$is_gateway_from_db" in
		true|1)
			is_gateway_from_db=1
			;;
		false|0)
			is_gateway_from_db=0
			;;
		*)
			is_gateway_from_db=""
			;;
	esac
	
	echo "[DEBUG] Final result after conversion: is_gateway_from_db='${is_gateway_from_db}'" >&2
	
	if [ -n "$is_gateway_from_db" ]; then
		gateway_mode="$is_gateway_from_db"
		echo "✅ DB config loaded: is_gateway=${gateway_mode}"
		
		# 🔴 [로깅 포인트 #5.2] 설정 로드 완료
		echo "[giipAgent3.sh] 🟢 [5.2] 설정 로드 완료: lssn=${lssn}, hostname=${hn}, is_gateway=${gateway_mode}, timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')"
		
		kvs_put "lssn" "${lssn}" "api_lsvrgetconfig_success" "{\"is_gateway\":${gateway_mode},\"source\":\"db_api\"}"
	else
		echo "⚠️  Failed to parse is_gateway from DB, using default: gateway_mode=${gateway_mode}"
		echo "[DEBUG] All parsing methods failed. API response first 500 chars: $(head -c 500 "$config_tmpfile")" >&2
		kvs_put "lssn" "${lssn}" "api_lsvrgetconfig_parse_failed" "{\"response\":${api_response},\"debug\":\"all_methods_failed\"}"
	fi
	
	rm -f "$config_tmpfile"
else
	echo "⚠️  Failed to fetch server config from DB, using default: gateway_mode=${gateway_mode}"
	kvs_put "lssn" "${lssn}" "api_lsvrgetconfig_failed" "{\"api_url\":\"${api_url}\",\"error\":\"API call failed or no response file\"}"
fi

# ============================================================================
# Initialize Logging
# ============================================================================

# Setup log directory
init_log_dir "$SCRIPT_DIR"

# Log startup
logdt=$(date '+%Y%m%d%H%M%S')
log_message "INFO" "========================================"
log_message "INFO" "Starting GIIP Agent V${sv}"
log_message "INFO" "LSSN: ${lssn}, Hostname: ${hn}"
log_message "INFO" "Mode: $([ "$gateway_mode" = "1" ] && echo "GATEWAY" || echo "NORMAL")"
log_message "INFO" "========================================"

# ============================================================================
# Get Version Tracking Info (for startup logging)
# ============================================================================

# Get Git commit hash (if available)
export GIT_COMMIT="unknown"
if command -v git >/dev/null 2>&1 && [ -d "${SCRIPT_DIR}/.git" ]; then
	GIT_COMMIT=$(git -C "${SCRIPT_DIR}" rev-parse --short HEAD 2>/dev/null || echo "unknown")
fi

# Get file modification date
export FILE_MODIFIED=$(stat -c %y "${BASH_SOURCE[0]}" 2>/dev/null || stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "${BASH_SOURCE[0]}" 2>/dev/null || echo "unknown")

log_message "INFO" "Git Commit: ${GIT_COMMIT}, File Modified: ${FILE_MODIFIED}"

# ============================================================================
# Check Dependencies
# ============================================================================

check_dos2unix

# ============================================================================
# Handle Server Registration (LSSN=0)
# ============================================================================

if [ "${lssn}" = "0" ]; then
	log_message "INFO" "Server not registered, registering now..."
	
	local tmpFileName="giipTmpScript.sh"
	local lwAPIURL=$(build_api_url "${apiaddrv2}" "${apiaddrcode}")
	local lwDownloadText="CQEQueueGet 0 ${hn} ${os} op"
	
	wget -O $tmpFileName \
		--post-data="text=${lwDownloadText}&token=${sk}" \
		--header="Content-Type: application/x-www-form-urlencoded" \
		"${lwAPIURL}" \
		--no-check-certificate -q
	
	lssn=$(cat ${tmpFileName})
	cnfdmp=$(cat ../giipAgent.cnf | sed -e "s|lssn=\"0\"|lssn=\"${lssn}\"|g")
	echo "${cnfdmp}" > ../giipAgent.cnf
	rm -f $tmpFileName
	
	log_message "INFO" "Server registered with LSSN: ${lssn}"
fi

# ============================================================================
# Mode Selection: Gateway or Normal
# ============================================================================

if [ "${gateway_mode}" = "1" ]; then
	# ========================================================================
	# GATEWAY MODE
	# ========================================================================
	
	# 🔴 [로깅 포인트 #5.3] Gateway 모드 감지 및 초기화
	echo "[giipAgent3.sh] 🟢 [5.3] Gateway 모드 감지 및 초기화: lssn=${lssn}, gateway_mode=1, timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')"
	
	log_message "INFO" "Running in GATEWAY MODE"
	
	# Load gateway and db_clients libraries
	. "${LIB_DIR}/db_clients.sh"
	. "${LIB_DIR}/gateway.sh"
	
	# Initialize Gateway
	startup_status="{\"status\":\"started\",\"version\":\"${sv}\",\"lssn\":${lssn},\"timestamp\":\"$(date '+%Y-%m-%d %H:%M:%S')\",\"mode\":\"gateway\",\"is_gateway\":1}"
	save_gateway_status "startup" "$startup_status"
	
	init_details="{\"config_file\":\"giipAgent.cnf\",\"api_endpoint\":\"${apiaddrv2}\",\"pid\":$$,\"is_gateway\":1,\"git_commit\":\"${GIT_COMMIT}\",\"file_modified\":\"${FILE_MODIFIED}\",\"script_path\":\"${BASH_SOURCE[0]}\"}"
	save_execution_log "startup" "$init_details"
	
	# Check and install dependencies
	check_sshpass || error_handler "Failed to setup sshpass" 1
	# Note: DB clients are checked/installed only when needed in check_managed_databases()
	
	# Verify DB connectivity (first time)
	log_message "INFO" "Verifying DB connectivity..."
	server_list_file=$(get_gateway_servers)
	if [ $? -eq 0 ] && [ -f "$server_list_file" ]; then
		server_count=$(grep -o '{[^}]*}' "$server_list_file" | wc -l)
		log_message "INFO" "Found ${server_count} servers in DB"
		rm -f "$server_list_file"
	else
		log_message "WARNING" "Could not fetch servers from DB (will retry each cycle)"
		server_count=0
	fi
	
	# Save initialization complete
	init_complete_details="{\"db_connectivity\":\"verified\",\"server_count\":${server_count}}"
	save_execution_log "gateway_init" "$init_complete_details"
	
	# Gateway main loop (run once per execution, cron will re-run)
	log_message "INFO" "Starting Gateway cycle..."
	
	# Process gateway servers (query DB each cycle)
	process_gateway_servers
	
	# Check managed databases (tManagedDatabase)
	log_message "INFO" "Checking managed databases..."
	check_managed_databases
	
	log_message "INFO" "Gateway cycle completed"
	
	# Shutdown log
	save_execution_log "shutdown" "{\"mode\":\"gateway\",\"status\":\"normal_exit\"}"

	
else
	# ========================================================================
	# NORMAL MODE
	# ========================================================================
	
	log_message "INFO" "Running in NORMAL MODE"
	
	# Load normal mode library
	. "${LIB_DIR}/normal.sh"
	
	# Run normal mode (single execution)
	run_normal_mode "$lssn" "$hn" "$os"
	
fi

# ============================================================================
# Cleanup and Exit
# ============================================================================

log_message "INFO" "GIIP Agent V${sv} completed"
exit 0
