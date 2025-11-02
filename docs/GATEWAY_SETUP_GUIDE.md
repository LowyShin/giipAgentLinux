# Gateway 서버를 통한 원격 서버 제어 가이드

## 📋 환경 개요

### Gateway 서버의 역할
- 원격 서버와 GIIP API 사이의 중계 역할
- 인터넷 접속이 가능한 서버에 설치
- SSH를 통해 원격 서버들을 제어

### 제어 대상 서버
- 직접 인터넷 접속이 불가능한 서버
- Gateway 서버에서 SSH 접속 가능
- 각 서버는 고유한 LSSN(서버 ID) 보유

> **참고**: 이 문서는 실제 운영 환경 설정 예시입니다. LSSN과 IP는 샘플이므로 실제 환경에 맞게 수정하세요.

---

## 🎯 작동 원리

```
┌─────────────────────┐
│   GIIP API Server   │
│ (Azure Functions)   │
└──────────┬──────────┘
           │ HTTPS
           │ Queue 다운로드 (각 서버의 LSSN별)
           │
┌──────────▼──────────┐
│  Gateway Server     │
│  LSSN: (예: 71240)  │ ← 인터넷 접속 가능
│ giipAgentGateway.sh │
└──────────┬──────────┘
           │ SSH
           ├─────────────────┬─────────────────┐
           │                 │                 │
┌──────────▼──────────┐  ┌──▼────────────┐  ┌──▼────────────┐
│  Server 1           │  │  Server 2     │  │  Server 3     │
│  LSSN: (예: 71221)  │  │  LSSN: 71222  │  │  LSSN: 71223  │
│  명령 실행          │  │  명령 실행    │  │  명령 실행    │
└─────────────────────┘  └───────────────┘  └───────────────┘
```

**동작 순서**:
1. Gateway가 GIIP API에서 각 서버의 명령 큐를 LSSN별로 다운로드
2. SSH를 통해 각 서버에 연결
3. 다운로드한 명령을 원격 서버에서 실행
4. 실행 결과를 GIIP API에 전송

---

## ⚙️ 설치 및 설정

### Step 1: Gateway 서버에 접속

```bash
# Gateway 서버에 SSH 접속
ssh user@gateway-server-ip

# 작업 디렉토리로 이동 (없으면 giipAgentLinux 클론)
cd ~/giipAgentLinux

# Gateway 자동 설치 스크립트 실행
chmod +x install-gateway.sh
./install-gateway.sh
```

> **간단 설치 방법**: install-gateway.sh를 실행하면 자동으로 설정됩니다.
> 
> 수동 설치를 원하면 다음 명령으로 직접 설정할 수도 있습니다:
> ```bash
> mkdir -p ~/giipAgentGateway && cd ~/giipAgentGateway
> cp ~/giipAgentLinux/giipAgentGateway.sh .
> cp ~/giipAgentLinux/giipAgentGateway.cnf.template giipAgentGateway.cnf
> cp ~/giipAgentLinux/giipAgentGateway_servers.csv.template giipAgentGateway_servers.csv
> chmod +x giipAgentGateway.sh
> ```

### Step 2: Gateway 설정 파일 편집

#### 2-1. `giipAgentGateway.cnf` 설정

```bash
cd ~/giipAgentGateway
vi giipAgentGateway.cnf
```

**설정 내용**:
```bash
# GIIP 시크릿 키 (Gateway 서버의 SK)
# - GIIP 웹 포털에서 lsvrdetail?id=<gateway_lssn> 접속
# - "Agent 설정" 또는 "Secret Key" 항목에서 확인
sk="your_gateway_secret_key_here"

# 체크 주기 (초) - 기본 60초
giipagentdelay="60"

# API 주소 (변경 불필요)
apiaddr="https://giipasp.azurewebsites.net"

# 서버 목록 파일 경로 (변경 불필요)
serverlist_file="./giipAgentGateway_servers.csv"
```

> **Secret Key 확인 방법**:
> 1. GIIP 웹 포털 로그인
> 2. lsvrdetail?id=<gateway_server_lssn> 페이지 접속
> 3. "sk" 또는 "Secret Key" 필드 값 복사

#### 2-2. `giipAgentGateway_servers.csv` 설정

```bash
vi giipAgentGateway_servers.csv
```

**설정 예시** (실제 환경에 맞게 수정):
```csv
# hostname,lssn,ssh_host,ssh_user,ssh_port,ssh_key_path,os_info,enabled

# 예시: 원격 서버 3대
server1,71221,192.168.1.21,root,22,~/.ssh/giip_gateway_key,Linux,1
server2,71222,192.168.1.22,root,22,~/.ssh/giip_gateway_key,Linux,1
server3,71223,192.168.1.23,root,22,~/.ssh/giip_gateway_key,Linux,1

# 주석 처리된 서버 (비활성화)
# server_old,71220,192.168.1.20,root,22,~/.ssh/giip_gateway_key,Linux,0
```

**필드 설명**:
| 필드 | 값 예시 | 설명 |
|------|---------|------|
| `hostname` | server1 | 서버 식별용 이름 (임의 지정 가능) |
| `lssn` | 71221 | **GIIP 포털의 서버 ID** (정확히 일치해야 함) |
| `ssh_host` | 192.168.1.21 | SSH 접속 IP 또는 호스트명 |
| `ssh_user` | root | SSH 접속 사용자 (sudo 권한 권장) |
| `ssh_port` | 22 | SSH 포트 (기본 22) |
| `ssh_key_path` | ~/.ssh/giip_gateway_key | SSH 개인키 경로 |
| `os_info` | Linux | OS 정보 (공백 시 %20 사용, 예: CentOS%207) |
| `enabled` | 1 | 1=활성화, 0=비활성화 |

> **중요**: `lssn`은 GIIP 웹 포털에서 확인한 정확한 서버 ID여야 합니다.
> - URL `lsvrdetail?id=71221`의 `id` 값이 LSSN입니다.
> - 잘못된 LSSN은 명령 큐를 받지 못합니다.

---

## 🔐 SSH 키 설정

### Step 3-1: Gateway에서 SSH 키 생성

```bash
# SSH 키 생성 (비밀번호 없이)
ssh-keygen -t rsa -b 4096 -f ~/.ssh/giip_gateway_key -N ""

# 권한 설정
chmod 600 ~/.ssh/giip_gateway_key
chmod 644 ~/.ssh/giip_gateway_key.pub
```

### Step 3-2: 원격 서버(71221, 71222, 71223)에 공개키 배포

**방법 1: ssh-copy-id 사용 (권장)**
```bash
# 71221 서버
ssh-copy-id -i ~/.ssh/giip_gateway_key.pub root@192.168.1.21

# 71222 서버
ssh-copy-id -i ~/.ssh/giip_gateway_key.pub root@192.168.1.22

# 71223 서버
ssh-copy-id -i ~/.ssh/giip_gateway_key.pub root@192.168.1.23
```

**방법 2: 수동 배포**
```bash
# 공개키 내용 복사
cat ~/.ssh/giip_gateway_key.pub

# 각 원격 서버에 접속하여
ssh root@192.168.1.21

# authorized_keys에 추가
mkdir -p ~/.ssh
chmod 700 ~/.ssh
echo "위에서 복사한 공개키 내용" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
exit

# 71222, 71223도 동일하게 반복
```

### Step 3-3: SSH 연결 테스트

```bash
# 71221 테스트
ssh -i ~/.ssh/giip_gateway_key root@192.168.1.21 "echo 'Connection OK'"

# 71222 테스트
ssh -i ~/.ssh/giip_gateway_key root@192.168.1.22 "echo 'Connection OK'"

# 71223 테스트
ssh -i ~/.ssh/giip_gateway_key root@192.168.1.23 "echo 'Connection OK'"
```

**예상 출력**: `Connection OK`

---

## 🧪 테스트 및 실행

### Step 4-1: Gateway 전체 테스트

```bash
cd ~/giipAgentGateway
../giipAgentLinux/test-gateway.sh
```

**예상 출력**:
```
======================================
GIIP Agent Gateway Test Script
======================================

✓ Configuration loaded
✓ Server list found: ./giipAgentGateway_servers.csv

Checking required commands...
  ✓ ssh
  ✓ scp
  ✓ dos2unix
  ✓ wget
  ✓ curl

Testing SSH connections...
  ✓ server71221 (root@192.168.1.21:22) - Connection OK
  ✓ server71222 (root@192.168.1.22:22) - Connection OK
  ✓ server71223 (root@192.168.1.23:22) - Connection OK

All tests passed!
```

### Step 4-2: Gateway Agent 실행

```bash
cd ~/giipAgentGateway
./giipAgentGateway.sh
```

**로그 확인**:
```bash
tail -f /var/log/giipAgentGateway_$(date +%Y%m%d).log
```

**예상 로그**:
```
[20251102120001] Gateway Agent Started (v1.0)
[20251102120001] Starting server processing cycle...
[20251102120001] Processing server: server71221 (LSSN: 71221, SSH: root@192.168.1.21:22)
[20251102120002] Queue received for server71221, executing remotely...
[20251102120005] Successfully executed on server71221
[20251102120005] Processing server: server71222 (LSSN: 71222, SSH: root@192.168.1.22:22)
[20251102120006] No queue for server71222
[20251102120006] Processing server: server71223 (LSSN: 71223, SSH: root@192.168.1.23:22)
[20251102120007] No queue for server71223
[20251102120007] Cycle completed, sleeping 60 seconds...
```

### Step 4-3: Cron 자동 실행 등록

```bash
crontab -e
```

**추가할 내용**:
```bash
# GIIP Agent Gateway - 5분마다 실행 (종료 시 자동 재시작)
*/5 * * * * cd $HOME/giipAgentGateway && ./giipAgentGateway.sh >/dev/null 2>&1
```

---

## 📊 GIIP 웹 포털에서 서버 등록 확인

### Step 5-1: LSSN 확인

각 서버가 GIIP 포털에 올바르게 등록되어 있는지 확인:

1. **71221 서버**: `https://giip.co.kr/lsvrdetail?id=71221`
2. **71222 서버**: `https://giip.co.kr/lsvrdetail?id=71222`
3. **71223 서버**: `https://giip.co.kr/lsvrdetail?id=71223`

### Step 5-2: Gateway 연결 상태 확인

- Gateway 서버 상세 페이지(`lsvrdetail?id=71240`)에서 로그 확인
- 마지막 통신 시간이 최근인지 확인 (60초 주기)

---

## 🛠️ 운영 및 관리

### 서버 추가

새 서버(예: 71224)를 추가하려면:

```bash
vi ~/giipAgentGateway/giipAgentGateway_servers.csv
```

**추가**:
```csv
server71224,71224,192.168.1.24,root,22,~/.ssh/giip_gateway_key,Linux,1
```

**SSH 키 배포**:
```bash
ssh-copy-id -i ~/.ssh/giip_gateway_key.pub root@192.168.1.24
```

**재시작 불필요** - 다음 주기(60초 후)에 자동 적용됨

### 서버 일시 중지

특정 서버를 일시적으로 제어 대상에서 제외:

```bash
vi ~/giipAgentGateway/giipAgentGateway_servers.csv
```

**변경**: `enabled` 값을 `0`으로 변경
```csv
server71223,71223,192.168.1.23,root,22,~/.ssh/giip_gateway_key,Linux,0
```

### 서버 제거

```bash
vi ~/giipAgentGateway/giipAgentGateway_servers.csv
```

**삭제** 또는 **주석 처리**:
```csv
# server71223,71223,192.168.1.23,root,22,~/.ssh/giip_gateway_key,Linux,1
```

### 로그 확인

```bash
# 오늘 로그
tail -f /var/log/giipAgentGateway_$(date +%Y%m%d).log

# 최근 50줄
tail -n 50 /var/log/giipAgentGateway_$(date +%Y%m%d).log

# 에러만 필터
grep -i error /var/log/giipAgentGateway_$(date +%Y%m%d).log

# 특정 서버 로그만
grep "server71221" /var/log/giipAgentGateway_$(date +%Y%m%d).log
```

### Gateway Agent 재시작

```bash
# 프로세스 중지
pkill -f giipAgentGateway.sh

# 재시작
cd ~/giipAgentGateway && ./giipAgentGateway.sh
```

---

## 🔧 문제 해결

### 문제 1: SSH 연결 실패

**증상**:
```
[20251102120001] Error getting queue for server71221: Connection timed out
```

**해결**:
```bash
# 수동 SSH 테스트
ssh -i ~/.ssh/giip_gateway_key root@192.168.1.21

# 방화벽 확인
telnet 192.168.1.21 22

# SSH 키 권한 확인
ls -la ~/.ssh/giip_gateway_key  # 600이어야 함
```

### 문제 2: 명령 실행 실패

**증상**:
```
[20251102120002] Failed to execute on server71221
```

**해결**:
```bash
# 원격 서버 접속하여 수동 테스트
ssh -i ~/.ssh/giip_gateway_key root@192.168.1.21

# 임시 스크립트 확인
ls -l /tmp/giipTmpScript.sh
cat /tmp/giipTmpScript.sh

# 실행 권한 확인
chmod +x /tmp/giipTmpScript.sh
/tmp/giipTmpScript.sh
```

### 문제 3: LSSN이 잘못 설정됨

**증상**: GIIP 포털에서 서버 정보가 보이지 않음

**해결**:
```bash
# CSV 파일에서 LSSN 확인
cat ~/giipAgentGateway/giipAgentGateway_servers.csv

# GIIP 포털에서 정확한 LSSN 확인
# lsvrdetail 페이지에서 "id" 파라미터 값
```

### 문제 4: Gateway Agent가 중복 실행됨

**증상**:
```
[20251102120001] Terminate by process count 4
```

**해결**:
```bash
# 모든 프로세스 중지
pkill -f giipAgentGateway.sh

# 프로세스 확인
ps aux | grep giipAgentGateway.sh | grep -v grep

# 재시작
cd ~/giipAgentGateway && ./giipAgentGateway.sh
```

### 문제 5: 큐를 다운로드하지 못함

**증상**:
```
[20251102120002] Queue received for server71221, but contains HTTP Error
```

**해결**:
```bash
# Secret Key 확인
grep "^sk=" ~/giipAgentGateway/giipAgentGateway.cnf

# API 연결 테스트
curl -X POST https://giipasp.azurewebsites.net/api \
  -d "text=KVSAdviceGet queuetask&token=YOUR_SK_HERE"

# 인터넷 연결 확인
ping -c 3 giipasp.azurewebsites.net
```

---

## 📝 체크리스트

### 초기 설정 체크리스트

- [ ] Gateway 서버(71240)에 giipAgentGateway 설치됨
- [ ] `giipAgentGateway.cnf`에 Secret Key 설정됨
- [ ] `giipAgentGateway_servers.csv`에 3개 서버(71221, 71222, 71223) 등록됨
- [ ] SSH 키 생성됨 (`~/.ssh/giip_gateway_key`)
- [ ] SSH 공개키가 3개 원격 서버에 배포됨
- [ ] SSH 연결 테스트 성공 (3개 서버 모두)
- [ ] `test-gateway.sh` 테스트 통과
- [ ] Gateway Agent 실행 확인
- [ ] 로그에서 성공 메시지 확인
- [ ] Cron 등록으로 자동 재시작 설정됨
- [ ] GIIP 포털에서 3개 서버 상태 확인됨

### 운영 중 점검 체크리스트

- [ ] Gateway Agent 프로세스 실행 중: `ps aux | grep giipAgentGateway`
- [ ] 최근 로그 정상: `tail -n 20 /var/log/giipAgentGateway_*.log`
- [ ] SSH 연결 정상: 로그에 "Connection timed out" 없음
- [ ] 명령 실행 성공: 로그에 "Successfully executed" 있음
- [ ] GIIP 포털 통신 정상: 마지막 통신 시간 < 5분 전

---

## 📚 관련 문서

- **전체 매뉴얼**: `README_GATEWAY.md` - Gateway Agent 전체 기능 설명
- **빠른 시작**: `GATEWAY_QUICKSTART_KR.md` - 일반적인 설치 가이드
- **구현 요약**: `docs/GATEWAY_IMPLEMENTATION_SUMMARY.md` - 기술적 구현 세부사항

---

## 🆘 도움말

### 추가 지원이 필요한 경우

1. **로그 수집**:
   ```bash
   tar czf giip_gateway_logs.tar.gz /var/log/giipAgentGateway_*.log
   ```

2. **설정 파일 백업**:
   ```bash
   tar czf giip_gateway_config.tar.gz ~/giipAgentGateway/*.{cnf,csv}
   ```

3. **시스템 정보**:
   ```bash
   uname -a > system_info.txt
   ps aux | grep giip >> system_info.txt
   crontab -l >> system_info.txt
   ```

---

**문서 버전**: 1.0  
**작성일**: 2025-11-02  
**대상 환경**: Gateway(71240) → Remote(71221, 71222, 71223)  
**업데이트**: 환경 변경 시 이 문서를 업데이트하여 최신 상태 유지
