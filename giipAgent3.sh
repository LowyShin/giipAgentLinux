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
echo "[giipAgent3.sh] 🟢 [5.1] Agent 시작: version=${sv}"

# 🔴 [DEBUG-로깅 #1] 환경 변수 검증 (KVS 저장 실패 진단용)
echo "[giipAgent3.sh] 🔍 [DEBUG-1] SCRIPT_DIR=${SCRIPT_DIR}" >&2
echo "[giipAgent3.sh] 🔍 [DEBUG-1] LIB_DIR=${LIB_DIR}" >&2

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
		echo "[giipAgent3.sh] 🟢 [5.2] 설정 로드 완료: lssn=${lssn}, hostname=${hn}, is_gateway=${gateway_mode}"
		
		# 🔴 [DEBUG-로깅 #2] KVS 필수 변수 검증 (라인 300, 305에서 kvs_put 호출 전)
		echo "[giipAgent3.sh] 🔍 [DEBUG-2] Validating KVS variables before auto-discover phase" >&2
		echo "[giipAgent3.sh] 🔍 [DEBUG-2] sk=${sk:-(empty ❌)}" >&2
		echo "[giipAgent3.sh] 🔍 [DEBUG-2] apiaddrv2=${apiaddrv2:-(empty ❌)}" >&2
		echo "[giipAgent3.sh] 🔍 [DEBUG-2] apiaddrcode=${apiaddrcode:-(empty)}" >&2
		
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
# Load Optional Modules
# ============================================================================

# Load discovery module (safe integration with error handling)
if [ -f "${LIB_DIR}/discovery.sh" ]; then
	. "${LIB_DIR}/discovery.sh"
	
	# Run discovery if needed (6시간 주기)
	# 🔴 [Option 2: lib/discovery.sh 개선됨 - 명시적 에러 처리 추가됨]
	if collect_infrastructure_data "${lssn}"; then
		log_message "INFO" "Discovery completed successfully"
	else
		log_message "WARN" "Discovery failed but continuing (error handling applied)"
	fi
fi

# ============================================================================
# Mode Selection: Gateway or Normal
# ============================================================================

if [ "${gateway_mode}" = "1" ]; then
	# ========================================================================
	# GATEWAY MODE
	# ========================================================================
	
	# 🔴 [로깅 포인트 #5.3] Gateway 모드 감지 및 초기화
	echo "[giipAgent3.sh] 🟢 [5.3] Gateway 모드 감지 및 초기화: lssn=${lssn}, gateway_mode=1"
	
	log_message "INFO" "Running in GATEWAY MODE"
	
	# Load gateway and db_clients libraries
	. "${LIB_DIR}/db_clients.sh"
	. "${LIB_DIR}/gateway.sh"
	
	# Initialize Gateway
	startup_status="{\"status\":\"started\",\"version\":\"${sv}\",\"lssn\":${lssn},\"mode\":\"gateway\",\"is_gateway\":1}"
	save_gateway_status "startup" "$startup_status"
	
	init_details="{\"config_file\":\"giipAgent.cnf\",\"api_endpoint\":\"${apiaddrv2}\",\"pid\":$$,\"is_gateway\":1,\"git_commit\":\"${GIT_COMMIT}\",\"file_modified\":\"${FILE_MODIFIED}\",\"script_path\":\"${BASH_SOURCE[0]}\"}"
	save_execution_log "startup" "$init_details"
	
	# Check and install dependencies
	check_sshpass || error_handler "Failed to setup sshpass" 1
	# Note: DB clients are checked/installed only when needed in check_managed_databases()
	
	# Verify DB connectivity (connectivity check only, no file operations)
	log_message "INFO" "Verifying DB connectivity..."
	# Note: Actual server list will be fetched inside process_gateway_servers()
	# This is just a connectivity check
	
	# Save initialization complete (server_count will be set by process_gateway_servers)
	init_complete_details="{\"db_connectivity\":\"will_verify\",\"server_count\":0}"
	save_execution_log "gateway_init" "$init_complete_details"
	
	# ================================================================
	# [NEW] Auto-Discover Phase (before Gateway processing)
	# ================================================================
	
	# STEP-1: Configuration Check (변수 검증)
	log_auto_discover_step "STEP-1" "Configuration Check" "auto_discover_step_1_config" "{\"lssn\":${lssn},\"sk_length\":${#sk},\"apiaddrv2_set\":$([ -n \"$apiaddrv2\" ] && echo 'true' || echo 'false')}"
	log_auto_discover_validation "STEP-1" "sk_variable" "$([ -n \"$sk\" ] && echo 'PASS' || echo 'FAIL')" "{\"length\":${#sk}}"
	log_auto_discover_validation "STEP-1" "apiaddrv2_variable" "$([ -n \"$apiaddrv2\" ] && echo 'PASS' || echo 'FAIL')" "{\"value\":\"${apiaddrv2:-(empty)}\"}"
	
	if [ -z "$sk" ] || [ -z "$apiaddrv2" ]; then
		log_auto_discover_error "STEP-1" "CONFIG_MISSING" "Required variables not set" "{\"sk_set\":$([ -n \"$sk\" ] && echo 'true' || echo 'false'),\"apiaddrv2_set\":$([ -n \"$apiaddrv2\" ] && echo 'true' || echo 'false')}"
		return 1
	fi
	
	# STEP-2: Script Path Check (auto-discover 스크립트 파일 검증)
	# Handle case where SCRIPT_DIR might already include /lib
	auto_discover_base_dir="$SCRIPT_DIR"
	
	# DEBUG: Log path stripping process
	echo "DEBUG STEP-2: SCRIPT_DIR=$SCRIPT_DIR" | tee -a /tmp/auto_discover_debug_$$.log
	echo "DEBUG STEP-2: initial auto_discover_base_dir=$auto_discover_base_dir" | tee -a /tmp/auto_discover_debug_$$.log
	
	if [[ "$auto_discover_base_dir" == */lib ]]; then
		auto_discover_base_dir="${auto_discover_base_dir%/lib}"
		echo "DEBUG STEP-2: lib stripped, new auto_discover_base_dir=$auto_discover_base_dir" | tee -a /tmp/auto_discover_debug_$$.log
	fi
	
	auto_discover_script="${auto_discover_base_dir}/giipscripts/auto-discover-linux.sh"
	
	# DEBUG: Final paths
	echo "DEBUG STEP-2: final auto_discover_script=$auto_discover_script" | tee -a /tmp/auto_discover_debug_$$.log
	echo "DEBUG STEP-2: file_exists=$([ -f "$auto_discover_script" ] && echo 'true' || echo 'false')" | tee -a /tmp/auto_discover_debug_$$.log
	[ -f "$auto_discover_script" ] && echo "DEBUG STEP-2: ls -la $auto_discover_script: $(ls -la "$auto_discover_script" 2>&1)" | tee -a /tmp/auto_discover_debug_$$.log
	
	log_auto_discover_step "STEP-2" "Script Path Check" "auto_discover_step_2_scriptpath" "{\"path\":\"${auto_discover_script}\",\"exists\":$([ -f \"$auto_discover_script\" ] && echo 'true' || echo 'false')}"
	log_auto_discover_validation "STEP-2" "script_file_exists" "$([ -f \"$auto_discover_script\" ] && echo 'PASS' || echo 'FAIL')" "{\"path\":\"${auto_discover_script}\"}"
	
	if [ ! -f "$auto_discover_script" ]; then
		log_auto_discover_error "STEP-2" "SCRIPT_NOT_FOUND" "auto-discover script not found" "{\"searched_path\":\"${auto_discover_script}\",\"base_dir\":\"${auto_discover_base_dir}\"}"
		return 1
	fi
	
	# STEP-3: Initialize KVS Records (auto_discover_init KVS 저장)
	log_auto_discover_step "STEP-3" "Initialize KVS Records" "auto_discover_step_3_init" "{\"action\":\"storing_init_marker\",\"lssn\":${lssn}}"
	
	# 실제 kvs_put 호출 (raw JSON 데이터)
	local init_data="{\"status\":\"starting\",\"script_path\":\"${auto_discover_script}\",\"hostname\":\"${hn}\",\"os\":\"${os}\"}"
	kvs_put "lssn" "${lssn}" "auto_discover_init" "$init_data" 2>&1 | tee -a /tmp/kvs_put_init_$$.log
	kvs_put_init_result=$?
	
	log_auto_discover_validation "STEP-3" "kvs_put_auto_discover_init" "$([ $kvs_put_init_result -eq 0 ] && echo 'PASS' || echo 'FAIL')" "{\"exit_code\":${kvs_put_init_result}}"
	
	if [ $kvs_put_init_result -ne 0 ]; then
		local init_error=$(tail -5 /tmp/kvs_put_init_$$.log 2>/dev/null | tr '\n' ' ')
		log_auto_discover_error "STEP-3" "KVS_PUT_INIT_FAILED" "Failed to store auto_discover_init" "{\"exit_code\":${kvs_put_init_result},\"error_detail\":\"${init_error}\"}"
		return 1
	fi
	
	# STEP-4: Execute Auto-Discover Script (실제 auto-discover 실행)
	log_auto_discover_step "STEP-4" "Execute Auto-Discover Script" "auto_discover_step_4_execution" "{\"script\":\"${auto_discover_script}\",\"timeout_sec\":60}"
	
	auto_discover_result_file="/tmp/auto_discover_result_$$.json"
	auto_discover_log_file="/tmp/auto_discover_log_$$.log"
	execute_start_time=$(date '+%Y-%m-%d %H:%M:%S')
	
	timeout 60 bash "$auto_discover_script" "$lssn" "$hn" "$os" > "$auto_discover_result_file" 2> "$auto_discover_log_file"
	auto_discover_exit_code=$?
	execute_end_time=$(date '+%Y-%m-%d %H:%M:%S')
	
	# STEP-4 결과 분석
	if [ $auto_discover_exit_code -eq 0 ]; then
		log_auto_discover_validation "STEP-4" "script_execution" "PASS" "{\"exit_code\":0,\"start_time\":\"${execute_start_time}\",\"end_time\":\"${execute_end_time}\"}"
	elif [ $auto_discover_exit_code -eq 124 ]; then
		log_auto_discover_error "STEP-4" "SCRIPT_TIMEOUT" "Script execution timed out (60 seconds)" "{\"exit_code\":124,\"timeout_sec\":60}"
		return 1
	else
		local script_error=$(tail -10 "$auto_discover_log_file" 2>/dev/null | tr '\n' ';')
		log_auto_discover_error "STEP-4" "SCRIPT_EXECUTION_FAILED" "Script failed with non-zero exit code" "{\"exit_code\":${auto_discover_exit_code},\"error_log\":\"${script_error}\"}"
		return 1
	fi
	
	# STEP-5: Validate Result File (결과 파일 유효성 검증)
	log_auto_discover_step "STEP-5" "Validate Result File" "auto_discover_step_5_validation" "{\"result_file\":\"${auto_discover_result_file}\"}"
	
	result_size=$(wc -c < "$auto_discover_result_file" 2>/dev/null || echo "0")
	log_auto_discover_validation "STEP-5" "result_file_size" "$([ $result_size -gt 0 ] && echo 'PASS' || echo 'FAIL')" "{\"bytes\":${result_size}}"
	
	if [ $result_size -eq 0 ]; then
		log_auto_discover_error "STEP-5" "RESULT_FILE_EMPTY" "Result file is empty or does not exist" "{\"file\":\"${auto_discover_result_file}\",\"size\":0}"
		return 1
	fi
	
	# STEP-6: Store Result to Files (auto_discover_result 파일 생성)
	# NOTE: kvs_put은 다른 위치에서 처리 (파일만 생성)
	log_auto_discover_step "STEP-6" "Store Result to Files" "auto_discover_step_6_store_result" "{\"file_size\":${result_size}}"
	
	# DEBUG: Log file details
	echo "DEBUG STEP-6: result_file=$auto_discover_result_file" | tee -a /tmp/auto_discover_debug_$$.log
	echo "DEBUG STEP-6: file_exists=$([ -f "$auto_discover_result_file" ] && echo 'true' || echo 'false')" | tee -a /tmp/auto_discover_debug_$$.log
	echo "DEBUG STEP-6: file_size=$([ -f "$auto_discover_result_file" ] && stat -f%z "$auto_discover_result_file" 2>/dev/null || stat -c%s "$auto_discover_result_file" 2>/dev/null || echo 'unknown')" | tee -a /tmp/auto_discover_debug_$$.log
	
	# Read the actual discovery result data
	auto_discover_json=$(cat "$auto_discover_result_file")
	
	# DEBUG: Log json content
	echo "DEBUG STEP-6: json_length=${#auto_discover_json}" | tee -a /tmp/auto_discover_debug_$$.log
	echo "DEBUG STEP-6: json_first_200=$(echo "$auto_discover_json" | head -c 200)" | tee -a /tmp/auto_discover_debug_$$.log
	
	# Parse and store discovery results by type (각 kFactor별로 파일만 생성, kvs_put은 나중에)
	# The auto_discover_json contains: {"servers":[...], "networks":[...], "services":[...], etc.}
	if [ -n "$auto_discover_json" ]; then
		echo "DEBUG STEP-6: Creating individual component files (no kvs_put - handled elsewhere)" | tee -a /tmp/auto_discover_debug_$$.log
		
		# 1. auto_discover_result: Store complete discovery result
		echo "DEBUG STEP-6: Creating file for auto_discover_result" | tee -a /tmp/auto_discover_debug_$$.log
		auto_discover_result_kvalue_file="/tmp/kvs_kValue_auto_discover_result_$$.json"
		echo "$auto_discover_json" > "$auto_discover_result_kvalue_file"
		echo "DEBUG STEP-6: Created $auto_discover_result_kvalue_file (size: $(wc -c < "$auto_discover_result_kvalue_file"))" | tee -a /tmp/auto_discover_debug_$$.log
		
		# 2. auto_discover_servers: Extract and store servers
		echo "DEBUG STEP-6: Creating file for auto_discover_servers" | tee -a /tmp/auto_discover_debug_$$.log
		servers_data=$(echo "$auto_discover_json" | jq '.servers // empty' 2>/dev/null)
		auto_discover_servers_kvalue_file="/tmp/kvs_kValue_auto_discover_servers_$$.json"
		echo "$servers_data" > "$auto_discover_servers_kvalue_file"
		echo "DEBUG STEP-6: Created $auto_discover_servers_kvalue_file (size: $(wc -c < "$auto_discover_servers_kvalue_file"))" | tee -a /tmp/auto_discover_debug_$$.log
		
		# 3. auto_discover_networks: Extract and store networks
		echo "DEBUG STEP-6: Creating file for auto_discover_networks" | tee -a /tmp/auto_discover_debug_$$.log
		networks_data=$(echo "$auto_discover_json" | jq '.networks // empty' 2>/dev/null)
		auto_discover_networks_kvalue_file="/tmp/kvs_kValue_auto_discover_networks_$$.json"
		echo "$networks_data" > "$auto_discover_networks_kvalue_file"
		echo "DEBUG STEP-6: Created $auto_discover_networks_kvalue_file (size: $(wc -c < "$auto_discover_networks_kvalue_file"))" | tee -a /tmp/auto_discover_debug_$$.log
		
		# 4. auto_discover_services: Extract and store services
		echo "DEBUG STEP-6: Creating file for auto_discover_services" | tee -a /tmp/auto_discover_debug_$$.log
		services_data=$(echo "$auto_discover_json" | jq '.services // empty' 2>/dev/null)
		auto_discover_services_kvalue_file="/tmp/kvs_kValue_auto_discover_services_$$.json"
		echo "$services_data" > "$auto_discover_services_kvalue_file"
		echo "DEBUG STEP-6: Created $auto_discover_services_kvalue_file (size: $(wc -c < "$auto_discover_services_kvalue_file"))" | tee -a /tmp/auto_discover_debug_$$.log
		
		echo "DEBUG STEP-6: All component files created in /tmp/kvs_kValue_* (ready for kvs_put from elsewhere)" | tee -a /tmp/auto_discover_debug_$$.log
	else
		# No data to store
		echo "DEBUG STEP-6: ERROR - No discovery data generated (auto_discover_json is empty)" | tee -a /tmp/auto_discover_debug_$$.log
		# Store error status for tracking
		auto_discover_result_error_file="/tmp/kvs_kValue_auto_discover_result_ERROR_$$.json"
		echo "{\"status\":\"error\",\"message\":\"No discovery data generated\"}" > "$auto_discover_result_error_file"
		kvs_put "lssn" "${lssn}" "auto_discover_result" "{\"status\":\"error\",\"message\":\"No discovery data generated\"}" 2>&1 | tee -a /tmp/kvs_put_auto_discover_result_$$.log
	fi
	
	log_auto_discover_step "STEP-6" "Store Result to KVS" "auto_discover_step_6_store_result" "{\"status\":\"completed\",\"kValues_saved_to\":\"/tmp/kvs_kValue_auto_discover_*_$$.json\"}"
	
	# STEP-6 직접 kvs_put: 파일들을 KVS에 저장
	echo "[AUTO-DISCOVER] STEP-6: Direct kvs_put - Storing files to KVS" >&2
	
	# DEBUG: 파일 크기 확인
	echo "[AUTO-DISCOVER] STEP-6: File sizes:" >&2
	ls -la /tmp/kvs_kValue_auto_discover_*.json 2>/dev/null | tee -a /tmp/auto_discover_debug_$$.log >&2
	
	if [ -f "/tmp/kvs_kValue_auto_discover_result_$$.json" ]; then
		result_data=$(cat "/tmp/kvs_kValue_auto_discover_result_$$.json" 2>/dev/null)
		echo "[AUTO-DISCOVER] STEP-6: Uploading auto_discover_result (${#result_data} bytes)" >&2
		kvs_put "lssn" "${lssn}" "auto_discover_result" "$result_data" 2>&1 | tee -a /tmp/auto_discover_debug_$$.log
	fi
	
	if [ -f "/tmp/kvs_kValue_auto_discover_servers_$$.json" ]; then
		servers_data=$(cat "/tmp/kvs_kValue_auto_discover_servers_$$.json" 2>/dev/null)
		echo "[AUTO-DISCOVER] STEP-6: Uploading auto_discover_servers (${#servers_data} bytes)" >&2
		kvs_put "lssn" "${lssn}" "auto_discover_servers" "$servers_data" 2>&1 | tee -a /tmp/auto_discover_debug_$$.log
	fi
	
	if [ -f "/tmp/kvs_kValue_auto_discover_networks_$$.json" ]; then
		networks_data=$(cat "/tmp/kvs_kValue_auto_discover_networks_$$.json" 2>/dev/null)
		echo "[AUTO-DISCOVER] STEP-6: Uploading auto_discover_networks (${#networks_data} bytes)" >&2
		kvs_put "lssn" "${lssn}" "auto_discover_networks" "$networks_data" 2>&1 | tee -a /tmp/auto_discover_debug_$$.log
	fi
	
	if [ -f "/tmp/kvs_kValue_auto_discover_services_$$.json" ]; then
		services_data=$(cat "/tmp/kvs_kValue_auto_discover_services_$$.json" 2>/dev/null)
		echo "[AUTO-DISCOVER] STEP-6: Uploading auto_discover_services (${#services_data} bytes)" >&2
		kvs_put "lssn" "${lssn}" "auto_discover_services" "$services_data" 2>&1 | tee -a /tmp/auto_discover_debug_$$.log
	fi
	
	echo "[AUTO-DISCOVER] STEP-6: Direct kvs_put completed" >&2
	
	# STEP-7: Store All Data to KVS (확인 메시지만)
	log_auto_discover_step "STEP-7" "Store Discovery Data to KVS" "auto_discover_step_7_complete" "{\"status\":\"storing_data\"}"
	
	echo "[AUTO-DISCOVER] STEP-7: All discovery data stored to KVS via STEP-6" >&2
	
	# Final Complete Marker
	log_auto_discover_step "STEP-7" "Store Complete Marker" "auto_discover_step_7_complete" "{\"status\":\"completed\"}"
	
	# Initialize kvs_put_complete_code before using it
	kvs_put_complete_code=0
	
	# ✅ PROHIBITED_ACTION_13 준수: 이전 단계 실패 여부 확인 후 최종 상태 결정
	local final_status="PASSED"
	if [ $kvs_put_init_result -ne 0 ] || [ $kvs_put_result_code -ne 0 ]; then
		final_status="FAILED"
	fi
	
	local complete_data="{\"status\":\"completed\",\"timestamp\":\"$(date '+%Y-%m-%d %H:%M:%S')\",\"all_steps_passed\":$([ \"$final_status\" = \"PASSED\" ] && echo 'true' || echo 'false'),\"final_status\":\"${final_status}\"}"
	log_auto_discover_step "COMPLETE" "Auto-Discover Phase Complete" "auto_discover_complete" "$complete_data"
	kvs_put_complete_code=$?
	
	# Cleanup temp files
	rm -f /tmp/kvs_put_init_$$.log /tmp/kvs_put_result_$$.log /tmp/kvs_put_complete_$$.log /tmp/auto_discover_result_$$.json /tmp/auto_discover_log_$$.log
	
	if [ $? -ne 0 ]; then
		return 1
	fi
	
	# Final Summary - ✅ PROHIBITED_ACTION_13 준수: 실제 최종 상태 기록
	log_auto_discover_step "COMPLETE" "Auto-Discover Phase Complete" "auto_discover_complete" "{\"all_steps\":\"${final_status}\"}"
	
	# ================================================================
	# [로깅 #8] auto-discover 단계 완료
	echo "[giipAgent3.sh] 🟢 [5.2.end] Auto-discover phase completed" >&2
	kvs_put "lssn" "${lssn}" "auto_discover_complete" "{\"status\":\"complete\",\"timestamp\":\"$(date '+%Y-%m-%d %H:%M:%S')\"}"
	
	# Gateway main loop (run once per execution, cron will re-run)
	log_message "INFO" "Starting Gateway cycle..."
	
	# 🔴 DEBUG: process_gateway_servers 호출 직전
	echo "[giipAgent3.sh] 🔵 About to call process_gateway_servers() now" >&2
	
	# Process gateway servers (query DB each cycle)
	# Capture stderr output and log to tKVS
	# Use temp file to avoid subshell issues with stderr capture
	gw_temp_log="/tmp/gateway_stderr_$$.log"
	process_gateway_servers > /dev/null 2> "$gw_temp_log"
	process_gw_result=$?
	gateway_stderr_log=$(cat "$gw_temp_log" 2>/dev/null)
	rm -f "$gw_temp_log"
	
	# 🔴 DEBUG: process_gateway_servers 반환 후
	echo "[giipAgent3.sh] 🔵 process_gateway_servers() returned with code: $process_gw_result" >&2
	echo "[giipAgent3.sh] 🔵 Captured stderr lines: $(echo "$gateway_stderr_log" | wc -l)" >&2
	
	# Log gateway operation details to tKVS for visibility
	if [ -n "$gateway_stderr_log" ]; then
		# Parse stderr for key information
		gateway_servers_found=$(echo "$gateway_stderr_log" | grep -c "\[5\.[0-9]*\]")
		gateway_errors=$(echo "$gateway_stderr_log" | grep -c "❌")
		gateway_success=$(echo "$gateway_stderr_log" | grep -c "🟢")
		
		kvs_put "lssn" "${lssn}" "gateway_cycle_log" "{\"result\":\"${process_gw_result}\",\"log_entries\":${gateway_servers_found},\"successes\":${gateway_success},\"errors\":${gateway_errors},\"full_log\":\"$(echo "$gateway_stderr_log" | tr '\n' '|' | head -c 1000)\"}"
	fi
	
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

# Clean up temporary files created by PREVIOUS script executions
# Only delete files that are NOT from the current PID
current_pid=$$

# Function to safely delete old files (not from current process)
cleanup_old_temp_files() {
	local pattern=$1
	for file in /tmp/${pattern}; do
		if [ -f "$file" ] && [ -s "$file" ]; then
			# Extract the PID from the filename (assumes format: prefix_${PID}.ext)
			local file_pid=$(echo "$file" | sed -E 's/.*_([0-9]+)\.(log|json|txt)$/\1/')
			# Only delete if PID doesn't match current process and file is NOT empty
			if [ "$file_pid" != "$current_pid" ] && [ "$file_pid" != "${pattern}" ]; then
				rm -f "$file" 2>/dev/null
			fi
		fi
	done
}

# Clean up old files from previous executions
cleanup_old_temp_files "auto_discover_debug_*.log"
cleanup_old_temp_files "auto_discover_result_*.json"
cleanup_old_temp_files "auto_discover_log_*.log"
cleanup_old_temp_files "auto_discover_services_*.json"
cleanup_old_temp_files "auto_discover_servers_*.json"
cleanup_old_temp_files "auto_discover_networks_*.json"
cleanup_old_temp_files "discovery_kvs_log_*.txt"
cleanup_old_temp_files "kvs_put_init_*.log"
cleanup_old_temp_files "kvs_kValue_auto_discover_result_*.json"
cleanup_old_temp_files "kvs_kValue_auto_discover_servers_*.json"
cleanup_old_temp_files "kvs_kValue_auto_discover_networks_*.json"
cleanup_old_temp_files "kvs_kValue_auto_discover_services_*.json"
cleanup_old_temp_files "kvs_put_auto_discover_result_*.log"
cleanup_old_temp_files "kvs_put_auto_discover_servers_*.log"
cleanup_old_temp_files "kvs_put_auto_discover_networks_*.log"
cleanup_old_temp_files "kvs_put_auto_discover_services_*.log"

# Clean up old kvs_post_data.txt (from old kvs.sh implementations)
rm -f /tmp/kvs_post_data.txt 2>/dev/null
cleanup_old_temp_files "gateway_stderr_*.log"

log_message "INFO" "GIIP Agent V${sv} completed"
exit 0
