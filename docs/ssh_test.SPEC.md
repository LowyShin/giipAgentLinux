# ssh_test.sh 사양서 (Gateway SSH 테스트 모듈)

## 1. 개요

### 목적
`giipAgent3.sh` 실행 중 생성되는 `/tmp/gateway_servers_*.json` 파일을 읽어서 각 서버에 대한 SSH 접속 테스트를 수행하는 독립적인 스크립트

### 버전
- Version: 1.0
- Date: 2025-11-27
- Author: Generated Script

---

## 2. 기능 명세

### 2.1 주요 기능

| 기능 | 설명 |
|------|------|
| JSON 파일 자동 감지 | `/tmp/gateway_servers_*.json` 파일을 자동으로 최신 파일 검색 |
| SSH 연결 테스트 | 각 서버에 SSH 연결을 시도하고 결과 기록 |
| 인증 방식 지원 | 키 기반 인증, 비밀번호 인증, 기본 SSH 키 인증 모두 지원 |
| 상세 로깅 | 텍스트 기반 리포트 파일 생성 |
| JSON 결과 출력 | 구조화된 JSON 형식으로 테스트 결과 저장 |
| 컬러 출력 | 색상 코드를 이용한 직관적인 콘솔 출력 |
| 요약 통계 | 성공/실패/스킵된 서버 수 통계 제공 |

### 2.2 입력 데이터 구조 (gateway_servers_*.json)

```json
{
  "data": [
    {
      "hostname": "서버명",
      "lssn": "1000",
      "ssh_host": "192.168.1.100",
      "ssh_user": "admin",
      "ssh_port": 22,
      "ssh_key_path": "/path/to/key",
      "ssh_password": "password",
      "os_info": "Linux"
    },
    ...
  ]
}
```

또는 배열 형식:
```json
[
  {
    "hostname": "서버명",
    "lssn": "1000",
    ...
  },
  ...
]
```

### 2.3 추출되는 필드

| 필드 | 타입 | 설명 | 기본값 |
|------|------|------|--------|
| `hostname` | String | 서버 호스트명 | 필수 |
| `lssn` | Number | 서버 LSSN ID | 필수 |
| `ssh_host` | String | SSH 접속 IP/도메인 | 필수 |
| `ssh_user` | String | SSH 사용자명 | 필수 |
| `ssh_port` | Number | SSH 포트 | 22 |
| `ssh_key_path` | String | SSH 개인 키 경로 | 선택사항 |
| `ssh_password` | String | SSH 비밀번호 | 선택사항 |
| `os_info` | String | 운영체제 정보 | Linux |

---

## 3. 사용 방법

### 3.1 기본 사용법

```bash
# 최신 gateway_servers_*.json 파일 자동 감지
./test_ssh_from_gateway_json.sh

# 특정 JSON 파일 지정
./test_ssh_from_gateway_json.sh /tmp/gateway_servers_12345.json

# 절대 경로 지정
./test_ssh_from_gateway_json.sh /path/to/gateway_servers.json
```

### 3.2 출력 위치

| 파일 | 경로 | 설명 |
|------|------|------|
| 텍스트 리포트 | `/tmp/ssh_test_logs/ssh_test_report_YYYYMMDD_HHMMSS.txt` | 상세 테스트 로그 |
| JSON 결과 | `/tmp/ssh_test_logs/ssh_test_results_YYYYMMDD_HHMMSS.json` | 구조화된 테스트 결과 |

---

## 4. 인증 방식 우선순위

1. **SSH 키 파일** (우선): `ssh_key_path`가 지정되고 파일이 존재하는 경우
2. **비밀번호**: `ssh_password`가 지정되고 `sshpass`가 설치된 경우
3. **기본 SSH 키**: 위 두 가지 모두 없는 경우 ~/.ssh의 기본 키 사용

---

## 4.1 "ERROR: sk variable not configured properly!" 에러

### 에러 메시지
```bash
🚨 ERROR: sk variable not configured properly!
   This file (/home/shinh/scripts/infraops01/giipAgentLinux/giipAgent.cnf) is a TEMPLATE ONLY
   Use REAL config file on production server: ~/giipAgent/giipAgent.cnf
   Command: cat ~/giipAgent/giipAgent.cnf | grep -E '^(sk|apiaddrv2|apiaddrcode)='
```

### 원인 분석

**왜 발생하는가?**

1. **git 저장소의 `giipAgent.cnf`는 템플릿** ❌
   - 이 파일은 참고용도만 제공
   - 실제 운영에 사용되지 않음
   - `sk` 값이 기본값(`<your secret key>`)이거나 비어있음

2. **실제 설정 파일의 위치** ✅
   - **Standard Agent**: `~/giipAgent/giipAgent.cnf` (홈 디렉토리)
   - **Gateway Agent**: `~/giipAgentGateway/giipAgent.cnf` (Gateway 폴더)
   - **Admin Scripts**: 저장소 상위 폴더 (상대 경로: `../../giipAgent.cnf`)

3. **파일 구조 혼동**
```
❌ 템플릿 (git 저장소 내)
/home/shinh/scripts/infraops01/giipAgentLinux/giipAgent.cnf
└── sk="<your secret key>"  ← 기본값 (비설정)

✅ 실제 파일 (홈 디렉토리)
/home/shinh/giipAgent/giipAgent.cnf
└── sk="abc123def456..."    ← 실제 값
```

### 해결 방법

**빠른 해결**:
```bash
# 실제 설정 파일이 있는지 확인
cat ~/giipAgent/giipAgent.cnf | grep -E '^(sk|apiaddrv2|apiaddrcode)='

# Secret Key 확인
grep "^sk=" ~/giipAgent/giipAgent.cnf
```

**설정 파일이 없으면**:
```bash
# 디렉토리 생성
mkdir -p ~/giipAgent

# 설정 파일 생성
cat > ~/giipAgent/giipAgent.cnf << 'EOF'
sk="YOUR_ACTUAL_SECRET_KEY_HERE"
lssn="0"
apiaddrv2="https://giipfaw.azurewebsites.net/api/giipApiSk2"
apiaddrcode="YOUR_AZURE_FUNCTION_KEY"
giipagentdelay="60"
EOF

# 권한 설정
chmod 644 ~/giipAgent/giipAgent.cnf
```

**재실행**:
```bash
# ssh_test.sh 다시 실행
bash gateway/ssh_test.sh
```

### 핵심 이해

| 구분 | 내용 |
|------|------|
| **Template 파일** | `giipAgentLinux/giipAgent.cnf` ← git 저장소 |
| **실제 파일** | `~/giipAgent/giipAgent.cnf` ← 홈 디렉토리 |
| **Template 용도** | 참고/설명용만 (실행에 사용 안 함) |
| **실제 파일 용도** | 실제 운영 에이전트가 읽음 |
| **Template sk 값** | `<your secret key>` (설정 필요함) |
| **실제 sk 값** | GIIP 포털에서 확인한 실제 키 |

---

## 5. 예외 처리

### 5.1 파일 관련 예외

| 상황 | 처리 방식 | 반환값 |
|------|---------|--------|
| JSON 파일 지정 안 됨 & `/tmp`에 파일 없음 | 에러 메시지 출력 후 종료 | exit 1 |
| 지정한 JSON 파일 없음 | 파일 존재 확인 후 에러 메시지 출력 | exit 1 |
| JSON 파일이 비어있음 | 파일 크기 확인 후 에러 메시지 출력 | exit 1 |
| JSON 파일이 손상됨 | 파싱 실패 시 jq/grep 폴백 사용 | 계속 진행 |

### 5.2 서버 매개변수 관련 예외

| 상황 | 처리 방식 | 상태 |
|------|---------|------|
| `ssh_host` 없음 | 스킵 처리 및 로깅 | SKIPPED |
| `ssh_user` 없음 | 스킵 처리 및 로깅 | SKIPPED |
| 포트 번호 없음 | 기본값 22 사용 | 계속 진행 |
| 키 파일 경로 없음 | 다음 인증 방식 시도 | 계속 진행 |

### 5.3 SSH 연결 관련 예외

| 상황 | 처리 방식 | 상태 |
|------|---------|------|
| SSH 연결 타임아웃 (10초) | 연결 실패 처리 | FAILED |
| SSH 명령 실행 오류 | 에러 메시지 기록 | FAILED |
| `sshpass` 미설치 | 비밀번호 인증 스킵 | SKIPPED |
| `jq` 미설치 | grep 폴백 사용 | 계속 진행 |

---

## 6. 테스트 결과 상태

### 6.1 상태 값

| 상태 | 의미 | 카운트 대상 |
|------|------|-----------|
| `SUCCESS` | SSH 연결 성공 | success_count |
| `FAILED` | SSH 연결 실패 | failure_count |
| `SKIPPED` | 필수 매개변수 부족 또는 도구 미설치 | skipped_count |
| `PENDING` | 테스트 진행 중 | 카운트 안 함 |

---

## 7. 출력 형식

### 7.1 콘솔 출력

```
ℹ️  Starting SSH connection tests from: /tmp/gateway_servers_12345.json
ℹ️  Report file: /tmp/ssh_test_logs/ssh_test_report_20251127_143000.txt
ℹ️  Results JSON: /tmp/ssh_test_logs/ssh_test_results_20251127_143000.json

ℹ️  Testing SSH connection to: server01 (192.168.1.100:22) [LSSN:1000]
✅ Connected successfully to server01

ℹ️  Testing SSH connection to: server02 (192.168.1.101:22) [LSSN:1001]
❌ SSH key authentication failed

===================================================================

ℹ️  Test Summary
[2025-11-27 14:30:00] [SUMMARY] Total servers: 2
[2025-11-27 14:30:00] [SUMMARY] Successful: 1
[2025-11-27 14:30:00] [SUMMARY] Failed: 1
[2025-11-27 14:30:00] [SUMMARY] Skipped: 0

✅ Report saved to: /tmp/ssh_test_logs/ssh_test_report_20251127_143000.txt
✅ JSON results saved to: /tmp/ssh_test_logs/ssh_test_results_20251127_143000.json
```

### 7.2 텍스트 리포트 형식

```
[2025-11-27 14:30:00] [START] SSH Connection Test Started
[2025-11-27 14:30:00] [INFO] Source file: /tmp/gateway_servers_12345.json
[2025-11-27 14:30:00] [INFO] File size: 1024 bytes
===================================================================
[2025-11-27 14:30:01] [SSH_TEST] SUCCESS | server01 (192.168.1.100:22) | LSSN:1000 | Time:0.523s
[2025-11-27 14:30:02] [SSH_TEST] FAILED | server02 (192.168.1.101:22) | LSSN:1001 | Time:10.001s
===================================================================

[2025-11-27 14:30:02] [SUMMARY] Total servers: 2
[2025-11-27 14:30:02] [SUMMARY] Successful: 1
[2025-11-27 14:30:02] [SUMMARY] Failed: 1
[2025-11-27 14:30:02] [SUMMARY] Skipped: 0
[2025-11-27 14:30:02] [END] SSH Connection Test Completed
```

### 7.3 JSON 결과 형식

```json
{
  "test_start": "2025-11-27 14:30:00",
  "source_file": "/tmp/gateway_servers_12345.json",
  "servers": [
    {
      "hostname": "server01",
      "ssh_host": "192.168.1.100",
      "ssh_user": "admin",
      "ssh_port": 22,
      "lssn": 1000,
      "status": "SUCCESS",
      "connection_time_sec": 0.523,
      "error": ""
    },
    {
      "hostname": "server02",
      "ssh_host": "192.168.1.101",
      "ssh_user": "admin",
      "ssh_port": 22,
      "lssn": 1001,
      "status": "FAILED",
      "connection_time_sec": 10.001,
      "error": "SSH key authentication failed"
    }
  ],
  "test_end": "2025-11-27 14:30:02",
  "summary": {
    "total": 2,
    "success": 1,
    "failed": 1,
    "skipped": 0
  }
}
```

---

## 8. 환경 요구사항

### 8.1 필수 도구
- `bash` 4.0 이상
- `curl` - API 호출용 (이미 설치됨)
- `sed`, `grep` - 텍스트 처리
- `bc` - 계산 (시간 계산)
- `ssh` - SSH 연결

### 8.2 선택사항 도구
| 도구 | 용도 | 없을 때 처리 |
|------|------|-----------|
| `jq` | JSON 파싱 | grep 폴백 사용 |
| `sshpass` | 비밀번호 인증 | 비밀번호 인증 스킵 |
| `bc` | 시간 계산 | 0으로 처리 |

---

## 9. 반환 코드

| 코드 | 의미 |
|------|------|
| 0 | 테스트 완료 (성공/실패 상관없음) |
| 1 | JSON 파일을 찾을 수 없음 |
| 1 | JSON 파일이 비어있음 |
| 1 | JSON 파일이 존재하지 않음 |

---

## 10. 로그 및 디버깅

### 10.1 로그 레벨

| 레벨 | 설명 | 예시 |
|------|------|------|
| START | 테스트 시작 | `[START] SSH Connection Test Started` |
| INFO | 정보성 로그 | `[INFO] Source file: ...` |
| SSH_TEST | SSH 테스트 결과 | `[SSH_TEST] SUCCESS \| server01 ...` |
| SUMMARY | 최종 통계 | `[SUMMARY] Total servers: ...` |
| END | 테스트 종료 | `[END] SSH Connection Test Completed` |

### 10.2 디버깅 정보

- 각 서버별 연결 시간 측정 (초 단위)
- JSON 파일 크기 기록
- 파싱 방식 (jq vs grep) 기록
- 인증 방식별 시도 기록

---

## 11. 제한사항 및 주의사항

### 11.1 보안

- SSH 개인 키 경로는 평문으로 저장됨
- SSH 비밀번호는 평문으로 JSON에 저장됨
- 로그 파일에 SSH 접속 정보가 포함될 수 있음
- `StrictHostKeyChecking=no`로 설정되어 MITM 공격에 취약할 수 있음

### 11.2 성능

- 기본 연결 타임아웃: 10초
- 명령 실행 타임아웃: 15초
- 순차 처리: 서버를 하나씩 처리 (병렬 처리 안 함)

### 11.3 호환성

- Linux/Unix 기반 시스템 전용
- Windows에서 WSL 사용 권장
- macOS 지원

---

## 12. 향후 개선사항

- [ ] 병렬 처리로 성능 향상
- [ ] SSH 포트 스캔 기능 추가
- [ ] 연결 풀 관리
- [ ] 재시도 로직 추가
- [ ] SSH 명령 커스터마이징
- [ ] 암호화된 비밀번호 저장
- [ ] SFTP 파일 전송 테스트
- [ ] 실시간 모니터링 모드
