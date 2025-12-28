#!/bin/bash
# giipAgent Ver. 3.0 (Refactored)
sv="3.00"
# Written by Lowy Shin at 20140922
# Updated to modular architecture at 2025-01-10
# Supported OS : MacOS, CentOS, Ubuntu, Some Linux
# 20251104 Lowy, Add Gateway mode support with auto-dependency installation
# 20250110 Lowy, Refactor to modular architecture (lib/*.sh)

# ============================================================================
# ⭐ UTF-8 환경 강제 설정 (최우선!)
# ============================================================================
# 목적: 일본어/한글 로케일 환경에서 Python 인라인 코드 파싱 에러 방지
# 이슈: CentOS 7.4 일본어 환경에서 멀티바이트 문자 깨짐 문제 해결
# 날짜: 2025-12-28
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8


# Usable giip variables =========
# {{today}} : Replace today to "YYYYMMDD"

# ============================================================================
# Self-Cleanup / Singleton Logic
# ============================================================================
# Automatically kill previous instances of this specific script to prevent duplicates/loops.
# We match by the absolute path of the script to avoid killing other agents.

CURRENT_PID=$$
SCRIPT_ABS_PATH=$(readlink -f "${BASH_SOURCE[0]}")

# Strict Singleton Pattern: If another instance is running, WE EXIT.
# Do NOT kill the existing process, as that causes race conditions and infinite restart loops.

if pgrep -f "bash $SCRIPT_ABS_PATH" | grep -v "$CURRENT_PID" > /dev/null; then
    echo "⚠️  [$(date)] Another instance of $SCRIPT_ABS_PATH is already running. Exiting to prevent overlap."
    exit 0
fi


SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="${SCRIPT_DIR}/lib"

# ============================================================================
# Auto-Fix CRLF Line Endings (Windows → Linux)
# ============================================================================
# Windows에서 Git pull 시 CRLF가 포함될 수 있으므로 자동 변환
# 날짜: 2025-12-28
# 목적: Linux 환경에서 "$'\r': command not found" 에러 방지

CRLF_FILES=(
    "${LIB_DIR}/net3d.sh"
    "${LIB_DIR}/parse_ss.py"
    "${LIB_DIR}/parse_netstat.py"
)

for file in "${CRLF_FILES[@]}"; do
    if [ -f "$file" ]; then
        # Check if file has CRLF
        if file "$file" 2>/dev/null | grep -q "CRLF"; then
            echo "🔧 Converting CRLF → LF: $file"
            
            # Try dos2unix first (most reliable)
            if command -v dos2unix >/dev/null 2>&1; then
                dos2unix "$file" 2>/dev/null
            # Fallback to sed
            elif command -v sed >/dev/null 2>&1; then
                sed -i 's/\r$//' "$file" 2>/dev/null
            # Fallback to tr
            elif command -v tr >/dev/null 2>&1; then
                tr -d '\r' < "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
            else
                echo "⚠️  Warning: Cannot convert CRLF for $file (no dos2unix/sed/tr found)"
            fi
        fi
    fi
done


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

# Load cleanup module
if [ -f "${LIB_DIR}/cleanup.sh" ]; then
	. "${LIB_DIR}/cleanup.sh"
else
	echo "❌ Error: cleanup.sh not found in ${LIB_DIR}"
	exit 1
fi

# Load target list module
if [ -f "${LIB_DIR}/target_list.sh" ]; then
	. "${LIB_DIR}/target_list.sh"
else
	echo "❌ Error: target_list.sh not found in ${LIB_DIR}"
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

# ============================================================================
# Early Cleanup: Remove old GIIP temporary files from previous executions
# ============================================================================

cleanup_all_temp_files
echo ""

# 🔴 [로깅 포인트 #5.1] Agent 시작
echo "[giipAgent3.sh] 🟢 [5.1] Agent 시작: version=${sv}"

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

curl -s -X POST "${api_url}" \
	-d "text=${config_text}&token=${sk}&jsondata=${config_jsondata}" \
	-H "Content-Type: application/x-www-form-urlencoded" \
	--insecure -o "$config_tmpfile" 2>&1

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
	fi
	
	# Method 2: If jq failed or not available, try sed/grep on normalized text
	if [ -z "$is_gateway_from_db" ]; then
		normalized=$(tr -d '\n\r' < "$config_tmpfile")
		is_gateway_from_db=$(echo "$normalized" | sed -n 's/.*"is_gateway"\s*:\s*\([^,}]*\).*/\1/p' | head -1 | tr -d ' ')
	fi
	
	# Method 3: If still empty, try grep with literal search
	if [ -z "$is_gateway_from_db" ]; then
		if grep -q '"is_gateway"\s*:\s*true' "$config_tmpfile" 2>/dev/null; then
			is_gateway_from_db="true"
		elif grep -q '"is_gateway"\s*:\s*false' "$config_tmpfile" 2>/dev/null; then
			is_gateway_from_db="false"
		elif grep -q '"is_gateway"\s*:\s*1' "$config_tmpfile" 2>/dev/null; then
			is_gateway_from_db="1"
		elif grep -q '"is_gateway"\s*:\s*0' "$config_tmpfile" 2>/dev/null; then
			is_gateway_from_db="0"
		fi
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
	
	if [ -n "$is_gateway_from_db" ]; then
		gateway_mode="$is_gateway_from_db"
		echo "✅ DB config loaded: is_gateway=${gateway_mode}"
		
		# 🔴 [로깅 포인트 #5.2] 설정 로드 완료
		echo "[giipAgent3.sh] 🟢 [5.2] 설정 로드 완료: lssn=${lssn}, hostname=${hn}, is_gateway=${gateway_mode}"
		
		kvs_put "lssn" "${lssn}" "api_lsvrgetconfig_success" "{\"is_gateway\":${gateway_mode},\"source\":\"db_api\"}"
	else
		echo "⚠️  Failed to parse is_gateway from DB, using default: gateway_mode=${gateway_mode}"
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
check_mssql_tools


# ============================================================================
# Handle Server Registration (LSSN=0)
# ============================================================================

if [ "${lssn}" = "0" ]; then
	log_message "INFO" "Server not registered, registering now..."
	
	local tmpFileName="giipTmpScript.sh"
	local lwAPIURL=$(build_api_url "${apiaddrv2}" "${apiaddrcode}")
	
	# Build JSON data (matching new API rules: text=parameter names, jsondata=actual values)
	local jsondata
	jsondata=$(echo "{\"lssn\":0,\"hostname\":\"${hn}\",\"os\":\"${os}\",\"op\":\"op\"}" | tr -d '\n ')
	
	curl -s -X POST "${lwAPIURL}" \
		-d "text=CQEQueueGet&token=${sk}&jsondata=${jsondata}" \
		-H "Content-Type: application/x-www-form-urlencoded" \
		--insecure -o $tmpFileName 2>&1
	
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

# Load Net3D module (Network Topology)
if [ -f "${LIB_DIR}/net3d.sh" ]; then
	. "${LIB_DIR}/net3d.sh"
	
	# Run Net3D collection (5 min interval handled inside)
	collect_net3d_data "${lssn}"
fi

# ============================================================================
# Mode Selection: Gateway or Normal
# ============================================================================

# Run gateway mode if enabled
if [ "${gateway_mode}" = "1" ]; then
	# ========================================================================
	# GATEWAY MODE - Execute external script
	# ========================================================================
	
	log_message "INFO" "Running in GATEWAY MODE"
	
	GATEWAY_MODE_SCRIPT="${SCRIPT_DIR}/scripts/gateway_mode.sh"
	if [ -f "$GATEWAY_MODE_SCRIPT" ]; then
		bash "$GATEWAY_MODE_SCRIPT" "${SCRIPT_DIR}/../giipAgent.cnf"
		GATEWAY_MODE_EXIT_CODE=$?
		log_message "INFO" "Gateway mode script completed with exit code: $GATEWAY_MODE_EXIT_CODE"
	else
		log_message "WARN" "gateway_mode.sh not found at $GATEWAY_MODE_SCRIPT, skipping gateway mode"
	fi
fi

# ========================================================================
# NORMAL MODE - Always executed
# ========================================================================

log_message "INFO" "Running in NORMAL MODE"

# Execute normal mode as external script
NORMAL_MODE_SCRIPT="${SCRIPT_DIR}/scripts/normal_mode.sh"
if [ -f "$NORMAL_MODE_SCRIPT" ]; then
	bash "$NORMAL_MODE_SCRIPT" "${SCRIPT_DIR}/../giipAgent.cnf"
	NORMAL_MODE_EXIT_CODE=$?
	log_message "INFO" "Normal mode script completed with exit code: $NORMAL_MODE_EXIT_CODE"
else
	log_message "WARN" "normal_mode.sh not found at $NORMAL_MODE_SCRIPT, skipping normal mode"
fi

# ============================================================================
# Shutdown Log and Completion
# ============================================================================

# Record execution shutdown log
save_execution_log "shutdown" "{\"mode\":\"$([ "$gateway_mode" = "1" ] && echo "gateway+normal" || echo "normal")\",\"status\":\"normal_exit\"}"

log_message "INFO" "GIIP Agent V${sv} completed"
exit 0
