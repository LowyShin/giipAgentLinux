#!/bin/bash
# lib/kvs_metrics.sh - Helper function to collect core system metrics for KVS logging
# This is a separate file to keep standard library files (lib/kvs.sh, lib/kvs_standard.sh) clean and untouched.

_get_kvs_system_metrics() {
	# 1. CPU Usage
	kvs_cpu_usage=0
	
	# Load common.sh if get_cpu_usage is not already defined
	if ! command -v get_cpu_usage >/dev/null 2>&1; then
		local lib_dir
		lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
		if [ -f "${lib_dir}/common.sh" ]; then
			local set_e_active=0
			if [[ "$-" == *e* ]]; then
				set_e_active=1
				set +e
			fi
			. "${lib_dir}/common.sh" >/dev/null 2>&1 || true
			if [ $set_e_active -eq 1 ]; then
				set -e
			fi
		fi
	fi

	# Call get_cpu_usage (redirect stderr to avoid printing syntax errors from common.sh)
	if command -v get_cpu_usage >/dev/null 2>&1; then
		kvs_cpu_usage=$(get_cpu_usage 2>/dev/null)
	fi

	# Ensure it is a valid integer
	if [[ ! "$kvs_cpu_usage" =~ ^[0-9]+$ ]]; then
		kvs_cpu_usage=0
	fi

	# Fallback to /proc/stat if CPU usage is 0 or invalid, and /proc/stat exists
	if [ "$kvs_cpu_usage" -eq 0 ] && [ -f /proc/stat ]; then
		local line
		line=$(grep '^cpu ' /proc/stat | head -n 1 || true)
		if [ -n "$line" ]; then
			local user nice system idle iowait irq softirq steal total active
			user=$(echo "$line" | awk '{print $2}' || echo 0)
			nice=$(echo "$line" | awk '{print $3}' || echo 0)
			system=$(echo "$line" | awk '{print $4}' || echo 0)
			idle=$(echo "$line" | awk '{print $5}' || echo 0)
			iowait=$(echo "$line" | awk '{print $6}' || echo 0)
			irq=$(echo "$line" | awk '{print $7}' || echo 0)
			softirq=$(echo "$line" | awk '{print $8}' || echo 0)
			steal=$(echo "$line" | awk '{print $9}' || echo 0)

			# Sanitize values to ensure they are clean integers
			user=$(echo "$user" | tr -cd '0-9'); [ -z "$user" ] && user=0
			nice=$(echo "$nice" | tr -cd '0-9'); [ -z "$nice" ] && nice=0
			system=$(echo "$system" | tr -cd '0-9'); [ -z "$system" ] && system=0
			idle=$(echo "$idle" | tr -cd '0-9'); [ -z "$idle" ] && idle=0
			iowait=$(echo "$iowait" | tr -cd '0-9'); [ -z "$iowait" ] && iowait=0
			irq=$(echo "$irq" | tr -cd '0-9'); [ -z "$irq" ] && irq=0
			softirq=$(echo "$softirq" | tr -cd '0-9'); [ -z "$softirq" ] && softirq=0
			steal=$(echo "$steal" | tr -cd '0-9'); [ -z "$steal" ] && steal=0

			total=$((user + nice + system + idle + iowait + irq + softirq + steal))
			active=$((user + nice + system + irq + softirq + steal))
			if [ $total -gt 0 ]; then
				kvs_cpu_usage=$((active * 100 / total))
			fi
		fi
	fi

	# Final check to ensure it is a valid integer
	if [[ ! "$kvs_cpu_usage" =~ ^[0-9]+$ ]]; then
		kvs_cpu_usage=0
	fi

	# 2. Memory Usage
	kvs_mem_usage=0
	if command -v get_mem_usage >/dev/null 2>&1; then
		kvs_mem_usage=$(get_mem_usage 2>/dev/null)
	fi
	if [[ ! "$kvs_mem_usage" =~ ^[0-9]+$ ]]; then
		kvs_mem_usage=0
	fi
	if [ "$kvs_mem_usage" -eq 0 ] && [ -f /proc/meminfo ]; then
		local total free buffers cached
		total=$(grep MemTotal /proc/meminfo | awk '{print $2}' || echo 0)
		free=$(grep MemFree /proc/meminfo | awk '{print $2}' || echo 0)
		buffers=$(grep Buffers /proc/meminfo | awk '{print $2}' || echo 0)
		cached=$(grep ^Cached /proc/meminfo | awk '{print $2}' || echo 0)

		# Sanitize values to ensure they are clean integers
		total=$(echo "$total" | tr -cd '0-9'); [ -z "$total" ] && total=0
		free=$(echo "$free" | tr -cd '0-9'); [ -z "$free" ] && free=0
		buffers=$(echo "$buffers" | tr -cd '0-9'); [ -z "$buffers" ] && buffers=0
		cached=$(echo "$cached" | tr -cd '0-9'); [ -z "$cached" ] && cached=0

		if [ "$total" -gt 0 ]; then
			local used=$((total - free - buffers - cached))
			kvs_mem_usage=$((used * 100 / total))
		fi
	fi
	if [[ ! "$kvs_mem_usage" =~ ^[0-9]+$ ]]; then
		kvs_mem_usage=0
	fi

	# 3. Disk Usage (Root filesystem '/')
	kvs_disk_usage=0
	if command -v df >/dev/null 2>&1; then
		kvs_disk_usage=$(df -P / 2>/dev/null | awk 'NR==2 {print $5}' | tr -d '%' || echo 0)
	fi
	kvs_disk_usage=$(echo "$kvs_disk_usage" | tr -cd '0-9')
	if [ -z "$kvs_disk_usage" ] || [[ ! "$kvs_disk_usage" =~ ^[0-9]+$ ]]; then
		kvs_disk_usage=0
	fi

	# 4. Load Average (1-minute)
	kvs_load_avg="0.00"
	if [ -f /proc/loadavg ]; then
		kvs_load_avg=$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo "0.00")
	elif command -v uptime >/dev/null 2>&1; then
		kvs_load_avg=$(uptime 2>/dev/null | awk -F'load average:' '{ print $2 }' | cut -d, -f1 | tr -d ' ' || echo "0.00")
	fi
	# Convert comma to dot if any (for non-US locales)
	kvs_load_avg=$(echo "$kvs_load_avg" | tr ',' '.')
	if [ -z "$kvs_load_avg" ] || [[ ! "$kvs_load_avg" =~ ^[0-9]+\.[0-9]+$ ]]; then
		kvs_load_avg="0.00"
	fi

	# 5. Process Count
	kvs_proc_count=0
	if command -v ps >/dev/null 2>&1; then
		kvs_proc_count=$(ps -e 2>/dev/null | wc -l | tr -d '[:space:]' || echo 0)
	fi
	kvs_proc_count=$(echo "$kvs_proc_count" | tr -cd '0-9')
	if [ -z "$kvs_proc_count" ] || [[ ! "$kvs_proc_count" =~ ^[0-9]+$ ]]; then
		kvs_proc_count=0
	fi

	# 6. Connection Count (TCP Established)
	kvs_conn_count=0
	if command -v ss >/dev/null 2>&1; then
		kvs_conn_count=$(ss -t -a 2>/dev/null | grep -i est | wc -l | tr -d '[:space:]' || echo 0)
	elif command -v netstat >/dev/null 2>&1; then
		kvs_conn_count=$(netstat -an 2>/dev/null | grep -i est | wc -l | tr -d '[:space:]' || echo 0)
	fi
	kvs_conn_count=$(echo "$kvs_conn_count" | tr -cd '0-9')
	if [ -z "$kvs_conn_count" ] || [[ ! "$kvs_conn_count" =~ ^[0-9]+$ ]]; then
		kvs_conn_count=0
	fi
}
