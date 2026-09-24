#!/bin/bash
# giipAgent Gateway Mode Library (Main Orchestrator)
# Version: 4.00
# Date: 2025-11-27
# Purpose: Main entry point that orchestrates gateway processing
# Rule: Follow giipapi_rules.md - text contains parameter names only, jsondata contains actual values
#
# ARCHITECTURE: Micromodules Pattern
# - gateway.sh (THIS FILE): Main orchestrator, import & delegate ONLY
# - gateway_log.sh: Logging (gateway_log)
# - gateway_api.sh: API calls (get_gateway_servers, get_db_queries, get_managed_databases)
# - gateway_server.sh: Server parsing (extract_server_params, validate_server_params)
# - gateway_remote.sh: SSH execution (execute_remote_command)
# - gateway_queue.sh: Queue management (get_remote_queue, get_script_by_mssn)
# - ssh_connection_logger.sh: SSH logging (log_ssh_attempt, log_ssh_result)
# - remote_ssh_test.sh: SSH test API (report_ssh_test_result)
# - kvs.sh: KVS storage (kvs_put)
# - normal.sh: Queue fetching (fetch_queue)
# - check_managed_databases.sh: DB health checks (check_managed_databases)

# ============================================================================
# Module Loading
# ============================================================================

SCRIPT_DIR_GATEWAY="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Load all required modules (fail if critical)
. "${SCRIPT_DIR_GATEWAY}/gateway_log.sh" || { echo "❌ FATAL: gateway_log.sh not found" >&2; exit 1; }
. "${SCRIPT_DIR_GATEWAY}/gateway_api.sh" || { echo "❌ FATAL: gateway_api.sh not found" >&2; exit 1; }
. "${SCRIPT_DIR_GATEWAY}/gateway_server.sh" || { echo "❌ FATAL: gateway_server.sh not found" >&2; exit 1; }
. "${SCRIPT_DIR_GATEWAY}/gateway_remote.sh" || { echo "❌ FATAL: gateway_remote.sh not found" >&2; exit 1; }
. "${SCRIPT_DIR_GATEWAY}/gateway_queue.sh" || { echo "❌ FATAL: gateway_queue.sh not found" >&2; exit 1; }

# Load optional modules (warn if missing)
[ -f "${SCRIPT_DIR_GATEWAY}/ssh_connection_logger.sh" ] && . "${SCRIPT_DIR_GATEWAY}/ssh_connection_logger.sh" || echo "⚠️  ssh_connection_logger.sh not found" >&2
[ -f "${SCRIPT_DIR_GATEWAY}/remote_ssh_test.sh" ] && . "${SCRIPT_DIR_GATEWAY}/remote_ssh_test.sh" || echo "⚠️  remote_ssh_test.sh not found" >&2
[ -f "${SCRIPT_DIR_GATEWAY}/kvs.sh" ] && . "${SCRIPT_DIR_GATEWAY}/kvs.sh" || { kvs_put() { echo "[gateway.sh] ⚠️  kvs_put stub" >&2; return 1; }; }
[ -f "${SCRIPT_DIR_GATEWAY}/normal.sh" ] && . "${SCRIPT_DIR_GATEWAY}/normal.sh" || { fetch_queue() { echo "[gateway.sh] ⚠️  fetch_queue stub" >&2; return 1; }; }
[ -f "${SCRIPT_DIR_GATEWAY}/check_managed_databases.sh" ] && . "${SCRIPT_DIR_GATEWAY}/check_managed_databases.sh" || { check_managed_databases() { echo "[Gateway] ⚠️  check_managed_databases stub" >&2; return 1; }; }

# ============================================================================
# Main Processing (Orchestration Only)
# ============================================================================

# Function: Process single server - ORCHESTRATION (delegates all work to modules)
process_single_server() {
	local server_json="$1"
	local tmpdir="$2"
	local global_lssn="${lssn}"
	
	gateway_log "🔵" "[5.5.0-ENTRY]" "process_single_server 호출됨"
	[[ -z "$server_json" || "$server_json" == "{}" ]] && return 0
	
	# Step 1: Extract parameters
	local server_params=$(extract_server_params "$server_json")
	gateway_log "🔵" "[5.5.1-EXTRACT]" "extract_server_params 완료"
	[ -z "$server_params" ] && { gateway_log "❌" "[5.5.1-DEBUG]" "extract_server_params returned empty"; return 0; }
	
	# Step 1.5: Log extracted parameters to tKVS
	local extract_log_params="{\"action\":\"server_params_extracted\",\"server_params\":${server_params}}"
	type kvs_put >/dev/null 2>&1 && kvs_put "lssn" "${global_lssn:-0}" "gateway_server_extract" "$extract_log_params" 2>/dev/null
	gateway_log "🟢" "[5.5.1.5]" "Extracted params logged to tKVS"
	
	# Step 2: Validate parameters
	gateway_log "🔵" "[5.5.2-VALIDATE]" "validate_server_params 시작"
	if ! validate_server_params "$server_params"; then
		local hostname=$(echo "$server_params" | jq -r '.hostname // empty' 2>/dev/null)
		gateway_log "⚠️ " "[5.5.2-SKIPPED]" "Server skipped (validation failed): $hostname"
		return 0
	fi
	
	# Step 3: Extract individual values
	local hostname=$(echo "$server_params" | jq -r '.hostname' 2>/dev/null)
	local server_lssn=$(echo "$server_params" | jq -r '.lssn' 2>/dev/null)
	local ssh_host=$(echo "$server_params" | jq -r '.ssh_host' 2>/dev/null)
	local ssh_user=$(echo "$server_params" | jq -r '.ssh_user' 2>/dev/null)
	local ssh_port=$(echo "$server_params" | jq -r '.ssh_port' 2>/dev/null)
	local ssh_key_path=$(echo "$server_params" | jq -r '.ssh_key_path' 2>/dev/null)
	local ssh_password=$(echo "$server_params" | jq -r '.ssh_password' 2>/dev/null)
	local os_info=$(echo "$server_params" | jq -r '.os_info' 2>/dev/null)
	
	gateway_log "🟢" "[5.6]" "Server parsed: hostname=${hostname}, lssn=${server_lssn}"
	echo "[$(date '+%Y%m%d%H%M%S')] [Gateway] Processing: $hostname (LSSN:$server_lssn)" >> $LogFileName
	type log_remote_execution >/dev/null 2>&1 && log_remote_execution "started" "$hostname" "$server_lssn" "$ssh_host" "$ssh_port" "unknown"
	
	# Step 4: Get remote queue
	local tmpfile="${tmpdir}/script_${server_lssn}.sh"
	get_remote_queue "$server_lssn" "$hostname" "$os_info" "$tmpfile"
	
	local ssh_result=1
	if [ -s "$tmpfile" ]; then
		local err_check=$(cat "$tmpfile" | grep "HTTP Error")
		if [ -n "$err_check" ]; then
			gateway_log "❌" "[5.8-ERROR]" "Queue fetch failed"
			type log_remote_execution >/dev/null 2>&1 && log_remote_execution "failed" "$hostname" "$server_lssn" "$ssh_host" "$ssh_port" "false" "Queue fetch error"
		else
			gateway_log "🟢" "[5.8]" "Queue fetched successfully"
			
			# ✅ Step 4.5: Save complete connection info to KVS BEFORE SSH attempt
			# This includes: hostname, IP, port, user, auth method, and original server params
			local auth_method="unknown"
			[ -n "$ssh_password" ] && auth_method="password"
			[ -n "$ssh_key_path" ] && [ -f "$ssh_key_path" ] && auth_method="key"
			
			local ssh_connection_info="{\"phase\":\"[5.8.5]\",\"hostname\":\"${hostname}\",\"lssn\":${server_lssn},\"ssh_host\":\"${ssh_host}\",\"ssh_port\":${ssh_port},\"ssh_user\":\"${ssh_user}\",\"auth_method\":\"${auth_method}\",\"ssh_key_path\":\"${ssh_key_path}\",\"has_password\":$([ -n \"$ssh_password\" ] && echo 'true' || echo 'false'),\"os_info\":\"${os_info}\",\"server_info_file\":\"$(basename $server_info_file)\"}"
			
			gateway_log "🔵" "[5.8.5-KVS]" "SSH 접속 정보 KVS 기록 시작"
			if type kvs_put >/dev/null 2>&1; then
				kvs_put "lssn" "${lssn:-0}" "ssh_connection_info_before_attempt" "$ssh_connection_info" 2>/dev/null
				gateway_log "🟢" "[5.8.5-KVS]" "SSH 접속 정보 KVS 기록 완료"
			fi
			
			# Step 5: Execute SSH
			gateway_log "🟢" "[5.9]" "SSH attempt to ${ssh_host}:${ssh_port}"
			execute_remote_command "$ssh_host" "$ssh_user" "$ssh_port" "$ssh_key_path" "$ssh_password" "$tmpfile" "$server_lssn" "$hostname" >> $LogFileName
			ssh_result=$?
			
			# Log result
			if [ $ssh_result -eq 0 ]; then
				gateway_log "🟢" "[5.10]" "SSH success"
				type log_remote_execution >/dev/null 2>&1 && log_remote_execution "success" "$hostname" "$server_lssn" "$ssh_host" "$ssh_port" "true"
			else
				gateway_log "❌" "[5.10]" "SSH failed: code=${ssh_result}"
				type log_remote_execution >/dev/null 2>&1 && log_remote_execution "failed" "$hostname" "$server_lssn" "$ssh_host" "$ssh_port" "true" "SSH failed"
			fi
		fi
	else
		gateway_log "🟢" "[5.11]" "No queue (empty)"
		type log_remote_execution >/dev/null 2>&1 && log_remote_execution "success" "$hostname" "$server_lssn" "$ssh_host" "$ssh_port" "false"
	fi
	
	rm -f "$tmpfile"
	
	# Step 6: Call RemoteServerSSHTest API
	if [ $ssh_result -eq 0 ] && type report_ssh_test_result >/dev/null 2>&1; then
		gateway_log "🟢" "[5.10.1]" "RemoteServerSSHTest API call"
		report_ssh_test_result "$server_lssn" "$global_lssn" && gateway_log "🟢" "[5.10.2]" "API success" || gateway_log "❌" "[5.10.3]" "API failed"
	fi
	
	return 0
}

# Function: Process server list from file
process_server_list() {
	local server_list_file="$1"
	local tmpdir="$2"
	local temp_servers_file="${tmpdir}/servers_to_process.jsonl"
	
	[ ! -s "$server_list_file" ] && { gateway_log "❌" "[5.5-TEST]" "서버 목록 파일이 비어있음"; return 1; }
	
	# Parse servers
	if command -v jq &> /dev/null; then
		gateway_log "🟢" "[5.5-JQ-USED]" "jq로 JSON 파싱"
		jq -c '.data[]? // .[]? // .' "$server_list_file" 2>/dev/null > "$temp_servers_file"
	else
		gateway_log "🟢" "[5.5-GREP-FALLBACK]" "grep fallback 사용"
		tr -d '\n' < "$server_list_file" | sed 's/}/}\n/g' | grep -o '{[^}]*}' > "$temp_servers_file"
	fi
	
	# Process each server
	local server_count=0
	[ -s "$temp_servers_file" ] && while IFS= read -r server_json; do
		[ -z "$server_json" ] && continue
		process_single_server "$server_json" "$tmpdir"
		((server_count++))
	done < "$temp_servers_file"
	
	rm -f "$temp_servers_file"
	[ $server_count -gt 0 ] && gateway_log "🟢" "[5.5-PROCESSING]" "서버 처리 완료: count=${server_count}" || gateway_log "⚠️ " "[5.5-NO-SERVERS]" "처리할 서버 없음"
}

# ============================================================================
# Main Gateway Processing Function
# ============================================================================

process_gateway_servers() {
	local tmpdir="/tmp/giipAgent_gateway_$$"
	mkdir -p "$tmpdir"
	gateway_log "🔵" "[5.4.5-PROCESS_ENTRY]" "process_gateway_servers 호출됨"
	
	# [5.3.1] Gateway 자신의 큐 처리
	gateway_log "🟢" "[5.3.1]" "Gateway 자신의 큐 조회 시작"
	local gateway_queue_file="/tmp/gateway_self_queue_$$.sh"
	
	if type fetch_queue >/dev/null 2>&1; then
		fetch_queue "$lssn" "$hn" "$os" "$gateway_queue_file"
		if [ -s "$gateway_queue_file" ]; then
			gateway_log "🟢" "[5.3.1-EXECUTE]" "Gateway 자신의 큐 실행"
			command -v dos2unix >/dev/null 2>&1 && dos2unix "$gateway_queue_file" 2>/dev/null || sed -i 's/\r$//' "$gateway_queue_file" 2>/dev/null
			bash "$gateway_queue_file" && gateway_log "🟢" "[5.3.1-COMPLETED]" "Gateway 자신의 큐 실행 완료" || gateway_log "❌" "[5.3.1-ERROR]" "Gateway 큐 실행 실패"
		else
			gateway_log "🟢" "[5.3.1-EMPTY]" "Gateway 자신의 큐 없음 (404)"
		fi
		rm -f "$gateway_queue_file"
	fi
	
	# Get servers from DB
	local server_list_file=$(get_gateway_servers)
	[ $? -ne 0 ] || [ ! -f "$server_list_file" ] && { gateway_log "❌" "[5.5-ERROR]" "서버 목록 파일 확인 실패"; rm -rf "$tmpdir"; return 1; }
	
	gateway_log "🟢" "[5.5]" "서버 목록 파일 확인 성공" "\"file_size\":$(wc -c < \"$server_list_file\")"
	echo "[$(date '+%Y%m%d%H%M%S')] [Gateway] Starting server processing cycle..." >> $LogFileName
	
	# Process servers
	process_server_list "$server_list_file" "$tmpdir"
	
	# Clean up
	rm -f "$server_list_file"
	rm -rf "$tmpdir"
	
	# Complete
	gateway_log "🟢" "[5.12]" "Gateway 사이클 완료"
	echo "[$(date '+%Y%m%d%H%M%S')] [Gateway] Cycle completed" >> $LogFileName
	
	type save_execution_log >/dev/null 2>&1 && save_execution_log "gateway_cycle_end" "{\"status\":\"completed\",\"lssn\":${lssn}}" && gateway_log "🟢" "[5.13]" "실행 로그 저장 완료"
}

# ============================================================================
# Export Functions
# ============================================================================

export -f process_single_server
export -f process_server_list
export -f process_gateway_servers
export -f check_managed_databases
