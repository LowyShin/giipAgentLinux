#!/bin/bash
# issue_workflow_runner.sh
# CQE 큐로부터 실행됨. GIIP Issue를 AI 에이전트로 처리.

set -euo pipefail

ISN="${1:-}"
WORKFLOW="${2:-gissue-proc}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="${SCRIPT_DIR}/.."  # giipAgentLinux root
PROJECT_ROOT="${BASE_DIR}/.."  # giipprj root

echo "[IssueWorkflowRunner] START: isn=${ISN}, workflow=${WORKFLOW}"

# 1. AI 에이전트 CLI 탐지
AGENT_CMD=""
if command -v antigravity &>/dev/null; then
    AGENT_CMD="antigravity"
elif command -v gemini &>/dev/null; then
    AGENT_CMD="gemini"
elif command -v claude &>/dev/null; then
    AGENT_CMD="claude"
fi

if [ -z "$AGENT_CMD" ]; then
    echo "[IssueWorkflowRunner] ERROR: AI 에이전트 CLI 없음"
    # 실패 코멘트 등록
    if [ -f "${PROJECT_ROOT}/giipdb/mgmt/addIssueComment.ps1" ]; then
        pwsh -File "${PROJECT_ROOT}/giipdb/mgmt/addIssueComment.ps1" \
            -isn "$ISN" \
            -content "❌ 에이전트 실행 실패: AI 에이전트 CLI가 설치되지 않았습니다." \
            -issuetype "result" 2>/dev/null || true
    fi
    exit 1
fi

echo "[IssueWorkflowRunner] 에이전트: ${AGENT_CMD}"

# 2. 프로젝트 루트에서 실행
if [ ! -f "${PROJECT_ROOT}/GEMINI.md" ]; then
    echo "[IssueWorkflowRunner] ERROR: 프로젝트 루트 없음: ${PROJECT_ROOT}"
    exit 1
fi

cd "${PROJECT_ROOT}"

# 3. 에이전트 실행 (비대화형)
RESULT=$("${AGENT_CMD}" --dangerously-skip-permissions --print "/${WORKFLOW} ${ISN}" 2>&1) || true
EXIT_CODE=$?

echo "[IssueWorkflowRunner] 실행 완료 (exit=${EXIT_CODE})"

# 4. 결과 코멘트 등록
SUMMARY=$(echo "$RESULT" | head -c 2000)
COMMENT="## 원격 에이전트 실행 결과\n\n${SUMMARY}\n\n**머신**: $(hostname)\n**종료 코드**: ${EXIT_CODE}"

if [ -f "${PROJECT_ROOT}/giipdb/mgmt/addIssueComment.ps1" ]; then
    pwsh -File "${PROJECT_ROOT}/giipdb/mgmt/addIssueComment.ps1" \
        -isn "$ISN" \
        -content "$COMMENT" \
        -issuetype "result" 2>/dev/null || \
    bash -c "source '${BASE_DIR}/lib/common.sh' && load_config '${BASE_DIR}/giipAgent.cnf' && \
        curl -s -X POST \"\${apiaddrv2}\" \
        -d \"text=GiipIssueCommentPut+isn+content+issuetype&token=\${sk}&jsondata={\\\"isn\\\":${ISN},\\\"content\\\":\\\"${COMMENT//\"/\\\"}\\\",\\\"issuetype\\\":\\\"result\\\"}\" \
        -H 'Content-Type: application/x-www-form-urlencoded'"
else
    # giipdb가 없는 경우 curl 직접 호출 시도 (common.sh가 있다고 가정)
    if [ -f "${BASE_DIR}/lib/common.sh" ]; then
        source "${BASE_DIR}/lib/common.sh"
        if [ -f "${BASE_DIR}/giipAgent.cnf" ]; then
            load_config "${BASE_DIR}/giipAgent.cnf"
            curl -s -X POST "${apiaddrv2}" \
        -d "text=GiipIssueCommentPut+isn+content+issuetype&token=${sk}&jsondata={\"isn\":${ISN},\"content\":\"${COMMENT//\"/\\\"}\",\"issuetype\":\"result\"}" \
        -H 'Content-Type: application/x-www-form-urlencoded'
        fi
    fi
fi

echo "[IssueWorkflowRunner] END"
