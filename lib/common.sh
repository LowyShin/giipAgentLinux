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
