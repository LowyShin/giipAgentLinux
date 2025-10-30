# KVSPut Endpoint Configuration Priority

## Issue Summary
- **Date**: 2025-10-30
- **Problem**: `kvsput.sh` was calling old `giipApi` endpoint instead of `giipApiSk2`
- **Root Cause**: `Endpoint` config had higher priority than `apiaddrv2`, causing old API usage

## Background

### Why Two Endpoint Configurations Exist

**giipAgent.cnf** has two endpoint configurations:
```ini
[Agent]
Endpoint=https://giipfaw.azurewebsites.net/api/giipApi?code=<FUNCTION_KEY>     # Old API (v1)
apiaddrv2=https://giipfaw.azurewebsites.net/api/giipApiSk2                     # New API (v2)
apiaddrcode=<FUNCTION_KEY>                                                     # Azure Function authentication code

[KVS]
Endpoint=https://giipfaw.azurewebsites.net/api/giipApi?code=<FUNCTION_KEY>     # Inherits from [Agent]
```

**Why keep both?**
- Old agent scripts (giipAgent.sh, etc.) still use `Endpoint` → `giipApi`
- New scripts (kvsput.sh) must use `apiaddrv2` → `giipApiSk2`
- Cannot modify `giipAgent.cnf` because old code depends on it

## API Comparison

### giipApi (Old - v1)
- **Location**: `giipfaw/giipApi/run.ps1`
- **Issues**:
  - KVSPut calls `pApiKVSPutbyAK` (old typo, wrong SP name)
  - Sends 6 parameters instead of 5 → "too many arguments" error
  - No KVSPut special handling
  - Legacy parameter processing

### giipApiSk2 (New - v2)
- **Location**: `giipfaw/giipApiSk2/run.ps1`
- **Features**:
  - ✅ KVSPut special handling (lines 88-124)
  - ✅ Parses jsondata to extract individual values
  - ✅ Calls correct SP: `pApiKVSPutbySk` 
  - ✅ Sends 5 parameters: (sk, kType, kKey, kFactor, kValue)
  - ✅ Debug logging with ★★★ markers
  - ✅ Response includes debug info

## Solution

### kvsput.sh Priority Change

**Before** (Wrong):
```bash
# Priority: Endpoint > apiaddrv2
if [[ -n "${KVS_CONFIG[Endpoint]}" ]]; then
  ENDPOINT="${KVS_CONFIG[Endpoint]}"      # Used giipApi (v1) ❌
elif [[ -n "${KVS_CONFIG[apiaddrv2]}" ]]; then
  ENDPOINT="${KVS_CONFIG[apiaddrv2]}"
```

**After** (Correct):
```bash
# Priority: apiaddrv2 > Endpoint (prefer v2 API for KVS)
if [[ -n "${KVS_CONFIG[apiaddrv2]}" ]]; then
  ENDPOINT="${KVS_CONFIG[apiaddrv2]}"     # Uses giipApiSk2 (v2) ✅
elif [[ -n "${KVS_CONFIG[Endpoint]}" ]]; then
  ENDPOINT="${KVS_CONFIG[Endpoint]}"      # Fallback only
```

**Commit**: `94f906a` - Fix: kvsput.sh to prioritize apiaddrv2 (giipApiSk2) over Endpoint

### Function Code Priority
Also changed to prefer v2 authentication:
```bash
# Priority: apiaddrcode > FunctionCode (prefer v2)
if [[ -n "${KVS_CONFIG[apiaddrcode]}" ]]; then
  ENDPOINT+="?code=${KVS_CONFIG[apiaddrcode]}"
elif [[ -n "${KVS_CONFIG[FunctionCode]}" ]]; then
  ENDPOINT+="?code=${KVS_CONFIG[FunctionCode]}"
```

## Verification

### Check Current Endpoint Usage
```bash
# On server
grep "Endpoint:" /var/log/giip-auto-discover.log | tail -5
```

**Expected Output** (Correct):
```
[DIAG] Endpoint: https://giipfaw.azurewebsites.net/api/giipApiSk2?code=...
```

**Wrong Output** (Before fix):
```
[DIAG] Endpoint: https://giipfaw.azurewebsites.net/api/giipApi?code=...
```

### Check Azure Function Logs
```bash
az monitor app-insights query --app 0d98310d-a204-44e7-8ad6-ae10657bf0b8 \
  --analytics-query "traces | where timestamp > ago(5m) and message contains '★★★' | project timestamp, message"
```

**Expected** (KVSPut special handling active):
```
[DEBUG] ★★★ KVSPut special handling ACTIVATED ★★★
[DEBUG] KVSPut query built from jsondata: exec pApiKVSPutbySk '...', 'lssn', '71174', 'autodiscover', '{...}'
```

**Wrong** (Before fix - not using giipApiSk2):
```
(no ★★★ markers found)
Error: pApiKVSPutbyAK has too many arguments specified
```

## Related Files

### Modified Files
- **giipAgentLinux/giipscripts/kvsput.sh** (Line 81-96)
  - Changed endpoint priority to `apiaddrv2` first
  - Changed auth code priority to `apiaddrcode` first

### Related Azure Functions
- **giipfaw/giipApi/run.ps1** - Old API (v1), DO NOT use for KVSPut
- **giipfaw/giipApiSk2/run.ps1** - New API (v2), KVSPut compatible

### Configuration File
- **giipAgent.cnf** - Server-side config
  - `[Agent]` section: Both `Endpoint` and `apiaddrv2` must exist
  - Old scripts use `Endpoint`
  - New scripts (kvsput.sh) use `apiaddrv2`

## Deployment Process

### Update Server
```bash
# On each server
cd /opt/giipAgentLinux  # or agent install path
git pull
bash giip-auto-discover.sh
```

### Verify Success
```bash
# Check log for correct endpoint
tail -100 /var/log/giip-auto-discover.log | grep -A 5 "DIAG.*Endpoint"

# Should show:
# [DIAG] Endpoint: https://giipfaw.azurewebsites.net/api/giipApiSk2?code=...
# [INFO] KVS upload result: (successful response with data)
```

## Troubleshooting

### Issue: Still Using Old Endpoint After git pull

**Check 1**: Verify git pull succeeded
```bash
cd /opt/giipAgentLinux
git log --oneline -5 | grep "94f906a"
```

**Check 2**: Verify kvsput.sh content
```bash
grep -A 5 "Priority:" giipscripts/kvsput.sh
# Should show: "Priority: apiaddrv2 > Endpoint"
```

**Check 3**: Verify config file has apiaddrv2
```bash
cat giipAgent.cnf | grep -E "apiaddrv2|apiaddrcode"
```

### Issue: KVSPut Still Failing

**Symptom**: "pApiKVSPutbyAK has too many arguments"

**Cause**: Using old `giipApi` endpoint

**Solution**: 
1. Check log: `grep "Endpoint:" /var/log/giip-auto-discover.log | tail -1`
2. If shows `giipApi` → kvsput.sh not updated, run `git pull`
3. If shows `giipApiSk2` but still error → Azure Function cache issue, restart function app

### Issue: No jsondata in Request

**Symptom**: Azure logs show "NOT KVSPut special handling"

**Cause**: kvsput.sh not sending jsondata parameter

**Check**:
```bash
grep "jsondata (file) preview:" /var/log/giip-auto-discover.log | tail -1
```

If missing → Check JSON file generation in giip-auto-discover.sh

## Design Principles

### Why Not Remove Old Endpoint?

**Cannot remove `Endpoint` from giipAgent.cnf because:**
1. Old agent scripts (giipAgent.sh) hardcoded to use `Endpoint`
2. Multiple servers may have different agent versions
3. Backward compatibility required during transition period

**Strategy**: Make new scripts prefer `apiaddrv2`, but keep `Endpoint` as fallback

### Why Priority Matters

**Wrong priority** (Endpoint first):
```
giipAgent.cnf has both configs → kvsput.sh picks Endpoint → calls giipApi (v1) → KVSPut fails
```

**Correct priority** (apiaddrv2 first):
```
giipAgent.cnf has both configs → kvsput.sh picks apiaddrv2 → calls giipApiSk2 (v2) → KVSPut succeeds
```

## Testing Checklist

After deploying kvsput.sh changes:

- [ ] Server: `git pull` successful
- [ ] Server: `grep "Priority:" giipscripts/kvsput.sh` shows apiaddrv2 first
- [ ] Server: Run `bash giip-auto-discover.sh`
- [ ] Log: `grep "Endpoint:" /var/log/giip-auto-discover.log | tail -1` shows giipApiSk2
- [ ] Log: `grep "KVS upload result:" /var/log/giip-auto-discover.log | tail -1` shows success (no error)
- [ ] Azure: `az monitor app-insights query` shows "★★★ KVSPut special handling ACTIVATED ★★★"
- [ ] Database: `SELECT TOP 5 * FROM tKVS WHERE kKey='71174' ORDER BY kRegdt DESC` shows new data
- [ ] Web UI: Navigate to KVS factor list page, verify data displays

## Future Improvements

### Eventual Migration Plan
1. **Phase 1** (Current): New scripts use apiaddrv2, old scripts use Endpoint
2. **Phase 2**: Update all agent scripts to use apiaddrv2
3. **Phase 3**: Deprecate giipApi (v1) endpoint
4. **Phase 4**: Remove Endpoint config, only use apiaddrv2

### Monitoring
- Add alert when giipApi (v1) receives KVSPut requests
- Dashboard to track endpoint usage by script
- Automated test to verify kvsput.sh uses correct endpoint

## References

- **Root Cause Analysis**: giipfaw/docs/KVSPUT_PARAMETER_FIX.md
- **API Rules**: giipfaw/docs/giipapi_rules.md
- **KVSPut Implementation**: giipfaw/giipApiSk2/run.ps1 (lines 88-124)
- **Agent Configuration**: giipAgentLinux/README.md

## Change History

| Date | Commit | Description |
|------|--------|-------------|
| 2025-10-30 | 94f906a | Fix: kvsput.sh to prioritize apiaddrv2 over Endpoint |
| 2025-10-30 | fbec2b3 | Initial kvsput.sh implementation |
| 2025-10-30 | 0fb7bb5 | Add debug info to API response |
| 2025-10-30 | 17da35e | Force redeploy to clear cache |
| 2025-10-30 | 666af23 | Fix missing closing brace |
| 2025-10-30 | cf0af8a | Add debug logging |
| 2025-10-30 | 10f0d0c | Initial KVSPut parameter fix |
