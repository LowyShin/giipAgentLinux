# SSH Connection Test Module - 사용 가이드

## 개요

`ssh_connection.sh` 모듈은 giipAgentLinux에서 리모트 서버로의 SSH 연결을 테스트하고 원격 명령을 실행하기 위한 별도 컴포넌트입니다.

이 모듈은 다음과 같은 기능을 제공합니다:
- ✅ SSH 연결 테스트 (연결성 확인만)
- ✅ 원격 서버에서 스크립트 실행
- ✅ 비밀번호 인증 및 키 기반 인증 지원
- ✅ 상세한 로깅 및 오류 처리
- ✅ 다른 스크립트에서 독립적으로 사용 가능

## 파일 구조

```
giipAgentLinux/
├── lib/
│   ├── ssh_connection.sh       # 📦 NEW: SSH 연결 테스트 모듈
│   ├── gateway.sh              # ✏️ 수정됨: ssh_connection.sh 로드
│   ├── remote_ssh_test.sh      # API 결과 보고
│   └── ... (기타 모듈)
└── test-ssh-connection.sh      # 📦 NEW: 테스트 및 사용 예제 스크립트
```

## 함수 레퍼런스

### 1. test_ssh_connection() - SSH 연결 테스트

**목적:** 리모트 서버의 SSH 연결성을 테스트합니다.

**사용법:**
```bash
test_ssh_connection <host> <port> <user> <key> <password> [lssn] [hostname]
```

**매개변수:**

| 매개변수 | 설명 | 필수 | 기본값 |
|---------|------|------|--------|
| host | 리모트 서버의 IP 또는 호스트명 | O | - |
| port | SSH 포트 | O | - |
| user | SSH 사용자명 | O | - |
| key | SSH 개인키 파일 경로 (키 인증 시) | X | - |
| password | SSH 비밀번호 (비밀번호 인증 시) | X | - |
| lssn | 리모트 서버 LSSN (로깅용) | X | 0 |
| hostname | 호스트명 (로깅용) | X | unknown |

**반환값:**

| 코드 | 설명 |
|------|------|
| 0 | SSH 연결 성공 |
| 1 | SSH 연결 실패 (타임아웃, 거부, 인증 실패 등) |
| 125 | 인증 정보 없음 (비밀번호도 키도 제공 안 됨) |
| 126 | SSH 명령 실패 |
| 127 | sshpass 미설치 (비밀번호 인증 사용 시) |

**사용 예제:**

```bash
# 비밀번호 인증 방식
test_ssh_connection "192.168.1.100" "22" "root" "" "mypassword" "1001" "server-01"
if [ $? -eq 0 ]; then
    echo "✅ SSH 연결 성공"
else
    echo "❌ SSH 연결 실패"
fi

# 키 기반 인증 방식
test_ssh_connection "192.168.1.101" "22" "ubuntu" "/home/user/.ssh/id_rsa" "" "1002" "server-02"
result=$?

# 비표준 포트 사용
test_ssh_connection "192.168.1.102" "2222" "admin" "" "securepass" "1003" "server-03"
```

---

### 2. execute_remote_command() - 원격 명령 실행

**목적:** SSH를 통해 리모트 서버에서 스크립트를 실행합니다.

**사용법:**
```bash
execute_remote_command <host> <user> <port> <key> <password> <script> [lssn] [hostname]
```

**매개변수:**

| 매개변수 | 설명 | 필수 |
|---------|------|------|
| host | 리모트 서버의 IP 또는 호스트명 | O |
| user | SSH 사용자명 | O |
| port | SSH 포트 | O |
| key | SSH 개인키 파일 경로 | O |
| password | SSH 비밀번호 | O |
| script | 실행할 로컬 스크립트 파일 경로 | O |
| lssn | 리모트 서버 LSSN (로깅용) | X |
| hostname | 호스트명 (로깅용) | X |

**동작 프로세스:**
1. SCP를 사용하여 스크립트를 리모트 서버의 `/tmp/giipTmpScript.sh`로 전송
2. 리모트 서버에서 스크립트에 실행 권한(chmod +x) 부여
3. 스크립트 실행
4. 실행 후 원격 임시 파일 삭제

**반환값:** 0 = 성공, 1 = 실패

**사용 예제:**

```bash
# 로컬 스크립트 파일 준비
cat > /tmp/check_disk.sh << 'EOF'
#!/bin/bash
df -h / | tail -1
echo "Disk check completed"
EOF

# 비밀번호 인증으로 실행
execute_remote_command "192.168.1.100" "root" "22" "" "mypassword" \
                      "/tmp/check_disk.sh" "1001" "server-01"

if [ $? -eq 0 ]; then
    echo "✅ 원격 명령 실행 성공"
else
    echo "❌ 원격 명령 실행 실패"
fi

# 키 기반 인증으로 실행
execute_remote_command "192.168.1.101" "ubuntu" "22" \
                      "/home/user/.ssh/id_rsa" "" \
                      "/tmp/check_disk.sh" "1002" "server-02"
```

---

## 사용 시나리오

### 시나리오 1: 단일 서버 연결 테스트

```bash
#!/bin/bash

# 모듈 로드
. /path/to/lib/ssh_connection.sh

# 테스트 수행
test_ssh_connection "192.168.1.100" "22" "root" "" "password123" "5001" "prod-app"

exit_code=$?

# 결과 처리
case $exit_code in
    0)
        echo "✅ 연결 성공 - 원격 명령 실행 진행"
        # 다음 단계: execute_remote_command 호출
        ;;
    125)
        echo "❌ 인증 정보 필요"
        exit 1
        ;;
    127)
        echo "❌ sshpass 미설치 - 설치 필요"
        exit 1
        ;;
    *)
        echo "❌ 연결 실패 (코드: $exit_code)"
        exit 1
        ;;
esac
```

### 시나리오 2: 여러 서버 배치 테스트

```bash
#!/bin/bash

. /path/to/lib/ssh_connection.sh

# 서버 목록
SERVERS=(
    "prod-web-01:192.168.1.100:root:password123:5001"
    "prod-web-02:192.168.1.101:root:password123:5002"
    "prod-app-01:192.168.1.102:ubuntu:/etc/ssh/key.pem:5003"
)

# 테스트 루프
for server_info in "${SERVERS[@]}"; do
    IFS=':' read -r name host user auth_data lssn <<< "$server_info"
    
    # 인증 방식 판단
    if [ -f "$auth_data" ]; then
        key="$auth_data"
        pass=""
    else
        key=""
        pass="$auth_data"
    fi
    
    echo "[테스트] $name 연결 테스트 중..."
    test_ssh_connection "$host" "22" "$user" "$key" "$pass" "$lssn" "$name"
    
    if [ $? -eq 0 ]; then
        echo "✅ $name 성공"
    else
        echo "❌ $name 실패"
    fi
done
```

### 시나리오 3: Gateway에서 사용

```bash
# gateway.sh는 이미 ssh_connection.sh를 로드하고 있습니다.
# lib/gateway.sh에서:

# process_single_server 함수 내부에서:
test_ssh_connection "$ssh_host" "$ssh_port" "$ssh_user" \
                   "$ssh_key_path" "$ssh_password" \
                   "$server_lssn" "$hostname"

if [ $? -eq 0 ]; then
    # SSH 연결 성공 - 원격 명령 실행
    execute_remote_command "$ssh_host" "$ssh_user" "$ssh_port" \
                          "$ssh_key_path" "$ssh_password" \
                          "$script_file" "$server_lssn" "$hostname"
fi
```

### 시나리오 4: 재시도 로직 포함

```bash
#!/bin/bash

. /path/to/lib/ssh_connection.sh

MAX_RETRIES=3
RETRY_INTERVAL=5

test_with_retry() {
    local host=$1
    local port=$2
    local user=$3
    local key=$4
    local pass=$5
    local lssn=$6
    local name=$7
    
    for attempt in $(seq 1 $MAX_RETRIES); do
        echo "[$name] 시도 $attempt/$MAX_RETRIES"
        
        test_ssh_connection "$host" "$port" "$user" "$key" "$pass" "$lssn" "$name"
        
        if [ $? -eq 0 ]; then
            echo "✅ $name 연결 성공"
            return 0
        fi
        
        if [ $attempt -lt $MAX_RETRIES ]; then
            echo "⚠️  ${RETRY_INTERVAL}초 후 재시도..."
            sleep $RETRY_INTERVAL
        fi
    done
    
    echo "❌ $name 연결 실패 (모든 재시도 소진)"
    return 1
}

# 사용
test_with_retry "192.168.1.100" "22" "root" "" "password" "5001" "server-01"
```

---

## 로깅

모든 SSH 연결 테스트는 stderr에 상세한 로깅 정보를 출력합니다.

**로그 포맷:**
```
[ssh_connection.sh] 🟢 SSH 연결 테스트 시작: host=192.168.1.100, port=22, user=root, auth=password, lssn=5001, timestamp=2025-11-22 10:30:45.123

[ssh_connection.sh] 🟢 SSH 연결 성공: host=192.168.1.100:22, user=root, auth=password, duration=2초, lssn=5001, hostname=server-01, timestamp=2025-11-22 10:30:47.456

[ssh_connection.sh] ❌ SSH 연결 실패: host=192.168.1.100:22, user=root, auth=password, exit_code=1, duration=10초, lssn=5001, hostname=server-01, timestamp=2025-11-22 10:30:55.789
```

**로그 캡처:**
```bash
# stderr를 파일로 리다이렉트
test_ssh_connection "host" "22" "user" "" "pass" "1001" "srv" 2> /tmp/ssh_test.log

# 로그 확인
cat /tmp/ssh_test.log

# 특정 정보 추출
grep "성공" /tmp/ssh_test.log      # 성공한 연결만
grep "❌" /tmp/ssh_test.log         # 실패한 연결만
grep "duration" /tmp/ssh_test.log  # 소요 시간 정보
```

---

## 테스트 스크립트 실행

포함된 테스트 스크립트를 사용하여 모듈의 기능을 확인할 수 있습니다.

```bash
# 테스트 스크립트 실행
bash /path/to/test-ssh-connection.sh

# 출력 내용:
# - SSH 연결 테스트 실패 케이스 시연
# - 다양한 사용 예제
# - 함수 레퍼런스
# - 실제 프로덕션 사용 예제
```

---

## 설치 및 의존성

### 필수 요구사항

1. **Bash 4.0 이상**
2. **SSH 클라이언트 설치**
   ```bash
   # CentOS/RHEL
   yum install -y openssh-clients
   
   # Ubuntu/Debian
   apt-get install -y openssh-client
   ```

3. **비밀번호 인증 사용 시: sshpass 설치**
   ```bash
   # CentOS/RHEL
   yum install -y sshpass
   
   # Ubuntu/Debian
   apt-get install -y sshpass
   
   # 또는 giipAgent3.sh 실행 시 자동 설치됨
   ```

### 선택 사항

- **jq** (JSON 파싱 최적화용)
  ```bash
  # CentOS/RHEL
  yum install -y jq
  
  # Ubuntu/Debian
  apt-get install -y jq
  ```

---

## 보안 고려사항

### 1. 비밀번호 보안

- 스크립트에 비밀번호를 하드코딩하지 마세요
- 환경 변수나 설정 파일(제한된 권한)을 사용하세요
- 프로덕션 환경에서는 SSH 키 기반 인증을 권장합니다

```bash
# ❌ 나쁜 예
test_ssh_connection "host" "22" "user" "" "hardcoded_password" "1001" "srv"

# ✅ 좋은 예
SSH_PASS=$(cat /etc/giip/ssh_password)  # 권한: 600
test_ssh_connection "host" "22" "user" "" "$SSH_PASS" "1001" "srv"
```

### 2. SSH 키 보안

- SSH 개인키 파일 권한: `600`
- SSH 개인키 위치: 안전한 경로 (예: `/etc/giip/ssh/`)
- 공개 저장소에 개인키 업로드 금지

```bash
# 키 파일 권한 설정
chmod 600 /etc/giip/ssh/id_rsa
chmod 700 /etc/giip/ssh/
```

### 3. StrictHostKeyChecking 설정

현재 모듈은 `StrictHostKeyChecking=no`를 사용합니다. 프로덕션 환경에서 필요시 수정하세요:

```bash
# ssh_connection.sh 수정
local ssh_opts="-o StrictHostKeyChecking=accept-new ..."
```

---

## 트러블슈팅

### 문제: "Permission denied (publickey,password)"

```bash
# 확인 사항:
1. 사용자명 확인: 실제 리모트 서버의 SSH 사용자와 일치?
2. 비밀번호 확인: 올바른 비밀번호 입력?
3. 키 파일 확인: 올바른 개인키 파일?
4. 권한 확인: 키 파일 권한 600?
```

### 문제: "sshpass not found"

```bash
# 해결: sshpass 설치
sudo yum install -y sshpass     # CentOS/RHEL
sudo apt-get install -y sshpass # Ubuntu/Debian
```

### 문제: "Connection timeout"

```bash
# 확인 사항:
1. 호스트 주소 정확성
2. 포트 번호 정확성
3. 네트워크 연결성: ping 192.168.1.100
4. 방화벽 설정: SSH 포트 개방 여부
5. 리모트 서버 SSH 서비스 실행 상태
```

### 문제: "scp: command not found"

```bash
# 해결: SSH 클라이언트 설치 필요
# scp는 ssh 패키지에 포함되어 있습니다
sudo yum install -y openssh-clients     # CentOS/RHEL
sudo apt-get install -y openssh-client  # Ubuntu/Debian
```

---

## 마이그레이션 가이드 (기존 코드)

기존에 `gateway.sh` 내부에서 `execute_remote_command()`를 호출했다면, 동일하게 계속 사용할 수 있습니다.

```bash
# gateway.sh 내부에서 (수정 불필요)
execute_remote_command "$ssh_host" "$ssh_user" "$ssh_port" \
                      "$ssh_key_path" "$ssh_password" \
                      "$tmpfile" "$server_lssn" "$hostname"

# 모듈이 자동으로 ssh_connection.sh에서 로드됩니다.
```

새로운 `test_ssh_connection()` 함수는 연결 테스트만 필요할 때 사용합니다:

```bash
# 연결 테스트만 필요한 경우
test_ssh_connection "$ssh_host" "$ssh_port" "$ssh_user" \
                   "$ssh_key_path" "$ssh_password" \
                   "$server_lssn" "$hostname"

if [ $? -eq 0 ]; then
    # 연결 성공 - 다음 작업 진행
fi
```

---

## 라이센스

giipAgent 프로젝트의 일부입니다.

---

## 버전 히스토리

- **v1.00** (2025-11-22): 초기 버전
  - test_ssh_connection() 함수 추가
  - execute_remote_command() 함수 분리 및 최적화
  - 상세한 로깅 기능
  - 여러 인증 방식 지원
