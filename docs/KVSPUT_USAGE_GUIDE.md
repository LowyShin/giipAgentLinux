# kvsput.sh Usage Guide

## Overview
`kvsput.sh` is a utility script that uploads JSON data to the GIIP KVS (Key-Value Store) system via Azure Function endpoint.

## Location
```
giipAgentLinux/giipscripts/kvsput.sh
```

## Syntax
```bash
./kvsput.sh <json_file> <kfactor>
```

## Parameters

### 1. `<json_file>` (Required)
- **Type**: File path
- **Description**: Path to a JSON file containing the data to upload
- **Validation**: File must exist and be readable

### 2. `<kfactor>` (Required)
- **Type**: String (factor name)
- **Description**: Classification key that identifies the data type in tKVS table
- **Examples**:
  - `appinv` - Application inventory
  - `cqeresult` - CQE (Custom Query Execution) results
  - `sqlnetinv` - Network inventory
  - `osinfo` - OS distribution information
  - Custom factor names as needed

## Configuration Requirements

### giipAgent.cnf
The script reads configuration from `../../giipAgent.cnf` (relative to script location):

```ini
# Required fields:
Endpoint=https://your-function-app.azurewebsites.net/api/giipApiSk2
FunctionCode=your-azure-function-code-here
UserToken=your-user-token
KType=YourKType
KKey=YourKKey
Enabled=true
```

**Configuration Fields**:
| Field | Required | Description |
|-------|----------|-------------|
| `Endpoint` | ✅ Yes | Azure Function API endpoint URL |
| `UserToken` | ✅ Yes | Authentication token (SK or AK) |
| `KType` | ✅ Yes | Key type identifier |
| `KKey` | ✅ Yes | Key value (usually hostname or lssn) |
| `Enabled` | ✅ Yes | `true` to upload, `false` to only display JSON |
| `FunctionCode` | ⚠️ Optional | Azure Function access code (appended as `?code=`) |

## API Request Format

The script sends data as `application/x-www-form-urlencoded` with three parameters:

```
text=KVSPut lssn <KKey> <kfactor>
token=<UserToken>
jsondata=<compacted_json_content>
```

**Example HTTP Request**:
```
POST https://example.azurewebsites.net/api/giipApiSk2?code=abc123
Content-Type: application/x-www-form-urlencoded

text=KVSPut%20lssn%20cctrank03%20osinfo
&token=sk_abc123xyz
&jsondata=%7B%22os%22%3A%22ubuntu%22%2C%22version%22%3A%2220.04%22%7D
```

## Database Result

Data is stored in `tKVS` table:
```sql
SELECT * FROM tKVS WHERE KFactor = 'osinfo'
```

**tKVS Schema**:
| Column | Type | Description |
|--------|------|-------------|
| KVSsn | int | Primary key (auto-increment) |
| LSsn | int | Server identifier (FK to tLSvr) |
| KFactor | nvarchar | Factor name (e.g., 'osinfo', 'appinv') |
| KData | nvarchar(MAX) | JSON data content |
| kRegdt | datetime | Registration timestamp |

## Usage Examples

### Example 1: Upload OS Information
```bash
#!/bin/bash
# Create JSON file with OS data
cat > /tmp/osinfo.json <<EOF
{
  "distribution": "ubuntu",
  "version": "20.04",
  "kernel": "5.4.0-150-generic",
  "architecture": "x86_64"
}
EOF

# Upload to KVS with factor 'osinfo'
/opt/giipAgentLinux/giipscripts/kvsput.sh /tmp/osinfo.json osinfo
```

### Example 2: Upload Network Debug Data
```bash
#!/bin/bash
# Collect network data
ip -o link show | grep -v "lo:" > /tmp/network-debug.txt

# Create JSON
cat > /tmp/netdebug.json <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "hostname": "$(hostname)",
  "interfaces": $(ip -j link show | jq -c '[.[] | select(.ifname != "lo")]')
}
EOF

# Upload with custom factor
/opt/giipAgentLinux/giipscripts/kvsput.sh /tmp/netdebug.json netdebug
```

### Example 3: Conditional Upload (Only if Data Exists)
```bash
#!/bin/bash
JSON_FILE="/tmp/mydata.json"
KFACTOR="mydata"

# Generate data
echo '{"test": "value"}' > "$JSON_FILE"

# Check if file has content
if [ -s "$JSON_FILE" ]; then
    /opt/giipAgentLinux/giipscripts/kvsput.sh "$JSON_FILE" "$KFACTOR"
    echo "Upload completed"
else
    echo "No data to upload"
fi
```

### Example 4: Upload from CQE (existing usage)
```bash
# From giipCQE.sh line 363:
sh "$kvsput_script" "$TMP_RESULT" "cqeresult"
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success (or upload disabled) |
| 2 | Missing or invalid JSON file |
| 3 | Missing required configuration |
| 4 | Missing required tools (jq or curl) |
| N | curl error code (network/API failure) |

## Output Examples

### Success
```
[DIAG] Endpoint: https://example.azurewebsites.net/api/giipApiSk2?code=abc123
[DIAG] KVSP text: KVSPut lssn cctrank03 osinfo
[DIAG] jsondata (file) preview: {"distribution":"ubuntu","version":"20.04",...
[INFO] KVS upload result: {"status":"success","kvsn":12345}
```

### Disabled Mode (Enabled=false)
```
[INFO] KVS upload disabled. Showing JSON:
{"distribution":"ubuntu","version":"20.04"}
```

### Error: Missing File
```
[ERROR] JSON file required as first argument.
```

## Dependencies
- `jq` - JSON processing
- `curl` - HTTP requests
- `bash` 4.0+ - Associative arrays

## Best Practices

### 1. Use Descriptive Factor Names
```bash
# ✅ Good: Clear purpose
kvsput.sh data.json sqlnetinv
kvsput.sh data.json osinfo

# ❌ Bad: Unclear
kvsput.sh data.json test
kvsput.sh data.json data1
```

### 2. Validate JSON Before Upload
```bash
# Validate JSON syntax
if jq empty "$JSON_FILE" 2>/dev/null; then
    kvsput.sh "$JSON_FILE" "$KFACTOR"
else
    echo "Invalid JSON: $JSON_FILE"
fi
```

### 3. Handle Errors
```bash
if kvsput.sh "$JSON_FILE" "$KFACTOR"; then
    echo "✓ Upload successful"
    rm -f "$JSON_FILE"  # Clean up on success
else
    echo "✗ Upload failed, keeping file: $JSON_FILE"
fi
```

### 4. Use Temporary Files
```bash
TMPFILE=$(mktemp)
trap "rm -f $TMPFILE" EXIT  # Auto-cleanup

echo '{"data":"value"}' > "$TMPFILE"
kvsput.sh "$TMPFILE" myfactor
```

## Troubleshooting

### Issue: "jq is required but not found"
```bash
# Ubuntu/Debian
sudo apt-get install jq

# CentOS/RHEL
sudo yum install jq
```

### Issue: "Missing config: Endpoint"
- Check `giipAgent.cnf` exists at `../../giipAgent.cnf` relative to script
- Verify all required fields are present
- Ensure values are not empty

### Issue: "curl failed with exit code 6"
- Network connectivity issue
- Check firewall rules
- Verify endpoint URL is correct

### Issue: Data not appearing in tKVS
- Check Azure Function logs
- Verify `UserToken` has write permissions
- Ensure `KKey` matches server hostname or lssn
- Check SP `pApiKvsPutbySk` execution

## Related Files
- `giipAgent.cnf` - Configuration file
- `giipCQE.sh` - Uses kvsput for CQE results
- `collect_app_info.sh` - Uses kvsput for app inventory
- `auto-discover-linux.sh` - Could use kvsput for debug data

## Version History
- **v1.0.0** (2024): Initial version
- **v1.1.0** (Current): Updated documentation

---

**Last Updated**: October 30, 2025  
**Maintainer**: GIIP Development Team
