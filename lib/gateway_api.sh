#!/bin/bash
# Gateway API Wrapper Functions
# Version: 1.00
# Purpose: API calls for server and database data retrieval
# Responsibility: Handle all API communication ONLY

# Function: Get remote servers from database (real-time query, no cache)
# Per GATEWAY_CONFIG_PHILOSOPHY.md: Database as Single Source of Truth
# Returns: temp file path with JSON data (caller must delete!)
get_gateway_servers() {
	local temp_file="/tmp/gateway_servers_$$.json"
	local api_url="${apiaddrv2}"
	[ -n "$apiaddrcode" ] && api_url="${api_url}?code=${apiaddrcode}"
	
	# 🔴 [로깅 포인트 #5.4] Gateway 서버 목록 조회 시작
	gateway_log "🟢" "[5.4]" "Gateway 서버 목록 조회 시작"
	
	local text="GatewayRemoteServerListForAgent lssn"
	local jsondata="{\"lssn\":${lssn}}"
	
	curl -s -X POST "$api_url" \
		-d "text=${text}&token=${sk}&jsondata=${jsondata}" \
		-H "Content-Type: application/x-www-form-urlencoded" \
		--insecure -o "$temp_file" 2>&1
	
	if [ ! -s "$temp_file" ]; then
		# 🔴 [로깅 포인트 #5.4-ERROR] 서버 목록 조회 실패
		gateway_log "❌" "[5.4-ERROR]" "Gateway 서버 목록 조회 실패: file_empty=true"
		rm -f "$temp_file"
		return 1
	fi
	
	# Check for error response
	local err_check=$(cat "$temp_file" | grep -i "rstval.*40[0-9]")
	if [ -n "$err_check" ]; then
		# 🔴 [로깅 포인트 #5.4-ERROR] API 에러 응답
		gateway_log "❌" "[5.4-ERROR]" "Gateway 서버 목록 API 에러"
		rm -f "$temp_file"
		return 1
	fi
	
	# 🔴 [로깅 포인트 #5.4-SUCCESS] 서버 목록 조회 성공
	local server_count=$(cat "$temp_file" | grep -o '{[^}]*}' | wc -l)
	gateway_log "🟢" "[5.4-SUCCESS]" "Gateway 서버 목록 조회 성공"
	
	# 🔴 DEBUG: 다음 함수 호출 확인
	gateway_log "🔵" "[5.4-RETURN]" "server_list_file 반환: $temp_file"
	
	echo "$temp_file"
	return 0
}

# Function: Get DB queries from database (real-time query, no cache)
# Returns: temp file path with JSON data (caller must delete!)
get_db_queries() {
	local temp_file="/tmp/gateway_db_queries_$$.json"
	local api_url="${apiaddrv2}"
	[ -n "$apiaddrcode" ] && api_url="${api_url}?code=${apiaddrcode}"
	
	local text="GatewayDBQueryList lssn"
	local jsondata="{\"lssn\":${lssn}}"
	
	curl -s -X POST "$api_url" \
		-d "text=${text}&token=${sk}&jsondata=${jsondata}" \
		-H "Content-Type: application/x-www-form-urlencoded" \
		--insecure -o "$temp_file" 2>&1
	
	if [ ! -s "$temp_file" ]; then
		rm -f "$temp_file"
		return 1
	fi
	
	echo "$temp_file"
	return 0
}

# Function: Get managed databases from tManagedDatabase (real-time query, no cache)
# Returns: temp file path with JSON data (caller must delete!)
get_managed_databases() {
	local temp_file="/tmp/managed_databases_$$.json"
	local api_url="${apiaddrv2}"
	[ -n "$apiaddrcode" ] && api_url="${api_url}?code=${apiaddrcode}"
	
	local text="GatewayManagedDatabaseList lssn"
	local jsondata="{\"lssn\":${lssn}}"
	
	curl -s -X POST "$api_url" \
		-d "text=${text}&token=${sk}&jsondata=${jsondata}" \
		-H "Content-Type: application/x-www-form-urlencoded" \
		--insecure -o "$temp_file" 2>&1
	
	if [ ! -s "$temp_file" ]; then
		echo "[Gateway] ⚠️  Failed to fetch managed databases from DB" >&2
		rm -f "$temp_file"
		return 1
	fi
	
	# Check for error response
	local err_check=$(cat "$temp_file" | grep -i "rstval.*40[0-9]")
	if [ -n "$err_check" ]; then
		echo "[Gateway] ⚠️  API error response" >&2
		rm -f "$temp_file"
		return 1
	fi
	
	echo "$temp_file"
	return 0
}

# Export functions
export -f get_gateway_servers
export -f get_db_queries
export -f get_managed_databases
