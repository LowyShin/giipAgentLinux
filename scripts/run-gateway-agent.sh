#!/bin/bash
# Windows에서 원격으로 71240 agent 실행 및 로그 수집 (사용 예시)

# 사용 방법:
# 1. Linux 환경에서 직접 실행:
#    cd /g/giipAgentLinux && bash giipAgent3.sh
#
# 2. SSH를 통해 원격 실행:
#    ssh user@71240-server "cd /g/giipAgentLinux && bash giipAgent3.sh"
#
# 3. 실행 후 로그 확인 (PowerShell에서):
#    pwsh .\giipdb\check-gateway-logs.ps1 -lssn "71240" -hours 1

# 로컬 실행 (이 서버가 71240인 경우):
cd /g/giipAgentLinux || exit 1

echo "🚀 Gateway Agent 실행 시작..."
bash giipAgent3.sh 2>&1

echo ""
echo "✅ Gateway Agent 실행 완료"
echo "📋 로그 확인 명령 (Windows PowerShell):"
echo "   pwsh .\giipdb\check-gateway-logs.ps1 -lssn '71240' -hours 1"
