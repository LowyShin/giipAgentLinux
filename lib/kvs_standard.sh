#!/bin/bash
#
# KVS 표준 송신 라이브러리
# Version: 1.0
# Date: 2025-11-14
# Purpose: KVS 데이터 송신 표준화
#
# SPECIFICATIONS:
#   - Standard: giipdb/docs/KVS_STANDARD_SPECIFICATION.md ⭐⭐⭐
#   - API Rules: giipfaw/docs/giipapi_rules.md
#   - Parser: giipv3/src/lib/kvsParser.ts
#
# USAGE:
#   source lib/kvs_standard.sh
#   kvs_send "giipagent" "startup" '{"config_loaded":true}'
#   kvs_send_file "/tmp/data.json" "autodiscover"
#

set -e

# ============================================================================
# KVS 표준 송신 함수
# ============================================================================

# Function: KVS 표준 송신
# Usage: kvs_send "factor_name" "event_type" '{"details":"json"}'
# 
# Parameters:
#   $1: kFactor (autodiscover, giipagent, cqeresult, ssh_connection, etc.)
#   $2: event_type (startup, error, ssh_connection_attempt, etc.)
#   $3: details_json (Factor별 상세 데이터, JSON 문자열)
#
# Environment Variables (Required):
#   lssn: Server LSSN
#   sk: Server Key (token)
#   apiaddrv2: API endpoint
#   sv: Agent version (optional)
#
# Example:
#   kvs_send "giipagent" "startup" '{"config_loaded":true,"mode":"gateway"}'
#   kvs_send "ssh_connection" "ssh_connection_attempt" '{"target_lssn":71221,"status":"attempting"}'
#
# Returns: 
#   0 = success
#   1 = validation error
#   2 = network error
#   3 = API error
kvs_send() {
	local kfactor=$1
	local event_type=$2
	local details_json=$3
	
	# ============================================================================
	# Step 1: 입력 검증
	# ============================================================================
	
	if [ -z "$kfactor" ]; then
		echo "[KVS-Send] ❌ ERROR: kfactor required (1st parameter)" >&2
		echo "[KVS-Send] Usage: kvs_send <kfactor> <event_type> <details_json>" >&2
		return 1
	fi
	
	if [ -z "$event_type" ]; then
		echo "[KVS-Send] ❌ ERROR: event_type required (2nd parameter)" >&2
		echo "[KVS-Send] Usage: kvs_send <kfactor> <event_type> <details_json>" >&2
		return 1
	fi
	
	# details_json 기본값 (빈 객체)
	if [ -z "$details_json" ]; then
		details_json='{}'
	fi
	
	# ============================================================================
	# Step 2: 환경 변수 검증
	# ============================================================================
	
	if [ -z "$lssn" ]; then
		echo "[KVS-Send] ❌ ERROR: lssn not set (environment variable required)" >&2
		return 1
	fi
	
	if [ -z "$sk" ]; then
		echo "[KVS-Send] ❌ ERROR: sk not set (environment variable required)" >&2
		return 1
	fi
	
	if [ -z "$apiaddrv2" ]; then
		echo "[KVS-Send] ❌ ERROR: apiaddrv2 not set (environment variable required)" >&2
		return 1
	fi
	
	# ============================================================================
	# Step 3: 표준 kValue 구조 생성
	# ============================================================================
	
	local timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')  # ISO 8601 UTC
	local hostname=$(hostname)
	local version="${sv:-unknown}"
	
	# jq를 사용하여 표준 구조 생성
	if ! command -v jq >/dev/null 2>&1; then
		echo "[KVS-Send] ❌ ERROR: jq is required but not installed" >&2
		return 1
	fi
	
	# ✅ 표준 kValue 구조 (KVS_STANDARD_SPECIFICATION.md 준수)
	local kvalue
	kvalue=$(jq -n \
		--arg event_type "$event_type" \
		--arg timestamp "$timestamp" \
		--arg lssn "$lssn" \
		--arg hostname "$hostname" \
		--arg version "$version" \
		--argjson details "$details_json" \
		'{
			event_type: $event_type,
			timestamp: $timestamp,
			lssn: ($lssn | tonumber),
			hostname: $hostname,
			version: $version,
			details: $details
		}')
	
	if [ $? -ne 0 ]; then
		echo "[KVS-Send] ❌ ERROR: Failed to build kValue (invalid details_json?)" >&2
		echo "[KVS-Send] details_json: ${details_json:0:200}..." >&2
		return 1
	fi
	
	# ============================================================================
	# Step 4: API 요청 데이터 생성
	# ============================================================================
	
	# API URL 구성
	local kvs_url="${apiaddrv2}"
	
	# ✅ giipapi_rules.md 준수: text에는 파라미터 이름만
	local text="KVSPut kType kKey kFactor"
	
	# ✅ jsondata에 실제 값 (kValue는 JSON 객체로 전달)
	local jsondata
	jsondata=$(jq -n \
		--arg kType "lssn" \
		--arg kKey "$lssn" \
		--arg kFactor "$kfactor" \
		--argjson kValue "$kvalue" \
		'{kType: $kType, kKey: $kKey, kFactor: $kFactor, kValue: $kValue}')
	
	if [ $? -ne 0 ]; then
		echo "[KVS-Send] ❌ ERROR: Failed to build jsondata" >&2
		return 1
	fi
	
	# ✅ URL 인코딩 (jq 사용)
	local post_data="text=$(printf '%s' "$text" | jq -sRr '@uri')"
	post_data+="&token=$(printf '%s' "$sk" | jq -sRr '@uri')"
	post_data+="&jsondata=$(printf '%s' "$jsondata" | jq -sRr '@uri')"
	
	# ============================================================================
	# Step 5: 로깅 (최소화)
	# ============================================================================
	
	echo "[KVS-Send] 📤 Sending: kFactor=$kfactor, event=$event_type, lssn=$lssn" >&2
	
	# Payload 크기 확인
	local payload_size=${#jsondata}
	echo "[KVS-Send] 📦 Payload size: $payload_size bytes" >&2
	
	if [ $payload_size -gt 1000000 ]; then
		echo "[KVS-Send] ⚠️  WARNING: Large payload (>1MB) may cause timeout" >&2
	fi
	
	# ============================================================================
	# Step 6: API 호출
	# ============================================================================
	
	local response_file=$(mktemp)
	local stderr_file=$(mktemp)
	
	# wget 사용 (timeout 30초, retry 2회)
	wget -O "$response_file" \
		--post-data="$post_data" \
		--header="Content-Type: application/x-www-form-urlencoded" \
		"${kvs_url}" \
		--no-check-certificate \
		--timeout=30 \
		--tries=2 \
		--server-response \
		-v 2>"$stderr_file"
	
	local exit_code=$?
	
	# ============================================================================
	# Step 7: 응답 검증 (표준 형식)
	# ============================================================================
	
	if [ $exit_code -eq 0 ]; then
		# 응답 파싱 (RstVal=200 확인)
		if jq -e '.data[0].RstVal == 200' "$response_file" >/dev/null 2>&1; then
			echo "[KVS-Send] ✅ Success: $event_type" >&2
			rm -f "$response_file" "$stderr_file"
			return 0
		else
			# API 에러 (200이 아님)
			local rstval=$(jq -r '.data[0].RstVal // "unknown"' "$response_file" 2>/dev/null)
			local rstmsg=$(jq -r '.data[0].RstMsg // "unknown"' "$response_file" 2>/dev/null)
			echo "[KVS-Send] ❌ API Error: RstVal=$rstval, Msg=$rstmsg" >&2
			echo "[KVS-Send] ❌ Response: $(cat "$response_file" | head -c 200)" >&2
			rm -f "$response_file" "$stderr_file"
			return 3
		fi
	else
		# 네트워크 에러
		local http_status=$(grep "HTTP/" "$stderr_file" 2>/dev/null | tail -1)
		echo "[KVS-Send] ❌ Network Error: exit_code=$exit_code" >&2
		echo "[KVS-Send] ❌ HTTP Status: $http_status" >&2
		
		case $exit_code in
			4) echo "[KVS-Send] Network failure (check connection)" >&2 ;;
			5) echo "[KVS-Send] SSL verification error (--no-check-certificate used)" >&2 ;;
			6) echo "[KVS-Send] Authentication failed" >&2 ;;
			7) echo "[KVS-Send] Protocol error" >&2 ;;
			8) echo "[KVS-Send] Server error response" >&2 ;;
		esac
		
		rm -f "$response_file" "$stderr_file"
		return 2
	fi
}

# ============================================================================
# 파일 기반 KVS 송신 (기존 kvsput.sh 호환)
# ============================================================================

# Function: 파일 기반 KVS 송신
# Usage: kvs_send_file "/path/to/data.json" "autodiscover"
#
# Parameters:
#   $1: json_file (JSON 파일 경로)
#   $2: kfactor (autodiscover, cqeresult, etc.)
#
# Description:
#   JSON 파일을 읽어서 KVS에 업로드합니다.
#   파일 내부에 event_type이 있으면 사용하고, 없으면 "data_upload"로 설정합니다.
#
# Example:
#   kvs_send_file "/var/log/giip-discovery-latest.json" "autodiscover"
#
# Returns: kvs_send의 반환값 (0=success, 1-3=error)
kvs_send_file() {
	local json_file=$1
	local kfactor=$2
	
	# ============================================================================
	# Step 1: 입력 검증
	# ============================================================================
	
	if [ -z "$json_file" ]; then
		echo "[KVS-Send-File] ❌ ERROR: json_file required (1st parameter)" >&2
		return 1
	fi
	
	if [ ! -f "$json_file" ]; then
		echo "[KVS-Send-File] ❌ ERROR: File not found: $json_file" >&2
		return 1
	fi
	
	if [ -z "$kfactor" ]; then
		echo "[KVS-Send-File] ❌ ERROR: kfactor required (2nd parameter)" >&2
		return 1
	fi
	
	# ============================================================================
	# Step 2: JSON 파일 읽기
	# ============================================================================
	
	local file_content
	file_content=$(cat "$json_file")
	
	if [ -z "$file_content" ]; then
		echo "[KVS-Send-File] ❌ ERROR: Empty file: $json_file" >&2
		return 1
	fi
	
	# JSON 유효성 검증
	if ! echo "$file_content" | jq empty >/dev/null 2>&1; then
		echo "[KVS-Send-File] ❌ ERROR: Invalid JSON in file: $json_file" >&2
		echo "[KVS-Send-File] First 200 chars: ${file_content:0:200}" >&2
		return 1
	fi
	
	# ============================================================================
	# Step 3: event_type 추출 또는 기본값 설정
	# ============================================================================
	
	# 파일 내부에 event_type이 있으면 사용
	local event_type
	event_type=$(echo "$file_content" | jq -r '.event_type // "data_upload"' 2>/dev/null)
	
	if [ -z "$event_type" ]; then
		event_type="data_upload"
	fi
	
	echo "[KVS-Send-File] 📄 Reading: $json_file (event=$event_type)" >&2
	
	# ============================================================================
	# Step 4: kvs_send 호출 (파일 내용을 details로 전달)
	# ============================================================================
	
	# 파일 전체를 details로 전달
	kvs_send "$kfactor" "$event_type" "$file_content"
}

# ============================================================================
# Export functions
# ============================================================================

export -f kvs_send
export -f kvs_send_file

echo "[KVS-Standard] ✅ Loaded: kvs_send, kvs_send_file" >&2
