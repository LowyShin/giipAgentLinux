#!/bin/bash
# GATEWAY_DISCOVERY_INTEGRATION.md
# giipAgent3.sh에서 Gateway Discovery 모듈 통합 방법

# ============================================================================
# 개요
# ============================================================================
#
# Gateway 서버에서 원격 Linux 서버들의 Infrastructure 데이터를 자동으로 수집하고
# DB에 저장하는 모듈 통합 가이드
#
# 핵심 모듈:
#   - lib/discovery.sh: 로컬/원격 auto-discover 실행 및 DB 저장
#   - lib/gateway-discovery.sh: Gateway에서 모든 원격 서버 순회 처리
#

# ============================================================================
# 1. 전제 조건
# ============================================================================
#
# Gateway 서버:
#   ✅ SSH 키 설정: /root/.ssh/giip_key 또는 /root/.ssh/id_rsa
#   ✅ python3 설치 (JSON 파싱용)
#   ✅ 원격 서버와 SSH 연결 가능
#
# 원격 서버:
#   ✅ SSH 접근 가능 (인증키 기반)
#   ✅ bash 설치
#   ✅ auto-discover-linux.sh 존재 또는 Gateway에서 전송 가능
#   ✅ python3 설치 (JSON 파싱용)
#

# ============================================================================
# 2. giipAgent3.sh 통합 방법
# ============================================================================

# ------ giipAgent3.sh 상단 (라이브러리 로드 섹션) ------
#
# 기존:
#   source ./lib/kvs.sh
#   source ./lib/gateway.sh
#
# 추가:
#   source ./lib/discovery.sh           # Infrastructure Discovery (로컬)
#   source ./lib/gateway-discovery.sh   # Gateway Discovery (원격)
#

# ------ giipAgent3.sh 메인 루프 (Gateway 모드) ------
#
# Normal 에이전트 (로컬 서버):
#
#   while true; do
#       # 기존 작업
#       process_queue
#       check_gateway_status
#       
#       # Infrastructure Discovery (6시간마다)
#       if should_run_discovery "$local_lssn"; then
#           echo "[Agent3] 🔍 Running infrastructure discovery..." >&2
#           collect_infrastructure_data "$local_lssn"  # 원격_info 파라미터 없음 = 로컬
#       fi
#       
#       sleep 60
#   done
#

# Gateway 에이전트 (원격 서버 관리):
#
#   while true; do
#       # 기존 작업
#       check_gateway_queue
#       manage_remote_servers
#       
#       # Gateway Discovery (모든 원격 서버)
#       if should_run_discovery "gateway_$gateway_lssn"; then
#           echo "[Agent3] 🔍 Running gateway discovery..." >&2
#           run_gateway_discovery "$gateway_lssn"
#       fi
#       
#       sleep 120
#   done
#

# ============================================================================
# 3. 로컬 서버 Discovery 예제
# ============================================================================

example_local_discovery() {
    # 로컬 서버의 Infrastructure Discovery
    local lssn=1
    
    if should_run_discovery "$lssn"; then
        echo "[Example] 🔍 Running local discovery for LSSN=$lssn" >&2
        
        if collect_infrastructure_data "$lssn"; then
            echo "[Example] ✅ Local discovery succeeded" >&2
        else
            echo "[Example] ❌ Local discovery failed" >&2
        fi
    fi
}

# ============================================================================
# 4. 원격 서버 Discovery 예제 (단일)
# ============================================================================

example_remote_discovery_single() {
    # 단일 원격 서버의 Infrastructure Discovery
    local lssn=2
    local ssh_user="root"
    local ssh_host="192.168.1.100"
    local ssh_port="22"
    local remote_info="${ssh_user}@${ssh_host}:${ssh_port}"
    
    echo "[Example] 📡 Running remote discovery for LSSN=$lssn (Host=$ssh_host)" >&2
    
    if collect_infrastructure_data "$lssn" "$remote_info"; then
        echo "[Example] ✅ Remote discovery succeeded" >&2
    else
        echo "[Example] ❌ Remote discovery failed" >&2
    fi
}

# ============================================================================
# 5. 여러 원격 서버 Discovery 예제 (Gateway 모드)
# ============================================================================

example_gateway_discovery() {
    # Gateway 서버에서 관리하는 모든 원격 서버의 Discovery
    local gateway_lssn=100  # Gateway 서버의 LSSN
    
    echo "[Example] 🚀 Running gateway discovery for gateway LSSN=$gateway_lssn" >&2
    
    if run_gateway_discovery "$gateway_lssn"; then
        echo "[Example] ✅ Gateway discovery completed" >&2
    else
        echo "[Example] ⚠️  Gateway discovery completed with errors" >&2
    fi
}

# ============================================================================
# 6. 캐시 파일 설정 (원격 서버 목록)
# ============================================================================

setup_gateway_cache() {
    local gateway_lssn="$1"
    
    # 캐시 파일 위치: /tmp/giip_gateway_servers_{gateway_lssn}.txt
    # 형식:
    #   LSSN|SSH_USER|SSH_HOST|SSH_PORT
    #   2|root|192.168.1.100|22
    #   3|root|192.168.1.101|22
    #   4|root|192.168.1.102|2222
    
    cat > "/tmp/giip_gateway_servers_${gateway_lssn}.txt" <<EOF
2|root|192.168.1.100|22
3|root|192.168.1.101|22
4|root|192.168.1.102|2222
5|admin|remote.example.com|22
EOF
    
    chmod 600 "/tmp/giip_gateway_servers_${gateway_lssn}.txt"
    
    echo "[Setup] ✅ Cache file created: /tmp/giip_gateway_servers_${gateway_lssn}.txt" >&2
}

# ============================================================================
# 7. SSH 키 설정
# ============================================================================

# SSH 키 사용:
#   기본: /root/.ssh/giip_key 또는 /root/.ssh/id_rsa (자동 감지)
#   커스텀: SSH_KEY 환경변수 설정
#
# 예제:
#   export SSH_KEY="/root/.ssh/custom_key"
#   collect_infrastructure_data 2 "root@192.168.1.100:22"
#

# SSH 키 생성 (처음 한 번):
#   ssh-keygen -t rsa -N "" -f /root/.ssh/giip_key
#   ssh-copy-id -i /root/.ssh/giip_key root@192.168.1.100
#

# ============================================================================
# 8. 환경변수 설정
# ============================================================================

#   # giipAgent3.sh 시작 시 설정
#   export LOG_FILE="/var/log/giipagent.log"
#   export SSH_KEY="/root/.ssh/giip_key"
#   export DISCOVERY_INTERVAL=21600  # 6시간 (초 단위)
#

# ============================================================================
# 9. 테스트 및 디버깅
# ============================================================================

# ------ 테스트 1: 로컬 Discovery ------
#
#   source lib/discovery.sh
#   collect_infrastructure_data 1
#   echo "Status: $?"
#

# ------ 테스트 2: 원격 Discovery (단일) ------
#
#   source lib/discovery.sh
#   collect_infrastructure_data 2 "root@192.168.1.100:22"
#   echo "Status: $?"
#

# ------ 테스트 3: Gateway Discovery (여러 서버) ------
#
#   source lib/discovery.sh
#   source lib/gateway-discovery.sh
#   setup_gateway_cache 100  # 캐시 파일 생성
#   run_gateway_discovery 100
#   echo "Status: $?"
#

# ------ 테스트 4: SSH 연결 확인 ------
#
#   ssh -i /root/.ssh/giip_key -p 22 root@192.168.1.100 "hostname"
#

# ------ 테스트 5: auto-discover 스크립트 원격 실행 ------
#
#   ssh -i /root/.ssh/giip_key -p 22 root@192.168.1.100 \
#       "bash /opt/giip/agent/linux/giipscripts/auto-discover-linux.sh | jq ."
#

# ============================================================================
# 10. 로그 모니터링
# ============================================================================

# 실시간 로그 확인:
#
#   tail -f /var/log/giipagent.log | grep -E "\[Discovery\]|\[GatewayDiscovery\]"
#

# 특정 LSSN의 로그만 보기:
#
#   grep "LSSN=2" /var/log/giipagent.log
#

# Discovery 실행 기록 확인:
#
#   ls -lh /tmp/giip_discovery_state*
#

# ============================================================================
# 11. 에러 처리
# ============================================================================

# ------ SSH 연결 실패 ------
#
# 증상: "[Discovery] 📡 Connecting to root@192.168.1.100:22... [Discovery] ❌ Error"
# 원인:
#   1. SSH 포트 오류
#   2. 인증 실패 (SSH 키 없음 또는 권한 문제)
#   3. 원격 서버 다운
#   4. 방화벽 차단
#
# 해결:
#   1. SSH 연결 테스트: ssh -i /root/.ssh/giip_key -p 22 root@192.168.1.100 "hostname"
#   2. SSH 키 권한: chmod 600 /root/.ssh/giip_key
#   3. 원격 서버 상태 확인: ping 192.168.1.100
#

# ------ auto-discover 스크립트 실행 실패 ------
#
# 증상: "[Discovery] ❌ Error: Failed to execute discovery script on 192.168.1.100"
# 원인:
#   1. 원격 서버에 auto-discover-linux.sh 없음
#   2. 원격 서버에 bash 없음
#   3. 원격 서버에 python3 없음
#   4. 스크립트 권한 부족
#
# 해결:
#   1. 원격 서버에서 확인:
#      ssh -i /root/.ssh/giip_key root@192.168.1.100 \
#          "ls -l /opt/giip/agent/linux/giipscripts/auto-discover-linux.sh"
#   2. auto-discover-linux.sh 전송 (lib/discovery.sh가 자동 처리)
#

# ------ JSON 파싱 실패 ------
#
# 증상: "[Discovery] ❌ Error: Invalid JSON from ... discovery script"
# 원인:
#   1. auto-discover-linux.sh에서 에러 메시지 출력
#   2. 스크립트가 불완전한 JSON 반환
#
# 해결:
#   1. 원격에서 직접 실행해 보기:
#      ssh -i /root/.ssh/giip_key root@192.168.1.100 \
#          "bash /opt/giip/agent/linux/giipscripts/auto-discover-linux.sh | jq . 2>&1"
#   2. 에러 메시지 확인
#

# ============================================================================
# 12. 성능 최적화
# ============================================================================

# ------ 병렬 처리 (여러 원격 서버) ------
#
# Gateway Discovery에서는 현재 순차 처리합니다.
# 대량의 원격 서버가 있는 경우 병렬 처리 추가:
#
#   # lib/gateway-discovery.sh 수정
#   # while IFS='|' read -r lssn ssh_user ssh_host ssh_port; do
#   #     ...
#   # done < <(cat "$cache_file") &  # 백그라운드 실행
#
# 주의: SSH 동시 연결 수 제한 (보안, 리소스)
#

# ------ SSH 연결 타임아웃 ------
#
# 기본: 10초 (ConnectTimeout=10)
# giipscripts/auto-discover-linux.sh 내에서도 명령어별 타임아웃 설정 권장
#

# ------ 파일 전송 최소화 ------
#
# auto-discover-linux.sh가 이미 원격 서버에 있으면 전송 생략
# 버전 확인 등으로 최신 버전만 전송하는 로직 추가 가능
#

# ============================================================================
# 13. 실제 구현 체크리스트
# ============================================================================

# Phase 1: 기초 준비
# [ ] lib/discovery.sh 파일 생성 (✅ 완료)
# [ ] lib/gateway-discovery.sh 파일 생성 (✅ 완료)
# [ ] SSH 키 설정: /root/.ssh/giip_key 생성 및 원격 서버 등록
# [ ] 원격 서버 SSH 접근 테스트

# Phase 2: 로컬 테스트
# [ ] 로컬 서버에서 collect_infrastructure_data 1 실행
# [ ] JSON 출력 확인
# [ ] DB 저장 로직 구현 및 테스트

# Phase 3: 원격 테스트
# [ ] 단일 원격 서버에서 collect_infrastructure_data 2 "root@host:22" 실행
# [ ] SSH 전송/실행 동작 확인
# [ ] 로그 확인

# Phase 4: Gateway 통합
# [ ] giipAgent3.sh에 lib 로드 추가
# [ ] 캐시 파일 설정: /tmp/giip_gateway_servers_*.txt
# [ ] Gateway 모드 메인 루프에 run_gateway_discovery 호출 추가
# [ ] 6시간 스케줄링 동작 확인

# Phase 5: 프로덕션
# [ ] 에러 처리 및 재시도 로직 추가
# [ ] 로그 로테이션 설정
# [ ] 모니터링 알림 설정

echo "[GATEWAY_DISCOVERY_INTEGRATION] Integration guide loaded"
