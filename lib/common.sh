#!/bin/bash
# giipAgent Common Functions Library
# Version: 2.00
# Date: 2025-01-10
# Purpose: Common utilities for giipAgent (config loading, logging, error handling)

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
	
	return 0
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
	if [ "$level" = "ERROR" ] || [ "$level" = "WARNING" ]; then
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
	[ -n "$apiaddrcode" ] && api_url="${api_url}?code=${apiaddrcode}"
	
	local hostname=$(hostname)
	local source="giipAgent"
	
	# Build jsondata
	local jsondata="{\"source\":\"${source}\",\"errorMessage\":\"${error_message}\",\"errorType\":\"${error_type}\",\"stackTrace\":\"${stack_trace}\",\"lssn\":${lssn:-0},\"hostname\":\"${hostname}\",\"severity\":\"error\"}"
	
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

# Function: Build API URL with code parameter
# Usage: build_api_url "$apiaddrv2" "$apiaddrcode"
build_api_url() {
	local base_url="$1"
	local code="$2"
	
	if [ -n "$code" ]; then
		echo "${base_url}?code=${code}"
	else
		echo "${base_url}"
	fi
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
export -f detect_os
export -f error_handler
export -f init_log_dir
export -f build_api_url
export -f log_auto_discover_step
export -f log_auto_discover_error
export -f log_auto_discover_validation

