#!/bin/bash
################################################################################
# Temporary Files Cleanup Module
# Purpose: Clean up old GIIP temporary files from previous executions
# Author: GIIP Agent
# Version: 1.0
# Date: 2025-11-27
#
# Usage:
#   . "${LIB_DIR}/cleanup.sh"
#   cleanup_all_temp_files
#
# This module provides:
#   - cleanup_old_temp_files: Delete old files matching pattern
#   - cleanup_all_temp_files: Clean all old GIIP temp files
################################################################################

# Function to safely delete old files (not from current process)
cleanup_old_temp_files() {
	local pattern=$1
	local count=0
	for file in /tmp/${pattern}; do
		if [ -f "$file" ] && [ -s "$file" ]; then
			# Extract the PID from the filename (assumes format: prefix_${PID}.ext)
			local file_pid=$(echo "$file" | sed -E 's/.*_([0-9]+)\.(log|json|txt|sh)$/\1/')
			# Only delete if PID doesn't match current process and file is NOT empty
			if [ "$file_pid" != "$current_pid" ] && [ "$file_pid" != "${pattern}" ]; then
				rm -f "$file" 2>/dev/null && ((count++))
			fi
		fi
	done
	[ $count -gt 0 ] && echo "[cleanup] ✓ Cleaned up $count old ${pattern} files"
}

# Main cleanup function for all GIIP temporary files
cleanup_all_temp_files() {
	echo "[cleanup] 🟢 Cleaning up old GIIP temporary files from previous executions..."
	
	# Get current process ID
	current_pid=$$
	
	# Clean up old discovery files
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
	
	# Clean up gateway-related temporary files
	cleanup_old_temp_files "gateway_servers_*.json"
	cleanup_old_temp_files "gateway_self_queue_*.sh"
	cleanup_old_temp_files "giipAgent_gateway_*"
	
	# Clean up SSH test temporary files
	cleanup_old_temp_files "servers_to_test_*.jsonl"
	
	# Clean up queue_get test temporary files and directories
	if [ -d "/tmp/queue_get_test" ]; then
		rm -f /tmp/queue_get_test/* 2>/dev/null
		echo "[cleanup] ✓ Cleaned up queue_get test files"
	fi
	
	echo "[cleanup] ✓ Old temporary files cleanup completed"
}

################################################################################
# Export functions for use in other scripts
################################################################################

export -f cleanup_old_temp_files
export -f cleanup_all_temp_files
