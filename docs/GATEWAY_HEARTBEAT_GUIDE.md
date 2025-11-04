# GIIP Agent Gateway - Heartbeat 설정 가이드

## 개요
Gateway 서버가 관리 중인 원격 서버들의 정보를 자동으로 수집하여 DB에 업데이트하는 기능입니다.

## 동작 방식

```
┌─────────────────┐                    ┌──────────────────┐
│ Gateway Server  │                    │  Remote Server 1 │
│                 │ ──SSH Connect──>   │  (No Agent)      │
│ Heartbeat       │ <─Server Info───   │                  │
│ Script Running  │                    └──────────────────┘
│                 │                    
│                 │                    ┌──────────────────┐
│                 │ ──SSH Connect──>   │  Remote Server 2 │
│                 │ <─Server Info───   │  (No Agent)      │
│                 │                    └──────────────────┘
│                 │                    
│                 │ ──API Call──>      ┌──────────────────┐
│                 │                    │  GIIP DB         │
│                 │ <─Update LSChkdt── │  tLSvr Table     │
└─────────────────┘                    └──────────────────┘
```

## 설치 순서

### 1. Gateway 서버 설정

```bash
cd /home/giip/giipAgentLinux

# 설정 파일 생성
cp giipAgentGateway.cnf.template giipAgentGateway.cnf
vi giipAgentGateway.cnf
```

**필수 설정 항목**:
```bash
# Secret Key (GIIP 포털에서 확인)
sk="your_secret_key_here"

# Azure Function API 설정
apiaddrv2="https://giipfaw.azurewebsites.net/api/giipApiSk2"
apiaddrcode="your_azure_function_key"

# Gateway 서버 정보
gateway_lssn="71240"    # 이 Gateway 서버의 LSSN (tLSvr 테이블에서 확인)
csn="70363"             # 고객사 번호 (tCorp 테이블에서 확인)

# Heartbeat 주기 (초)
heartbeat_interval="300"  # 5분마다 실행
```

### 2. 필수 도구 설치

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y ssh sshpass curl jq

# CentOS/RHEL
sudo yum install -y openssh-clients sshpass curl jq
```

### 3. 스크립트 권한 설정

```bash
chmod +x giipAgentGateway-heartbeat.sh
```

### 4. 수동 테스트

```bash
# 단일 실행 테스트
./giipAgentGateway-heartbeat.sh

# 로그 확인
tail -f /var/log/giipAgentGateway_heartbeat_$(date +%Y%m%d).log
```

### 5. Cron 등록 (자동 실행)

```bash
# Crontab 편집
crontab -e

# 5분마다 실행
*/5 * * * * cd /home/giip/giipAgentLinux && ./giipAgentGateway-heartbeat.sh >/dev/null 2>&1

# 또는 10분마다 실행
*/10 * * * * cd /home/giip/giipAgentLinux && ./giipAgentGateway-heartbeat.sh >/dev/null 2>&1
```

## 원격 서버 등록

### Web UI에서 등록

1. GIIP 포털 로그인
2. **Server List** 메뉴
3. **Add Server** 버튼
4. 서버 정보 입력:
   - **Hostname**: p-cnsldb01m
   - **Gateway Server**: Gateway 서버 선택
   - **SSH Connection**:
     - SSH Host: p-cnsldb01m (또는 IP)
     - SSH Port: 22
     - SSH User: istyle
     - Auth Type: Password
     - SSH Password: ****
5. **Save** 버튼

### API로 등록 (선택사항)

```bash
curl -X POST "https://giipfaw.azurewebsites.net/api/giipApiSk2?code=YOUR_CODE" \
  -H "Content-Type: application/json" \
  -d '{
    "text": "ServerAdd",
    "token": "YOUR_SK",
    "csn": 70363,
    "jsondata": {
      "LSHostname": "p-cnsldb01m",
      "gateway_lssn": 71240,
      "gateway_ssh_host": "p-cnsldb01m",
      "gateway_ssh_user": "istyle",
      "gateway_ssh_port": 22,
      "gateway_auth_type": "password",
      "gateway_ssh_password": "YOUR_PASSWORD"
    }
  }'
```

## 작동 확인

### 1. 로그 확인

```bash
# 오늘 로그
tail -f /var/log/giipAgentGateway_heartbeat_$(date +%Y%m%d).log

# 예상 출력:
# [20251104123456] Gateway Heartbeat Started (v1.0) - Gateway LSSN: 71240
# [20251104123456] Fetching managed server list from API...
# [20251104123457] Found 3 managed servers
# [20251104123457] Processing: p-cnsldb01m (LSSN: 71221) → istyle@p-cnsldb01m:22
# [20251104123458]   → ✅ Info collected successfully
# [20251104123459]   → ✅ Update successful
```

### 2. DB 확인

```sql
-- 최근 체크된 서버 목록
SELECT 
    LSSN,
    LSHostname,
    LSChkdt,
    DATEDIFF(MINUTE, LSChkdt, GETDATE()) AS minutes_ago,
    gateway_lssn
FROM tLSvr
WHERE gateway_lssn = 71240  -- Gateway LSSN
ORDER BY LSChkdt DESC;
```

### 3. Web UI 확인

1. **Server Detail** 페이지 접속
2. Gateway 서버 상세 페이지에서 **"관리 중인 서버 목록"** 확인
3. 각 서버의 상태가 "정상" 또는 "지연"으로 표시되는지 확인
4. "미체크 (아직 점검 안 됨)" 상태가 사라졌는지 확인

## 트러블슈팅

### 문제: "jq: command not found"

```bash
# Ubuntu/Debian
sudo apt-get install jq

# CentOS/RHEL
sudo yum install jq
```

### 문제: "sshpass: command not found"

```bash
# Ubuntu/Debian
sudo apt-get install sshpass

# CentOS/RHEL
sudo yum install sshpass
```

### 문제: SSH 연결 실패

```bash
# 수동으로 SSH 연결 테스트
ssh -o StrictHostKeyChecking=no istyle@p-cnsldb01m

# Password 방식인 경우
sshpass -p 'your_password' ssh -o StrictHostKeyChecking=no istyle@p-cnsldb01m

# 연결 성공하면 hostname 확인
hostname -f
exit
```

### 문제: API 호출 실패

```bash
# Gateway 설정 확인
grep -E "gateway_lssn|csn|sk|apiaddrv2|apiaddrcode" giipAgentGateway.cnf

# API 테스트 (수동 호출)
curl -X POST "https://giipfaw.azurewebsites.net/api/giipApiSk2?code=YOUR_CODE" \
  -H "Content-Type: application/json" \
  -d '{
    "text": "GatewayRemoteServerList",
    "token": "YOUR_SK",
    "csn": 70363,
    "gateway_lssn": 71240
  }'
```

### 문제: 서버 목록이 비어있음

```sql
-- DB에서 Gateway 관리 서버 확인
SELECT LSSN, LSHostname, gateway_lssn, gateway_ssh_host, gateway_ssh_user
FROM tLSvr
WHERE gateway_lssn = 71240;  -- Gateway LSSN

-- 결과가 없으면 서버를 Gateway에 등록해야 함
```

## 수집되는 정보

- **Hostname**: 서버 호스트명
- **OS**: OS 종류 및 버전
- **Memory**: 전체 메모리 (GB)
- **Disk**: 디스크 용량 (GB)
- **CPU**: CPU 모델 및 코어 수
- **IP**: Primary IP 주소
- **LSChkdt**: 마지막 체크 시간 (자동 업데이트)

## 참고 문서

- [Gateway 설치 가이드](./README_GATEWAY.md)
- [Gateway 빠른 시작 가이드](./GATEWAY_QUICKSTART_KR.md)
- [API 호출 규칙](../giipv3/docs/giipapi_rules.md)

## 라이센스

MIT License - Free to use and modify
