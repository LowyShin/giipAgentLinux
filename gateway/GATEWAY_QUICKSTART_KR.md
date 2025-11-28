# GIIP Agent Gateway - 빠른 시작 가이드

## 개요

Gateway Agent는 방화벽이나 네트워크 제한으로 인해 직접 인터넷에 접속할 수 없는 서버들을 관리하기 위한 솔루션입니다.

## 아키텍처

```
[GIIP API] <--HTTPS--> [Gateway 서버] <--SSH--> [원격 서버들]
                       (인터넷 접속 가능)      (인터넷 차단됨)
```

## 설치 방법

### 1. 자동 설치 (권장)

```bash
cd ~/giipAgentLinux
chmod +x admin/install-gateway.sh
./admin/install-gateway.sh
```

### 2. 수동 설치

```bash
# 설치 디렉토리 생성
mkdir -p ~/giipAgentGateway
cd ~/giipAgentGateway

# 파일 복사
cp ~/giipAgentLinux/gateway/giipAgentGateway.sh .
cp ~/giipAgentLinux/giipAgent.cnf.template giipAgent.cnf
cp ~/giipAgentLinux/gateway/giipAgentGateway_servers.csv.template giipAgentGateway_servers.csv

# 실행 권한 부여
chmod +x giipAgentGateway.sh
```

## 설정

### 1. Gateway 설정 (`giipAgent.cnf`)

```bash
vi giipAgent.cnf
```

```bash
# GIIP 시크릿 키 (웹 포털에서 확인)
sk="your_secret_key_here"

# 체크 주기 (초)
giipagentdelay="60"

# API 주소 (기본값 사용)
apiaddr="https://giipasp.azurewebsites.net"
```

### 2. 서버 목록 설정 (`giipAgentGateway_servers.csv`)

```bash
vi giipAgentGateway_servers.csv
```

**형식**: `hostname,lssn,ssh_host,ssh_user,ssh_port,ssh_key_path,os_info,enabled`

**예시**:
```csv
webserver01,1001,192.168.1.10,root,22,~/.ssh/id_rsa,CentOS%207,1
dbserver01,1002,192.168.1.20,dbadmin,22,~/.ssh/id_rsa,Ubuntu%2020.04,1
appserver01,1003,10.0.0.30,appuser,2222,~/.ssh/app_key,RHEL%208,1
```

**필드 설명**:
- `hostname`: 서버 호스트명 (GIIP 식별용)
- `lssn`: GIIP 서버 ID (웹 포털에서 확인, 0이면 자동 등록)
- `ssh_host`: SSH 접속 주소 (IP 또는 호스트명)
- `ssh_user`: SSH 사용자명
- `ssh_port`: SSH 포트 (보통 22)
- `ssh_key_path`: SSH 개인키 경로 (비어있으면 패스워드 인증)
- `os_info`: OS 정보 (공백은 %20으로 표기)
- `enabled`: 1=활성화, 0=비활성화

## SSH 키 설정

### SSH 키 생성

```bash
# 게이트웨이용 SSH 키 생성
ssh-keygen -t rsa -b 4096 -f ~/.ssh/giip_gateway_key

# 권한 설정
chmod 600 ~/.ssh/giip_gateway_key
chmod 644 ~/.ssh/giip_gateway_key.pub
```

### 원격 서버에 공개키 배포

**방법 1: ssh-copy-id 사용 (권장)**
```bash
ssh-copy-id -i ~/.ssh/giip_gateway_key.pub root@192.168.1.10
```

**방법 2: 수동 배포**
```bash
# 게이트웨이 서버에서 공개키 복사
cat ~/.ssh/giip_gateway_key.pub

# 원격 서버에 접속하여 추가
ssh root@192.168.1.10
mkdir -p ~/.ssh
chmod 700 ~/.ssh
vi ~/.ssh/authorized_keys  # 공개키 붙여넣기
chmod 600 ~/.ssh/authorized_keys
```

### SSH 연결 테스트

```bash
# 테스트 스크립트 실행
cd ~/giipAgentGateway
chmod +x ../giipAgentLinux/test-gateway.sh
../giipAgentLinux/test-gateway.sh

# 또는 수동 테스트
ssh -i ~/.ssh/giip_gateway_key root@192.168.1.10 "hostname && uname -a"
```

## 실행

### 수동 실행

```bash
cd ~/giipAgentGateway
./giipAgentGateway.sh
```

### Cron 자동 실행 설정

```bash
# Crontab 편집
crontab -e

# 아래 라인 추가 (5분마다 실행)
*/5 * * * * cd $HOME/giipAgentGateway && ./giipAgentGateway.sh >/dev/null 2>&1
```

## 로그 확인

```bash
# 오늘 로그 실시간 확인
tail -f /var/log/giipAgentGateway_$(date +%Y%m%d).log

# 최근 100줄 확인
tail -100 /var/log/giipAgentGateway_$(date +%Y%m%d).log

# 특정 서버 로그만 확인
grep "webserver01" /var/log/giipAgentGateway_$(date +%Y%m%d).log
```

## 로그 예시

```
[20251101120001] Gateway Agent Started (v1.0)
[20251101120001] Starting server processing cycle...
[20251101120001] Processing server: webserver01 (LSSN: 1001, SSH: root@192.168.1.10:22)
[20251101120002] Queue received for webserver01, executing remotely...
[20251101120005] Successfully executed on webserver01
[20251101120005] Processing server: dbserver01 (LSSN: 1002, SSH: dbadmin@192.168.1.20:22)
[20251101120006] No queue for dbserver01
[20251101120006] Cycle completed, sleeping 60 seconds...
```

## 문제 해결

### SSH 연결 실패

```bash
# 상세 디버그 정보 확인
ssh -vvv -i ~/.ssh/giip_gateway_key root@192.168.1.10

# SSH 키 권한 확인
ls -l ~/.ssh/giip_gateway_key  # 600이어야 함
chmod 600 ~/.ssh/giip_gateway_key

# Known hosts 갱신
ssh-keyscan -H 192.168.1.10 >> ~/.ssh/known_hosts
```

### Queue 다운로드 실패

```bash
# API 연결 테스트
curl "https://giipasp.azurewebsites.net/api/cqe/cqequeueget03.asp?sk=YOUR_SK&lssn=1001&hn=test&os=Linux&df=os&sv=1.0"

# 설정 확인
cat <installation_directory>/giipAgent.cnf | grep sk=  # e.g., /opt/giipAgent.cnf
```

### Agent 실행되지 않음

```bash
# 프로세스 확인
ps aux | grep giipAgentGateway.sh

# 중복 프로세스 종료
pkill -f giipAgentGateway.sh

# 재시작
cd ~/giipAgentGateway && ./giipAgentGateway.sh
```

## 서버 추가/제거

### 서버 추가

1. 웹 포털에서 서버 등록하고 LSSN 확인
2. SSH 키 배포
3. `giipAgentGateway_servers.csv`에 라인 추가
4. 자동으로 다음 주기에 적용됨 (재시작 불필요)

### 서버 일시 비활성화

```bash
# enabled를 0으로 변경
vi giipAgentGateway_servers.csv
# webserver01,1001,192.168.1.10,root,22,~/.ssh/id_rsa,CentOS%207,0
```

### 서버 영구 제거

```bash
# CSV에서 해당 라인 삭제 또는 주석 처리
vi giipAgentGateway_servers.csv
# #webserver01,1001,192.168.1.10,root,22,~/.ssh/id_rsa,CentOS%207,1
```

## 주의사항

1. ✅ SSH 키 인증 사용 (패스워드 인증은 비권장)
2. ✅ SSH 키 권한 확인 (600)
3. ✅ 최소 권한 원칙 (전용 SSH 사용자 생성 권장)
4. ✅ GIIP 시크릿 키 보안 유지 (git 커밋 금지)
5. ✅ 정기적인 로그 모니터링
6. ✅ 사용하지 않는 서버는 비활성화 (enabled=0)

## 기존 Agent에서 마이그레이션

기존에 각 서버에 표준 Agent를 설치했고 Gateway로 전환하려면:

```bash
# 1. 원격 서버의 LSSN 확인
ssh server1 "grep lssn <installation_directory>/giipAgent.cnf"  # e.g., /opt/giipAgent.cnf

# 2. Gateway 서버 목록에 추가
vi ~/giipAgentGateway/giipAgentGateway_servers.csv
# server1,1001,192.168.1.10,root,22,~/.ssh/id_rsa,CentOS%207,1

# 3. Gateway 테스트 (로그 확인)
tail -f /var/log/giipAgentGateway_*.log

# 4. 정상 동작 확인 후 원격 서버의 표준 Agent 중지
ssh server1 "crontab -l | grep -v giipAgent.sh | crontab -"
```

## 더 자세한 정보

- [상세 매뉴얼](README_GATEWAY.md)
- [표준 Agent 매뉴얼](README.md)
- [CQE 아키텍처](docs/CQE_ARCHITECTURE.md)

## 지원

문의사항:
- GitHub: https://github.com/LowyShin/giipAgentLinux
- Email: support@giip.net

---

**Last Updated**: 2025-11-01
