# GIIP Agent Gateway 솔루션 구현 완료

## 생성된 파일 목록

### 핵심 실행 파일
1. **giipAgentGateway.sh** (4.6 KB)
   - 게이트웨이 에이전트 메인 스크립트
   - SSH를 통한 원격 명령 실행 로직
   - 여러 서버 순차 처리

2. **giipAgentGateway.cnf.template** (1.0 KB)
   - 게이트웨이 설정 템플릿
   - GIIP API 키 및 주기 설정
   - 실제 사용시 복사하여 편집

3. **giipAgentGateway_servers.csv.template** (1.7 KB)
   - 관리 대상 서버 목록 템플릿
   - CSV 형식 (hostname,lssn,ssh_host,ssh_user,ssh_port,ssh_key,os,enabled)
   - 예시 및 상세 주석 포함

### 설치 및 테스트 도구
4. **install-gateway.sh** (5.5 KB)
   - 자동 설치 스크립트
   - 필수 패키지 확인 및 설치
   - SSH 키 생성 및 배포 가이드
   - Cron 작업 설정

5. **test-gateway.sh** (3.1 KB)
   - SSH 연결 테스트 스크립트
   - 각 서버별 접속 검증
   - 연결 가능 여부 리포트

### 문서
6. **README_GATEWAY.md** (11.0 KB)
   - 완전한 영문 매뉴얼
   - 아키텍처 설명
   - 설치, 설정, 운영 가이드
   - 문제 해결 방법

7. **GATEWAY_QUICKSTART_KR.md** (7.0 KB)
   - 한국어 빠른 시작 가이드
   - 단계별 설치 방법
   - 주요 명령어 및 예시
   - 일반적인 문제 해결

### 기타 수정
8. **.gitignore** (업데이트)
   - 게이트웨이 설정 파일 추가
   - 민감 정보 보호

9. **README.md** (업데이트)
   - Gateway Agent 옵션 추가
   - 배포 방식 설명

## 주요 기능

### 1. 멀티 서버 관리
- CSV 파일로 여러 서버 중앙 관리
- 서버별 독립적인 LSSN (Server ID)
- 개별 SSH 설정 (호스트, 포트, 키, 사용자)

### 2. 유연한 서버 제어
- `enabled` 플래그로 서버 활성화/비활성화
- 재시작 없이 설정 변경 반영
- 주석으로 서버 임시 제거

### 3. 보안
- SSH 키 기반 인증
- 연결 타임아웃 설정
- StrictHostKeyChecking 옵션
- BatchMode로 패스워드 프롬프트 방지

### 4. 모니터링 및 로깅
- 서버별 실행 결과 로그
- 성공/실패 상태 기록
- 날짜별 로그 파일 분리
- 상세한 디버그 정보

## 사용 시나리오

### 시나리오 1: DMZ 서버 관리
```
[인터넷] <--> [Gateway in DMZ] <-SSH-> [내부 서버들]
```
- DMZ의 게이트웨이만 인터넷 접속 가능
- 내부 서버는 SSH로만 접근

### 시나리오 2: 하이브리드 클라우드
```
[GIIP API] <--> [On-Prem Gateway] <-SSH-> [Cloud 서버들]
                                  <-SSH-> [On-Prem 서버들]
```
- 온프레미스 게이트웨이에서 클라우드 및 로컬 서버 통합 관리

### 시나리오 3: 보안 정책
```
[GIIP API] <--> [Bastion Server] <-SSH-> [Production 서버들]
```
- 보안 정책상 프로덕션 서버는 직접 외부 접속 불가
- Bastion을 통한 중앙 집중식 관리

## 설치 예시

```bash
# 1. 자동 설치
cd ~/giipAgentLinux
chmod +x install-gateway.sh
./install-gateway.sh

# 2. 설정
vi ~/giipAgentGateway/giipAgentGateway.cnf
# sk="your_secret_key"

vi ~/giipAgentGateway/giipAgentGateway_servers.csv
# webserver01,1001,192.168.1.10,root,22,~/.ssh/id_rsa,CentOS%207,1

# 3. SSH 키 배포
ssh-copy-id -i ~/.ssh/id_rsa.pub root@192.168.1.10

# 4. 테스트
cd ~/giipAgentGateway
../giipAgentLinux/test-gateway.sh

# 5. 실행
./giipAgentGateway.sh

# 6. Cron 등록
crontab -e
# */5 * * * * cd $HOME/giipAgentGateway && ./giipAgentGateway.sh >/dev/null 2>&1
```

## 기존 Agent와 비교

| 항목 | 표준 Agent | Gateway Agent |
|------|-----------|---------------|
| 설치 위치 | 각 서버 | 게이트웨이 서버 |
| 실행 방식 | 로컬 실행 | SSH 원격 실행 |
| 인터넷 필요 | 필수 | 게이트웨이만 |
| LSSN | 서버당 1개 | 원격 서버당 1개 |
| 설정 | 분산 | 중앙 집중 |
| 적용 사례 | 일반 서버 | 격리된 네트워크 |

## 기술적 특징

### SSH 원격 실행 메커니즘
```bash
# 1. Queue 다운로드
wget -O script.sh "https://api/cqequeueget?lssn=1001"

# 2. 원격 복사
scp script.sh user@host:/tmp/

# 3. 원격 실행
ssh user@host "chmod +x /tmp/script.sh && /tmp/script.sh"

# 4. 정리
ssh user@host "rm -f /tmp/script.sh"
```

### 프로세스 보호
- 중복 실행 방지 (최대 3개 프로세스)
- 자동 종료 조건
- 주기적 재실행 (Cron)

### 에러 처리
- HTTP 에러 감지
- SSH 연결 타임아웃
- 실패 로깅
- 다음 서버로 계속 진행

## 운영 가이드

### 일상 모니터링
```bash
# 실시간 로그
tail -f /var/log/giipAgentGateway_*.log

# 오늘의 실행 횟수
grep "Starting server processing cycle" /var/log/giipAgentGateway_$(date +%Y%m%d).log | wc -l

# 성공/실패 통계
grep "Successfully executed" /var/log/giipAgentGateway_$(date +%Y%m%d).log | wc -l
grep "Failed to execute" /var/log/giipAgentGateway_$(date +%Y%m%d).log | wc -l
```

### 서버 추가
```bash
# 1. 웹 포털에서 서버 등록 -> LSSN 확인
# 2. SSH 키 배포
ssh-copy-id -i ~/.ssh/id_rsa.pub root@new-server

# 3. CSV에 추가
echo "newserver,1005,192.168.1.50,root,22,~/.ssh/id_rsa,Ubuntu%2022.04,1" >> giipAgentGateway_servers.csv

# 4. 자동 반영 (재시작 불필요)
```

### 문제 해결
```bash
# SSH 연결 테스트
test-gateway.sh

# 특정 서버만 테스트
ssh -i ~/.ssh/id_rsa root@192.168.1.10 "echo success"

# 프로세스 재시작
pkill -f giipAgentGateway.sh
cd ~/giipAgentGateway && ./giipAgentGateway.sh
```

## 향후 개선 가능 항목

1. **병렬 실행**: 여러 서버 동시 처리 (현재는 순차)
2. **실행 결과 수집**: 원격 실행 결과를 GIIP API로 전송
3. **헬스체크**: 원격 서버 상태 주기적 확인
4. **알림**: 연결 실패시 알림 발송
5. **WebUI**: 실시간 모니터링 대시보드

## 마이그레이션 시나리오

### 표준 Agent → Gateway Agent
```bash
# 1. 기존 서버의 정보 수집
for server in server1 server2 server3; do
  echo -n "$server,"
  ssh $server "grep lssn ~/giipAgent/giipAgent.cnf | cut -d'\"' -f2"
done

# 2. Gateway 서버에 목록 작성
# 3. 테스트
# 4. 기존 Agent 중지
for server in server1 server2 server3; do
  ssh $server "crontab -l | grep -v giipAgent.sh | crontab -"
done
```

## 보안 체크리스트

- [x] SSH 키 권한 확인 (600)
- [x] GIIP Secret Key git 제외
- [x] 서버 목록 CSV git 제외
- [x] SSH 연결 타임아웃 설정
- [x] 최소 권한 사용자 사용
- [x] 로그 접근 권한 제한
- [x] 정기적인 SSH 키 로테이션 계획

## 결론

Gateway Agent는 다음과 같은 환경에서 효과적입니다:

1. ✅ 방화벽으로 인터넷 접속이 제한된 서버
2. ✅ DMZ 또는 격리된 네트워크 환경
3. ✅ 보안 정책상 직접 외부 접속 불가
4. ✅ 중앙 집중식 관리 필요
5. ✅ 여러 서버를 단일 포인트에서 관리

기존 `giipAgent.sh`는 그대로 유지하고, 새로운 Gateway 옵션을 추가하여 다양한 네트워크 환경에 대응할 수 있게 되었습니다.

---

**작성일**: 2025-11-01  
**버전**: 1.0  
**작성자**: GitHub Copilot
