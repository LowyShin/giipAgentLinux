#!/bin/bash
# DB Check: HTTP
# Purpose: Perform HTTP health check

perform_check_http() {
	local mdb_id="$1"
	local db_name="$2"
	local enabled="$3"
	local url="$4"
	local method="$5"
	local timeout_val="$6"
	local expected_code="$7"
	
	local check_status="unknown"
	local check_message="Not tested"
	local performance_json="{}"
	local start_time=$(date +%s%3N)
	
	if [ "$enabled" = "1" ] || [ "$enabled" = "true" ]; then
		if [ -z "$url" ]; then
			check_status="error"
			check_message="URL empty"
			echo "[$(date '+%Y%m%d%H%M%S')] [Gateway]   ❌ HTTP check URL missing" >> $LogFileName
		else
			local http_result=$(check_http_health "$url" "$method" "$timeout_val" "$expected_code")
			IFS='|' read -r check_status response_time http_code check_message <<< "$http_result"
			
			if [ "$check_status" = "success" ]; then
				echo "[$(date '+%Y%m%d%H%M%S')] [Gateway]   ✅ HTTP check OK: $url" >> $LogFileName
			else
				echo "[$(date '+%Y%m%d%H%M%S')] [Gateway]   ❌ HTTP check failed: $check_message" >> $LogFileName
			fi
			performance_json="{\"http_code\": \"$http_code\", \"response_time_ms\": $response_time, \"url\": \"$url\", \"method\": \"$method\"}"
		fi
	else
		check_status="warning"
		check_message="HTTP check disabled"
		echo "[$(date '+%Y%m%d%H%M%S')] [Gateway]   ⚠️  HTTP check disabled" >> $LogFileName
	fi

	echo "{\"mdb_id\":${mdb_id},\"status\":\"${check_status}\",\"message\":\"${check_message}\",\"response_time_ms\":${response_time},\"performance_metrics\":${performance_json},\"db_name\":\"${db_name}\",\"db_type\":\"HTTP\"}"
}

export -f perform_check_http
