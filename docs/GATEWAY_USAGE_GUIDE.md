# Gateway Server 사용 가이드

## 📖 목차
1. [개요](#개요)
2. [Gateway 서버란?](#gateway-서버란)
3. [설정 방법](#설정-방법)
4. [사용 시나리오](#사용-시나리오)
5. [트러블슈팅](#트러블슈팅)
6. [FAQ](#faq)
7. [보안 고려사항](#보안-고려사항)

---

## 개요

Gateway 서버 기능을 사용하면 SSH를 통해 원격 서버들을 중앙에서 관리할 수 있습니다. 
웹 UI에서 설정만 하면 필요한 스크립트가 자동으로 설치되어, 더 이상 서버에 직접 SSH 접속하여 수동으로 설정할 필요가 없습니다.

### 핵심 장점
- ✅ **웹 UI 기반 설정**: 클릭 한 번으로 Gateway 서버 설정
- ✅ **자동 설치**: CQE를 통해 필요한 스크립트 자동 배포
- ✅ **중앙 관리**: 여러 원격 서버를 한 곳에서 관리
- ✅ **실시간 동기화**: 웹 UI에서 서버 추가/제거 시 자동 반영

---

## Gateway 서버란?

### 구조
```
┌──────────────┐
│  giip API    │
│  (Azure)     │
└──────┬───────┘
       │
       │ CQE Commands
       ↓
┌──────────────────┐     SSH      ┌──────────────┐
│ Gateway 서버     │ ──────────→  │ 원격 서버 1  │
│ (giipAgent)      │              └──────────────┘
│                  │     SSH      ┌──────────────┐
│ + giipAgentGateway│ ──────────→ │ 원격 서버 2  │
└──────────────────┘              └──────────────┘
                          SSH      ┌──────────────┐
                       ──────────→ │ 원격 서버 3  │
                                   └──────────────┘
```

### 역할
- **Gateway 서버**: SSH를 통해 원격 서버들에 명령을 전달하는 중계 서버
- **원격 서버**: Gateway를 통해 관리되는 서버들 (giipAgent 설치 불필요)

---

## 설정 방법

### 1단계: Gateway 서버 설정

#### 웹 UI에서 설정
1. **서버 목록** (`/lsvrlist`)에서 Gateway로 사용할 서버 선택
2. **서버 상세** (`/lsvrdetail`) 페이지로 이동
3. **Gateway 설정** 섹션에서 "▼ 펼치기" 클릭
4. **"Gateway로 설정"** 체크박스 선택
5. **저장** 버튼 클릭

#### 자동으로 진행되는 작업
```bash
1. pGatewayServerPut SP 실행
   └─> is_gateway = 1 설정
   └─> setup_gateway_auto.sh 스크립트를 CQE 큐에 추가

2. giipAgent가 큐를 폴링하여 스크립트 실행
   └─> Git 레포지토리 클론
   └─> giipAgent.cnf 생성
   └─> giipAgentGateway_servers.csv 생성 (API에서 가져옴)
   └─> Cron 작업 등록 (5분마다 실행)
   └─> SSH 키 디렉토리 생성

3. 설정 완료 (5-10분 소요)
```

#### 설치 확인
```bash
# Gateway 서버에 SSH 접속하여 확인
ssh user@gateway-server

# 1. Config 파일 확인
cat /opt/giipAgentLinux/giipAgent.cnf

# 2. 서버 목록 파일 확인
cat /opt/giipAgentLinux/giipAgentGateway_servers.csv

# 3. Cron 작업 확인
crontab -l | grep giipAgentGateway

# 4. 로그 확인
tail -f /var/log/giipAgentGateway.log
```

---

### 2단계: 원격 서버 연결

#### 웹 UI에서 설정
1. **원격 서버**의 상세 페이지 (`/lsvrdetail`) 이동
2. **Gateway 설정** 섹션에서 "▼ 펼치기" 클릭
3. **"Gateway 서버 선택"** 드롭다운에서 Gateway 선택
4. **SSH 설정** 입력:
   - **SSH 호스트**: 원격 서버의 IP 또는 도메인 (필수)
   - **SSH 포트**: SSH 포트 (기본값: 22)
   - **SSH 사용자**: SSH 접속 사용자명 (기본값: root)
   - **SSH 키 경로**: Gateway 서버 기준 SSH 키 경로 (선택사항)
5. **저장** 버튼 클릭

#### 자동으로 진행되는 작업
```bash
1. pGatewayServerPut SP 실행
   └─> gateway_lssn 설정
   └─> SSH 정보 저장
   └─> refresh_gateway_serverlist.sh 큐에 추가 (Gateway 서버로)

2. Gateway 서버가 스크립트 실행
   └─> API에서 최신 서버 목록 가져오기
   └─> giipAgentGateway_servers.csv 업데이트

3. 다음 Cron 실행 시 원격 서버로 명령 전달 시작
```

---

## 사용 시나리오

### 시나리오 1: 단일 Gateway로 여러 원격 서버 관리

```
회사 환경:
- Gateway 서버 1대 (공용 IP 보유)
- 내부 네트워크의 서버 10대 (사설 IP)

설정:
1. 공용 IP 서버를 Gateway로 설정
2. 내부 서버 10대를 모두 이 Gateway에 연결
3. 내부 서버들의 SSH 호스트는 사설 IP 입력 (Gateway에서 접근 가능)

결과:
- 웹 UI에서 모든 서버에 CQE 명령 전송 가능
- Gateway가 SSH를 통해 내부 서버들에 명령 전달
```

### 시나리오 2: 다중 Gateway 구조

```
글로벌 환경:
- 한국 Gateway 서버 1대
- 미국 Gateway 서버 1대
- 각 지역별로 관리 대상 서버들

설정:
1. 한국 서버 1대를 Gateway로 설정 → 한국 내 서버들 연결
2. 미국 서버 1대를 Gateway로 설정 → 미국 내 서버들 연결

결과:
- 지역별로 네트워크 레이턴시 최소화
- 각 Gateway가 독립적으로 동작
```

### 시나리오 3: 보안 강화 환경

```
보안 요구사항:
- 외부에서 내부 서버로 직접 SSH 불가
- Bastion Host(Gateway) 경유 필수

설정:
1. Bastion Host를 Gateway로 설정
2. 내부 서버들에 giipAgent 설치 불필요
3. SSH 키 기반 인증 설정

결과:
- 외부 → Gateway → 내부 서버 경로로만 접근
- 중앙화된 보안 관리
```

---

## 트러블슈팅

### 문제 1: Gateway 설정 후 원격 서버에 명령이 전달되지 않음

#### 증상
- 웹 UI에서 원격 서버를 Gateway에 연결했으나 CQE 명령이 실행되지 않음

#### 원인 및 해결
1. **SSH 키 미설정**
   ```bash
   # Gateway 서버에서 SSH 키 생성
   ssh-keygen -t rsa -b 4096 -f /opt/giipAgentLinux/ssh_keys/id_rsa -N ""
   
   # 원격 서버에 공개키 복사
   ssh-copy-id -i /opt/giipAgentLinux/ssh_keys/id_rsa.pub user@remote-server
   ```

2. **방화벽 차단**
   ```bash
   # 원격 서버에서 SSH 포트 확인
   sudo firewall-cmd --list-all
   
   # Gateway IP 허용
   sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="<gateway-ip>" port protocol="tcp" port="22" accept'
   sudo firewall-cmd --reload
   ```

3. **서버 목록 갱신 안됨**
   ```bash
   # Gateway 서버에서 수동 갱신
   cd /opt/giipAgentLinux
   bash giipscripts/refresh_gateway_serverlist.sh
   
   # 로그 확인
   tail -f /var/log/giipAgentGateway.log
   ```

---

### 문제 2: "setup_gateway_auto.sh" 실행 실패

#### 증상
- Gateway로 설정했으나 자동 설정이 완료되지 않음

#### 원인 및 해결
1. **Git 미설치**
   ```bash
   # Ubuntu/Debian
   sudo apt-get update && sudo apt-get install -y git
   
   # CentOS/RHEL
   sudo yum install -y git
   ```

2. **CQE 큐 확인**
   ```sql
   -- tMgmtQue 테이블에서 큐 상태 확인
   SELECT * FROM tMgmtQue 
   WHERE lssn = <gateway-lssn> 
   ORDER BY mqRegdt DESC
   ```

3. **스크립트 수동 실행**
   ```bash
   # Gateway 서버에서
   cd /opt/giipAgentLinux
   
   # SK, LSSN, API 주소를 환경변수로 설정 후 실행
   export SK="your-security-key"
   export LSSN="gateway-lssn"
   export APIADDRV2="https://your-api.azurewebsites.net/api/giipApiSk2"
   
   # 스크립트 실행 (변수 치환 후)
   bash giipscripts/setup_gateway_auto.sh
   ```

---

### 문제 3: SSH 연결 오류

#### 증상
- `Permission denied (publickey)` 오류

#### 해결
```bash
# 1. Gateway 서버에서 SSH 키 권한 확인
chmod 700 /opt/giipAgentLinux/ssh_keys
chmod 600 /opt/giipAgentLinux/ssh_keys/id_rsa
chmod 644 /opt/giipAgentLinux/ssh_keys/id_rsa.pub

# 2. 원격 서버에서 authorized_keys 확인
cat ~/.ssh/authorized_keys

# 3. 수동 SSH 테스트
ssh -i /opt/giipAgentLinux/ssh_keys/id_rsa user@remote-server

# 4. 상세 디버그 모드
ssh -vvv -i /opt/giipAgentLinux/ssh_keys/id_rsa user@remote-server
```

---

### 문제 4: 서버 목록 동기화 실패

#### 증상
- 웹 UI에서 서버를 추가했으나 Gateway의 CSV 파일에 반영되지 않음

#### 해결
```bash
# 1. API 연결 확인
curl -X POST "https://your-api.azurewebsites.net/api/giipApiSk2" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode 'text=GatewayExportServerList gateway_lssn' \
  --data-urlencode "token=<your-sk>" \
  --data-urlencode "jsondata={\"gateway_lssn\":<lssn>}"

# 2. 수동 갱신 스크립트 실행
cd /opt/giipAgentLinux
bash giipscripts/refresh_gateway_serverlist.sh

# 3. CSV 파일 확인
cat /opt/giipAgentLinux/giipAgentGateway_servers.csv
```

---

## FAQ

### Q1: Gateway 서버에도 giipAgent가 필요한가요?
**A**: 네, Gateway 서버에는 `giipAgent.sh`가 필요합니다. Gateway로 설정하면 추가로 `giipAgentGateway.sh`가 설치됩니다.

### Q2: 원격 서버에 giipAgent를 설치해야 하나요?
**A**: 아니요, 원격 서버에는 giipAgent 설치가 **필요 없습니다**. Gateway가 SSH를 통해 직접 명령을 실행합니다.

### Q3: 하나의 Gateway에 몇 대까지 연결할 수 있나요?
**A**: 이론적으로 제한은 없지만, 실무에서는 **50-100대** 정도를 권장합니다. 그 이상은 다중 Gateway 구조를 고려하세요.

### Q4: Gateway를 다른 Gateway에 연결할 수 있나요?
**A**: 아니요, Gateway 서버는 다른 Gateway에 연결할 수 없습니다. (DB 제약: `is_gateway=1`이면 `gateway_lssn=NULL`)

### Q5: SSH 키는 어디에 저장되나요?
**A**: Gateway 서버의 `/opt/giipAgentLinux/ssh_keys/` 디렉토리에 저장됩니다. 이 경로는 기본값이며, 웹 UI에서 변경 가능합니다.

### Q6: Gateway 설정을 해제하려면?
**A**: 웹 UI에서 "Gateway로 설정" 체크박스를 해제하고 저장하면 됩니다. 단, 연결된 원격 서버가 있으면 먼저 연결을 해제해야 합니다.

### Q7: 원격 서버가 오프라인이면 어떻게 되나요?
**A**: Gateway가 SSH 연결을 시도하고 실패합니다. 로그에 오류가 기록되며, 다음 Cron 실행 시 재시도합니다.

### Q8: 여러 Gateway가 동일한 원격 서버를 관리할 수 있나요?
**A**: 가능은 하지만 권장하지 않습니다. 하나의 원격 서버는 하나의 Gateway에만 연결하는 것이 관리상 명확합니다.

### Q9: Gateway 서버의 성능 요구사항은?
**A**: 
- **CPU**: 2코어 이상 (원격 서버 수에 비례)
- **메모리**: 2GB 이상
- **네트워크**: 안정적인 연결 (원격 서버들과 SSH 통신)

### Q10: Gateway 로그는 어디서 확인하나요?
**A**: 
- **Gateway 로그**: `/var/log/giipAgentGateway.log`
- **CQE 로그**: `/var/log/giipAgent.log` (일반 Agent 로그)
- **Cron 로그**: `/var/log/cron` (Cron 실행 이력)

---

## 보안 고려사항

### SSH 키 관리
```bash
# 1. SSH 키는 반드시 파일 권한 제한
chmod 600 /opt/giipAgentLinux/ssh_keys/id_rsa

# 2. 정기적으로 키 로테이션
ssh-keygen -t rsa -b 4096 -f /opt/giipAgentLinux/ssh_keys/id_rsa_new -N ""
# 원격 서버에 새 키 배포 후 구 키 제거

# 3. 키 암호화 (선택사항, 자동화에는 부적합)
ssh-keygen -p -f /opt/giipAgentLinux/ssh_keys/id_rsa
```

### 방화벽 설정
```bash
# Gateway 서버: 원격 서버로의 SSH 아웃바운드 허용
sudo firewall-cmd --permanent --add-service=ssh
sudo firewall-cmd --reload

# 원격 서버: Gateway IP에서만 SSH 인바운드 허용
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="<gateway-ip>/32" port protocol="tcp" port="22" accept'
sudo firewall-cmd --permanent --remove-service=ssh  # 기본 SSH 룰 제거
sudo firewall-cmd --reload
```

### SSH 설정 강화
```bash
# 원격 서버의 /etc/ssh/sshd_config 설정
PermitRootLogin prohibit-password  # 키 기반 인증만 허용
PasswordAuthentication no          # 비밀번호 로그인 비활성화
PubkeyAuthentication yes           # 공개키 인증 활성화
AllowUsers gateway-user            # 특정 사용자만 허용

# 설정 적용
sudo systemctl restart sshd
```

### 접근 제어
- **최소 권한 원칙**: Gateway 서버는 필요한 원격 서버에만 SSH 접근 권한 부여
- **네트워크 분리**: 가능하면 Gateway를 DMZ에 배치
- **감사 로그**: 모든 SSH 접속 및 명령 실행 로그 보관

### 모니터링
```bash
# Gateway 서버에서 SSH 접속 로그 모니터링
tail -f /var/log/auth.log | grep sshd

# 실패한 SSH 시도 확인
grep "Failed password" /var/log/auth.log

# 성공한 SSH 접속 확인
grep "Accepted publickey" /var/log/auth.log
```

---

## 관련 문서
- [GATEWAY_AUTO_CONFIGURATION.md](./GATEWAY_AUTO_CONFIGURATION.md) - Gateway 자동 설정 아키텍처
- [CQE_ARCHITECTURE.md](../../giipAgentAdmLinux/docs/CQE_ARCHITECTURE.md) - CQE 시스템 구조
- [CQE_V2_SUMMARY.md](./CQE_V2_SUMMARY.md) - CQE v2 개선 사항

---

## 변경 이력
- **2025-11-02**: 초안 작성 (Gateway 자동 설정 기능 추가)
