#!/bin/bash
# Gateway Remote Execution Functions
# Version: 1.00
# Purpose: SSH connection and remote script execution
# Responsibility: Handle SSH authentication and remote execution ONLY

# Function: Execute command on remote server
execute_remote_command() {
	local remote_host=$1
	local remote_user=$2
	local remote_port=$3
	local ssh_key=$4
	local ssh_password=$5
	local script_file=$6
	local remote_lssn=${7:-0}      # Optional LSSN parameter
	local hostname=${8:-"unknown"}  # Optional hostname parameter
	
	local ssh_opts="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"
	local start_time=$(date +%s)
	local auth_method="none"
	
	# Determine authentication method
	if [ -n "${ssh_password}" ]; then
		auth_method="password"
	elif [ -n "${ssh_key}" ] && [ -f "${ssh_key}" ]; then
		auth_method="key"
	fi
	
	# 🔍 Log SSH connection attempt
	if type log_ssh_attempt >/dev/null 2>&1; then
		log_ssh_attempt "$remote_host" "$remote_port" "$remote_user" "$auth_method" "$remote_lssn" "$hostname"
	fi
	
	local exit_code=1
	
	if [ -n "${ssh_password}" ]; then
		if ! command -v sshpass &> /dev/null; then
			echo "  ❌ sshpass not available"
			local duration=$(($(date +%s) - start_time))
			
			# Log failure
			if type log_ssh_result >/dev/null 2>&1; then
				log_ssh_result "$remote_host" "$remote_port" "127" "$duration" "$remote_lssn" "$hostname"
			fi
			return 1
		fi
		
		# SSH 테스트 결과를 임시 파일에 저장
		local ssh_test_output="/tmp/ssh_test_${remote_lssn}_$$.txt"
		
		sshpass -p "${ssh_password}" scp ${ssh_opts} -P ${remote_port} \
		    ${script_file} ${remote_user}@${remote_host}:/tmp/giipTmpScript.sh 2>&1 | tee -a "$ssh_test_output"
		
		if [ $? -ne 0 ]; then
			local duration=$(($(date +%s) - start_time))
			
			# Log SCP failure
			if type log_ssh_result >/dev/null 2>&1; then
				log_ssh_result "$remote_host" "$remote_port" "126" "$duration" "$remote_lssn" "$hostname"
			fi
			
			# 실패 결과도 KVS에 기록
			if [ -f "$ssh_test_output" ]; then
				local ssh_error=$(cat "$ssh_test_output")
				if type kvs_put >/dev/null 2>&1; then
					kvs_put "lssn" "${lssn:-0}" "gateway_ssh_test_failed" "$ssh_error" 2>/dev/null
				fi
			fi
			return 1
		fi
		
		sshpass -p "${ssh_password}" ssh ${ssh_opts} -p ${remote_port} \
		    ${remote_user}@${remote_host} \
		    "chmod +x /tmp/giipTmpScript.sh && /tmp/giipTmpScript.sh && rm -f /tmp/giipTmpScript.sh" 2>&1 | tee -a "$ssh_test_output"
		
		exit_code=$?
		
		# SSH 테스트 성공/실패 결과를 KVS에 기록
		if [ -f "$ssh_test_output" ]; then
			local ssh_result=$(cat "$ssh_test_output")
			if [ $exit_code -eq 0 ]; then
				if type kvs_put >/dev/null 2>&1; then
					kvs_put "lssn" "${lssn:-0}" "gateway_ssh_test_success" "$ssh_result" 2>/dev/null
				fi
			else
				if type kvs_put >/dev/null 2>&1; then
					kvs_put "lssn" "${lssn:-0}" "gateway_ssh_test_failed" "$ssh_result" 2>/dev/null
				fi
			fi
		fi
	elif [ -n "${ssh_key}" ] && [ -f "${ssh_key}" ]; then
		# SSH 테스트 결과를 임시 파일에 저장
		local ssh_test_output="/tmp/ssh_test_${remote_lssn}_$$.txt"
		
		scp ${ssh_opts} -i ${ssh_key} -P ${remote_port} \
		    ${script_file} ${remote_user}@${remote_host}:/tmp/giipTmpScript.sh 2>&1 | tee -a "$ssh_test_output"
		
		if [ $? -ne 0 ]; then
			local duration=$(($(date +%s) - start_time))
			
			# Log SCP failure
			if type log_ssh_result >/dev/null 2>&1; then
				log_ssh_result "$remote_host" "$remote_port" "126" "$duration" "$remote_lssn" "$hostname"
			fi
			
			# 실패 결과도 KVS에 기록
			if [ -f "$ssh_test_output" ]; then
				local ssh_error=$(cat "$ssh_test_output")
				if type kvs_put >/dev/null 2>&1; then
					kvs_put "lssn" "${lssn:-0}" "gateway_ssh_test_failed" "$ssh_error" 2>/dev/null
				fi
			fi
			return 1
		fi
		
		ssh ${ssh_opts} -i ${ssh_key} -p ${remote_port} \
		    ${remote_user}@${remote_host} \
		    "chmod +x /tmp/giipTmpScript.sh && /tmp/giipTmpScript.sh && rm -f /tmp/giipTmpScript.sh" 2>&1 | tee -a "$ssh_test_output"
		
		exit_code=$?
		
		# SSH 테스트 성공/실패 결과를 KVS에 기록
		if [ -f "$ssh_test_output" ]; then
			local ssh_result=$(cat "$ssh_test_output")
			if [ $exit_code -eq 0 ]; then
				if type kvs_put >/dev/null 2>&1; then
					kvs_put "lssn" "${lssn:-0}" "gateway_ssh_test_success" "$ssh_result" 2>/dev/null
				fi
			else
				if type kvs_put >/dev/null 2>&1; then
					kvs_put "lssn" "${lssn:-0}" "gateway_ssh_test_failed" "$ssh_result" 2>/dev/null
				fi
			fi
		fi
	else
		echo "  ❌ No authentication method available"
		local duration=$(($(date +%s) - start_time))
		
		# Log no auth failure
		if type log_ssh_result >/dev/null 2>&1; then
			log_ssh_result "$remote_host" "$remote_port" "125" "$duration" "$remote_lssn" "$hostname"
		fi
		return 1
	fi
	
	# Calculate duration
	local duration=$(($(date +%s) - start_time))
	
	# 🔍 Log SSH connection result
	if type log_ssh_result >/dev/null 2>&1; then
		log_ssh_result "$remote_host" "$remote_port" "$exit_code" "$duration" "$remote_lssn" "$hostname"
	fi
	
	return $exit_code
}

# Export functions
export -f execute_remote_command
