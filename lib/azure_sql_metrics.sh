#!/bin/bash
#===============================================================================
# Azure SQL (PaaS) Monitor Metrics Module
#
# Description:
#   Azure SQL Database용 Azure Monitor 지표(CPU/DTU/IO/Storage 등)를 az CLI로 수집한다.
#   db_host가 *.database.windows.net 인 경우에만 동작한다(온프레미스/VM SQL Server는 대상 아님
#   — 그런 서버는 azure_status: not_applicable 로 조용히 스킵된다).
#
#   인증은 giipAgent.cnf 의 서비스 프린시펄(az_client_id/az_client_secret/az_tenant_id)을
#   재사용한다 — AZURE_COST_COLLECTOR_SPECIFICATION.md §4 와 동일 패턴/동일 키 이름.
#   각 CSN이 자기 giipAgent 호스트에서 이 값을 직접 설정(또는 기존 az login 세션 유지)해야
#   하며, 둘 다 없으면 "login_required" 상태로 보고한다(에러로 취급하지 않음 — 화면에서
#   사용자가 "로그인이 필요하다"를 그대로 인지할 수 있게 하기 위함).
#
# Version: 1.0.0
# Date: 2026-08-07
# Related: giip-issue #921
#
# Usage:
#   source lib/azure_sql_metrics.sh
#   result=$(collect_azure_sql_metrics "host" "database")
#
# Returns (always valid JSON, never fails hard):
#   {"azure_status":"not_applicable"}                    # host isn't *.database.windows.net
#   {"azure_status":"not_installed"}                     # az CLI missing
#   {"azure_status":"login_required"}                    # no SPN creds in cnf and no active az session
#   {"azure_status":"forbidden","reason":".."}           # az call failed (permission/RG lookup/etc.)
#   {"azure_status":"ok","cpu_percent":..,"dtu_consumption_percent":..,...}
#===============================================================================

_azure_login_done=""   # module-level cache: attempt SPN login at most once per agent run

collect_azure_sql_metrics() {
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local db_host="$1"
    local db_database="$2"

    # 1. Applicability check — only Azure SQL PaaS databases
    if [[ "$db_host" != *.database.windows.net ]]; then
        echo '{"azure_status":"not_applicable"}'
        return 0
    fi

    if ! command -v az &>/dev/null; then
        echo '{"azure_status":"not_installed"}'
        return 0
    fi

    # 2. Ensure logged in (service-principal preferred, per AZURE_COST_COLLECTOR_SPECIFICATION.md §4)
    if [ -z "$_azure_login_done" ]; then
        if az account show >/dev/null 2>&1; then
            _azure_login_done="existing_session"
        elif [ -n "$az_client_id" ] && [ -n "$az_client_secret" ] && [ -n "$az_tenant_id" ]; then
            if az login --service-principal -u "$az_client_id" -p "$az_client_secret" --tenant "$az_tenant_id" >/dev/null 2>&1; then
                _azure_login_done="spn_login"
            fi
        fi
    fi

    if [ -z "$_azure_login_done" ]; then
        echo '{"azure_status":"login_required"}'
        return 0
    fi

    if [ -n "$az_subscription" ]; then
        az account set --subscription "$az_subscription" >/dev/null 2>&1
    fi

    # 3. Resolve server name + resource group (file-cached, 24h TTL —
    #    resource group essentially never changes for a given server, staleness risk is low)
    local server_name="${db_host%%.database.windows.net}"
    local rg_cache_file="/tmp/giip_azure_rg_cache_${server_name}.txt"
    local resource_group=""

    if [ -f "$rg_cache_file" ]; then
        local mtime now age
        mtime=$(stat -c %Y "$rg_cache_file" 2>/dev/null || echo 0)
        now=$(date +%s)
        age=$(( now - mtime ))
        if [ "$age" -lt 86400 ]; then
            resource_group=$(cat "$rg_cache_file" 2>/dev/null)
        fi
    fi

    if [ -z "$resource_group" ]; then
        resource_group=$(timeout 15 az sql server list --query "[?fullyQualifiedDomainName=='${db_host}'].resourceGroup | [0]" -o tsv 2>/dev/null)
        if [ -n "$resource_group" ]; then
            echo "$resource_group" > "$rg_cache_file" 2>/dev/null
        fi
    fi

    if [ -z "$resource_group" ]; then
        echo '{"azure_status":"forbidden","reason":"resource_group_not_found"}'
        return 0
    fi

    # 4. Build resource ID and query Azure Monitor metrics
    local sub_id="$az_subscription"
    if [ -z "$sub_id" ]; then
        sub_id=$(az account show --query id -o tsv 2>/dev/null)
    fi
    if [ -z "$sub_id" ]; then
        echo '{"azure_status":"forbidden","reason":"subscription_not_resolved"}'
        return 0
    fi

    local resource_id="/subscriptions/${sub_id}/resourceGroups/${resource_group}/providers/Microsoft.Sql/servers/${server_name}/databases/${db_database}"

    local metrics_json
    metrics_json=$(timeout 15 az monitor metrics list \
        --resource "$resource_id" \
        --metric "cpu_percent" "dtu_consumption_percent" "physical_data_read_percent" "log_write_percent" "storage_percent" "workers_percent" "sessions_percent" \
        --interval PT1M --aggregation Average -o json 2>/dev/null)

    if [ -z "$metrics_json" ]; then
        echo '{"azure_status":"forbidden","reason":"metrics_call_failed"}'
        return 0
    fi

    local parsed
    parsed=$(python3 "${SCRIPT_DIR}/parse_azure_sql_metrics.py" <<< "$metrics_json" 2>/dev/null)
    if [ -z "$parsed" ]; then
        echo '{"azure_status":"forbidden","reason":"metrics_parse_failed"}'
    else
        echo "$parsed"
    fi
    return 0
}

export -f collect_azure_sql_metrics
