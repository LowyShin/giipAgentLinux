# test_ssh_from_gateway_json.sh 사용 가이드

## 개요

`giipAgent3.sh` 실행 중 생성되는 `/tmp/gateway_servers_*.json` 파일을 읽어서 각 서버에 대한 SSH 접속 테스트를 수행합니다.

## 빠른 시작

### 가장 간단한 사용 방법

```bash
# 최신 gateway_servers_*.json 파일 자동 감지
bash test_ssh_from_gateway_json.sh

# 특정 JSON 파일 지정
bash test_ssh_from_gateway_json.sh /tmp/gateway_servers_12345.json
```

## 출력 예시

### 콘솔 출력

```
ℹ️  JSON file not specified, searching for latest gateway_servers_*.json...
✅ Found latest file: /tmp/gateway_servers_23436.json
ℹ️  Validating JSON format...
✅ JSON format validation passed (using jq)
ℹ️  Checking for server data in JSON...
✅ Found 2 server(s) in JSON file

...

✅ Starting SSH connection tests from: /tmp/gateway_servers_23436.json
ℹ️  Report file: /tmp/ssh_test_logs/ssh_test_report_20251127_223905.txt
ℹ️  Results JSON: /tmp/ssh_test_logs/ssh_test_results_20251127_223905.json

ℹ️  Using jq for JSON parsing

[Server #1] Testing: webserver01
  └─ Address: 192.168.1.100:22
  └─ User: admin
  └─ LSSN: 1000
  └─ [1] Trying key-based auth: /home/admin/.ssh/id_rsa
  └─ ✓ Connected with key auth

[Server #2] Testing: dbserver01
  └─ Address: 192.168.1.101:22
  └─ User: root
  └─ LSSN: 1001
  └─ [1] Trying key-based auth: /home/root/.ssh/id_rsa
  │   └─ Key auth failed, trying next method...
  └─ [2] Trying password-based auth
  │   └─ Password auth failed, trying next method...
  └─ [3] Trying default SSH key from ~/.ssh
  └─ ✗ All authentication methods failed

═══════════════════════════════════════════════════════════════

📊 Test Summary

✓ Successful:     1/2
✗ Failed:         1/2
⊘ Skipped:        0/2

Success Rate:    50%

✓ Report saved to: /tmp/ssh_test_logs/ssh_test_report_20251127_223905.txt
✓ JSON results saved to: /tmp/ssh_test_logs/ssh_test_results_20251127_223905.json
```

## 출력 해석

### 서버별 테스트 과정

#### 1. 서버 정보 표시
```
[Server #1] Testing: webserver01
  └─ Address: 192.168.1.100:22
  └─ User: admin
  └─ LSSN: 1000
```
- 테스트할 서버의 기본 정보를 표시합니다

#### 2. 인증 시도 순서
```
  └─ [1] Trying key-based auth: /home/admin/.ssh/id_rsa
  └─ ✓ Connected with key auth
```
- `[1]` → `[2]` → `[3]` 순으로 인증 방식을 시도합니다
- 각 시도 결과를 실시간으로 표시합니다

#### 3. 실패 시 다음 방식 시도
```
  └─ [1] Trying key-based auth: /path/to/key
  │   └─ Key auth failed, trying next method...
  └─ [2] Trying password-based auth
```
- 하나의 인증 방식이 실패하면 다음 방식을 시도합니다

### 최종 통계

| 항목 | 설명 |
|------|------|
| ✓ Successful | 성공한 연결 수 |
| ✗ Failed | 실패한 연결 수 |
| ⊘ Skipped | 스킵된 서버 수 (필수 정보 부족) |
| Success Rate | 성공률 (색상: 100%=초록, 75%+=파랑, 50%+=노랑, <50%=빨강) |

## 결과 저장 위치

### 텍스트 리포트
```
/tmp/ssh_test_logs/ssh_test_report_YYYYMMDD_HHMMSS.txt
```

예:
```
[2025-11-27 22:39:05] [START] SSH Connection Test Started
[2025-11-27 22:39:05] [INFO] Source file: /tmp/gateway_servers_23436.json
[2025-11-27 22:39:05] [INFO] File size: 887 bytes
[2025-11-27 22:39:05] [INFO] Server count: 2
===================================================================
[2025-11-27 22:39:06] [SSH_TEST] SUCCESS | hostname:webserver01 | 192.168.1.100:22 | user:admin | LSSN:1000 | Time:0.523s
[2025-11-27 22:39:10] [SSH_TEST] FAILED | hostname:dbserver01 | 192.168.1.101:22 | user:root | LSSN:1001 | Time:10.001s | error:SSH connection with default key failed
===================================================================
```

### JSON 결과 파일
```
/tmp/ssh_test_logs/ssh_test_results_YYYYMMDD_HHMMSS.json
```

예:
```json
{
  "test_start": "2025-11-27 22:39:05",
  "source_file": "/tmp/gateway_servers_23436.json",
  "servers": [
    {
      "hostname": "webserver01",
      "ssh_host": "192.168.1.100",
      "ssh_user": "admin",
      "ssh_port": 22,
      "lssn": 1000,
      "status": "SUCCESS",
      "connection_time_sec": 0.523,
      "error": ""
    },
    {
      "hostname": "dbserver01",
      "ssh_host": "192.168.1.101",
      "ssh_user": "root",
      "ssh_port": 22,
      "lssn": 1001,
      "status": "FAILED",
      "connection_time_sec": 10.001,
      "error": "SSH connection with default key failed"
    }
  ],
  "test_end": "2025-11-27 22:39:10",
  "summary": {
    "total": 2,
    "success": 1,
    "failed": 1,
    "skipped": 0,
    "actual_processed": 2
  }
}
```

## 인증 방식 우선순위

1. **SSH 키 파일** (1순위)
   - `ssh_key_path`가 지정되고 파일이 존재하는 경우
   - 키 파일 경로: `/home/user/.ssh/id_rsa` 등

2. **비밀번호** (2순위)
   - `ssh_password`가 지정되고 `sshpass` 설치된 경우
   - sshpass 설치 확인: `which sshpass`

3. **기본 SSH 키** (3순위)
   - `~/.ssh/id_rsa`, `~/.ssh/id_dsa` 등
   - 위 두 방식 모두 실패할 때만 시도

## 상태별 의미

| 상태 | 색상 | 의미 | 대응 방법 |
|------|------|------|---------|
| SUCCESS | 🟢 녹색 | SSH 연결 성공 | 문제 없음 |
| FAILED | 🔴 빨강 | SSH 연결 실패 | IP, 포트, 인증 정보 확인 |
| SKIPPED | 🟡 노랑 | 필수 정보 부족 | DB의 서버 설정 확인 |

## 문제 해결

### "SSH key authentication failed"
```
해결 방법:
1. 키 파일 경로 확인: ssh_key_path 값 확인
2. 키 파일 권한 확인: chmod 600 /path/to/key
3. 서버에 공개 키 등록: ssh-copy-id -i /path/to/key user@host
```

### "sshpass not installed"
```
해결 방법:
1. sshpass 설치 (Ubuntu/Debian): sudo apt-get install sshpass
2. sshpass 설치 (CentOS/RHEL): sudo yum install sshpass
3. 또는 DB의 ssh_key_path에 유효한 키 파일 경로 설정
```

### "Connection timed out"
```
해결 방법:
1. 서버 IP 주소 확인: ssh_host 값 확인
2. 네트워크 연결 확인: ping {ssh_host}
3. 방화벽 설정 확인: 포트 22 열려 있는지 확인
4. SSH 서버 실행 확인: telnet {ssh_host} 22
```

### "Permission denied"
```
해결 방법:
1. 사용자명 확인: ssh_user 값 확인
2. 비밀번호 확인: ssh_password 값 확인
3. 키 파일 있는지 확인: ssh_key_path 파일 존재 여부
4. 서버에서 사용자 확인: id {user}
```

## 고급 사용법

### 특정 로그 파일 확인

```bash
# 가장 최근 리포트 확인
cat /tmp/ssh_test_logs/$(ls -t /tmp/ssh_test_logs/ssh_test_report_*.txt | head -1)

# 모든 테스트 결과 JSON 합치기
cat /tmp/ssh_test_logs/ssh_test_results_*.json | jq -s '.'

# 실패한 서버만 필터링
cat /tmp/ssh_test_logs/ssh_test_results_*.json | jq '.servers[] | select(.status=="FAILED")'
```

### 정기적인 테스트 (cron)

```bash
# 매일 오전 2시에 SSH 테스트 실행
0 2 * * * /home/user/giipAgentLinux/test_ssh_from_gateway_json.sh >> /var/log/ssh_test.log 2>&1
```

## 제한사항

- Windows에서는 WSL 또는 Git Bash 필요
- 순차 처리: 서버를 하나씩 처리 (병렬 처리 미지원)
- 기본 SSH 타임아웃: 10초 (변경 불가)

## 버전 정보

- Version: 1.0
- Last Updated: 2025-11-27
- Author: Generated Script
