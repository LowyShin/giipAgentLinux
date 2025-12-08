# Git Auto-Sync for Windows (Force Download)

Windows 환경에서 GitHub 변경사항을 **강제로 다운로드**하는 배치 스크립트입니다.

> **⚠ 중요**: 로컬 변경사항은 모두 삭제됩니다. 원격 저장소의 내용으로 강제 덮어쓰기됩니다.

## 버전

**v1.0.0 (Force Download)** (2025-12-08)

## 기능

### 강제 다운로드 (Force Download)

1. **Hard Reset**
   - 로컬 변경사항 모두 제거 (`git reset --hard`)
   - 원격 저장소 내용으로 강제 덮어쓰기
   - Untracked 파일도 삭제 (`git clean -fd`)

2. **보안**
   - ✅ GitHub → Server 단방향 강제 동기화
   - ⚠️ 로컬 변경사항 **복구 불가능** (Stash 없음)
   - ✅ 항상 원격 저장소와 100% 동일한 상태 유지

## Linux 버전과의 차이점

| 기능 | Linux (git-auto-sync.sh) | Windows (gitautosync.bat) |
|------|-------------------------|--------------------------|
| 로컬 변경 처리 | Stash로 보존 | **Hard Reset (삭제)** |
| Untracked 파일 | 유지 | **삭제 (git clean)** |
| 복구 가능성 | ✅ 가능 (git stash pop) | ❌ 불가능 |
| 동기화 방식 | Soft (보존형) | **Hard (강제형)** |

## 설치 방법

### 1. 스크립트 확인

```batch
cd C:\path\to\giipAgentLinux\scripts
dir gitautosync.bat
```

### 2. 수동 테스트

```batch
cd C:\path\to\giipAgentLinux\scripts
gitautosync.bat
```

### 3. 로그 확인

```batch
type ..\logs\git_auto_sync_20251208.log
```

## Windows 작업 스케줄러 설정

### GUI를 통한 설정

1. **작업 스케줄러 열기**
   ```
   시작 메뉴 → "작업 스케줄러" 검색 → 실행
   ```

2. **새 작업 만들기**
   - 우클릭 → "기본 작업 만들기"
   - 이름: `GIIP Git Auto-Sync`
   - 설명: `GitHub 변경사항 강제 다운로드 (5분마다)`

3. **트리거 설정**
   - 트리거: `매일`
   - 반복 간격: `5분`
   - 지속 시간: `무기한`

4. **동작 설정**
   - 동작: `프로그램 시작`
   - 프로그램/스크립트: `C:\path\to\giipAgentLinux\scripts\gitautosync.bat`
   - 시작 위치: `C:\path\to\giipAgentLinux`

5. **조건 설정**
   - ✅ `컴퓨터의 AC 전원이 켜져 있을 때만 작업 시작` (선택 해제)
   - ✅ `작업을 실행하기 위해 절전 모드 종료` (체크)

### PowerShell 명령어로 설정

```powershell
# 작업 스케줄러 등록
$action = New-ScheduledTaskAction -Execute "C:\path\to\giipAgentLinux\scripts\gitautosync.bat" -WorkingDirectory "C:\path\to\giipAgentLinux"
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration ([TimeSpan]::MaxValue)
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
Register-ScheduledTask -TaskName "GIIP-GitAutoSync" -Action $action -Trigger $trigger -Settings $settings -Description "GitHub 변경사항 강제 다운로드"
```

### 작업 스케줄러 확인

```powershell
# 등록된 작업 확인
Get-ScheduledTask -TaskName "GIIP-GitAutoSync"

# 작업 실행 이력 확인
Get-ScheduledTaskInfo -TaskName "GIIP-GitAutoSync"

# 작업 수동 실행
Start-ScheduledTask -TaskName "GIIP-GitAutoSync"
```

## 사용 예시

### 수동 실행

```batch
cd C:\path\to\giipAgentLinux\scripts
gitautosync.bat
```

### 로그 분석

```batch
REM 오늘 로그 보기
type ..\logs\git_auto_sync_%date:~0,4%%date:~5,2%%date:~8,2%.log

REM 최근 50줄
powershell "Get-Content ..\logs\git_auto_sync_20251208.log -Tail 50"

REM 에러만 검색
findstr /C:"ERROR" ..\logs\git_auto_sync_*.log

REM 경고 메시지 검색
findstr /C:"WARNING" ..\logs\git_auto_sync_*.log
```

## 동작 흐름

```
[Step 0] Git 환경 확인
    ↓
[Step 1] 현재 브랜치 확인
    ↓
[Step 2] 로컬 변경사항 검사
    ↓
    ├─ Changes Found
    │   └─ ⚠ WARNING: 로컬 변경사항 발견 (삭제 예정)
    │
    └─ No Changes → Skip
    ↓
[Step 3] Fetch Remote
    ↓
[Step 4] Force Reset (Hard Reset)
    ↓
    ├─ git reset --hard origin/main
    │   └─ ⚠ 로컬 변경사항 모두 제거
    │
    └─ Already Up-to-date → Skip
    ↓
[Step 5] Clean Untracked Files
    ↓
    └─ git clean -fd (Untracked 파일 삭제)
    ↓
[Complete] (Force Download Mode)
```

## 보안 특징

### 로컬 변경사항 처리

```batch
REM 로컬 변경 감지 시
WARNING: Local changes detected - will be DISCARDED!

NOTICE: Force download mode enabled
        All local changes will be permanently removed

REM Hard Reset 실행
git reset --hard origin/main

REM Untracked 파일 삭제
git clean -fd

⚠ 주의: 로컬 변경사항은 복구 불가능
```

### Push 차단

- ❌ `git add -A` - 실행 안 됨
- ❌ `git commit` - 실행 안 됨
- ❌ `git push` - 실행 안 됨
- ✅ `git fetch` - 실행됨
- ✅ `git reset --hard` - 실행됨 (강제)

## 에러 처리

### 1. Git이 설치되지 않음

```batch
ERROR: Git is not installed or not in PATH

REM 해결 방법
REM 1. Git 설치: https://git-scm.com/download/win
REM 2. PATH 환경변수에 Git 경로 추가
```

### 2. Git 저장소가 아님

```batch
ERROR: Not a git repository: C:\path\to\directory

REM 해결 방법
cd C:\correct\path\to\giipAgentLinux
git status
```

### 3. Reset 실패

```batch
ERROR: git reset --hard failed

REM 수동 해결
cd C:\path\to\giipAgentLinux
git status
git reset --hard origin/main
git clean -fd
```

## 트러블슈팅

### 작업 스케줄러가 실행되지 않음

```powershell
# 작업 스케줄러 서비스 확인
Get-Service -Name "Schedule"

# 서비스 시작
Start-Service -Name "Schedule"

# 작업 로그 확인
Get-WinEvent -LogName "Microsoft-Windows-TaskScheduler/Operational" -MaxEvents 20
```

### Git 인증 실패

```batch
REM SSH 키 확인
dir %USERPROFILE%\.ssh\id_*

REM SSH 키 생성
ssh-keygen -t ed25519 -C "giip@windows"

REM 공개 키 복사
type %USERPROFILE%\.ssh\id_ed25519.pub
REM GitHub.com → Settings → SSH Keys에 추가

REM SSH 연결 테스트
ssh -T git@github.com
```

### 로그가 생성되지 않음

```batch
REM 로그 디렉토리 생성
mkdir C:\path\to\giipAgentLinux\logs

REM 권한 확인
icacls C:\path\to\giipAgentLinux\logs

REM 수동 실행으로 테스트
cd C:\path\to\giipAgentLinux\scripts
gitautosync.bat
dir ..\logs
```

## 사용 시나리오

### 시나리오 1: GitHub에서 스크립트 업데이트 받기

```batch
REM GitHub에서 스크립트 수정 (다른 개발자)
REM → 5분 후 자동으로 서버에 강제 다운로드
REM → 최신 버전 자동 적용 (로컬 변경사항 무시)

REM 확인
cd C:\path\to\giipAgentLinux
git log -1 --oneline
```

### 시나리오 2: 항상 최신 상태 유지

```batch
REM 실수로 로컬 파일 수정
REM → 5분 후 자동으로 원격 저장소로 복원
REM → 항상 GitHub와 동일한 상태 유지
```

### 시나리오 3: 중앙 집중식 배포

```batch
REM 개발팀이 GitHub에 코드 Push
REM → 모든 Windows 서버가 5분 내 자동 다운로드
REM → 로컬 변경사항 무시하고 강제 적용
REM → 수동 배포 작업 불필요
```

## ⚠️ 주의사항

### 로컬 변경사항 손실

- **모든 로컬 변경사항은 영구 삭제됩니다**
- Stash, 백업 없이 즉시 삭제됨
- 복구 불가능하므로 중요한 변경사항은 수동으로 백업 필요

### 권장 사용 환경

- ✅ **읽기 전용 서버** (GitHub에서만 코드 받는 환경)
- ✅ **프로덕션 서버** (로컬 변경 불필요)
- ✅ **자동 배포 서버** (항상 최신 상태 유지)
- ❌ **개발 서버** (로컬 변경 필요한 경우)

### 백업 권장사항

중요한 설정 파일은 `.gitignore`에 추가:

```gitignore
# 서버별 설정 (로컬 유지)
*.cnf.local
*.cfg.local
config/local/*

# 로그 파일
logs/*.log
*.log

# 백업 파일
*.bak
*.backup
```

## 로그 파일 위치

```
메인 로그:
- C:\path\to\giipAgentLinux\logs\git_auto_sync_YYYYMMDD.log

작업 스케줄러 로그:
- 이벤트 뷰어 → Windows 로그 → 응용 프로그램
- 이벤트 뷰어 → 작업 스케줄러 로그
```

## 버전 히스토리

### v1.0.0 (Force Download) (2025-12-08)
- ✨ 강제 다운로드 모드 구현
- ✅ `git reset --hard` 기반 동기화
- ✅ Untracked 파일 자동 삭제 (`git clean -fd`)
- ✅ Windows 배치 파일 형식
- ⚠️ 로컬 변경사항 복구 불가능 (의도된 동작)

## 관련 저장소

- **giipAgentLinux**: 공개 저장소 - Pull-Only/Force Download 모드
- **giipAgentWin**: 공개 저장소 - Pull-Only/Force Download 모드

## 참고 문서

- [GIT_AUTO_SYNC_LINUX.md](GIT_AUTO_SYNC_LINUX.md) - Linux 버전 (Stash 기반)
- [Windows Task Scheduler 가이드](https://docs.microsoft.com/windows-server/administration/windows-commands/schtasks)

## FAQ

### Q1: 로컬 변경사항을 백업하려면?

A: `.gitignore`에 파일을 추가하거나, 별도 디렉토리에 백업하세요.

```batch
REM 백업 예시
xcopy /E /I C:\path\to\giipAgentLinux\config C:\backup\config
```

### Q2: Force Download 대신 Stash 방식을 사용하려면?

A: Linux 버전 (`git-auto-sync.sh`)을 참고하여 PowerShell 스크립트로 구현하세요.

### Q3: 특정 파일만 보호하려면?

A: `.gitignore`에 추가:

```gitignore
giipAgent.cnf
config/*.local
```

## 라이선스

GIIP Project - Internal Use Only

---

**마지막 업데이트**: 2025-12-08  
**버전**: 1.0.0 (Force Download)  
**관리자**: GIIP Team
