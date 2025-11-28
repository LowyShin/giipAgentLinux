# ssh_test.sh 사용 가이드

> **📅 문서 메타데이터**  
> - 최초 작성: 2025-11-27  
> - 최종 수정: 2025-11-28  
> - 작성자: giipAgent Gateway Team  
> - 목적: ssh_test.sh 스크립트 사용 및 문제 해결 가이드
> - 적용 범위: giipAgentLinux Gateway 모드
> - 버전: 1.0
> - **준수 규칙**: PROHIBITED_ACTION #0 (추측 금지), #4 (메타데이터), #6 (Secret 보호), #11 (로그 요청 금지), #13 (조용한 실패 금지)
> - **참고 문서**: [PROHIBITED_ACTIONS.md](../../giipdb/docs/PROHIBITED_ACTIONS.md)

## 개요

`giipAgent3.sh`의 Gateway 모드에서 Remote 서버 SSH 연결 테스트를 수행합니다.
생성되는 `/tmp/gateway_servers_*.json` 파일을 읽어서 각 서버에 대한 SSH 접속 테스트를 수행합니다.

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

> **📌 근거 문서**:
> - [PROHIBITED_ACTIONS.md](../../giipdb/docs/PROHIBITED_ACTIONS.md) - 절대 금지 규칙
> - [PROHIBITED_ACTION_11_LOG_REQUEST.md](../../giipdb/docs/PROHIBITED_ACTION_11_LOG_REQUEST.md) - 로그 요청 금지
> - [PROHIBITED_ACTION_13_SILENT_FAILURES.md](../../giipdb/docs/PROHIBITED_ACTION_13_SILENT_FAILURES.md) - 오류 처리 규칙
> - [SHELL_SCRIPT_ERROR_HANDLING_STANDARD.md](../../giipdb/docs/SHELL_SCRIPT_ERROR_HANDLING_STANDARD.md) - 쉘 스크립트 오류 표준

### 📋 필수 사전 준비

ssh_test.sh 실행 전 다음을 확인하세요:

#### 필수 요구사항
1. **SSH 설정**: `~/.ssh` 디렉토리 및 인증 키 파일 존재
2. **필수 도구**: `jq` (JSON 파싱) 설치 여부 확인
3. **설정 파일**: `/<installation_path>/giipAgent.cnf` 존재 확인
4. **로그 디렉토리**: `/tmp/ssh_test_logs` 디렉토리 생성됨

#### 준비 확인
```bash
# SSH 디렉토리 확인
ls -la ~/.ssh

# jq 설치 확인
which jq

# giipAgent.cnf 파일 위치 확인
ls -la /<installation_path>/giipAgent.cnf
```

이 항목들이 없으면 ssh_test.sh 실행 시 오류가 발생합니다.

---

### 🚨 "ERROR: sk variable not configured properly!" 
> **이것은 가장 흔한 에러입니다!**

#### 에러 메시지 예시
```bash
🚨 ERROR: sk variable not configured properly!
   This file (/home/shinh/scripts/infraops01/giipAgentLinux/giipAgent.cnf) is a TEMPLATE ONLY
   Place REAL config file at: /home/shinh/scripts/infraops01/giipAgent.cnf
   To verify: cat /home/shinh/scripts/infraops01/giipAgent.cnf | grep -E '^(sk|apiaddrv2|apiaddrcode)='
```

#### 원인
- git repo 내의 `giipAgent.cnf`는 템플릿일 뿐 ❌
- ssh_test.sh는 **부모 디렉토리**에서 `giipAgent.cnf`를 찾음
- 실제 설정 파일이 필요한 위치: `giipAgentLinux` **부모 디렉토리** ✅

#### 파일 위치 구조

```
설치 디렉토리 구조
/home/shinh/scripts/infraops01/
├── giipAgent.cnf                   ✅ 실제 설정 파일 (여기!)
└── giipAgentLinux/                 ← git 저장소
    ├── gateway/
    │   └── ssh_test.sh
    ├── giipAgent.cnf                ❌ 템플릿만 (사용 안 함)
    └── ...
```

#### 해결 방법

**1단계: 현재 위치 확인**
```bash
# ssh_test.sh가 있는 곳에서 시작
pwd
# 출력 예: /home/shinh/scripts/infraops01/giipAgentLinux/gateway

# 부모 디렉토리로 이동 (설정 파일이 있어야 할 위치)
cd ../..
pwd
# 출력 예: /home/shinh/scripts/infraops01

# 설정 파일 확인
ls -la giipAgent.cnf
cat giipAgent.cnf | grep -E '^(sk|apiaddrv2|apiaddrcode)='
```

**2단계: 설정 파일이 없으면 생성**
```bash
# 현재 위치: /home/shinh/scripts/infraops01 (giipAgentLinux의 부모 디렉토리)
cat > giipAgent.cnf << 'EOF'
# Secret Key for GIIP API
sk="YOUR_ACTUAL_SECRET_KEY_HERE"

# Server ID
lssn="0"

# API v2 Address
apiaddrv2="https://giipfaw.azurewebsites.net/api/giipApiSk2"
apiaddrcode="YOUR_AZURE_FUNCTION_KEY_HERE"

# Agent Delay (seconds)
giipagentdelay="60"
EOF

chmod 600 giipAgent.cnf

# 확인
cat giipAgent.cnf
```

**3단계: SSH 테스트 실행**
```bash
# 현재 위치에서 상대 경로로 실행
cd giipAgentLinux/gateway
bash ssh_test.sh

# 또는 절대 경로로 실행
bash /home/shinh/scripts/infraops01/giipAgentLinux/gateway/ssh_test.sh
```

#### 중요한 구분

| 파일 | 위치 | 용도 | 실제 사용 |
|------|------|------|---------|
| **템플릿** | `giipAgentLinux/giipAgent.cnf` | 참고용 | ❌ 아님 |
| **실제 설정** | `giipAgentLinux` **부모 디렉토리**/giipAgent.cnf | 운영 설정 | ✅ 사용됨 |

### "SSH key authentication failed"

**원인**: SSH 키 인증이 실패함  
**확인 항목**:
1. 키 파일 경로가 DB의 `ssh_key_path` 값과 일치하는가?
2. 키 파일의 권한이 600인가? (`ls -la ~/.ssh/id_rsa` 출력에서 `-rw-------`)
3. 대상 서버의 `~/.ssh/authorized_keys`에 공개 키가 등록되어 있는가?

**수동 복구 방법**:
```bash
# 권한 수정
chmod 600 ~/.ssh/id_rsa

# 공개 키 설치
ssh-copy-id -i ~/.ssh/id_rsa user@host
```

### "sshpass not installed"

**원인**: 비밀번호 기반 SSH 인증이 필요하지만 sshpass가 설치되지 않은 경우  
**영향**: 비밀번호 인증은 스킵되고, SSH 키 기반 인증만 시도됨  
**해결** (선택사항, 비밀번호 인증이 필요한 경우만):
- Ubuntu/Debian: `sudo apt-get install -y sshpass`
- CentOS/RHEL: `sudo yum install -y sshpass`
- macOS: `brew install sshpass`

### "Connection timed out"

**원인**: SSH 서버에 접근할 수 없음  
**확인 항목**:
1. 서버 IP 주소가 DB의 `ssh_host` 값과 일치하는가?
2. 네트워크 연결 확인: `ping {ssh_host}` 응답 여부
3. 방화벽이 포트 22를 차단했는가? (`telnet {ssh_host} 22`)
4. 대상 서버의 SSH 서버가 실행 중인가?

### "Permission denied"

**원인**: SSH 접근이 거부됨  
**증거**: SSH 서버가 인증을 거부함 (로그 파일: `/tmp/ssh_test_logs/ssh_test_report_*.txt`)

**확인 항목**:
1. 사용자명이 DB의 `ssh_user` 값과 일치하는가?
2. 비밀번호가 올바른가? (암호화된 상태로 저장)
3. 키 파일이 지정되었을 경우, 파일 존재 여부 확인
4. 대상 서버에서 사용자 계정이 존재하는가?

## 고급 사용법

### 자동 진단 및 모니터링

#### 진단 스크립트 (자동 실행)

```bash
# gateway.sh에서 자동으로 생성되는 로그 파일 위치
/tmp/ssh_test_logs/ssh_test_report_YYYYMMDD_HHMMSS.txt
/tmp/ssh_test_logs/ssh_test_results_YYYYMMDD_HHMMSS.json
```

> **근거**: [PROHIBITED_ACTION_11_LOG_REQUEST.md](../../giipdb/docs/PROHIBITED_ACTION_11_LOG_REQUEST.md) - 사용자에게 로그를 요청하지 말고, AI/시스템이 자동으로 진단하도록 설계.

> ⚠️ **중요**: 문제 진단 시 AI나 지원팀에 직접 로그를 요청하지 마세요.  
> 대신 위 파일들을 자동으로 수집하는 진단 스크립트를 실행해주세요.

#### 정기적인 자동 테스트 (cron)

```bash
# /etc/crontab 또는 crontab -e에 추가
# 매일 오전 2시에 SSH 테스트 자동 실행
0 2 * * * cd /path/to/giipAgentLinux && bash gateway/ssh_test.sh > /var/log/ssh_test_cron.log 2>&1
```

#### 문제 진단 시 표준 절차

**문제 발생 시**: 반드시 다음 단계를 따르세요

1. 최근 로그 자동 생성 확인:
   ```bash
   ls -lt /tmp/ssh_test_logs/ssh_test_report_*.txt | head -5
   ```

2. 로그 파일 확인:
   ```bash
   cat /tmp/ssh_test_logs/ssh_test_report_*.txt
   cat /tmp/ssh_test_logs/ssh_test_results_*.json
   ```

> **근거**: [PROHIBITED_ACTION_13_SILENT_FAILURES.md](../../giipdb/docs/PROHIBITED_ACTION_13_SILENT_FAILURES.md) - 모든 오류는 기록되어야 하며, [SHELL_SCRIPT_ERROR_HANDLING_STANDARD.md](../../giipdb/docs/SHELL_SCRIPT_ERROR_HANDLING_STANDARD.md)에 따라 구조화된 로깅 필수.

## 제한사항

- Windows에서는 WSL 또는 Git Bash 필요
- 순차 처리: 서버를 하나씩 처리 (병렬 처리 미지원)
- 기본 SSH 타임아웃: 10초 (변경 불가)

## 버전 정보

- Version: 1.0
- Last Updated: 2025-11-27
- Author: Generated Script
