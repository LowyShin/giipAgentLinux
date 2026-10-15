#!/bin/bash
# scripts/collect_docker_usage.sh - Docker Usage Collector
# Purpose: Detect whether Docker is installed/running on this Linux server and, if so,
#          collect container/image/disk-usage metrics and upload them to KVS so that
#          giip web admin/docker-instances ("Provision now" target dropdown) can list this
#          server as a Docker-capable lssn (SP pApiDockerCapableLsvrListbyAK).
# kFactor: docker_usage   (kType=lssn, kKey=<lssn>)
# Counterpart: giipAgentWin giipscripts/modules/CollectDockerMetrics.ps1 (same JSON keys).
#
# Payload keys (identical to the Windows agent):
#   dockerInstalled, dockerVersion, containersRunning, containersTotal,
#   imagesCount, diskUsedGb, diskReclaimableGb, collectedAt
#
# Docker 가 없는 서버가 대부분이므로 CLI 없음/데몬 미기동은 에러가 아니라 정상 경로다.
# 이 경우 Windows 구현과 동일하게 dockerInstalled=false (나머지 0/빈값)만 올리고 끝난다.
# CSN 에 따른 분기는 없다(모든 CSN 동일 동작).
# Version: 1.0.0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"
CONFIG_FILE="${SCRIPT_DIR}/../../giipAgent.cnf"
ENV_FILE="${SCRIPT_DIR}/../../agent_env.json"
LAST_RUN_FILE="${GIIP_DOCKER_USAGE_LAST_RUN_FILE:-/tmp/giip_docker_usage_last_run}"
DOCKER_TIMEOUT=10

# Load libraries (kvs_put 가 이미 정의돼 있으면 - 예: 테스트 스텁 - 다시 로드하지 않는다)
if [ "$(type -t log_message)" != "function" ] && [ -f "${LIB_DIR}/common.sh" ]; then
	. "${LIB_DIR}/common.sh"
fi
if [ "$(type -t kvs_put)" != "function" ]; then
	if [ -f "${LIB_DIR}/kvs.sh" ]; then
		. "${LIB_DIR}/kvs.sh"
	else
		echo "[DockerUsage] ERROR: kvs.sh not found"
		exit 1
	fi
fi

# log_message 가 없는 환경 대비 (콘솔 출력만)
_du_log() {
	if [ "$(type -t log_message)" = "function" ]; then
		log_message "$1" "[DockerUsage] $2"
	else
		echo "[$1] [DockerUsage] $2"
	fi
}

# Load configuration (lssn/sk/apiaddrv2). 실패해도 계속 진행한다(값이 없으면 아래에서 건너뜀).
if [ -z "$sk" ] && [ -f "$CONFIG_FILE" ] && [ "$(type -t load_config)" = "function" ]; then
	load_config "$CONFIG_FILE" >/dev/null 2>&1 || true
fi

# Interval gate: 다른 수집기(collect_enhanced_metrics.sh)와 같은 규약 (기본 300초)
METRICS_INTERVAL=300
if [ -f "$ENV_FILE" ] && command -v jq >/dev/null 2>&1; then
	METRICS_INTERVAL=$(jq -r '.metrics_interval // 300' "$ENV_FILE" 2>/dev/null || echo 300)
fi
[ -n "${metrics_interval}" ] && METRICS_INTERVAL=$metrics_interval
[[ "$METRICS_INTERVAL" =~ ^[0-9]+$ ]] || METRICS_INTERVAL=300

CURRENT_TIME=$(date +%s)
if [ -f "$LAST_RUN_FILE" ]; then
	LAST_RUN=$(cat "$LAST_RUN_FILE" 2>/dev/null)
	if [[ "$LAST_RUN" =~ ^[0-9]+$ ]] && [ $((CURRENT_TIME - LAST_RUN)) -lt "$METRICS_INTERVAL" ]; then
		exit 0
	fi
fi
echo "$CURRENT_TIME" > "$LAST_RUN_FILE" 2>/dev/null

export LC_ALL=C
export LANG=C

# Run a docker command with a timeout when available (데몬 hang 방어)
_du_docker() {
	if command -v timeout >/dev/null 2>&1; then
		timeout "$DOCKER_TIMEOUT" docker "$@" 2>/dev/null
	else
		docker "$@" 2>/dev/null
	fi
}

# "1.199GB", "0B", "113.2MB (69%)" -> GB (Windows ConvertTo-GbFromSizeString 과 동일 환산: 1024 기준; docker 는 소문자 kB 도 씀)
# 파싱 실패 시 0 을 출력한다.
_du_size_to_gb() {
	echo "$1" | awk '{
		s = $1
		if (match(s, /^[0-9.]+(B|KB|kB|MB|GB|TB)$/)) {
			u = s; sub(/^[0-9.]+/, "", u)
			n = s; sub(/(B|KB|kB|MB|GB|TB)$/, "", n); n = n + 0
			if (u == "B") n = n / (1024*1024*1024)
			else if (u == "KB" || u == "kB") n = n / (1024*1024)
			else if (u == "MB") n = n / 1024
			else if (u == "TB") n = n * 1024
			printf "%.4f", n
		} else {
			printf "0"
		}
	}'
}

docker_installed=false
docker_version=""
containers_running=0
containers_total=0
images_count=0
disk_used_gb=0
disk_reclaimable_gb=0

if ! command -v docker >/dev/null 2>&1; then
	_du_log "INFO" "Docker CLI not found on this host. Reporting dockerInstalled=false (normal for most servers)."
else
	server_version=$(_du_docker version --format '{{.Server.Version}}')
	version_rc=$?
	server_version=$(echo "$server_version" | tr -d '\r' | head -n 1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
	if [ "$version_rc" -ne 0 ] || [ -z "$server_version" ]; then
		_du_log "INFO" "Docker CLI found but daemon is not reachable (not running). Reporting dockerInstalled=false."
	else
		docker_installed=true
		# JSON 문자열 안전화 (버전 문자열에 허용되는 문자만 남긴다)
		docker_version=$(echo "$server_version" | tr -cd 'A-Za-z0-9._+~-')
		_du_log "INFO" "Docker daemon detected (version ${docker_version}). Collecting resource metrics..."

		# docker info -> 컨테이너/이미지 개수
		info_line=$(_du_docker info --format '{{.ContainersRunning}} {{.Containers}} {{.Images}}')
		if [[ "$info_line" =~ ^([0-9]+)[[:space:]]+([0-9]+)[[:space:]]+([0-9]+)$ ]]; then
			containers_running=${BASH_REMATCH[1]}
			containers_total=${BASH_REMATCH[2]}
			images_count=${BASH_REMATCH[3]}
		else
			_du_log "ERROR" "Failed to parse 'docker info' output."
		fi

		# docker system df -> 타입별(Images/Containers/Local Volumes/Build Cache) Size/Reclaimable 합계
		df_out=$(_du_docker system df --format '{{.Size}}|{{.Reclaimable}}')
		if [ -n "$df_out" ]; then
			used_sum=0
			reclaim_sum=0
			while IFS='|' read -r size_txt reclaim_txt; do
				[ -z "$size_txt$reclaim_txt" ] && continue
				used_sum=$(awk -v a="$used_sum" -v b="$(_du_size_to_gb "$size_txt")" 'BEGIN{printf "%.4f", a+b}')
				reclaim_sum=$(awk -v a="$reclaim_sum" -v b="$(_du_size_to_gb "$reclaim_txt")" 'BEGIN{printf "%.4f", a+b}')
			done <<< "$(echo "$df_out" | tr -d '\r')"
			disk_used_gb=$(awk -v a="$used_sum" 'BEGIN{printf "%.2f", a}')
			disk_reclaimable_gb=$(awk -v a="$reclaim_sum" 'BEGIN{printf "%.2f", a}')
		else
			_du_log "ERROR" "Failed to run 'docker system df' (continuing with zero disk values)."
		fi
	fi
fi

COLLECTED_AT=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
PAYLOAD_JSON="{\"dockerInstalled\":${docker_installed},\"dockerVersion\":\"${docker_version}\",\"containersRunning\":${containers_running},\"containersTotal\":${containers_total},\"imagesCount\":${images_count},\"diskUsedGb\":${disk_used_gb},\"diskReclaimableGb\":${disk_reclaimable_gb},\"collectedAt\":\"${COLLECTED_AT}\"}"

if [ -z "$lssn" ] || [ -z "$sk" ] || [ -z "$apiaddrv2" ]; then
	_du_log "WARN" "Missing required variables (lssn/sk/apiaddrv2) for KVS upload."
	exit 1
fi

# giip 3079: kvs_put 반환값을 확인해 로그 레벨을 정직하게 고른다.
_du_log "INFO" "Uploading Docker resource usage to KVS (Factor: docker_usage)..."
if kvs_put "lssn" "$lssn" "docker_usage" "$PAYLOAD_JSON"; then
	_du_log "INFO" "Successfully collected and uploaded Docker resource usage (dockerInstalled=${docker_installed})."
else
	_du_log "ERROR" "KVS upload (docker_usage) failed (see [KVS-Put] errors above)."
	if command -v log_error >/dev/null 2>&1; then
		log_error "collect_docker_usage.sh: kvs_put failed" "ApiError" "lssn=$lssn"
	fi
	exit 1
fi
exit 0
