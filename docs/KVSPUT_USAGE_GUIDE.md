# kvsput.sh Usage Guide (레거시 - KVS_STORAGE_STANDARD.md로 이동)

> ⚠️ **이 문서는 구 버전(kvsput.sh) 설명입니다**  
> 👉 **[KVS_STORAGE_STANDARD.md](KVS_STORAGE_STANDARD.md) - 최신 표준 참조**

모든 KVS 저장 관련 내용이 중앙 표준 문서로 통합되었습니다.

---

## 빠른 링크

| 주제 | 참조 |
|------|------|
| **KVS 저장 표준** | **[KVS_STORAGE_STANDARD.md](KVS_STORAGE_STANDARD.md)** |
| lib/kvs.sh 사용법 | [KVS_STORAGE_STANDARD.md - 사용 방법](KVS_STORAGE_STANDARD.md#-사용-방법) |
| Raw JSON 저장 | [KVS_STORAGE_STANDARD.md - 올바른 사용법](KVS_STORAGE_STANDARD.md#-올바른-사용법) |
| 문제 해결 | [KVS_STORAGE_STANDARD.md - 문제 해결](KVS_STORAGE_STANDARD.md#-문제-해결) |

---

## 📝 kvsput.sh는?

- 구 버전 유틸리티 (호환성 유지)
- **새 개발에서는 `lib/kvs.sh` 사용 권장**
- 소스 코드는 유지 (기존 스크립트 호환성)

---

**최신 정보는 [KVS_STORAGE_STANDARD.md](KVS_STORAGE_STANDARD.md)를 참조하세요.**

---

## 📚 kvsput.sh 레거시 문서 (참고용)

> 이하 내용은 구 버전 문서입니다. 새 개발에서는 **[KVS_STORAGE_STANDARD.md](KVS_STORAGE_STANDARD.md)** 사용

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
# Option 1: Use standard giipAgent.cnf fields (Recommended)
apiaddrv2="https://giipfaw.azurewebsites.net/api/giipApiSk2"
apiaddrcode="YOUR_AZURE_FUNCTION_KEY_HERE"
sk="your-secret-key-here"
lssn="71174"

# Option 2: Use explicit KVS fields (Alternative)
Endpoint="https://giipfaw.azurewebsites.net/api/giipApiSk2"
FunctionCode="YOUR_AZURE_FUNCTION_KEY_HERE"
UserToken="your-secret-key-here"
KKey="cctrank03"
Enabled="true"
```

**Configuration Fields** (Priority Order):
| Field | Priority | Description |
|-------|----------|-------------|
| `Endpoint` | 1st | Azure Function API endpoint URL (giipApiSk2) |
| `apiaddrv2` | 2nd | Fallback endpoint if Endpoint not set |
| `FunctionCode` | 1st | Azure Function access code (appended as `?code=`) |
| `apiaddrcode` | 2nd | Fallback function code |
| `UserToken` | 1st | Authentication token (SK or AK) |
| `sk` | 2nd | Fallback token (session key) |
| `KKey` | 1st | Key value (usually hostname or lssn) |
| `lssn` | 2nd | Fallback to lssn if KKey not set |
| `Enabled` | Optional | `false` to only display JSON (default: enabled) |

**Note**: The script automatically uses **giipApiSk2** endpoint when `apiaddrv2` is configured.

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

### Example 5: Raw Data Upload (Debug Mode) ⭐ **NEW**

때때로 JSON 구조 에러로 인해 데이터가 저장되지 않을 때, **원본 데이터를 그대로 저장**해야 합니다:

```bash
# 원본 JSON을 그대로 저장 (구조 감싸지 않음)
/opt/giipAgentLinux/giipscripts/kvsput.sh /tmp/raw_discovery.json autodiscover_raw
```

**저장 방식 비교**:

| 모드 | 저장되는 데이터 | 용도 |
|------|----------------|------|
| **표준 (현재)** | `{kType:"lssn", kKey:"71240", kFactor:"autodiscover", kValue:{...}}` | 구조화된 데이터 저장 |
| **RAW (제안)** | `{... 원본 JSON ...}` | 진단/디버깅용 원본 데이터 보존 |

**예시**:
```bash
# Standard mode (현재)
$ ./kvsput.sh /tmp/data.json autodiscover
# tKVS에 저장되는 kValue:
# {"kType":"lssn","kKey":"71240","kFactor":"autodiscover","kValue":{"hostname":"server01",...}}

# Raw mode (원본만 저장 - 진단용)
$ ./kvsput.sh /tmp/data.json autodiscover_raw
# tKVS에 저장되는 kValue:
# {"hostname":"server01","os":"linux",...}
```

**사용 사례**:
```bash
#!/bin/bash

# Step 1: 원본 JSON 수집
DISCOVERY_FILE="/var/log/giip-discovery-latest.json"

# Step 2: 원본을 RAW 모드로 저장 (진단용)
/opt/giipAgentLinux/giipscripts/kvsput.sh "$DISCOVERY_FILE" autodiscover_raw

# Step 3: 정제된 JSON으로 표준 업로드
/opt/giipAgentLinux/giipscripts/kvsput.sh "$DISCOVERY_FILE" autodiscover

# Step 4: API 호출 및 응답도 저장
API_RESPONSE='{"status":"success","lssn":71240}'
echo "$API_RESPONSE" > /tmp/api_response.json
/opt/giipAgentLinux/giipscripts/kvsput.sh /tmp/api_response.json autodiscover_api_response
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

### Issue: "Missing config: Endpoint or apiaddrv2"
- Check `giipAgent.cnf` exists at `../../giipAgent.cnf` relative to script
- Ensure either `Endpoint` or `apiaddrv2` field is present
- Verify the value is a valid URL starting with `https://`

**Fix**:
```bash
# Edit giipAgent.cnf
cd /opt/giipAgentLinux
vi giipAgent.cnf

# Add this line:
apiaddrv2="https://giipfaw.azurewebsites.net/api/giipApiSk2"
```

### Issue: "curl failed with exit code 6"
- Network connectivity issue
- Check firewall rules
- Verify endpoint URL is correct

### Issue: Data not appearing in tKVS
- Check Azure Function logs
- Verify `UserToken` has write permissions
- Ensure `KKey` matches server hostname or lssn
- Check SP `pApiKvsPutbySk` execution

### Issue: JSON Structure Error - Data stored as escaped string ⭐ **NEW**

**증상**: KVS에 저장된 데이터가 문자열로 이스케이프됨 (예: `"{\"key\":\"value\"}"` 형태)

**원인**: 
- `kvsput.sh`에서 JSON을 `jq -Rs`로 처리하거나
- 입력 JSON 자체에 이스케이프 문제가 있을 때

**해결**:

**Step 1**: 원본 데이터를 진단용으로 RAW 모드로 저장
```bash
# 문제가 있는 JSON을 그대로 저장 (구조 감싸지 않음)
./kvsput.sh /tmp/problematic_data.json debug_raw
```

**Step 2**: KVS에서 원본 데이터 확인
```powershell
pwsh .\mgmt\check-latest.ps1 -kFactor debug_raw -Count 1
```

**Step 3**: 원본 JSON 검증
```bash
# JSON 유효성 확인
jq empty /tmp/problematic_data.json

# 이스케이프 문자 확인
cat /tmp/problematic_data.json | od -c | grep '\\'
```

**해결 방법**:
- JSON 생성 시 `jq -c`로 compact 형태로 생성
- `cat > file <<EOF` 방식 사용 (쉘 해석 피하기)
- 이스케이프 시퀀스 명시적 처리

**예시** - 잘못된 방식:
```bash
# ❌ 쉘이 변수 해석 → 이스케이프 문제 발생
cat > /tmp/data.json <<EOF
{
  "response": "$(curl ... | sed 's/"/\\"/g')"
}
EOF
```

**예시** - 올바른 방식:
```bash
# ✅ jq로 JSON 생성 → 자동 이스케이프 처리
RESPONSE=$(curl ...)
jq -n --argjson response "$RESPONSE" '{response: $response}' > /tmp/data.json
```

## Related Files
- `giipAgent.cnf` - Configuration file
- `giipCQE.sh` - Uses kvsput for CQE results
- `collect_app_info.sh` - Uses kvsput for app inventory
- `auto-discover-linux.sh` - Could use kvsput for debug data
- **`lib/kvs.sh`** ⭐ - Raw JSON KVS 저장 라이브러리 (시스템 전역에서 사용)

---

## 🔧 Advanced: Raw JSON Storage with lib/kvs.sh

**`lib/kvs.sh`**는 raw JSON을 직접 저장할 수 있는 **저수준 라이브러리**입니다. `kvsput.sh`와 다르게 JSON 구조를 감싸지 않고 **원본 그대로** 저장합니다.

### 용도
- ❌ kvsput.sh에서 계속 에러 발생
- ❌ 구조화된 JSON 저장이 실패할 때
- ✅ 원본 데이터를 진단/디버깅 목적으로 저장

### 함수 시그니처

```bash
source /opt/giipAgentLinux/lib/kvs.sh

# 형식
kvs_put <kType> <kKey> <kFactor> <kValue_json>

# 예시
kvs_put "lssn" "71240" "autodiscover_raw" '{"hostname":"server01","os":"linux"}'
```

### 필수 환경변수

```bash
export sk="your-secret-key"           # SK 토큰 (필수)
export apiaddrv2="https://..."        # KVS API 주소 (필수)
export apiaddrcode="YOUR_CODE"        # Azure Function Code (선택)
```

### 사용 예시

**Example 1: API 응답을 그대로 저장 (진단용)**

```bash
#!/bin/bash
source lib/kvs.sh

# Step 1: API 호출
API_RESPONSE=$(curl -s https://api.example.com/data)

# Step 2: 응답을 그대로 KVS에 저장 (구조 감싸지 않음!)
kvs_put "lssn" "71240" "api_response_raw" "$API_RESPONSE"
```

**Example 2: Auto-Discovery Raw Data 저장**

```bash
#!/bin/bash
source lib/kvs.sh

# Step 1: 발견 데이터 수집
DISCOVERY_DATA=$(./giipscripts/auto-discover-linux.sh)

# Step 2: 원본을 그대로 저장
kvs_put "lssn" "71240" "autodiscover_raw" "$DISCOVERY_DATA"
```

**Example 3: 에러 발생시 폴백 (kvsput.sh → kvs.sh)**

```bash
#!/bin/bash

# Try 1: Standard kvsput.sh
if ! ./giipscripts/kvsput.sh /tmp/data.json autodiscover; then
    echo "kvsput.sh failed, trying raw storage..."
    
    # Fallback: 원본을 그대로 저장
    source lib/kvs.sh
    DATA=$(cat /tmp/data.json)
    kvs_put "lssn" "71240" "autodiscover_raw" "$DATA"
fi
```

### 주의사항

⚠️ **반드시 준수하세요**:
1. **kValue는 RAW JSON만**: 문자열로 감싸지 말 것
2. **환경변수 필수**: `sk`, `apiaddrv2` 미리 설정
3. **따옴표 주의**: JSON에 따옴표가 있으면 백슬래시 처리

### ✅ 올바른 사용

```bash
# ✅ JSON 객체 (따옴표 없음)
kvs_put "lssn" "71240" "test" '{"status":"ok","code":200}'

# ✅ jq로 생성
DATA=$(jq -n '{status:"ok",code:200}')
kvs_put "lssn" "71240" "test" "$DATA"
```

### ❌ 잘못된 사용

```bash
# ❌ 문자열로 감싸기 (따옴표 추가)
kvs_put "lssn" "71240" "test" '"{\"status\":\"ok\"}"'

# ❌ 이스케이프 과다
kvs_put "lssn" "71240" "test" "{\"status\":\"ok\"}"
```

---
- **v1.0.0** (2024): Initial version
- **v1.1.0** (Current): Updated documentation

---

**Last Updated**: October 30, 2025  
**Maintainer**: GIIP Development Team
