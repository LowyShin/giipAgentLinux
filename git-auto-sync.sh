#!/bin/bash
#===============================================================================
# Git Auto-Sync Script (Pull-Only, Read-Only Version)
# 
# Description:
#   GitHub에서 변경사항을 자동으로 Pull하는 읽기 전용 스크립트
#   공개 저장소용 - 로컬 변경사항은 Push하지 않음 (보안)
#
# Version: 1.1.0 (Pull-Only + Auto-Discovery Integration)
# Author: GIIP Team
# Last Updated: 2025-10-30
#
# Usage:
#   bash git-auto-sync.sh
#
# Cron Example:
#   */5 * * * * /home/giip/giipAgentLinux/git-auto-sync.sh >> /var/log/giip/git_auto_sync_cron.log 2>&1
#
# Security:
#   - 로컬 변경사항은 자동 커밋/푸시 하지 않음
#   - GitHub → Server 단방향 동기화만 수행
#   - 공개 저장소이므로 기밀정보 유출 방지
#===============================================================================

set -e  # Exit on error

# ============================================================
# 설정
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="/var/log/giip"
LOG_FILE="$LOG_DIR/git_auto_sync_$(date +%Y%m%d).log"
HOSTNAME=$(hostname)

# ============================================================
# 로그 함수
# ============================================================
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "$LOG_FILE" >&2
}

# ============================================================
# 시작
# ============================================================
log "=========================================="
log "Git Auto-Sync v1.0.0 (Pull-Only) Started"
log "Repository: $SCRIPT_DIR"
log "Hostname: $HOSTNAME"
log "=========================================="

# 로그 디렉토리 생성
if [ ! -d "$LOG_DIR" ]; then
    mkdir -p "$LOG_DIR"
    log "Created log directory: $LOG_DIR"
fi

# Git 저장소 확인
if [ ! -d "$SCRIPT_DIR/.git" ]; then
    log_error "Not a git repository: $SCRIPT_DIR"
    exit 1
fi

cd "$SCRIPT_DIR"
log "Changed directory to: $SCRIPT_DIR"

# ============================================================
# Git 사용자 설정 확인 (읽기 전용이지만 필요)
# ============================================================
if [ -z "$(git config user.name)" ] || [ -z "$(git config user.email)" ]; then
    log "WARNING: Git user.name or user.email not configured"
    log "Setting default git config..."
    git config user.name "giipAgent-$HOSTNAME"
    git config user.email "giipagent@$HOSTNAME.local"
    log "Git config set: user.name=giipAgent-$HOSTNAME"
fi

# ============================================================
# 현재 브랜치 확인
# ============================================================
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>&1)
if [ $? -ne 0 ]; then
    log_error "Failed to get current branch"
    exit 1
fi
log "Current branch: $CURRENT_BRANCH"

# ============================================================
# Step 1: 로컬 변경사항 경고
# ============================================================
log "=========================================="
log "Step 1: Checking local changes..."
log "=========================================="

CHANGED_FILES=$(git status --porcelain)
if [ -n "$CHANGED_FILES" ]; then
    log "⚠ WARNING: Local changes detected (will NOT be pushed - Read-Only Mode):"
    echo "$CHANGED_FILES" | while IFS= read -r line; do
        log "  $line"
    done
    log ""
    log "⚠ SECURITY NOTICE: This is a public repository."
    log "⚠ Local changes will be stashed before pull to prevent conflicts."
    log "⚠ To commit changes, please use manual git workflow."
    log ""
    
    # Stash local changes
    log "Stashing local changes..."
    STASH_MSG="Auto-stash before pull at $(date '+%Y-%m-%d %H:%M:%S') on $HOSTNAME"
    git stash save "$STASH_MSG" 2>&1 | tee -a "$LOG_FILE"
    
    if [ $? -eq 0 ]; then
        log "✓ Local changes stashed successfully"
        log "To recover: git stash list && git stash pop"
        STASHED=true
    else
        log_error "Failed to stash local changes"
        exit 1
    fi
else
    log "✓ No local changes detected"
    STASHED=false
fi

# ============================================================
# Step 2: Fetch remote changes
# ============================================================
log "=========================================="
log "Step 2: Fetching remote changes..."
log "=========================================="

git fetch origin 2>&1 | tee -a "$LOG_FILE"
if [ $? -ne 0 ]; then
    log_error "git fetch failed"
    exit 1
fi
log "✓ Fetch completed successfully"

# ============================================================
# Step 3: Pull remote changes
# ============================================================
log "=========================================="
log "Step 3: Checking for updates..."
log "=========================================="

LOCAL_HASH=$(git rev-parse HEAD)
REMOTE_HASH=$(git rev-parse "origin/$CURRENT_BRANCH")

log "Local commit:  $LOCAL_HASH"
log "Remote commit: $REMOTE_HASH"

if [ "$LOCAL_HASH" != "$REMOTE_HASH" ]; then
    log "⚠ Remote changes detected, pulling..."
    
    git pull origin "$CURRENT_BRANCH" 2>&1 | tee -a "$LOG_FILE"
    
    if [ $? -eq 0 ]; then
        log "✓ Pull succeeded"
        NEW_HASH=$(git rev-parse HEAD)
        log "Updated to commit: $NEW_HASH"
        
        # Show what changed
        log "Changes pulled:"
        git log --oneline "$LOCAL_HASH..$NEW_HASH" 2>&1 | tee -a "$LOG_FILE"
    else
        log_error "Pull failed"
        
        # Restore stashed changes if any
        if [ "$STASHED" = true ]; then
            log "Restoring stashed changes..."
            git stash pop 2>&1 | tee -a "$LOG_FILE"
        fi
        exit 1
    fi
else
    log "✓ Already up to date with remote"
fi

# ============================================================
# Step 4: Restore stashed changes (optional)
# ============================================================
if [ "$STASHED" = true ]; then
    log "=========================================="
    log "Step 4: Stashed changes information"
    log "=========================================="
    log "Your local changes are stashed and NOT pushed (Read-Only Mode)"
    log "Stash list:"
    git stash list | head -5 | tee -a "$LOG_FILE"
    log ""
    log "To restore your changes:"
    log "  git stash pop"
    log "To discard stashed changes:"
    log "  git stash drop"
    log ""
    log "⚠ NOTE: This is a public repository."
    log "⚠ Do NOT commit sensitive information."
fi

# ============================================================
# Auto-Discovery 실행 (Pull 완료 후)
# ============================================================
if [ "$PULLED" = true ]; then
    log ""
    log "=========================================="
    log "Running Auto-Discovery after Git pull"
    log "=========================================="
    
    DISCOVER_SCRIPT="$SCRIPT_DIR/giip-auto-discover.sh"
    
    if [ -f "$DISCOVER_SCRIPT" ]; then
        log "Executing: $DISCOVER_SCRIPT"
        
        if bash "$DISCOVER_SCRIPT" >> "$LOG_FILE" 2>&1; then
            log "✓ Auto-Discovery completed successfully"
        else
            log_error "Auto-Discovery failed with exit code $?"
            log "  Check log: $LOG_FILE"
        fi
    else
        log_error "Auto-Discovery script not found: $DISCOVER_SCRIPT"
        log "  Skipping Auto-Discovery execution"
    fi
else
    log ""
    log "No changes pulled - Skipping Auto-Discovery"
fi

# ============================================================
# 완료
# ============================================================
log "=========================================="
log "Git Auto-Sync (Pull-Only) Completed"
log "=========================================="
log ""

# 최종 상태 출력
log "Final Status:"
log "  Branch: $CURRENT_BRANCH"
log "  Commit: $(git rev-parse --short HEAD)"
log "  Author: $(git log -1 --format='%an <%ae>')"
log "  Date:   $(git log -1 --format='%cd' --date=short)"
log "  Message: $(git log -1 --format='%s')"

if [ "$STASHED" = true ]; then
    log "  Stashed: YES ($(git stash list | wc -l) items)"
else
    log "  Stashed: NO"
fi

log ""
log "✓ Sync completed successfully (Pull-Only Mode)"

exit 0
