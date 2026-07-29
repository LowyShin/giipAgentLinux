#!/bin/bash
# ============================================================================
# ga-collect.cqe.sh — CQE-delivered GA4 collector (giip-803, Linux/bash port
# of giipAgentWin/giipscripts/cqe/ga-collect.cqe.ps1)
# ----------------------------------------------------------------------------
# This is a SELF-CONTAINED script body meant to be registered in the giip CQE
# repo (tMgmtScript, script_type='sh') and dispatched to a remote Linux PC's
# giipAgentLinux via CQE (lib/normal.sh execute_script -> `sh "$script_file"`).
#
# giipAgentLinux already exports $sk / $lssn / $apiaddrv2 into the environment
# (lib/common.sh load_config) before executing any fetched CQE script body, so
# unlike the Windows variant there is no {{sk}}/{{lssn}} template need here —
# just read them from the environment directly.
#
# CQE placeholder substitution (do NOT edit this token):
#   {{CustomVariables}} -> per-assignment custom_values injected as shell code
#                          (giipdb pApiCQERunForcebyAk / pApiCQEQGetbySk REPLACE).
#                          Must set:
#                            GaProperty='properties/123456789'
#                            GaKeyFile='/home/giip/ga-service-account.json'
#                          optional: GaFactor (default 'daily'), GaRange (default 'yesterday')
#
# Remote PC prerequisites:
#   - openssl, curl, jq (already required by the rest of giipAgentLinux).
#   - GA4 service-account key JSON present at $GaKeyFile (NOT shipped in ms_body).
#
# Registration: giipdb/mgmt/register-ga-cqe.ps1 -MsType sh -ScriptFile <this file>
# Spec: giip-678 / SPEC_20260720_GA_KVS_AI_REPORT.md T3 (CQE delivery variant)
# giip-803: 71174(cctrank03) 을 GA 수집기 노드로 등록하며 신규 작성.
# ============================================================================

GaFactor="${GaFactor:-daily}"
GaRange="${GaRange:-yesterday}"
GaProperty="${GaProperty:-}"
GaKeyFile="${GaKeyFile:-}"
# {{CustomVariables}}

log() { echo "[$(date '+%Y-%m-%dT%H:%M:%S')] [ga-cqe] $1: $2"; }

if [ -z "$GaProperty" ]; then log ERROR "GaProperty not set (custom_values)."; exit 1; fi
if [ -z "$GaKeyFile" ] || [ ! -f "$GaKeyFile" ]; then log ERROR "GaKeyFile not found: '$GaKeyFile'."; exit 1; fi
if [ -z "${sk:-}" ]; then log ERROR "giip sk token not present in environment (expected from load_config export)."; exit 1; fi
if [ -z "${apiaddrv2:-}" ]; then log ERROR "apiaddrv2 not present in environment."; exit 1; fi
for bin in openssl curl jq; do
	command -v "$bin" >/dev/null 2>&1 || { log ERROR "required binary not found: $bin"; exit 1; }
done

base64url() {
	openssl base64 -A | tr '+/' '-_' | tr -d '='
}

client_email=$(jq -r '.client_email // empty' "$GaKeyFile")
token_uri=$(jq -r '.token_uri // "https://oauth2.googleapis.com/token"' "$GaKeyFile")
if [ -z "$client_email" ]; then log ERROR "SA JSON missing client_email."; exit 1; fi

now=$(date +%s)
exp=$((now + 3600))

header_json='{"alg":"RS256","typ":"JWT"}'
claim_json=$(jq -n --arg iss "$client_email" --arg aud "$token_uri" --argjson iat "$now" --argjson exp "$exp" \
	'{iss:$iss, scope:"https://www.googleapis.com/auth/analytics.readonly", aud:$aud, iat:$iat, exp:$exp}')

header_b64=$(printf '%s' "$header_json" | base64url)
claim_b64=$(printf '%s' "$claim_json" | base64url)
signing_input="${header_b64}.${claim_b64}"

privkey_file=$(mktemp)
trap 'rm -f "$privkey_file"' EXIT
jq -r '.private_key // empty' "$GaKeyFile" > "$privkey_file"
if [ ! -s "$privkey_file" ]; then log ERROR "SA JSON missing private_key."; exit 1; fi
chmod 600 "$privkey_file"

sig_b64=$(printf '%s' "$signing_input" | openssl dgst -sha256 -sign "$privkey_file" | base64url)
rm -f "$privkey_file"
trap - EXIT

jwt="${signing_input}.${sig_b64}"

token_resp=$(curl -s -X POST "$token_uri" \
	--data-urlencode "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer" \
	--data-urlencode "assertion=${jwt}")

access_token=$(printf '%s' "$token_resp" | jq -r '.access_token // empty')
if [ -z "$access_token" ]; then
	log ERROR "OAuth token exchange failed: $token_resp"
	exit 1
fi

report_body=$(jq -n --arg range "$GaRange" \
	'{dateRanges:[{startDate:$range,endDate:$range}], metrics:[{name:"activeUsers"},{name:"sessions"},{name:"screenPageViews"},{name:"bounceRate"},{name:"conversions"},{name:"averageSessionDuration"}]}')

report_resp=$(curl -s -X POST "https://analyticsdata.googleapis.com/v1beta/${GaProperty}:runReport" \
	-H "Authorization: Bearer ${access_token}" \
	-H "Content-Type: application/json" \
	-d "$report_body")

metrics_json=$(printf '%s' "$report_resp" | jq -c '
	(.metricHeaders // []) as $headers
	| (.rows[0].metricValues // []) as $vals
	| reduce range(0; ($headers|length)) as $i ({}; . + {($headers[$i].name): ($vals[$i].value // null)})
' 2>/dev/null)
[ -z "$metrics_json" ] && metrics_json="{}"

if [ "$metrics_json" = "{}" ]; then
	log WARN "runReport returned no rows: $report_resp"
fi

collected_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

kvalue_json=$(jq -n --arg pid "$GaProperty" --arg range "$GaRange" --argjson metrics "$metrics_json" --arg ts "$collected_at" \
	'{propertyId:$pid, range:$range, metrics:$metrics, collectedAt:$ts, source:"giipAgentLinux/cqe/ga-collect.cqe.sh"}')

payload=$(jq -n --arg kkey "$GaProperty" --arg factor "$GaFactor" --argjson kvalue "$kvalue_json" \
	'{kKey:$kkey, kFactor:$factor, kValue:$kvalue}')

encoded_text=$(printf '%s' "GaPut kKey kFactor kValue" | jq -sRr '@uri')
encoded_token=$(printf '%s' "$sk" | jq -sRr '@uri')
encoded_jsondata=$(printf '%s' "$payload" | jq -sRr '@uri')

resp=$(curl -s -X POST "$apiaddrv2" \
	-H "Content-Type: application/x-www-form-urlencoded" \
	-d "text=${encoded_text}&token=${encoded_token}&jsondata=${encoded_jsondata}")

rst=$(printf '%s' "$resp" | jq -r '.data[0].Proc_MSG // .Proc_MSG // empty' 2>/dev/null)
if [[ "$rst" == 200* ]]; then
	log INFO "GaPut OK (${GaProperty})."
	exit 0
else
	log ERROR "GaPut failed: $resp"
	exit 1
fi
