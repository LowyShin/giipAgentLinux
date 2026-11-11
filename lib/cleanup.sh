#!/bin/bash
################################################################################
# Temporary Files Cleanup Module
# Purpose: Clean up old GIIP temporary files from previous executions
# Author: GIIP Agent
# Version: 2.0
# Date: 2025-11-27 (v2.0: 단일 find 배치 삭제, 2026-11-11)
#
# Usage:
#   . "${LIB_DIR}/cleanup.sh"
#   cleanup_all_temp_files
#
# This module provides:
#   - cleanup_old_temp_files: Delete old files matching ONE pattern
#   - cleanup_all_temp_files: Clean all old GIIP temp files (single directory pass)
#
# v2.0 변경 (매분 cron 에서 /tmp 스캔이 멈추던 사고 대응):
#   - 패턴별 for-glob + 파일별 `echo | sed` fork -> 전체 패턴을 하나의 find 로 한 번만 스캔
#   - 의도적 안전 변경: `-mmin +10` 추가 (동시 실행 중인 다른 인스턴스의 신선한 파일 보호)
#   - GIIP_TMP_DIR (기본 /tmp) 로 대상 디렉터리 지정 가능
################################################################################

# Core: delete old, non-empty files matching the given -name patterns in one find pass.
# Args: patterns... ; uses $current_pid (falls back to $$). Prints the deleted count.
_giip_cleanup_find() {
	local dir="${GIIP_TMP_DIR:-/tmp}"
	local pid="${current_pid:-$$}"
	local -a expr=()
	local p
	[ $# -eq 0 ] && { echo 0; return 0; }
	for p in "$@"; do
		[ ${#expr[@]} -gt 0 ] && expr+=(-o)
		expr+=(-name "$p")
	done
	local -a runner=()
	command -v timeout >/dev/null 2>&1 && runner=(timeout 20)
	"${runner[@]}" find "$dir" -maxdepth 1 -type f \( "${expr[@]}" \) \
		-size +0 -mmin +10 ! -name "*_${pid}.*" -delete -print 2>/dev/null | wc -l | tr -d ' '
}

# Function to safely delete old files for one pattern (compatible with v1 name/signature)
cleanup_old_temp_files() {
	local pattern=$1
	local count
	count=$(_giip_cleanup_find "$pattern")
	[ "${count:-0}" -gt 0 ] && echo "[cleanup] ✓ Cleaned up $count old ${pattern} files"
	return 0
}

# Main cleanup function for all GIIP temporary files
cleanup_all_temp_files() {
	echo "[cleanup] 🟢 Cleaning up old GIIP temporary files from previous executions..."

	# Get current process ID
	current_pid=$$

	local -a patterns=(
		# discovery files
		"auto_discover_debug_*.log"
		"auto_discover_result_*.json"
		"auto_discover_log_*.log"
		"auto_discover_services_*.json"
		"auto_discover_servers_*.json"
		"auto_discover_networks_*.json"
		"discovery_kvs_log_*.txt"
		"kvs_put_init_*.log"
		"kvs_kValue_auto_discover_result_*.json"
		"kvs_kValue_auto_discover_servers_*.json"
		"kvs_kValue_auto_discover_networks_*.json"
		"kvs_kValue_auto_discover_services_*.json"
		"kvs_put_auto_discover_result_*.log"
		"kvs_put_auto_discover_servers_*.log"
		"kvs_put_auto_discover_networks_*.log"
		"kvs_put_auto_discover_services_*.log"
		# KVS API call temporary files (lib/kvs.sh)
		"kvs_put_response_*"
		"kvs_put_stderr_*"
		"kvs_exec_response_*"
		"kvs_exec_stderr_*"
		"kvs_exec_post_*"
		# gateway-related
		"gateway_servers_*.json"
		"gateway_self_queue_*.sh"
		"giipAgent_gateway_*"
		# SSH test
		"servers_to_test_*.jsonl"
		# remote profile
		"remote_profile_*.json"
		# queue_get params
		"queue_get_params_*.json"
		# SSH test reports
		"ssh_test_report_*.txt"
		"ssh_test_results_*.json"
		"ssh_error_*.json"
		# managed DB API response
		"managed_db_api_response_*.json"
		# DB check results
		"db_check_results_*.jsonl"
	)

	local count
	count=$(_giip_cleanup_find "${patterns[@]}")
	[ "${count:-0}" -gt 0 ] && echo "[cleanup] ✓ Cleaned up $count old files"

	# Clean up ssh_test_logs directory
	if [ -d "/tmp/ssh_test_logs" ]; then
		rm -rf /tmp/ssh_test_logs 2>/dev/null
		echo "[cleanup] ✓ Cleaned up ssh_test_logs directory"
	fi

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

export -f _giip_cleanup_find
export -f cleanup_old_temp_files
export -f cleanup_all_temp_files
