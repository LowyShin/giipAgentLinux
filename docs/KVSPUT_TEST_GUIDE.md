# kvsput.sh Test Guide

## Quick Test

### Option 1: From Windows (Recommended)
```powershell
cd c:\Users\lowys\Downloads\projects\giipprj\giipAgentLinux
.\test-kvsput-remote.ps1
```

This will:
1. Upload `test-kvsput.sh` to server
2. Execute the test
3. Automatically check database for results

### Option 2: Direct on Server
```bash
ssh root@10.2.0.5
cd /opt/giipAgentLinux/giipscripts
bash test-kvsput.sh
```

---

## What the Test Does

### 1. Pre-flight Checks
- ✅ Verify `kvsput.sh` exists
- ✅ Verify `giipAgent.cnf` exists
- ✅ Check configuration values (apiaddrv2, apiaddrcode, sk)
- ✅ Verify required tools (jq, curl)

### 2. Create Test JSON
```json
{
  "test_id": "kvsput-test-12345",
  "timestamp": "2025-10-30T16:50:00+09:00",
  "hostname": "cctrank03",
  "test_purpose": "Verify kvsput.sh functionality",
  "network_test": {
    "interfaces": [
      {
        "name": "eth0",
        "ipv4": "10.2.0.5",
        "mac": "00:22:48:0e:a4:93"
      }
    ]
  },
  "system_info": {
    "os": "Linux",
    "kernel": "5.4.0-150-generic",
    "arch": "x86_64"
  }
}
```

### 3. Upload to KVS
- **KFactor**: `kvstest`
- **Endpoint**: `apiaddrv2` from config (giipApiSk2)
- **Authentication**: `sk` from config

### 4. Verify Upload
Check database for uploaded data:
```powershell
cd c:\Users\lowys\Downloads\projects\giipprj\giipdb
.\check_autodiscover_kvs.ps1 -KFactor kvstest
```

---

## Expected Output

### Success ✅
```
==========================================
kvsput.sh Test Script
==========================================

✓ Found kvsput.sh: /opt/giipAgentLinux/giipscripts/kvsput.sh
✓ Found config: /opt/giipAgentLinux/giipAgent.cnf

Configuration Check:
--------------------
✓ apiaddrv2: https://giipfaw.azurewebsites.net/api/giipApiSk2
✓ apiaddrcode: abc123xyz...
✓ sk: sk_1234567890...

Required Tools Check:
--------------------
✓ jq: /usr/bin/jq
✓ curl: /usr/bin/curl

==========================================
Creating Test JSON...
==========================================
✓ Test JSON created: /tmp/kvsput-test-12345.json

Preview:
{
  "test_id": "kvsput-test-12345",
  ...
}

==========================================
Uploading to KVS...
==========================================
KFactor: kvstest
File: /tmp/kvsput-test-12345.json

[DIAG] Endpoint: https://giipfaw.azurewebsites.net/api/giipApiSk2?code=...
[DIAG] KVSP text: KVSPut lssn cctrank03 kvstest
[DIAG] Token: sk_1234567890...
[DIAG] jsondata (file) preview: {"test_id":"kvsput-test-12345",...
[INFO] KVS upload result: {"RstVal":200,"RstTxt":"success"}

==========================================
✅ SUCCESS: Upload completed!
==========================================

Next Steps:
1. Check in Windows:
   cd c:\Users\lowys\Downloads\projects\giipprj\giipdb
   .\check_autodiscover_kvs.ps1 -KFactor kvstest
```

### Failure ❌ Examples

#### Missing jq
```
❌ ERROR: jq is required but not installed
   Install: sudo apt-get install jq  (Ubuntu/Debian)
           sudo yum install jq      (CentOS/RHEL)
```

**Fix**:
```bash
sudo apt-get update
sudo apt-get install jq
```

#### Missing Config
```
⚠ WARNING: apiaddrv2 not found in config
⚠ WARNING: sk not found in config
```

**Fix**:
```bash
vi /opt/giipAgentLinux/giipAgent.cnf

# Add these lines:
apiaddrv2="https://giipfaw.azurewebsites.net/api/giipApiSk2"
apiaddrcode="YOUR_FUNCTION_CODE_HERE"
sk="YOUR_SECRET_KEY_HERE"
```

#### Upload Failed
```
[ERROR] curl failed with exit code 7
[INFO] KVS upload result (partial): Could not resolve host

❌ ERROR: Upload failed!
```

**Troubleshooting**:
```bash
# Test network connectivity
curl -I https://giipfaw.azurewebsites.net

# Check DNS resolution
nslookup giipfaw.azurewebsites.net

# Check firewall
sudo iptables -L -n | grep -i output
```

---

## Manual Test (Custom Data)

### Create Custom JSON
```bash
cat > /tmp/my-test.json <<EOF
{
  "custom_field": "my_value",
  "timestamp": "$(date -Iseconds)",
  "hostname": "$(hostname)"
}
EOF
```

### Upload with kvsput.sh
```bash
cd /opt/giipAgentLinux/giipscripts
bash kvsput.sh /tmp/my-test.json mycustomfactor
```

### Check Result
```powershell
# Windows
.\check_autodiscover_kvs.ps1 -KFactor mycustomfactor
```

---

## Verify in Database

### SQL Query
```sql
-- Check test data
SELECT TOP 5
    KVSsn,
    LSsn,
    KFactor,
    LEN(KData) AS DataSize,
    kRegdt
FROM tKVS
WHERE KFactor = 'kvstest'
ORDER BY kRegdt DESC;

-- Get full JSON
SELECT KData 
FROM tKVS 
WHERE KFactor = 'kvstest' 
  AND kRegdt > DATEADD(MINUTE, -5, GETDATE())
ORDER BY kRegdt DESC;
```

### PowerShell Query
```powershell
$config = Get-Content "c:\Users\lowys\Downloads\projects\giipprj\giipdb\mgmt\dbconfig.json" | ConvertFrom-Json

$query = @"
SELECT TOP 1 KData 
FROM tKVS 
WHERE KFactor = 'kvstest'
ORDER BY kRegdt DESC
"@

$result = Invoke-Sqlcmd -ServerInstance $config.server -Database $config.database -Query $query
$result.KData | ConvertFrom-Json | ConvertTo-Json -Depth 10
```

---

## Automated Testing

### Add to Cron (Optional)
```bash
# Test kvsput.sh every hour
0 * * * * /opt/giipAgentLinux/giipscripts/test-kvsput.sh >> /var/log/kvsput-test.log 2>&1
```

### Monitor Test Results
```sql
-- Count test uploads by hour
SELECT 
    DATEPART(HOUR, kRegdt) AS Hour,
    COUNT(*) AS TestCount
FROM tKVS
WHERE KFactor = 'kvstest'
  AND kRegdt > DATEADD(DAY, -1, GETDATE())
GROUP BY DATEPART(HOUR, kRegdt)
ORDER BY Hour;
```

---

## Cleanup

### Remove Test Data
```sql
-- Delete test data older than 1 day
DELETE FROM tKVS 
WHERE KFactor = 'kvstest' 
  AND kRegdt < DATEADD(DAY, -1, GETDATE());
```

### Keep Only Recent Tests
```sql
-- Keep only latest 10 test records
DELETE FROM tKVS
WHERE KVSsn NOT IN (
    SELECT TOP 10 KVSsn 
    FROM tKVS 
    WHERE KFactor = 'kvstest' 
    ORDER BY kRegdt DESC
)
AND KFactor = 'kvstest';
```

---

## Troubleshooting

### Issue: "Missing config: Endpoint or apiaddrv2"
**Cause**: `giipAgent.cnf` doesn't have required fields

**Fix**:
```bash
vi /opt/giipAgentLinux/giipAgent.cnf

# Ensure these lines exist:
apiaddrv2="https://giipfaw.azurewebsites.net/api/giipApiSk2"
apiaddrcode="YOUR_CODE"
sk="YOUR_SK"
```

### Issue: "jq is required but not found"
**Cause**: jq not installed

**Fix**:
```bash
# Ubuntu/Debian
sudo apt-get install jq

# CentOS/RHEL
sudo yum install jq

# Alpine
apk add jq
```

### Issue: Upload succeeds but no data in DB
**Cause**: Wrong SK or endpoint

**Check**:
```bash
# Verify SK in config
grep "^sk=" /opt/giipAgentLinux/giipAgent.cnf

# Test API manually
curl -X POST "https://giipfaw.azurewebsites.net/api/giipApiSk2?code=YOUR_CODE" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "text=KVSPut lssn $(hostname) testfactor" \
  --data-urlencode "token=YOUR_SK" \
  --data-urlencode "jsondata={\"test\":\"value\"}"
```

---

## Related Files
- `giipscripts/kvsput.sh` - Main upload script
- `giipscripts/test-kvsput.sh` - Test script (this guide)
- `test-kvsput-remote.ps1` - Remote test from Windows
- `giipAgent.cnf` - Configuration file
- `giipdb/check_autodiscover_kvs.ps1` - DB verification script

---

**Last Updated**: October 30, 2025  
**Version**: 1.0.0
