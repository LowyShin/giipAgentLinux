@echo off
REM ===============================================================================
REM Git Auto-Sync Script for Windows (Force Download Version)
REM 
REM Description:
REM   GitHub에서 변경사항을 강제로 다운로드하는 스크립트
REM   로컬 변경사항은 무시하고 원격 저장소 내용으로 강제 덮어쓰기
REM
REM Version: 1.0.0 (Force Download)
REM Author: GIIP Team
REM Last Updated: 2025-12-08
REM
REM Usage:
REM   gitautosync.bat
REM
REM Windows Task Scheduler Example:
REM   Program: C:\path\to\giipAgentLinux\scripts\gitautosync.bat
REM   Trigger: Every 5 minutes
REM
REM Security Notice:
REM   - 로컬 변경사항은 모두 제거됩니다 (git reset --hard)
REM   - GitHub -> Server 단방향 강제 동기화
REM   - 주의: 로컬 변경사항은 복구 불가능
REM ===============================================================================

setlocal enabledelayedexpansion

REM ============================================================
REM Configuration
REM ============================================================
set SCRIPT_DIR=%~dp0
set LOG_DIR=%SCRIPT_DIR%..\logs
set LOG_FILE=%LOG_DIR%\git_auto_sync_%date:~0,4%%date:~5,2%%date:~8,2%.log
set REPO_DIR=%SCRIPT_DIR%..

REM ============================================================
REM Functions (using goto labels)
REM ============================================================
goto :main

:log
echo [%date% %time%] %~1 >> "%LOG_FILE%"
echo [%date% %time%] %~1
exit /b 0

:log_error
echo [%date% %time%] ERROR: %~1 >> "%LOG_FILE%"
echo [%date% %time%] ERROR: %~1 1>&2
exit /b 0

REM ============================================================
REM Main Script
REM ============================================================
:main

REM Create log directory if it doesn't exist
if not exist "%LOG_DIR%" (
    mkdir "%LOG_DIR%"
    call :log "Created log directory: %LOG_DIR%"
)

call :log "=========================================="
call :log "Git Auto-Sync v1.0.0 (Force Download) Started"
call :log "Repository: %REPO_DIR%"
call :log "Hostname: %COMPUTERNAME%"
call :log "=========================================="

REM Change to repository directory
cd /d "%REPO_DIR%"
if errorlevel 1 (
    call :log_error "Failed to change directory to: %REPO_DIR%"
    exit /b 1
)
call :log "Changed directory to: %REPO_DIR%"

REM Check if Git is installed
where git >nul 2>&1
if errorlevel 1 (
    call :log_error "Git is not installed or not in PATH"
    exit /b 1
)

REM Check if this is a git repository
if not exist ".git\" (
    call :log_error "Not a git repository: %REPO_DIR%"
    exit /b 1
)

REM ============================================================
REM Git User Configuration Check
REM ============================================================
git config user.name >nul 2>&1
if errorlevel 1 (
    call :log "WARNING: Git user.name not configured"
    call :log "Setting default git config..."
    git config user.name "giipAgent-%COMPUTERNAME%"
    git config user.email "giipagent@%COMPUTERNAME%.local"
    call :log "Git config set: user.name=giipAgent-%COMPUTERNAME%"
)

REM ============================================================
REM Step 1: Get Current Branch
REM ============================================================
call :log "=========================================="
call :log "Step 1: Checking current branch..."
call :log "=========================================="

for /f "tokens=*" %%i in ('git rev-parse --abbrev-ref HEAD 2^>^&1') do set CURRENT_BRANCH=%%i
if errorlevel 1 (
    call :log_error "Failed to get current branch"
    exit /b 1
)
call :log "Current branch: %CURRENT_BRANCH%"

REM ============================================================
REM Step 2: Check for Local Changes (Warning)
REM ============================================================
call :log "=========================================="
call :log "Step 2: Checking local changes..."
call :log "=========================================="

for /f %%i in ('git status --porcelain 2^>^&1 ^| find /c /v ""') do set CHANGE_COUNT=%%i
if %CHANGE_COUNT% gtr 0 (
    call :log "WARNING: Local changes detected - will be DISCARDED!"
    git status --porcelain >> "%LOG_FILE%" 2>&1
    call :log ""
    call :log "NOTICE: Force download mode enabled"
    call :log "       All local changes will be permanently removed"
    call :log ""
) else (
    call :log "No local changes detected"
)

REM ============================================================
REM Step 3: Fetch Remote Changes
REM ============================================================
call :log "=========================================="
call :log "Step 3: Fetching remote changes..."
call :log "=========================================="

git fetch origin >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    call :log_error "git fetch failed"
    exit /b 1
)
call :log "Fetch completed successfully"

REM ============================================================
REM Step 4: Force Reset to Remote (HARD RESET)
REM ============================================================
call :log "=========================================="
call :log "Step 4: Force resetting to remote..."
call :log "=========================================="

REM Get current and remote commit hashes
for /f "tokens=*" %%i in ('git rev-parse HEAD') do set LOCAL_HASH=%%i
for /f "tokens=*" %%i in ('git rev-parse origin/%CURRENT_BRANCH%') do set REMOTE_HASH=%%i

call :log "Local commit:  %LOCAL_HASH%"
call :log "Remote commit: %REMOTE_HASH%"

if "%LOCAL_HASH%" neq "%REMOTE_HASH%" (
    call :log "Remote changes detected - forcing reset..."
    
    REM Hard reset to remote branch
    git reset --hard origin/%CURRENT_BRANCH% >> "%LOG_FILE%" 2>&1
    if errorlevel 1 (
        call :log_error "git reset --hard failed"
        exit /b 1
    )
    
    call :log "Force reset completed successfully"
    
    for /f "tokens=*" %%i in ('git rev-parse HEAD') do set NEW_HASH=%%i
    call :log "Updated to commit: %NEW_HASH%"
    
    REM Show what changed
    call :log "Changes pulled:"
    git log --oneline %LOCAL_HASH%..%NEW_HASH% >> "%LOG_FILE%" 2>&1
    
) else (
    call :log "Already up to date with remote"
)

REM ============================================================
REM Step 5: Clean Untracked Files (Optional)
REM ============================================================
call :log "=========================================="
call :log "Step 5: Cleaning untracked files..."
call :log "=========================================="

git clean -fd >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    call :log "Warning: git clean failed (may be no files to clean)"
) else (
    call :log "Cleaned untracked files and directories"
)

REM ============================================================
REM Completion
REM ============================================================
call :log "=========================================="
call :log "Git Auto-Sync (Force Download) Completed"
call :log "=========================================="
call :log ""

REM Display final status
call :log "Final Status:"
for /f "tokens=*" %%i in ('git rev-parse --short HEAD') do call :log "  Commit: %%i"
for /f "tokens=*" %%i in ('git log -1 --format^=%%an ^<%%ae^>') do call :log "  Author: %%i"
for /f "tokens=*" %%i in ('git log -1 --format^=%%cd --date^=short') do call :log "  Date:   %%i"
for /f "tokens=*" %%i in ('git log -1 --format^=%%s') do call :log "  Message: %%i"

call :log ""
call :log "Sync completed successfully (Force Download Mode)"

exit /b 0
