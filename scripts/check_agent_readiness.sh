#!/bin/bash
# check_agent_readiness.sh
# AI 에이전트 원격 실행을 위한 로컬 환경 준비 상태 점검

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="${SCRIPT_DIR}/.."
PROJECT_ROOT="${BASE_DIR}/.."

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "=== GIIP Agent Readiness Check ==="

# 1. giipAgent3.sh 확인
if [ -f "${BASE_DIR}/giipAgent3.sh" ]; then
    echo -e "${GREEN}✅ giipAgent 실행 가능: YES (giipAgent3.sh 존재)${NC}"
else
    echo -e "${RED}❌ giipAgent 실행 가능: NO (giipAgent3.sh 없음)${NC}"
fi

# 2. AI 에이전트 CLI 확인
AGENT_CMD=""
AGENT_VERSION="N/A"
if command -v antigravity &>/dev/null; then
    AGENT_CMD="antigravity"
    AGENT_VERSION=$(antigravity --version 2>/dev/null || echo "v?")
elif command -v gemini &>/dev/null; then
    AGENT_CMD="gemini"
    AGENT_VERSION=$(gemini --version 2>/dev/null || echo "v?")
elif command -v claude &>/dev/null; then
    AGENT_CMD="claude"
    AGENT_VERSION=$(claude --version 2>/dev/null || echo "v?")
fi

if [ -n "$AGENT_CMD" ]; then
    echo -e "${GREEN}✅ AI 에이전트 CLI: ${AGENT_CMD} (${AGENT_VERSION})${NC}"
else
    echo -e "${RED}❌ AI 에이전트 CLI: 설치된 CLI를 찾을 수 없습니다. (antigravity/gemini/claude)${NC}"
fi

# 3. 프로젝트 루트 확인
if [ -f "${PROJECT_ROOT}/GEMINI.md" ]; then
    echo -e "${GREEN}✅ 프로젝트 루트 연결: ${PROJECT_ROOT} (GEMINI.md 확인)${NC}"
else
    echo -e "${RED}❌ 프로젝트 루트 연결: ${PROJECT_ROOT} (GEMINI.md 없음)${NC}"
fi

# 4. addIssueComment.ps1 확인
if [ -f "${PROJECT_ROOT}/giipdb/mgmt/addIssueComment.ps1" ]; then
    echo -e "${GREEN}✅ addIssueComment.ps1: 확인됨${NC}"
else
    echo -e "${RED}❌ addIssueComment.ps1: 파일 없음 (giipdb/mgmt/addIssueComment.ps1)${NC}"
fi

# 5. 설정 확인
if [ -f "${BASE_DIR}/giipAgent.cnf" ]; then
    SK=$(grep "^sk=" "${BASE_DIR}/giipAgent.cnf" | cut -d'=' -f2)
    if [ -n "$SK" ]; then
        echo -e "${GREEN}✅ SK 설정: giipAgent.cnf 확인됨${NC}"
    else
        echo -e "${RED}❌ SK 설정: giipAgent.cnf에 sk 값이 없습니다.${NC}"
    fi
else
    echo -e "${RED}❌ 설정 파일: giipAgent.cnf 없음${NC}"
fi

echo -e "\n점검 완료."
