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

# ============================================================================
# Initialize Logging
# ============================================================================

# Detect OS
os=$(detect_os)

# Setup log directory
init_log_dir "$SCRIPT_DIR"

# Get hostname
hn=$(hostname)

# Log startup
logdt=$(date '+%Y%m%d%H%M%S')
log_message "INFO" "========================================"
log_message "INFO" "Starting GIIP Agent V${sv}"
log_message "INFO" "LSSN: ${lssn}, Hostname: ${hn}"
log_message "INFO" "Mode: $([ "$gateway_mode" = "1" ] && echo "GATEWAY" || echo "NORMAL")"
log_message "INFO" "========================================"

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
	
	log_message "INFO" "Running in GATEWAY MODE"
	
	# Load gateway and db_clients libraries
	. "${LIB_DIR}/db_clients.sh"
	. "${LIB_DIR}/gateway.sh"
	
	# Initialize Gateway
	startup_status="{\"status\":\"started\",\"version\":\"${sv}\",\"lssn\":${lssn},\"timestamp\":\"$(date '+%Y-%m-%d %H:%M:%S')\",\"mode\":\"gateway\",\"is_gateway\":1}"
	save_gateway_status "startup" "$startup_status"
	
	init_details="{\"config_file\":\"giipAgent.cnf\",\"api_endpoint\":\"${apiaddrv2}\",\"pid\":$$,\"is_gateway\":1}"
	save_execution_log "startup" "$init_details"
	
	# Check and install dependencies
	check_sshpass || error_handler "Failed to setup sshpass" 1
	check_db_clients
	
	# Initial sync from API
	log_message "INFO" "Fetching initial server list from Web UI..."
	sync_gateway_servers
	sync_db_queries
	
	# Count servers
	server_count=0
	if [ -f "${gateway_serverlist}" ]; then
		server_count=$(grep -v "^#" "${gateway_serverlist}" | grep -v "^$" | wc -l)
		log_message "INFO" "Found ${server_count} servers to manage"
	fi
	
	# Save initialization complete
	init_complete_details="{\"server_sync_status\":\"success\",\"server_count\":${server_count}}"
	save_execution_log "gateway_init" "$init_complete_details"
	
	# Gateway main loop
	last_sync_time=$(date +%s)
	cntgiip=1
	
	while [ ${cntgiip} -le 3 ]; do
		# Check if we need to re-sync
		if [ "${gateway_sync_interval}" != "0" ]; then
			current_time=$(date +%s)
			time_diff=$((current_time - last_sync_time))
			
			if [ $time_diff -ge ${gateway_sync_interval} ]; then
				log_message "INFO" "Auto-refreshing server list..."
				sync_gateway_servers
				sync_db_queries
				last_sync_time=$current_time
			fi
		fi
		
		# Process gateway servers
		if [ -f "${gateway_serverlist}" ]; then
			process_gateway_servers
		fi
		
		# Sleep before next cycle
		log_message "INFO" "Sleeping ${giipagentdelay} seconds..."
		sleep $giipagentdelay
		
		# Re-check process count
		cntgiip=$(ps aux | grep giipAgent3.sh | grep -v grep | wc -l)
	done
	
	log_message "INFO" "Gateway mode terminated"
	
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
