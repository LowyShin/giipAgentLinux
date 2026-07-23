#!/bin/bash
# giipAgent System Info Collection Library
# Version: 1.00
# Date: 2026-01-28
# Purpose: Collect system information such as process list

# Function: Collect process list
collect_process_list() {
	local lssn=$1
	
	if [ -z "$lssn" ]; then
		log_message "ERROR" "collect_process_list: Missing LSSN"
		return 1
	fi

	local kvs_type="lssn"
	local kvs_key="${lssn}"
	local kvs_factor="process_list"
	
	# Capture ps -ef output, exclude kernel threads, limit to 5000 lines, escape for JSON
	# Kernel threads are shown as [name] and typically have PPID=2 (kthreadd)
	# We include the header line for context
	local ps_output=$(ps -ef | head -n 5000 | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | awk '{printf "%s\\n", $0}')
	
	# Send to KVS
	# kvs_put takes: kType kKey kFactor kValue_JSON
	# We want to store the string in kValue directly? Or as a JSON object?
	# Previous implementation: "kValue":"${ps_output}" (inside JSON)
	# kvs_put wrapper: kvs_put "sys_info" "process_list_${lssn}" "linux_ps" "\"${ps_output}\""
	
	log_message "INFO" "Collecting process list for LSSN ${lssn}..."
	kvs_put "${kvs_type}" "${kvs_key}" "${kvs_factor}" "\"${ps_output}\""
}
