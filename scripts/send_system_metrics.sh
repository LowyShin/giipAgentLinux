#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}/.."
# 1. 설정 로드
eval "$(sudo cat /home/giip/giipAgent.cnf)"
# 2. 표준 라이브러리 로드
source lib/kvs_standard.sh
# 3. KVS로 시스템 메트릭 전송
kvs_send "system_metrics" "heartbeat" '{"status":"ok","msg":"auto cron execution"}'
