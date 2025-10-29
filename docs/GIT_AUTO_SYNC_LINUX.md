# Git Auto-Sync for Linux (Pull-Only)

Linux 환경에서 GitHub 변경사항을 자동으로 받는 **읽기 전용** Bash 스크립트입니다.

> **⚠ 보안 공지**: 이 저장소는 공개 저장소입니다. 로컬 변경사항은 자동으로 Push되지 않습니다.

## 버전

**v1.0.0 (Pull-Only)** (2025-10-29)

## 기능

### 읽기 전용 동기화 (Pull-Only)

1. **Auto-Pull**
   - GitHub 원격 변경사항 자동 감지
   - 자동 풀 (GitHub → Server)
   - Stash로 로컬 변경사항 보호

2. **보안**
   - ❌ 로컬 변경사항 자동 커밋 **비활성화**
   - ❌ GitHub 푸시 **비활성화**
   - ✅ 공개 저장소 - 기밀정보 유출 방지
   - ✅ 로컬 변경사항은 Stash로 보존

## 설치 방법

### 1. 스크립트 다운로드

```bash
cd /home/giip/giipAgentLinux
chmod +x git-auto-sync.sh
```

### 2. 수동 테스트

```bash
bash git-auto-sync.sh
```

### 3. 로그 확인

```bash
tail -f /var/log/giip/git_auto_sync_$(date +%Y%m%d).log
```

## Cron 설정

### 방법 1: Crontab 직접 편집

```bash
crontab -e

# 5분마다 실행
*/5 * * * * /home/giip/giipAgentLinux/git-auto-sync.sh >> /var/log/giip/git_auto_sync_cron.log 2>&1
```

### 방법 2: Cron 파일 생성

```bash
sudo tee /etc/cron.d/giip-git-sync << 'EOF'
# Git Auto-Sync (Pull-Only)
*/5 * * * * giip /home/giip/giipAgentLinux/git-auto-sync.sh >> /var/log/giip/git_auto_sync_cron.log 2>&1
EOF

sudo chmod 644 /etc/cron.d/giip-git-sync
```

### Cron 확인

```bash
# Cron 목록 확인
crontab -l

# Cron 로그 확인
tail -50 /var/log/giip/git_auto_sync_cron.log

# 실시간 모니터링
tail -f /var/log/giip/git_auto_sync_$(date +%Y%m%d).log
```

## 사용 예시

### 수동 실행

```bash
cd /home/giip/giipAgentLinux
bash git-auto-sync.sh
```

### 로그 분석

```bash
# 오늘 로그 보기
cat /var/log/giip/git_auto_sync_$(date +%Y%m%d).log

# 최근 50줄
tail -50 /var/log/giip/git_auto_sync_$(date +%Y%m%d).log

# 에러만 검색
grep ERROR /var/log/giip/git_auto_sync_$(date +%Y%m%d).log

# 경고 메시지 검색
grep WARNING /var/log/giip/git_auto_sync_$(date +%Y%m%d).log

# Stash 관련 로그
grep -i stash /var/log/giip/git_auto_sync_$(date +%Y%m%d).log
```

## 동작 흐름

```
[Step 0] Fetch
    ↓
[Step 1] Local Changes Check
    ↓
    ├─ Changes Found
    │   ├─ git stash save "Auto-stash..."
    │   └─ ⚠ WARNING: Changes stashed (NOT pushed)
    │
    └─ No Changes → Skip
    ↓
[Step 2] Fetch Remote
    ↓
[Step 3] Pull Remote Changes
    ↓
    ├─ Remote Updated
    │   └─ git pull origin main
    │
    └─ Already Up-to-date → Skip
    ↓
[Step 4] Stash Information
    ↓
    └─ Show stash list and recovery commands
    ↓
[Complete] (Pull-Only Mode)
```

## 보안 특징

### 로컬 변경사항 처리

```bash
# 로컬 변경 감지 시
⚠ WARNING: Local changes detected (will NOT be pushed - Read-Only Mode)
⚠ SECURITY NOTICE: This is a public repository.
⚠ Local changes will be stashed before pull to prevent conflicts.

# Stash로 보존
git stash save "Auto-stash before pull at 2025-10-29 15:30:00 on server01"

# 복구 방법 안내
To restore your changes:
  git stash pop
To discard stashed changes:
  git stash drop
```

### Push 차단

- ❌ `git add -A` - 실행 안 됨
- ❌ `git commit` - 실행 안 됨
- ❌ `git push` - 실행 안 됨
- ✅ `git pull` - 실행됨
- ✅ `git stash` - 로컬 변경사항 보존

## 에러 처리

### 1. Git 설정 없음

```bash
# 자동으로 설정됨
git config user.name "giipAgent-server01"
git config user.email "giipagent@server01.local"
```

### 2. Pull 충돌

```bash
# 로그 확인
ERROR: Pull failed

# 수동 해결
cd /home/giip/giipAgentLinux
git status
git pull origin main
```

### 3. Stash 확인

```bash
# Stash 목록
git stash list

# Stash 내용 확인
git stash show -p

# Stash 복원
git stash pop

# Stash 삭제
git stash drop
```

## 트러블슈팅

### Cron이 실행되지 않음

```bash
# Cron 서비스 상태 확인
sudo systemctl status cron

# Cron 로그 확인
grep CRON /var/log/syslog | tail -20

# 수동 실행 테스트
bash /home/giip/giipAgentLinux/git-auto-sync.sh

# 권한 확인
ls -l /home/giip/giipAgentLinux/git-auto-sync.sh
# -rwxr-xr-x 필요
```

### Git 인증 실패

```bash
# SSH 키 확인
ls -l ~/.ssh/id_*

# SSH 키 생성
ssh-keygen -t ed25519 -C "giip@server01"

# 공개 키 복사
cat ~/.ssh/id_ed25519.pub
# GitHub.com → Settings → SSH Keys에 추가

# SSH 연결 테스트
ssh -T git@github.com
```

### 로그가 생성되지 않음

```bash
# 로그 디렉토리 생성
sudo mkdir -p /var/log/giip
sudo chown giip:giip /var/log/giip

# 권한 확인
ls -ld /var/log/giip
# drwxr-xr-x giip giip

# 수동 실행으로 테스트
bash /home/giip/giipAgentLinux/git-auto-sync.sh
tail /var/log/giip/git_auto_sync_$(date +%Y%m%d).log
```

## 사용 시나리오

### 시나리오 1: GitHub에서 스크립트 업데이트 받기

```bash
# GitHub에서 스크립트 수정 (다른 개발자)
# → 5분 후 자동으로 서버에 Pull됨
# → 최신 버전 자동 적용

# 확인
cd /home/giip/giipAgentLinux
git log -1 --oneline
```

### 시나리오 2: 로컬 설정 파일 보호

```bash
# 서버별 설정 파일 수정 (민감정보 포함)
vi /home/giip/giipAgentLinux/giipAgent.cnf
# → Stash로 보존됨
# → GitHub에 Push 안 됨 (보안 유지)

# 복구
git stash list
git stash pop
```

### 시나리오 3: 중앙 집중식 배포

```bash
# 개발팀이 GitHub에 코드 Push
# → 모든 운영 서버가 5분 내 자동 Pull
# → 수동 배포 작업 불필요
# → 서버별 기밀정보는 보호됨
```

## 성능 최적화

### 대용량 파일 제외

`.gitignore` 설정:

```gitignore
# 로그 파일 (너무 큰 경우)
logs/*.log
*.log

# 임시 파일
*.tmp
*.temp

# 백업 파일
*.bak
*.backup

# 서버별 설정 (민감정보)
*.cnf.local
*.cfg.local
```

## 로그 파일 위치

```
메인 로그:
- /var/log/giip/git_auto_sync_YYYYMMDD.log

Cron 로그:
- /var/log/giip/git_auto_sync_cron.log

시스템 로그:
- /var/log/syslog (Cron 실행 기록)
```

## 버전 히스토리

### v1.0.0 (Pull-Only) (2025-10-29)
- ✨ 읽기 전용 모드 구현
- ✅ GitHub → Server 단방향 동기화만 지원
- ✅ 로컬 변경사항 Stash로 보호
- ✅ 공개 저장소 보안 강화
- ❌ 자동 커밋/푸시 기능 제거 (보안)

## 관련 저장소

- **giipAgentLinux**: 공개 저장소 - Pull-Only 모드
- **giipAgentWin**: 공개 저장소 - Pull-Only 모드
- **giipAgentAdmLinux**: 비공개 저장소 - 양방향 동기화 가능 (v2.0.0)

## 참고 문서

- [GIT_AUTO_SYNC_WINDOWS.md](../../giipAgentWin/docs/GIT_AUTO_SYNC_WINDOWS.md) - Windows 버전
- [GIT_AUTO_SYNC.md](../../giipAgentAdmLinux/docs/GIT_AUTO_SYNC.md) - 양방향 동기화 버전

## 라이선스

GIIP Project - Internal Use Only

---

**마지막 업데이트**: 2025-10-29  
**버전**: 1.0.0 (Pull-Only)  
**관리자**: GIIP Team
