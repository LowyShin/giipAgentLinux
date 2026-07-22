#!/bin/bash
# ============================================================================
# execgiipga.sh
# Purpose : Daily (once/day) GA AI-analysis batch.
#           Enqueue latest GA data -> claim tickets -> AI analysis -> save result.
# Pattern : Mirrors the KVSAdvice batch (execgiipadv.sh) but for GA-only queue
#           (tGaAiReport, 01->02->03, 04 on retry-exhaust). NO points/Gas charge.
# Auth    : bySk verbs (GaQueueGet/GaAdvRstPut/GaAdvFail) use queueSk validated
#           by tGaConfig(queue_sk). byAK verb (GaAdvEnqueue) uses the same token
#           (SP resolves via lwGetUSNbyat). No sk is hardcoded in this source.
# Config  : JSON at $GA_BATCH_CONFIG (default $HOME/.giip/ga-collector.config.json),
#           matching giipdb/mgmt/ga-collector.config.json.sample.
# Cron    : 30 9 * * *  /path/to/execgiipga.sh   (own slot; no clash with execadm/execgiipadv)
# Spec    : giip-678 / SPEC_20260720_GA_KVS_AI_REPORT.md T5 (§4.4)
# ============================================================================
set -euo pipefail

log()  { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" >&2; }
die()  { log "ERROR: $*"; exit 1; }

command -v jq   >/dev/null 2>&1 || die "jq is required"
command -v curl >/dev/null 2>&1 || die "curl is required"

CFG="${GA_BATCH_CONFIG:-$HOME/.giip/ga-collector.config.json}"
[ -f "$CFG" ] || die "GA batch config not found: $CFG (see giipdb/mgmt/ga-collector.config.json.sample)"

DISP_AK=$(jq -r '.dispatcherUrl // empty'     "$CFG")     # byAK dispatcher (giipApi)
DISP_SK=$(jq -r '.dispatcherSk2Url // empty'  "$CFG")     # bySk dispatcher (giipApiSk2)
QUEUE_SK=$(jq -r '.batch.queueSk // empty'    "$CFG")
AI_KEY=$(jq -r '.batch.aiApiKey // empty'     "$CFG")
AI_MODEL=$(jq -r '.batch.aiModel // "gpt-4o-mini"' "$CFG")
MAX_ITEMS=$(jq -r '.batch.maxItemsPerRun // 20' "$CFG")
GA_KEYS=$(jq -r '.collector.properties[]?.propertyId // empty' "$CFG")

[ -n "$DISP_SK" ]  || die "dispatcherSk2Url missing in $CFG"
[ -n "$QUEUE_SK" ] || die "batch.queueSk missing in $CFG (must equal tGaConfig.queue_sk)"
[ -n "$AI_KEY" ]   || die "batch.aiApiKey missing in $CFG"
[ -n "$DISP_AK" ]  || DISP_AK="$DISP_SK"   # fall back to same host if only one dispatcher

# call_dispatcher <url> <token> <text> <jsondata>  -> prints raw response
call_dispatcher() {
  local url="$1" token="$2" text="$3" json="$4"
  local tmp; tmp=$(mktemp)
  {
    printf 'text=%s'      "$(printf '%s' "$text"  | jq -sRr @uri)"
    printf '&token=%s'    "$(printf '%s' "$token" | jq -sRr @uri)"
    printf '&jsondata=%s' "$(printf '%s' "$json"  | jq -sRr @uri)"
  } > "$tmp"
  curl -s -X POST "$url" \
    -H 'Content-Type: application/x-www-form-urlencoded' -H 'Expect:' \
    --max-time 60 --connect-timeout 10 --data-binary "@$tmp"
  local rc=$?
  rm -f "$tmp"
  return $rc
}

log "GA AI batch start (model=$AI_MODEL, maxItems=$MAX_ITEMS)"

# --- Phase 1: enqueue latest GA data per configured property (byAK) -----------
enq=0
if [ -n "$GA_KEYS" ]; then
  while IFS= read -r gaKey; do
    [ -z "$gaKey" ] && continue
    resp=$(call_dispatcher "$DISP_AK" "$QUEUE_SK" "GaAdvEnqueue gaKey" "$(jq -nc --arg gaKey "$gaKey" '{gaKey:$gaKey}')" || true)
    log "enqueue $gaKey -> $(echo "$resp" | jq -c '.data[0] // .' 2>/dev/null || echo "$resp")"
    enq=$((enq+1))
  done <<< "$GA_KEYS"
fi
log "enqueue phase done ($enq properties)"

# --- Phase 2: drain queue (bySk claim -> AI -> result) ------------------------
done_ct=0; fail_ct=0; i=0
while [ "$i" -lt "$MAX_ITEMS" ]; do
  i=$((i+1))
  claim=$(call_dispatcher "$DISP_SK" "$QUEUE_SK" "GaQueueGet" '{}' || true)
  # bySk dispatcher wraps result in {data:[...],debug:...}
  row=$(echo "$claim" | jq -c '.data[0] // .' 2>/dev/null || echo "$claim")
  rstval=$(echo "$row" | jq -r '.RstVal // empty' 2>/dev/null || true)
  if [ "$rstval" = "404" ]; then log "no more tickets"; break; fi
  garSn=$(echo "$row" | jq -r '.garSn // empty' 2>/dev/null || true)
  if [ -z "$garSn" ] || [ "$garSn" = "null" ]; then
    log "claim returned no ticket / unexpected: $row"; break
  fi
  gaKey=$(echo "$row"  | jq -r '.gaKey // empty')
  kValue=$(echo "$row" | jq -r '.kValue // "{}"')
  log "claimed garSn=$garSn gaKey=$gaKey"

  # --- Build AI prompt from GA metrics ---
  prompt=$(cat <<EOF
You are a web analytics assistant. Analyze the following Google Analytics 4 daily metrics
for property $gaKey. Provide a concise Markdown report with: (1) one-line summary,
(2) notable changes or anomalies, (3) 2-3 actionable recommendations.
Keep it under 200 words. Data (JSON):
$kValue
EOF
)
  aiPayload=$(jq -nc --arg model "$AI_MODEL" --arg content "$prompt" \
    '{model:$model, messages:[{role:"user",content:$content}], temperature:0.3}')

  aiResp=$(curl -s -X POST "https://api.openai.com/v1/chat/completions" \
    -H "Authorization: Bearer $AI_KEY" -H 'Content-Type: application/json' \
    --max-time 90 --data-binary "$aiPayload" || true)
  result=$(echo "$aiResp" | jq -r '.choices[0].message.content // empty' 2>/dev/null || true)

  if [ -z "$result" ]; then
    errmsg=$(echo "$aiResp" | jq -r '.error.message // "empty AI response"' 2>/dev/null || echo "AI call failed")
    log "AI failed for garSn=$garSn: $errmsg -> GaAdvFail"
    call_dispatcher "$DISP_SK" "$QUEUE_SK" "GaAdvFail garSn note" \
      "$(jq -nc --argjson garSn "$garSn" --arg note "$errmsg" '{garSn:$garSn, note:$note}')" >/dev/null || true
    fail_ct=$((fail_ct+1))
    continue
  fi

  put=$(call_dispatcher "$DISP_SK" "$QUEUE_SK" "GaAdvRstPut garSn garResult" \
    "$(jq -nc --argjson garSn "$garSn" --arg garResult "$result" '{garSn:$garSn, garResult:$garResult}')" || true)
  putval=$(echo "$put" | jq -r '.data[0].RstVal // .RstVal // empty' 2>/dev/null || true)
  if [ "$putval" = "200" ]; then
    log "garSn=$garSn completed"; done_ct=$((done_ct+1))
  else
    log "GaAdvRstPut unexpected for garSn=$garSn: $put -> GaAdvFail"
    call_dispatcher "$DISP_SK" "$QUEUE_SK" "GaAdvFail garSn note" \
      "$(jq -nc --argjson garSn "$garSn" --arg note "rst_put_failed" '{garSn:$garSn, note:$note}')" >/dev/null || true
    fail_ct=$((fail_ct+1))
  fi
done

log "GA AI batch end (enqueued=$enq, completed=$done_ct, failed=$fail_ct)"
exit 0
