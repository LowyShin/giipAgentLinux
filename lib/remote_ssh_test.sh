#!/bin/bash
# giipAgent Remote SSH Test Library
# Version: 1.00
# Date: 2025-11-22
# Purpose: SSH test on remote servers and report results to RemoteServerSSHTest API
# This module handles the complete SSH test workflow with logging and API calls

# ============================================================================
# Send SSH Test Result to API
# ============================================================================

# Function: Report remote server SSH test result to API (RemoteServerSSHTest)
# Per REMOTE_SERVER_SSH_TEST_DETAILED_SPEC.md
# This function is called after SSH test completes (success or fail)
# Parameters:
#   $1: lssn - Remote server LSSN (테스트 대상 리모트 서버)
#   $2: gateway_lssn - Gateway server LSSN (관리 Gateway 서버)
#
# Logging:
#   [로깅 포인트 #6.1] SSH 테스트 결과 API 호출 시작
#   [로깅 포인트 #6.2] SSH 테스트 결과 API 호출 성공 (RstVal=200)
#   [로깅 포인트 #6.3] SSH 테스트 결과 API 호출 실패
#   [로깅 포인트 #6.4] SSH 테스트 결과 KVS 저장
#
# Return codes:
#   0 = API call successful (RstVal=200)
#   1 = API call failed or no response

report_ssh_test_result() {
	local lssn=$1
	local gateway_lssn=$2
	
	# 🔴 [로깅 포인트 #6.1] SSH 테스트 결과 API 호출 시작
	echo "[remote_ssh_test.sh] 🟢 [6.1] SSH 테스트 결과 API 호출 시작: lssn=${lssn}, gateway_lssn=${gateway_lssn}, test_type=ssh, timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')" >&2
	
	# Build API call per REMOTE_SERVER_SSH_TEST_DETAILED_SPEC.md
	local api_url="${apiaddrv2}"
	[ -n "$apiaddrcode" ] && api_url="${api_url}?code=${apiaddrcode}"
	
	# Prepare JSON data: lssn, gateway_lssn, test_type 만 전송
	local jsondata="{\"lssn\":${lssn},\"gateway_lssn\":${gateway_lssn},\"test_type\":\"ssh\"}"
	
	# text는 파라미터명만 포함 (API 규칙)
	local text="RemoteServerSSHTest lssn gateway_lssn test_type"
	
	# Call API
	local api_response_file="/tmp/remote_ssh_test_api_$$.json"
	
	wget -O "$api_response_file" \
		--post-data="text=${text}&token=${sk}&jsondata=${jsondata}" \
		--header="Content-Type: application/x-www-form-urlencoded" \
		"$api_url" \
		--no-check-certificate -q 2>&1
	
	local result=1
	
	# Check response per REMOTE_SERVER_SSH_TEST_DETAILED_SPEC.md
	if [ -f "$api_response_file" ] && [ -s "$api_response_file" ]; then
		local api_rstval=$(cat "$api_response_file" | grep -o '"RstVal":"[^"]*"' | sed 's/"RstVal":"//; s/"$//' | head -1)
		[ -z "$api_rstval" ] && api_rstval=$(cat "$api_response_file" | grep -o '"RstVal":[^,}]*' | sed 's/"RstVal"://; s/"//g' | head -1)
		local api_data=$(cat "$api_response_file")
		
		case "$api_rstval" in
			"200")
				# 🔴 [로깅 포인트 #6.2] SSH 테스트 결과 API 호출 성공 (LSChkdt 업데이트 완료)
				echo "[remote_ssh_test.sh] 🟢 [6.2] SSH 테스트 결과 API 호출 성공: lssn=${lssn}, gateway_lssn=${gateway_lssn}, rstval=${api_rstval}, message='SSH 접속 테스트 성공', timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')" >&2
				
				# Log to KVS
				if type kvs_put >/dev/null 2>&1; then
					kvs_put "lssn" "${lssn}" "remote_ssh_test_api_success" "{\"gateway_lssn\":${gateway_lssn},\"test_type\":\"ssh\",\"rstval\":\"${api_rstval}\"}"
					
					# 🔴 [로깅 포인트 #6.4] SSH 테스트 결과 KVS 저장 성공
					echo "[remote_ssh_test.sh] 🟢 [6.4] SSH 테스트 결과 KVS 저장 성공: lssn=${lssn}, timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')" >&2
				fi
				
				result=0
				;;
			"401")
				# 🔴 [로깅 포인트 #6.3] 인증 실패 (Secret Key 불일치)
				echo "[remote_ssh_test.sh] ❌ [6.3] SSH 테스트 API 인증 실패: lssn=${lssn}, gateway_lssn=${gateway_lssn}, rstval=${api_rstval}, error='Secret Key 불일치', timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')" >&2
				result=1
				;;
			"404")
				# 🔴 [로깅 포인트 #6.3] 리모트 서버를 찾을 수 없음
				echo "[remote_ssh_test.sh] ❌ [6.3] SSH 테스트 API 서버 오류: lssn=${lssn}, gateway_lssn=${gateway_lssn}, rstval=${api_rstval}, error='리모트 서버를 찾을 수 없음', timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')" >&2
				result=1
				;;
			"422")
				# 🔴 [로깅 포인트 #6.3] SSH 접속 테스트 실패 (타임아웃, 거부 등)
				echo "[remote_ssh_test.sh] ❌ [6.3] SSH 테스트 API SSH 접속 실패: lssn=${lssn}, gateway_lssn=${gateway_lssn}, rstval=${api_rstval}, error='Connection timeout or refused', timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')" >&2
				result=1
				;;
			*)
				# 🔴 [로깅 포인트 #6.3] 기타 API 오류
				echo "[remote_ssh_test.sh] ❌ [6.3] SSH 테스트 API 호출 실패: lssn=${lssn}, gateway_lssn=${gateway_lssn}, rstval=${api_rstval}, response='${api_data}', timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')" >&2
				result=1
				;;
		esac
	else
		# 🔴 [로깅 포인트 #6.3] SSH 테스트 결과 API 응답 없음
		echo "[remote_ssh_test.sh] ❌ [6.3] SSH 테스트 결과 API 응답 없음: lssn=${lssn}, gateway_lssn=${gateway_lssn}, error='No API response', timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')" >&2
		
		# Log to KVS
		if type kvs_put >/dev/null 2>&1; then
			kvs_put "lssn" "${lssn}" "remote_ssh_test_api_no_response" "{\"gateway_lssn\":${gateway_lssn},\"error\":\"No API response\"}"
		fi
		
		result=1
	fi
	
	rm -f "$api_response_file"
	return $result
}

# ============================================================================
# Exports
# ============================================================================

export -f report_ssh_test_result
