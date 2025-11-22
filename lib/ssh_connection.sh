# ============================================================================
# SSH Connection Test Functions
# ============================================================================

# Function: Test SSH connection to remote server (Connection Test Only)
# Purpose: 리모트 서버의 SSH 연결성을 테스트하고 결과를 반환
# Parameters:
#   $1: remote_host - 리모트 서버의 호스트명 또는 IP 주소
#   $2: remote_port - SSH 포트 (기본값: 22)
#   $3: remote_user - SSH 사용자명
#   $4: ssh_key - SSH 개인키 파일 경로 (password 모드가 아닐 경우)
#   $5: ssh_password - SSH 비밀번호 (password 모드 사용 시)
#   $6: remote_lssn - (선택) 리모트 서버의 LSSN (로깅용)
#   $7: hostname - (선택) 리모트 서버의 호스트명 (로깅용)
#
# Return:
#   0 = SSH 연결 성공
#   1 = SSH 연결 실패
#   127 = sshpass 미설치
#   126 = SSH 명령 실패
#
# Usage Example:
#   # 비밀번호 인증 방식
#   test_ssh_connection "192.168.1.100" "22" "root" "" "mypassword" "1001" "server-01"
#   result=$?
#   
#   # 키 기반 인증 방식
#   test_ssh_connection "192.168.1.100" "22" "ubuntu" "/home/user/.ssh/id_rsa" "" "1002" "server-02"
#   result=$?

test_ssh_connection() {
	local remote_host=$1
	local remote_port=${2:-22}
	local remote_user=$3
	local ssh_key=$4
	local ssh_password=$5
	local remote_lssn=${6:-0}
	local hostname=${7:-"unknown"}
	
	# SSH 옵션: 엄격한 호스트 키 체크 비활성화, 타임아웃 설정, 배치 모드
	local ssh_opts="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"
	
	# 시작 시간 기록
	local start_time=$(date +%s)
	
	# 인증 방식 결정
	local auth_method="none"
	if [ -n "${ssh_password}" ]; then
		auth_method="password"
	elif [ -n "${ssh_key}" ] && [ -f "${ssh_key}" ]; then
		auth_method="key"
	fi
	
	# 연결 시도 로그
	echo "[ssh_connection.sh] 🟢 SSH 연결 테스트 시작: host=${remote_host}, port=${remote_port}, user=${remote_user}, auth=${auth_method}, lssn=${remote_lssn}" >&2
	
	local exit_code=1
	
	# 비밀번호 인증 방식
	if [ -n "${ssh_password}" ]; then
		# sshpass 설치 여부 확인
		if ! command -v sshpass &> /dev/null; then
			echo "[ssh_connection.sh] ❌ sshpass 명령 미설치: host=${remote_host}, lssn=${remote_lssn}" >&2
			local duration=$(($(date +%s) - start_time))
			echo "[ssh_connection.sh] 연결 실패 (sshpass 미설치): duration=${duration}초" >&2
			return 127
		fi
		
		# SSH 접속 테스트 (simple echo command)
		# sshpass를 사용하여 비밀번호 전달
		sshpass -p "${ssh_password}" ssh ${ssh_opts} -p ${remote_port} \
			${remote_user}@${remote_host} \
			"echo 'SSH connection test successful'" > /dev/null 2>&1
		
		exit_code=$?
	
	# 키 기반 인증 방식
	elif [ -n "${ssh_key}" ] && [ -f "${ssh_key}" ]; then
		# SSH 접속 테스트 (simple echo command)
		ssh ${ssh_opts} -i ${ssh_key} -p ${remote_port} \
			${remote_user}@${remote_host} \
			"echo 'SSH connection test successful'" > /dev/null 2>&1
		
		exit_code=$?
	
	# 인증 방식 없음
	else
		echo "[ssh_connection.sh] ❌ 사용 가능한 인증 방식 없음: host=${remote_host}, lssn=${remote_lssn}" >&2
		local duration=$(($(date +%s) - start_time))
		echo "[ssh_connection.sh] 연결 실패 (인증 방식 없음): duration=${duration}초" >&2
		return 125
	fi
	
	# 소요 시간 계산
	local duration=$(($(date +%s) - start_time))
	
	# 결과 로깅
	if [ $exit_code -eq 0 ]; then
		echo "[ssh_connection.sh] 🟢 SSH 연결 성공: host=${remote_host}:${remote_port}, user=${remote_user}, auth=${auth_method}, duration=${duration}초, lssn=${remote_lssn}, hostname=${hostname}" >&2
	else
		echo "[ssh_connection.sh] ❌ SSH 연결 실패: host=${remote_host}:${remote_port}, user=${remote_user}, auth=${auth_method}, exit_code=${exit_code}, duration=${duration}초, lssn=${remote_lssn}, hostname=${hostname}" >&2
	fi
	
	return $exit_code
}

# ============================================================================
# Exports
# ============================================================================

export -f test_ssh_connection
