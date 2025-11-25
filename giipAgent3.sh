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
	echo "[giipAgent3.sh] 🔵 DEBUG: About to enter auto-discover phase" >&2
	log_message "INFO" "[5.2] Starting auto-discover phase..."
	
	# [로깅 #1] auto-discover 시작 알림
	echo "[giipAgent3.sh] 🟢 [5.2] Starting auto-discover-linux.sh execution" >&2
	
	# auto-discover-linux.sh 경로
	# SCRIPT_DIR은 giipAgent3.sh의 디렉토리
	# 실제 서버: /home/.../giipAgentLinux/lib/giipscripts/auto-discover-linux.sh
	# 로컬 dev: /home/.../giipAgentLinux/giipscripts/auto-discover-linux.sh
	
	# 경로 1: giipscripts (로컬 dev 구조)
	auto_discover_script="${SCRIPT_DIR}/giipscripts/auto-discover-linux.sh"
	
	# 경로 2: lib/giipscripts (서버 구조)
	if [ ! -f "$auto_discover_script" ]; then
		auto_discover_script="${SCRIPT_DIR}/lib/giipscripts/auto-discover-linux.sh"
	fi
	
	echo "[giipAgent3.sh] 📍 DEBUG: auto_discover_script path: $auto_discover_script (exists: $([ -f "$auto_discover_script" ] && echo 'YES' || echo 'NO'))" >&2
	
	# 🔴 [DEBUG-로깅 #3] 파일 존재 여부 상세 검증
	echo "[giipAgent3.sh] 🔍 [DEBUG-3] BRANCH: auto-discover script check" >&2
	echo "[giipAgent3.sh] 🔍 [DEBUG-3] Expected path: $auto_discover_script" >&2
	echo "[giipAgent3.sh] 🔍 [DEBUG-3] File exists: $([ -f "$auto_discover_script" ] && echo 'YES ✅' || echo 'NO ❌')" >&2
	
	if [ ! -f "$auto_discover_script" ]; then
		log_message "WARN" "auto-discover script not found in both paths"
		echo "[giipAgent3.sh] 🔍 [DEBUG-3] Searched paths:" >&2
		echo "[giipAgent3.sh] 🔍 [DEBUG-3]   - Path 1: ${SCRIPT_DIR}/giipscripts/auto-discover-linux.sh" >&2
		echo "[giipAgent3.sh] 🔍 [DEBUG-3]   - Path 2: ${SCRIPT_DIR}/lib/giipscripts/auto-discover-linux.sh" >&2
		kvs_put "lssn" "${lssn}" "auto_discover_init" "{\"status\":\"failed\",\"reason\":\"script_not_found\",\"path\":\"${auto_discover_script}\",\"script_dir\":\"${SCRIPT_DIR}\"}"
		echo "[giipAgent3.sh] ⚠️ [5.2.1] auto-discover-linux.sh NOT FOUND at $auto_discover_script (SCRIPT_DIR=$SCRIPT_DIR)" >&2
	else
		echo "[giipAgent3.sh] 🔍 [DEBUG-3] Script found, proceeding with execution" >&2
		# [로깅 #2] auto-discover 실행 시작
		echo "[giipAgent3.sh] 📍 DEBUG: About to call kvs_put for auto_discover_init" >&2
		
		# 🔴 [DEBUG-로깅 #4] kvs_put 호출 전 최종 변수 검증
		echo "[giipAgent3.sh] 🔍 [DEBUG-4] BEFORE kvs_put auto_discover_init:" >&2
		echo "[giipAgent3.sh] 🔍 [DEBUG-4]   sk length: ${#sk}" >&2
		echo "[giipAgent3.sh] 🔍 [DEBUG-4]   apiaddrv2=${apiaddrv2:-(empty ❌)}" >&2
		echo "[giipAgent3.sh] 🔍 [DEBUG-4]   kType=lssn, kKey=${lssn}, kFactor=auto_discover_init" >&2
		
		# kvs_put 호출 (stderr 캡처로 로깅)
		kvs_put "lssn" "${lssn}" "auto_discover_init" "{\"status\":\"starting\",\"script_path\":\"${auto_discover_script}\",\"lssn\":${lssn},\"hostname\":\"${hn}\"}" 2>&1 | tee -a /tmp/kvs_put_debug_$$.log
		kvs_put_result=$?
		
		# 🔴 [DEBUG-로깅 #5] kvs_put 호출 후 결과 검증
		echo "[giipAgent3.sh] 🔍 [DEBUG-5] AFTER kvs_put auto_discover_init:" >&2
		echo "[giipAgent3.sh] 🔍 [DEBUG-5]   exit_code=$kvs_put_result (0=success, non-zero=failure)" >&2
		if [ $kvs_put_result -ne 0 ]; then
			echo "[giipAgent3.sh] ❌ [DEBUG-5] ERROR: kvs_put FAILED!" >&2
			echo "[giipAgent3.sh] 🔍 [DEBUG-5] kvs_put stderr (last 20 lines):" >&2
			[ -f /tmp/kvs_put_debug_$$.log ] && tail -20 /tmp/kvs_put_debug_$$.log | sed 's/^/  [DEBUG-5] /' >&2
		else
			echo "[giipAgent3.sh] ✅ [DEBUG-5] kvs_put SUCCESS" >&2
		fi
		echo "[giipAgent3.sh] 📍 DEBUG: kvs_put returned: $kvs_put_result" >&2
		
		echo "[giipAgent3.sh] ✅ [5.2.1] auto-discover-linux.sh found, executing..." >&2
		
		# [로깅 #3] 실행 환경 정보
		echo "[giipAgent3.sh] 📋 [5.2.2] Environment: LSSN=${lssn}, Hostname=${hn}, OS=${os}, PID=$$" >&2
		
		# 임시 결과 파일 생성
		auto_discover_result_file="/tmp/auto_discover_result_$$.json"
		auto_discover_log_file="/tmp/auto_discover_log_$$.log"
		
		# Timeout 설정 (60초)
		timeout_seconds=60
		
		# [로깅 #4] auto-discover 실행 시작 시간
		execute_start_time=$(date '+%Y-%m-%d %H:%M:%S')
		echo "[giipAgent3.sh] ⏱️ [5.2.3] Execution started at: ${execute_start_time}" >&2
		
		# Auto-discover 실행 (timeout 적용, 에러 캡처)
		if timeout "$timeout_seconds" bash "$auto_discover_script" "$lssn" "$hn" "$os" > "$auto_discover_result_file" 2> "$auto_discover_log_file"; then
			auto_discover_exit_code=$?
			execute_end_time=$(date '+%Y-%m-%d %H:%M:%S')
			
			# [로깅 #5] auto-discover 성공
			echo "[giipAgent3.sh] ✅ [5.2.4] auto-discover-linux.sh completed successfully (exit_code: $auto_discover_exit_code)" >&2
			echo "[giipAgent3.sh] 🕒 [5.2.5] Execution ended at: ${execute_end_time}" >&2
			
			# 결과 파일 크기 확인
			result_size=$(wc -c < "$auto_discover_result_file" 2>/dev/null || echo "0")
			echo "[giipAgent3.sh] 📊 [5.2.6] Result file size: ${result_size} bytes" >&2
			
			# 결과 파일이 있으면 DB에 저장
			if [ -s "$auto_discover_result_file" ]; then
				# 결과를 읽고 KVS에 저장
				auto_discover_json=$(cat "$auto_discover_result_file")
				
				# [로깅 #6] 결과 저장
				kvs_put "lssn" "${lssn}" "auto_discover_result" "{\"status\":\"success\",\"result_size\":${result_size},\"sample\":\"$(echo "$auto_discover_json" | head -c 100 | tr '\n' ' ')...\"}"
				echo "[giipAgent3.sh] 💾 [5.2.7] auto-discover result saved to KVS" >&2
				
				# 상세 결과 로그 저장 (첫 500자)
				auto_discover_summary=$(echo "$auto_discover_json" | head -c 500)
				kvs_put "lssn" "${lssn}" "auto_discover_full_result" "$auto_discover_json"
				echo "[giipAgent3.sh] 📝 [5.2.8] auto-discover full result saved" >&2
			else
				echo "[giipAgent3.sh] ⚠️ [5.2.7] Result file is empty" >&2
				kvs_put "lssn" "${lssn}" "auto_discover_result" "{\"status\":\"empty_result\",\"reason\":\"no_output\"}"
			fi
		else
			auto_discover_exit_code=$?
			execute_end_time=$(date '+%Y-%m-%d %H:%M:%S')
			
			# [로깅 #7] auto-discover 실패
			if [ $auto_discover_exit_code -eq 124 ]; then
				echo "[giipAgent3.sh] ❌ [5.2.4] auto-discover-linux.sh TIMEOUT (timeout after ${timeout_seconds}s)" >&2
				kvs_put "lssn" "${lssn}" "auto_discover_result" "{\"status\":\"timeout\",\"timeout_seconds\":${timeout_seconds},\"end_time\":\"${execute_end_time}\"}"
			else
				echo "[giipAgent3.sh] ❌ [5.2.4] auto-discover-linux.sh failed with exit_code: $auto_discover_exit_code" >&2
				kvs_put "lssn" "${lssn}" "auto_discover_result" "{\"status\":\"failed\",\"exit_code\":${auto_discover_exit_code},\"end_time\":\"${execute_end_time}\"}"
			fi
			
			# 에러 로그 캡처
			if [ -s "$auto_discover_log_file" ]; then
				error_log_lines=$(wc -l < "$auto_discover_log_file")
				error_log_preview=$(head -c 500 "$auto_discover_log_file")
				echo "[giipAgent3.sh] 📋 [5.2.5] Error log (${error_log_lines} lines): $error_log_preview" >&2
				kvs_put "lssn" "${lssn}" "auto_discover_error_log" "{\"error_lines\":${error_log_lines},\"preview\":\"$(echo "$error_log_preview" | tr '\n' '|' | head -c 200)\"}"
			fi
		fi
		
		# 임시 파일 정리
		rm -f "$auto_discover_result_file" "$auto_discover_log_file"
		echo "[giipAgent3.sh] 🧹 [5.2.9] Temporary files cleaned up" >&2
	fi
	
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

log_message "INFO" "GIIP Agent V${sv} completed"
exit 0
