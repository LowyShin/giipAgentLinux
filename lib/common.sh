#!/bin/bash
# giipAgentLinux Library: Common Functions
# Purpose: Core functions for Logging, Configuration and Communication
# ============================================================================
# 👉 MANDATORY: Read SPEC_AGENT_API_INTEGRITY_MANDATE.md before modification.
# Agent MUST protect API (Sk2/Sk3) integrity by ensuring valid data transmission.
# ============================================================================

# ============================================================================
# Configuration Functions
# ============================================================================

# Function: Load configuration file
load_config() {
	local config_file="${1:-../giipAgent.cnf}"
	
	if [ ! -f "$config_file" ]; then
		echo "❌ Error: Configuration file not found: $config_file"
		return 1
	fi
	
	# Source configuration
	. "$config_file"
	
	# lssn 정규화: CRLF 로 저장된 cnf 를 source 하면 값 끝에 \r 이 붙어
	# [ "$lssn" = "0" ] 비교가 실패한다. 앞뒤 공백/CR 을 제거한다.
	lssn="${lssn//$'\r'/}"
	lssn="${lssn//[[:space:]]/}"
	
	# lssn 사이드카 (giipAgent.lssn): cnf 가 읽기전용(예: Docker :ro bind mount)이라
	# 자동등록으로 발급된 lssn 을 cnf 에 쓰지 못했을 때 persist_lssn() 이 cnf 옆에 남긴다.
	# cnf 의 lssn 이 0/빈값이고 사이드카에 양의 정수가 있으면 그것을 쓴다 — 이게 없으면
	# 매 실행마다 재등록되어 tLSvr 행이 계속 늘어난다.
	if [ -z "${lssn}" ] || [ "${lssn}" = "0" ]; then
		local sidecar_lssn
		sidecar_lssn=$(read_lssn_sidecar "$config_file")
		if [ -n "$sidecar_lssn" ]; then
			lssn="$sidecar_lssn"
			echo "[load_config] ℹ️  cnf lssn is 0/empty; using lssn=${lssn} from sidecar $(lssn_sidecar_path "$config_file")" >&2
		fi
	fi
	
	# Set defaults if not defined
	if [ "${giipagentdelay}" = "" ]; then
		giipagentdelay="60"
	fi
	
	if [ "${gateway_mode}" = "" ]; then
		gateway_mode="0"
	fi
	
	if [ "${gateway_heartbeat_interval}" = "" ]; then
		gateway_heartbeat_interval="300"  # Default: 5 minutes
	fi
	
	# Note: gateway_serverlist and gateway_db_querylist are NOT used
	# Per GATEWAY_CONFIG_PHILOSOPHY.md: Database as Single Source of Truth
	# - NO CSV files (always query DB directly)
	# - Use temp files only, delete immediately after processing
	
	# Validate required variables
	if [ -z "${lssn}" ] || [ -z "${sk}" ] || [ -z "${apiaddrv2}" ]; then
		echo "❌ Error: Missing required configuration (lssn, sk, apiaddrv2)"
		return 1
	fi
	
	# Export critical configuration variables for sub-shells and metrics collection scripts
	export lssn
	export sk
	export apiaddrv2
	export gateway_mode
	
	return 0
}

# ============================================================================
# LSSN Persistence Functions (lssn=0 자동등록 결과 저장)
# ============================================================================
# 배경: lssn=0 으로 설치하면 첫 실행 시 CQEQueueGet 이 tLSvr 에 서버를 등록하고
# 새 lssn 을 돌려준다. 그 값을 cnf 에 저장하지 못하면 다음 실행에서 또 등록되어
# tLSvr 행이 무한히 늘어난다. 기존 `sed -i` 방식은
#   - Docker 단일파일 bind mount 에서 rename 이 EBUSY 로 실패하고
#   - 정확히 lssn="0" 만 매칭(lssn=0, lssn='0', CRLF 미매칭)하며
#   - 아무것도 안 바뀌어도 exit 0 이라 성공으로 오인 로그를 남겼다.
# 아래 함수들은 임시파일에 새 내용을 만든 뒤 `cat tmp > cnf` 로 덮어써 inode 를
# 유지(bind mount 에서도 동작)하고, 다시 읽어 검증한다.

# Function: Path of the lssn sidecar file (same directory as the cnf)
# Usage: lssn_sidecar_path "$config_file"
lssn_sidecar_path() {
	local config_file="$1"
	echo "$(dirname "$config_file")/giipAgent.lssn"
}

# Function: Read lssn value from a cnf file without sourcing it
# Accepts lssn=N, lssn="N", lssn='N', surrounding spaces, CRLF. Last match wins
# (same as shell source semantics).
# Usage: read_lssn_from_file "$config_file"   → echoes value (may be empty)
read_lssn_from_file() {
	local config_file="$1"
	[ -f "$config_file" ] || return 1
	grep -E '^[[:space:]]*lssn[[:space:]]*=' "$config_file" 2>/dev/null | tail -1 \
		| tr -d '\r' \
		| sed -e 's/^[[:space:]]*lssn[[:space:]]*=[[:space:]]*//' -e 's/[[:space:]]#.*$//' -e 's/[[:space:]]*$//' \
		| tr -d "\"'"
}

# Function: Read a positive integer lssn from the sidecar (empty if absent/invalid)
# Usage: read_lssn_sidecar "$config_file"
read_lssn_sidecar() {
	local sidecar
	sidecar=$(lssn_sidecar_path "$1")
	[ -f "$sidecar" ] || return 0
	local v
	v=$(head -1 "$sidecar" 2>/dev/null | tr -d "\r[:space:]\"'")
	if [[ "$v" =~ ^[0-9]+$ ]] && [ "$v" -gt 0 ]; then
		echo "$v"
	fi
}

# Function: Overwrite a file's content in place (keeps inode; works on single-file
# bind mounts where rename-based `sed -i` fails with EBUSY).
# Separate function so tests can stub it to simulate a read-only cnf.
# Usage: write_file_inplace "$src_tmp" "$dest"
write_file_inplace() {
	cat "$1" > "$2" 2>/dev/null
}

# Function: Persist a newly issued lssn
# Usage: persist_lssn "$config_file" "$new_lssn"
# Returns: 0 = cnf updated and verified
#          2 = cnf not writable, lssn written to sidecar (giipAgent.lssn) instead
#          1 = failed (invalid lssn, or neither cnf nor sidecar could be written)
persist_lssn() {
	local config_file="$1"
	local new_lssn="$2"
	
	if ! [[ "$new_lssn" =~ ^[0-9]+$ ]] || [ "$new_lssn" -le 0 ]; then
		log_message "ERROR" "persist_lssn: refusing invalid lssn '${new_lssn}'"
		return 1
	fi
	if [ ! -f "$config_file" ]; then
		log_message "ERROR" "persist_lssn: config file not found: ${config_file}"
		return 1
	fi
	
	local tmp_new tmp_bak
	tmp_new=$(mktemp "${TMPDIR:-/tmp}/giipAgent_cnf_new.XXXXXX") || return 1
	tmp_bak=$(mktemp "${TMPDIR:-/tmp}/giipAgent_cnf_bak.XXXXXX") || { rm -f "$tmp_new"; return 1; }
	cp "$config_file" "$tmp_bak" 2>/dev/null
	
	# 모든 lssn= 줄을 lssn="N" 으로 치환 (따옴표/공백 무관, 줄 끝 CR 은 보존).
	# lssn= 줄이 없으면 끝에 추가한다.
	awk -v v="$new_lssn" '
		{
			line = $0; cr = ""
			if (sub(/\r$/, "", line)) cr = "\r"
			if (line ~ /^[[:space:]]*lssn[[:space:]]*=/) { print "lssn=\"" v "\"" cr; done = 1; next }
			print $0
		}
		END { if (!done) print "lssn=\"" v "\"" }
	' "$config_file" > "$tmp_new"
	
	local rc=1
	if [ -s "$tmp_new" ] && write_file_inplace "$tmp_new" "$config_file" \
		&& [ "$(read_lssn_from_file "$config_file")" = "$new_lssn" ]; then
		log_message "INFO" "Configuration updated with LSSN: ${new_lssn} (${config_file})"
		rc=0
	else
		# 부분 기록 등으로 원본이 바뀌었으면 백업으로 복구 시도 (sk 등 다른 설정 보호)
		if [ -s "$tmp_bak" ] && ! cmp -s "$tmp_bak" "$config_file"; then
			write_file_inplace "$tmp_bak" "$config_file"
		fi
		local sidecar
		sidecar=$(lssn_sidecar_path "$config_file")
		if printf '%s\n' "$new_lssn" > "$sidecar" 2>/dev/null && [ "$(read_lssn_sidecar "$config_file")" = "$new_lssn" ]; then
			log_message "ERROR" "Cannot write ${config_file} (read-only?). LSSN ${new_lssn} saved to sidecar ${sidecar}. Please set lssn=\"${new_lssn}\" in the cnf."
			rc=2
		else
			log_message "ERROR" "Cannot write ${config_file} nor sidecar ${sidecar}. Please set lssn=\"${new_lssn}\" in the cnf manually."
			rc=1
		fi
	fi
	
	rm -f "$tmp_new" "$tmp_bak"
	return $rc
}

# ============================================================================
# Logging Functions
# ============================================================================

# Function: Log message with timestamp
# Usage: log_message "INFO" "Message text"
log_message() {
	local level="$1"
	local message="$2"
	local timestamp=$(date '+%Y%m%d%H%M%S')
	
	# Log to file if LogFileName is set
	if [ -n "$LogFileName" ]; then
		echo "[$timestamp] [$level] $message" >> "$LogFileName"
	fi
	
	# Also print to console for important messages
	# giip #1551: 코드베이스 전체가 "WARN"만 쓰고 "WARNING"은 한 번도 안 쓰는데(실측:
	# grep 31건 vs 0건) 이 조건이 "WARNING"만 걸러서 WARN 레벨 로그가 콘솔/stderr에
	# 전혀 안 찍히고 있었다 — cctrank03 net3d_mode.sh 진단 시 이 때문에 실제 실패 원인
	# (server_info.sh의 WARN 로그)이 안 보여 진단이 어려웠다.
	if [ "$level" = "ERROR" ] || [ "$level" = "WARN" ] || [ "$level" = "WARNING" ]; then
		echo "[$timestamp] [$level] $message" >&2
	fi
}

# Function: Log error to database via ErrorLogCreate API
# Usage: log_error "Error message" "ErrorType" "stack_trace"
log_error() {
	local error_message="$1"
	local error_type="${2:-ScriptError}"
	local stack_trace="${3:-}"
	
	# Validate required variables
	if [ -z "$sk" ] || [ -z "$apiaddrv2" ]; then
		echo "[Error-Log] ⚠️  Cannot log error: missing sk or apiaddrv2" >&2
		return 1
	fi
	
	local api_url="${apiaddrv2}"
	
	local hostname=$(hostname)
	local source="giipAgent"
	
	# Build jsondata
	# giip #2928: Use jq for proper JSON serialization to prevent malformed JSON on special characters
	local jsondata
	jsondata=$(jq -n \
		--arg source "$source" \
		--arg errorMessage "$error_message" \
		--arg errorType "$error_type" \
		--arg stackTrace "$stack_trace" \
		--arg hostname "$hostname" \
		--argjson lssn "${lssn:-0}" \
		'{source: $source, errorMessage: $errorMessage, errorType: $errorType, stackTrace: $stackTrace, lssn: $lssn, hostname: $hostname, severity: "error"}')
	
	# Call ErrorLogCreate API
	local text="ErrorLogCreate source errorMessage"
	
	wget -O /dev/null \
		--post-data="text=${text}&token=${sk}&jsondata=${jsondata}" \
		--header="Content-Type: application/x-www-form-urlencoded" \
		"${api_url}" \
		--no-check-certificate -q 2>&1
	
	local exit_code=$?
	if [ $exit_code -eq 0 ]; then
		echo "[Error-Log] ✅ Error logged to database" >&2
	else
		echo "[Error-Log] ⚠️  Failed to log error to database (exit_code=${exit_code})" >&2
	fi
	
	return $exit_code
}

# ============================================================================
# Dependency Check Functions
# ============================================================================

# Function: Check and install dos2unix
check_dos2unix() {
	local CHECK_Converter=`which dos2unix`
	local RESULT=$?
	
	if [ ${RESULT} -eq 0 ]; then
		return 0
	fi
	
	log_message "INFO" "dos2unix not found, installing..."
	
	# Detect OS
	local uname=`uname -a | awk '{print $1}'`
	
	if [ "${uname}" = "Darwin" ]; then
		brew install dos2unix
	else
		local ostype=`head -n 1 /etc/issue | awk '{print $1}'`
		if [ "${ostype}" = "Ubuntu" ]; then
			apt-get install -y dos2unix
		else
			yum install -y dos2unix
		fi
	fi
	
	return $?
}

# Function: Check and install mssql-tools
check_mssql_tools() {
	if command -v sqlcmd >/dev/null 2>&1; then
		return 0
	fi
	
	# Detect OS
	local uname=`uname -a | awk '{print $1}'`
	
	if [ "${uname}" = "Linux" ]; then
		if [ -f /etc/redhat-release ]; then
			# RHEL/CentOS
			# Check if already installed via rpm to avoid yum spam
			if rpm -q mssql-tools >/dev/null 2>&1; then
				# Installed but not in path?
				if [ -d "/opt/mssql-tools/bin" ]; then
					export PATH="$PATH:/opt/mssql-tools/bin"
					if command -v sqlcmd >/dev/null 2>&1; then
						return 0
					fi
				fi
			fi

			log_message "INFO" "sqlcmd not found, attempting to install mssql-tools..."
			
			curl https://packages.microsoft.com/config/rhel/7/prod.repo > /etc/yum.repos.d/msprod.repo
			yum remove -y unixODBC-utf16 unixODBC-utf16-devel
			ACCEPT_EULA=Y yum install -y mssql-tools unixODBC-devel
		elif [ -f /etc/lsb-release ] || [ -f /etc/debian_version ]; then
			# Ubuntu/Debian logic omitted
			:
		fi
	fi
	
	# Add to PATH
	if [ -d "/opt/mssql-tools/bin" ]; then
		export PATH="$PATH:/opt/mssql-tools/bin"
	fi
	
	if command -v sqlcmd >/dev/null 2>&1; then
		log_message "INFO" "mssql-tools installed successfully"
		return 0
	else
		log_message "WARN" "Failed to install mssql-tools automatically"
		return 1
	fi
}

# Function: Check and install jq
check_jq() {
	if command -v jq >/dev/null 2>&1; then
		return 0
	fi
	
	log_message "INFO" "jq not found, attempting to install..."
	
	# Detect OS
	local uname=`uname -a | awk '{print $1}'`
	
	if [ "${uname}" = "Darwin" ]; then
		brew install jq
	else
		# Linux - check package manager
		if command -v apt-get >/dev/null 2>&1; then
			apt-get update -q && apt-get install -y -q jq
		elif command -v yum >/dev/null 2>&1; then
			# yum requires epel-release for jq on some RHEL/CentOS versions
			yum install -y -q epel-release 2>/dev/null || true
			yum install -y -q jq
		elif command -v dnf >/dev/null 2>&1; then
			dnf install -y -q jq
		else
			log_message "WARN" "No known package manager found to install jq"
			return 1
		fi
	fi
	
	if command -v jq >/dev/null 2>&1; then
		log_message "INFO" "jq installed successfully"
		return 0
	else
		log_message "WARN" "Failed to install jq automatically"
		return 1
	fi
}

# Function: Detect OS information
detect_os() {
	local uname=`uname -a | awk '{print $1}'`
	
	if [ "${uname}" = "Darwin" ]; then
		local osname=`sw_vers -productName`
		local osver=`sw_vers -productVersion`
		os="${osname} ${osver}"
	else
		local ostype=`head -n 1 /etc/issue | awk '{print $1}'`
		if [ "${ostype}" = "Ubuntu" ]; then
			os=`lsb_release -d | sed 's/^ *\| *$//' | sed -e "s/Description\://g"`
		else
			os=`cat /etc/redhat-release`
		fi
	fi
	
	# URL encode spaces
	os=`echo "$os" | sed 's/^ *\| *$//' | sed -e "s/ /%20/g"`
	
	echo "$os"
}

# Function: Get CPU usage percentage
# Returns: Integer percentage (0-100)
get_cpu_usage() {
	local cpu_usage=0
	if command -v top >/dev/null 2>&1; then
		# top -bn1 gives a single snapshot; extract the idle field robustly
		# When idle=100.0, top omits the leading space: "ni,100.0 id" (not "ni, 100.0 id")
		# so positional awk field extraction is unreliable - use grep -oE instead
		local idle=$(top -bn1 | grep "Cpu(s)" | grep -oE '[0-9]+[.,][0-9]+ *id|[0-9]+ *id' | head -1 | grep -oE '[0-9]+' | head -1)
		if [ -n "$idle" ] && [[ "$idle" =~ ^[0-9]+$ ]]; then
			cpu_usage=$((100 - idle))
		fi
	elif [ -f /proc/stat ]; then
		# Fallback: parse /proc/stat
		# cpu  user nice system idle iowait irq softirq steal guest guest_nice
		local line=$(grep '^cpu ' /proc/stat)
		local user=$(echo "$line" | awk '{print $2}')
		local nice=$(echo "$line" | awk '{print $3}')
		local system=$(echo "$line" | awk '{print $4}')
		local idle=$(echo "$line" | awk '{print $5}')
		local iowait=$(echo "$line" | awk '{print $6}')
		local irq=$(echo "$line" | awk '{print $7}')
		local softirq=$(echo "$line" | awk '{print $8}')
		local steal=$(echo "$line" | awk '{print $9}')
		
		local total=$((user + nice + system + idle + iowait + irq + softirq + steal))
		local active=$((user + nice + system + irq + softirq + steal))
		
		cpu_usage=$((active * 100 / total))
	fi
	echo "$cpu_usage"
}

# Function: Get Memory usage percentage
# Returns: Integer percentage (0-100)
get_mem_usage() {
	local mem_usage=0
	if command -v free >/dev/null 2>&1; then
		# free -m | grep Mem: | awk '{print $3/$2 * 100.0}'
		local used=$(free -m | grep Mem: | awk '{print $3}')
		local total=$(free -m | grep Mem: | awk '{print $2}')
		if [ -n "$used" ] && [ -n "$total" ] && [ "$total" -gt 0 ]; then
			mem_usage=$((used * 100 / total))
		fi
	elif [ -f /proc/meminfo ]; then
		local total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
		local free=$(grep MemFree /proc/meminfo | awk '{print $2}')
		local buffers=$(grep Buffers /proc/meminfo | awk '{print $2}')
		local cached=$(grep ^Cached /proc/meminfo | awk '{print $2}')
		if [ -n "$total" ] && [ -n "$free" ]; then
			local used=$((total - free - buffers - cached))
			mem_usage=$((used * 100 / total))
		fi
	fi
	echo "$mem_usage"
}

# ============================================================================
# Error Handling Functions
# ============================================================================

# Function: Error handler
# Usage: error_handler "Error message" exit_code
error_handler() {
	local error_msg="$1"
	local exit_code="${2:-1}"
	
	log_message "ERROR" "$error_msg"
	
	# Save error to KVS if save_execution_log is available
	if command -v save_execution_log &> /dev/null; then
		local error_details="{\"error_type\":\"general_error\",\"error_message\":\"${error_msg}\",\"error_code\":${exit_code}}"
		save_execution_log "error" "$error_details"
	fi
	
	exit ${exit_code}
}

# ============================================================================
# Log Directory Setup
# ============================================================================

# Function: Initialize log directory and file
# Usage: init_log_dir [script_dir]
init_log_dir() {
	local script_dir="${1:-.}"
	local today=$(date '+%Y%m%d')
	
	LOG_DIR="${script_dir}/log"
	mkdir -p "$LOG_DIR"
	
	LogFileName="${LOG_DIR}/giipAgent2_${today}.log"
	
	export LOG_DIR
	export LogFileName
}

# ============================================================================
# API Helper Functions
# ============================================================================

# Function: Build API URL (now just returns base_url, code parameter deprecated)
# Usage: build_api_url "$apiaddrv2"
build_api_url() {
	local base_url="$1"
	# Second parameter (code) is deprecated and ignored
	
	echo "${base_url}"
}

# ============================================================================
# Auto-Discover Logging Functions (단계별 상세 진단)
# ============================================================================

# Function: Log auto-discover step with KVS storage
# Usage: log_auto_discover_step <step_num> <step_name> <kfactor> <json_data>
# Example: log_auto_discover_step "STEP-1" "Config Check" "auto_discover_config_check" "{...}"
log_auto_discover_step() {
	local step_num="$1"
	local step_name="$2"
	local kfactor="$3"
	local json_data="$4"
	local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
	
	# Console logging (with timestamp and step number)
	echo "[AUTO-DISCOVER] ${step_num} ${timestamp} 🔍 ${step_name}" >&2
	
	# KVS logging (if variables are available)
	if [ -n "${lssn}" ] && [ -n "${sk}" ] && [ -n "${apiaddrv2}" ]; then
		# Wrap json_data with timestamp and step info if not already wrapped
		local wrapped_data="{\"step\":\"${step_num}\",\"name\":\"${step_name}\",\"timestamp\":\"${timestamp}\",\"data\":${json_data}}"
		
		# DEBUG: Log parameters
		echo "[AUTO-DISCOVER] ${step_num} DEBUG: lssn=${lssn}, sk_length=${#sk}, kfactor=${kfactor}, data_length=${#json_data}" >&2
		
		# Call kvs_put and capture output
		local kvs_output=$(kvs_put "lssn" "${lssn}" "${kfactor}" "${wrapped_data}" 2>&1)
		local kvs_exit_code=$?
		
		# Log the result
		echo "[AUTO-DISCOVER] ${step_num} kvs_put result: exit_code=${kvs_exit_code}" >&2
		echo "[AUTO-DISCOVER] ${step_num} kvs_put output:" >&2
		echo "$kvs_output" | sed 's/^/  [AUTO-DISCOVER] /' >&2
		
		if [ $kvs_exit_code -eq 0 ]; then
			echo "[AUTO-DISCOVER] ${step_num} ✅ kvs_put SUCCESS for kFactor=${kfactor}" >&2
		else
			echo "[AUTO-DISCOVER] ${step_num} ❌ kvs_put FAILED with exit_code=${kvs_exit_code} for kFactor=${kfactor}" >&2
		fi
	else
		echo "[AUTO-DISCOVER] ${step_num} ⚠️  WARNING: Missing required variables (lssn=${lssn}, sk_length=${#sk}, apiaddrv2_length=${#apiaddrv2})" >&2
	fi
}

# Function: Log auto-discover error with detailed context
# Usage: log_auto_discover_error <step_num> <error_type> <error_msg> <context_json>
# Example: log_auto_discover_error "STEP-2" "kvs_put_failed" "Connection timeout" "{\"url\":\"...\",\"timeout\":30}"
log_auto_discover_error() {
	local step_num="$1"
	local error_type="$2"
	local error_msg="$3"
	local context_json="$4"
	local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
	
	# Console logging (prominent error marker)
	echo "[AUTO-DISCOVER] ${step_num} ${timestamp} ❌ ERROR: ${error_type}" >&2
	echo "[AUTO-DISCOVER] ${step_num} ${timestamp} 📝 Message: ${error_msg}" >&2
	echo "[AUTO-DISCOVER] ${step_num} ${timestamp} 🔧 Context: ${context_json}" >&2
	
	# KVS logging to error_log kfactor
	if [ -n "${lssn}" ] && [ -n "${sk}" ] && [ -n "${apiaddrv2}" ]; then
		local error_data="{\"step\":\"${step_num}\",\"type\":\"${error_type}\",\"message\":\"${error_msg}\",\"timestamp\":\"${timestamp}\",\"context\":${context_json}}"
		kvs_put "lssn" "${lssn}" "auto_discover_error_log" "${error_data}" 2>&1
	fi
}

# Function: Log auto-discover validation result
# Usage: log_auto_discover_validation <step_num> <check_name> <result> <detail_json>
# Example: log_auto_discover_validation "STEP-1" "sk_variable" "PASS" "{\"length\":32}"
log_auto_discover_validation() {
	local step_num="$1"
	local check_name="$2"
	local result="$3"  # PASS or FAIL
	local detail_json="$4"
	local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
	local icon="✅"
	
	if [ "$result" = "FAIL" ]; then
		icon="❌"
	fi
	
	# Console logging
	echo "[AUTO-DISCOVER] ${step_num} ${timestamp} ${icon} Validation: ${check_name} = ${result}" >&2
	
	# Log details if provided
	if [ -n "${detail_json}" ]; then
		echo "[AUTO-DISCOVER] ${step_num} ${timestamp}    Details: ${detail_json}" >&2
	fi
}

# ============================================================================
# Export Functions
# ============================================================================

# Export functions for use in other scripts
export -f load_config
export -f log_message
export -f check_dos2unix
export -f check_mssql_tools
export -f check_jq
export -f detect_os
export -f error_handler
export -f init_log_dir
export -f build_api_url
export -f log_auto_discover_step
export -f log_auto_discover_error
export -f log_auto_discover_validation
export -f get_cpu_usage
export -f get_mem_usage

