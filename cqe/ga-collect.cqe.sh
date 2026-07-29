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
#                          optional: GaKeyFile (local override path, skips DB fetch),
#                                    GaFactor (default 'daily'), GaRange (default 'yesterday')
#
# giip-803: GA4 서비스계정 키는 서버에 파일로 미리 배치하지 않는다 — ga-property 화면에서
#   입력/관리되는 값을 실행 시점에 pApiGaKeyGetbySk(자기 sk 인증)로 받아 임시파일로만 쓰고
#   즉시 삭제한다. $GaKeyFile 을 custom_values 로 명시 주입한 경우에만 로컬 파일을 우선한다.
#
# Remote PC prerequisites:
#   - openssl, curl, jq (already required by the rest of giipAgentLinux).
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

FETCHED_KEY_FILE=""
cleanup() { [ -n "$FETCHED_KEY_FILE" ] && rm -f "$FETCHED_KEY_FILE"; }
trap cleanup EXIT

if [ -z "$GaProperty" ]; then log ERROR "GaProperty not set (custom_values)."; exit 1; fi
if [ -z "${sk:-}" ]; then log ERROR "giip sk token not present in environment (expected from load_config export)."; exit 1; fi
if [ -z "${apiaddrv2:-}" ]; then log ERROR "apiaddrv2 not present in environment."; exit 1; fi
for bin in openssl curl jq; do
	command -v "$bin" >/dev/null 2>&1 || { log ERROR "required binary not found: $bin"; exit 1; }
done

base64url() {
	openssl base64 -A | tr '+/' '-_' | tr -d '='
}

# --- GA4 서비스계정 키 확보: 로컬 override 없으면 DB(ga-property 화면)에서 조회 ---
if [ -z "$GaKeyFile" ] || [ ! -f "$GaKeyFile" ]; then
	key_text="GaKeyGet gaPropertyId"
	key_jsondata="{\"gaPropertyId\":\"${GaProperty}\"}"
	key_encoded_text=$(printf '%s' "$key_text" | jq -sRr '@uri')
	key_encoded_token=$(printf '%s' "$sk" | jq -sRr '@uri')
	key_encoded_jsondata=$(printf '%s' "$key_jsondata" | jq -sRr '@uri')

	key_resp=$(curl -s -X POST "$apiaddrv2" \
		-H "Content-Type: application/x-www-form-urlencoded" \
		-d "text=${key_encoded_text}&token=${key_encoded_token}&jsondata=${key_encoded_jsondata}")

	# giipfaw 디스패처가 "\n"(리터럴 백슬래시+n) 을 실제 개행으로 깨버리는 버그가 있어
	# (2026-07-29 실측 확인) SP 가 base64 로 인코딩해 반환한다 — 여기서 디코드.
	key_b64=$(printf '%s' "$key_resp" | jq -r '.data[0].gaKeyJsonB64 // .gaKeyJsonB64 // empty' 2>/dev/null)
	if [ -z "$key_b64" ]; then
		pm=$(printf '%s' "$key_resp" | jq -r '.data[0].Proc_MSG // .Proc_MSG // empty' 2>/dev/null)
		log ERROR "GaKeyGet failed (property not registered with a key on ga-property page?): ${pm:-$key_resp}"
		exit 1
	fi

	FETCHED_KEY_FILE=$(mktemp)
	chmod 600 "$FETCHED_KEY_FILE"
	printf '%s' "$key_b64" | base64 -d > "$FETCHED_KEY_FILE"
	GaKeyFile="$FETCHED_KEY_FILE"
fi

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
cleanup() { [ -n "$FETCHED_KEY_FILE" ] && rm -f "$FETCHED_KEY_FILE"; rm -f "$privkey_file"; }
jq -r '.private_key // empty' "$GaKeyFile" > "$privkey_file"
if [ ! -s "$privkey_file" ]; then log ERROR "SA JSON missing private_key."; exit 1; fi
chmod 600 "$privkey_file"

sig_b64=$(printf '%s' "$signing_input" | openssl dgst -sha256 -sign "$privkey_file" | base64url)
rm -f "$privkey_file"

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
