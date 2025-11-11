# kvsput.sh API Specification

> **📚 관련 문서:**
> - [Azure Function Endpoints & Code](../../giipdb/docs/AZURE_FUNCTION_ENDPOINTS.md) - **Function Code 확인 (필수!)**
> - [Azure Function 인증 가이드](../../giipdb/docs/AZURE_FUNCTION_AUTH_GUIDE.md) - 401 에러 해결
> - [giipapi 규칙](../../giipfaw/docs/giipapi_rules.md) - API 호출 표준
> - [giipApiSk2 패턴](../../giipfaw/docs/GIIPAPISK2_API_PATTERN.md) - 호출 패턴 상세

⚠️ **개발 룰 필독!**: `giipfaw/docs/giipapi_rules.md`

**[필수] 모든 변수값(파라미터)은 반드시 jsondata 필드에 JSON 문자열로 만들어 전달해야 하며, text 필드에는 프로시저명과 파라미터 이름만 포함해야 합니다.**

## Overview
`kvsput.sh`는 JSON 데이터를 GIIP KVS (Key-Value Store) 시스템에 업로드하는 유틸리티입니다.

---

## Command Syntax

```bash
bash kvsput.sh <json_file> <kfactor>
```

### Parameters

| Parameter | Required | Type | Description |
|-----------|----------|------|-------------|
| `<json_file>` | ✅ Yes | File Path | 업로드할 JSON 파일 경로 |
| `<kfactor>` | ✅ Yes | String | 데이터 분류 키 (Factor name) |

### Example
```bash
bash kvsput.sh /tmp/mydata.json network_discovery
```

---

## Configuration (giipAgent.cnf)

### Location Priority
1. `../giipAgent.cnf` (스크립트 상위 디렉토리) - **PRIMARY**
2. `../../giipAgent.cnf` (두 단계 상위)
3. `/opt/giipAgentLinux/giipAgent.cnf` (절대 경로)

### Required Fields

```ini
# API Endpoint (giipApiSk2)
apiaddrv2="https://giipfaw.azurewebsites.net/api/giipApiSk2"

# Azure Function Code (⚠️ 필수! AZURE_FUNCTION_ENDPOINTS.md에서 확인)
# 참조: giipdb/docs/AZURE_FUNCTION_ENDPOINTS.md
apiaddrcode="YOUR_AZURE_FUNCTION_CODE_HERE"

# Secret Key (SK) - 인증 토큰
sk="YOUR_SECRET_KEY"

# LSSN - 서버 식별자 (숫자)
lssn="71174"
```

### Field Descriptions

| Field | Type | Purpose | Example | Notes |
|-------|------|---------|---------|-------|
| `apiaddrv2` | URL | giipApiSk2 엔드포인트 | `https://giipfaw.azurewebsites.net/api/giipApiSk2` | Azure Function URL |
| `apiaddrcode` | String | Azure Function 접근 코드 | `YOUR_FUNCTION_CODE` | Query string: `?code=` - [확인](../../giipdb/docs/AZURE_FUNCTION_ENDPOINTS.md) |
| `sk` | String | Secret Key (인증 토큰) | `ffd96879858f...` | SK 기반 인증 |
| `lssn` | Number | 서버 LSsn (식별자) | `71174` | **반드시 숫자** |

---

## API Call Structure (giipapi_rules.md 기준)

⚠️ **절대 규칙**: `text`에는 파라미터 **이름만**, `jsondata`에 **실제 값**!

### SP Definition (pApiKVSPutbySk)

```sql
-- SP: pApiKVSPutbySk
-- Reference: giipdb/SP/pApiKVSPutbySk.sql

CREATE procedure [dbo].[pApiKVSPutbySk]
    @sk varchar(200)          -- Authentication (from token parameter)
    , @kType varchar(32)      -- From jsondata.kType
    , @kKey varchar(100)      -- From jsondata.kKey
    , @kFactor varchar(32)    -- From jsondata.kFactor
    , @kValue nvarchar(max)   -- From jsondata.kValue (또는 jsondata.value)
```

### giipApiSk2 Request Format

```
POST https://giipfaw.azurewebsites.net/api/giipApiSk2?code=YOUR_CODE
Content-Type: application/x-www-form-urlencoded

text=KVSPut kType kKey kFactor kValue
token=YOUR_SECRET_KEY
jsondata={"kType":"lssn","kKey":"71174","kFactor":"netdiag","kValue":{...}}
```

### Parameter Breakdown

#### 1. `text` - Command String with Parameter NAMES ONLY
**Format**: `KVSPut kType kKey kFactor kValue`

⚠️ **절대 금지**: 실제 값을 `text`에 넣지 마세요!

```bash
# ✅ CORRECT (giipapi_rules.md 기준)
text="KVSPut kType kKey kFactor kValue"  # 파라미터 이름만!

# ❌ WRONG (절대 금지!)
text="KVSPut lssn 71174 netdiag {...}"  # 실제 값 (X)
```

**Why?**
- `giipfaw/docs/giipapi_rules.md` 필수 규칙:
  > **[필수] 모든 변수값(파라미터)은 반드시 jsondata 필드에 JSON 문자열로 만들어 전달해야 하며, 
  > text 필드에는 프로시저명과 파라미터 이름만 포함해야 합니다.**

- giipApiSk2는 `text`를 파싱하여 SP 파라미터 구조를 파악
- 실제 값은 `jsondata`에서 파라미터 이름으로 매핑하여 추출

#### 2. `token` - Authentication
**Format**: Secret Key 문자열

```bash
token="ffd96879858fe73fc31d923a74ae23b5"
```

- SK 기반 인증
- `giipAgent.cnf`의 `sk` 필드 사용
- SP의 `@sk` 파라미터로 전달

#### 3. `jsondata` - Actual Parameter Values
**Format**: JSON 객체 (compacted)

```json
{
  "kType": "lssn",
  "kKey": "71174",
  "kFactor": "netdiag",
  "kValue": {
    "hostname": "cctrank03",
    "network": [...]
  }
}
```

**Parameter Mapping**:

| `text` 위치 | Parameter Name | `jsondata` 필드 | Example Value | SP Parameter |
|------------|----------------|----------------|---------------|--------------|
| Position 2 | `kType` | `jsondata.kType` | `"lssn"` | `@kType` |
| Position 3 | `kKey` | `jsondata.kKey` | `"71174"` | `@kKey` |
| Position 4 | `kFactor` | `jsondata.kFactor` | `"netdiag"` | `@kFactor` |
| Position 5 | `kValue` | `jsondata.kValue` | `{...}` | `@kValue` |

**Important**: 
- `kValue`는 JSON 객체 또는 문자열 (자유 형식)
- `kType`은 현재 `"lssn"`만 지원 (SP Line 22)
- `kKey`는 문자열 (숫자처럼 보여도 VARCHAR(100))

---

## Backend Processing

### SP Call Pattern (giipApiSk2)

```csharp
// 1. Parse text parameter to get parameter names
string[] parts = text.Split(' ');
// parts[0] = "KVSPut"    → Command (SP name = pApiKVSPutbySk)
// parts[1] = "kType"     → Parameter name
// parts[2] = "kKey"      → Parameter name
// parts[3] = "kFactor"   → Parameter name
// parts[4] = "kValue"    → Parameter name

// 2. Parse jsondata to get actual values
var json = JsonConvert.DeserializeObject<JObject>(jsondata);
string kType = json["kType"].ToString();      // "lssn"
string kKey = json["kKey"].ToString();        // "71174"
string kFactor = json["kFactor"].ToString();  // "netdiag"
string kValue = json["kValue"].ToString();    // "{...}" or object

// 3. Execute SP with mapped values
EXEC pApiKVSPutbySk 
  @sk = @token,        -- from token parameter
  @kType = @kType,     -- from jsondata.kType
  @kKey = @kKey,       -- from jsondata.kKey
  @kFactor = @kFactor, -- from jsondata.kFactor
  @kValue = @kValue    -- from jsondata.kValue
```

### Database Insert (pApiKVSPutbySk)

```sql
-- SP: pApiKVSPutbySk (Line 17-33)
if @kType = 'lssn'  -- kType must be "lssn"
begin
    -- Validate LSsn exists in tLSvr
    if exists(select 1 from tLSvr where LSsn = @kKey and CGSn = @cgsn)
    begin
        insert into tKVS(kType, kKey, kFactor, kValue, kRegdt)
        values (@kType, @kKey, @kFactor, @kValue, GETDATE())
        
        select @RstVal = 200, @RstMsg = 'Success'
    end
    else
        select @RstVal = 411, @RstMsg = 'Invalid LSsn'
end
else
    select @RstVal = 404, @RstMsg = 'Invalid kType (must be lssn)'
```

**Result Table** (`tKVS`):
- `kType` = `"lssn"` (VARCHAR(32))
- `kKey` = `"71174"` (VARCHAR(100) - 문자열!)
- `kFactor` = `"netdiag"` (VARCHAR(32))
- `kValue` = `'{"hostname":"cctrank03",...}'` (NVARCHAR(MAX))
- `kRegdt` = `GETDATE()`

**Important**: `kKey`는 문자열입니다. 숫자처럼 보이지만 VARCHAR(100)로 저장됩니다.

---

## Current Implementation (kvsput.sh)

### Correct Code (Line 112-123)

```bash
# Line 112-114: giipapi_rules.md 준수!
# Per giipapi rules: 'text' must contain only the procedure name and parameter NAMES (no values)
# Actual values must be passed inside jsondata.

# Line 115: text에 파라미터 이름만
KVSP_TEXT="KVSPut kType kKey kFactor kValue"  # ✅ CORRECT!

# Line 117: JSON 파일 compact
JSON_FILE_COMPACT=$(jq -c . "$JSON_FILE")

# Line 120-123: POST data 구성
POST_DATA="text=$(printf "%s" "$KVSP_TEXT" | jq -sRr @uri)"
POST_DATA+="&token=$(printf "%s" "$USER_TOKEN" | jq -sRr @uri)"
POST_DATA+="&jsondata=$(printf "%s" "$JSON_FILE_COMPACT" | jq -sRr @uri)"
```

**⚠️ 문제점**: `jsondata` 구조가 불완전!

```bash
# ❌ CURRENT (Line 123)
# jsondata는 JSON 파일 내용 그대로
jsondata='{"hostname":"cctrank03","network":[...]}'

# ✅ SHOULD BE
# jsondata에 kType, kKey, kFactor 포함!
jsondata='{
  "kType": "lssn",
  "kKey": "71174",
  "kFactor": "netdiag",
  "kValue": {"hostname":"cctrank03","network":[...]}
}'
```

### Required Fix

**Line 115-119 변경 필요**:
```bash
# Compact the JSON file (this will be kValue)
JSON_FILE_COMPACT=$(jq -c . "$JSON_FILE")

# Build jsondata with kType, kKey, kFactor, kValue
JSON_PAYLOAD=$(jq -n \
  --arg kType "lssn" \
  --arg kKey "${KVS_CONFIG[KKey]}" \
  --arg kFactor "$KFACTOR" \
  --argjson kValue "$JSON_FILE_COMPACT" \
  '{kType: $kType, kKey: $kKey, kFactor: $kFactor, kValue: $kValue}')

# KVSP text (procedure name + param NAMES as required by giipapi)
KVSP_TEXT="KVSPut kType kKey kFactor kValue"  # ✅ 파라미터 이름만!

# Build form parameters
POST_DATA="text=$(printf "%s" "$KVSP_TEXT" | jq -sRr @uri)"
POST_DATA+="&token=$(printf "%s" "$USER_TOKEN" | jq -sRr @uri)"
POST_DATA+="&jsondata=$(printf "%s" "$JSON_PAYLOAD" | jq -sRr @uri)"  # ← JSON_PAYLOAD 사용!
```

### Example Complete Request

```bash
# Command line
kvsput.sh /tmp/discovery.json netdiag

# Generated curl command
curl -X POST "https://giipfaw.azurewebsites.net/api/giipApiSk2?code=abc123" \
  --data-urlencode 'text=KVSPut kType kKey kFactor kValue' \
  --data-urlencode 'token=ffd96879858fe73fc31d923a74ae23b5' \
  --data-urlencode 'jsondata={"kType":"lssn","kKey":"71174","kFactor":"netdiag","kValue":{"hostname":"cctrank03","network":[...]}}'
```

**Result**:
```json
{"RstVal": 200, "RstMsg": "Success"}
```

**Database State**:
```sql
SELECT * FROM tKVS WHERE kKey = '71174' AND kFactor = 'netdiag' ORDER BY kRegdt DESC
-- kType: lssn
-- kKey: 71174
-- kFactor: netdiag
-- kValue: {"hostname":"cctrank03",...}
-- kRegdt: 2025-01-15 14:30:00
```
---

## Configuration Parameter Details

### Parameter Priority Chains

| Purpose | Priority 1 (Recommended) | Priority 2 (Legacy) | Priority 3 (Fallback) | Code Line |
|---------|-------------------------|---------------------|----------------------|-----------|
| **Endpoint** | `Endpoint` | `apiaddrv2` | ERROR if missing | 73-79 |
| **Function Code** | `FunctionCode` | `apiaddrcode` | (Optional) | 82-86 |
| **Token** | `UserToken` | `sk` | ERROR if missing | 89-93 |
| **KKey** | `KKey` | `lssn` | `hostname()` | 96-102 |

**Example Config** (`giipAgent.cnf`):
```ini
# Recommended (Priority 1) - 권장 방식
Endpoint=https://giipfaw.azurewebsites.net
FunctionCode=abc123def456
UserToken=ffd96879858fe73fc31d923a74ae23b5
KKey=71174

# Legacy (Priority 2) - 하위 호환성
apiaddrv2=https://giipfaw.azurewebsites.net
apiaddrcode=abc123def456
sk=ffd96879858fe73fc31d923a74ae23b5
lssn=71174
```

### Field Descriptions

| Field Name | Type | Required | Description | Example |
|------------|------|----------|-------------|---------|
| `Endpoint` / `apiaddrv2` | URL | ✅ Yes | giipApiSk2 endpoint URL | `https://giipfaw.azurewebsites.net` |
| `FunctionCode` / `apiaddrcode` | String | ⚠️ Optional | Azure Function 인증 코드 (URL query) | `abc123def456` |
| `UserToken` / `sk` | String | ✅ Yes | Secret Key (SK) for authentication | `ffd96879858fe73fc31d923a74ae23b5` |
| `KKey` / `lssn` | String | ⚠️ Auto | 서버 식별자 (LSsn), 없으면 hostname 사용 | `71174` 또는 `cctrank03` |
| `Enabled` | Boolean | ⚠️ Optional | `false`면 실제 업로드 안하고 미리보기만 | `true` (default) |

**Priority Resolution Example**:
```bash
# If config has both Endpoint and apiaddrv2:
Endpoint=https://new.giip.net      # ← Used (Priority 1)
apiaddrv2=https://old.giip.net     # ← Ignored (Priority 2)

# If config has only apiaddrv2:
apiaddrv2=https://old.giip.net     # ← Used (Priority 2)

# If config has neither:
# ERROR: "ERROR: Endpoint not set in config file"
```

---

## Troubleshooting

### Issue 1: "ERROR: Endpoint not set in config file"
**Cause**: Config file missing both `Endpoint` and `apiaddrv2`

**Solution**:
```bash
echo "Endpoint=https://giipfaw.azurewebsites.net" >> /home/giip/giipAgent.cnf
```

### Issue 2: "ERROR: UserToken not set in config file"
**Cause**: Config file missing both `UserToken` and `sk`

**Solution**:
```bash
echo "UserToken=YOUR_SECRET_KEY" >> /home/giip/giipAgent.cnf
```

### Issue 3: Web UI doesn't show data (RstVal=200 but empty)
**Cause**: `kvsput.sh` `jsondata` 구조 불완전

**Current Code** (Line 123):
```bash
POST_DATA+="&jsondata=$(printf "%s" "$JSON_FILE_COMPACT" | jq -sRr @uri)"
# jsondata에 파일 내용만! (kType, kKey, kFactor 없음)
```

**Fix** (Line 117-119):
```bash
# Build proper jsondata structure
JSON_PAYLOAD=$(jq -n \
  --arg kType "lssn" \
  --arg kKey "${KVS_CONFIG[KKey]}" \
  --arg kFactor "$KFACTOR" \
  --argjson kValue "$JSON_FILE_COMPACT" \
  '{kType: $kType, kKey: $kKey, kFactor: $kFactor, kValue: $kValue}')

POST_DATA+="&jsondata=$(printf "%s" "$JSON_PAYLOAD" | jq -sRr @uri)"
```

**Verification**:
```sql
-- Check if kValue has data
SELECT kKey, kFactor, LEN(kValue) AS kValueLength, kRegdt 
FROM tKVS 
WHERE kKey = '71174' 
ORDER BY kRegdt DESC

-- If kValueLength = 0 or NULL → Fix needed!
```

---

## Version History

### v1.2.0 (2025-10-30) - giipapi_rules.md 기준 재작성 ⭐
- ✅ **CRITICAL FIX**: `giipfaw/docs/giipapi_rules.md` 기준으로 전면 수정
- ✅ **CLARIFIED**: `text`에는 파라미터 **이름만** (실제 값 금지!)
- ✅ **FIXED**: `jsondata`에 kType, kKey, kFactor, kValue 구조 포함
- ✅ **REMOVED**: 잘못된 "text에 실제 값" 설명 전부 삭제
- ✅ **ADDED**: giipapi_rules.md 필수 규칙 명시
- ⚠️ **BREAKING**: v1.1.0 기준 코드는 규칙 위반!

### v1.1.0 (2025-01-15) - ❌ 잘못된 이해
- ❌ **WRONG**: `text`에 실제 값 포함한다고 기재 (규칙 위반!)
- ❌ **WRONG**: SP만 보고 판단 (giipapi_rules.md 미확인)
- ⚠️ **DEPRECATED**: 이 버전은 개발 룰 위반

### v1.0.0 (2025-01-14) - ❌ 초기 작성 (부분적으로 잘못됨)
- ⚠️ jsondata 구조 불완전
- ⚠️ 일부 내용 누락

---

## Related Documents

⭐ **필수 참조**:
- **giipfaw/docs/giipapi_rules.md**: API 호출 절대 규칙
- **giipfaw/docs/GIIPAPISK2_API_PATTERN.md**: giipApiSk2 패턴
- **KVSPUT_USAGE_GUIDE.md**: Usage examples
- **KVSPUT_TEST_GUIDE.md**: Testing procedures
- **SQLNETINV_DATA_FLOW.md**: Complete data flow
- **SP Source**: `giipdb/SP/pApiKVSPutbySk.sql`

---

## Summary: kvsput.sh 절대 규칙

### ⚠️ 개발 룰 (giipapi_rules.md)

**[필수] 모든 변수값(파라미터)은 반드시 jsondata 필드에 JSON 문자열로 만들어 전달해야 하며, text 필드에는 프로시저명과 파라미터 이름만 포함해야 합니다.**

### ✅ CORRECT Implementation

```bash
# 1. JSON 파일 읽기
JSON_FILE_COMPACT=$(jq -c . "$JSON_FILE")

# 2. jsondata 구조 생성 (kType, kKey, kFactor, kValue)
JSON_PAYLOAD=$(jq -n \
  --arg kType "lssn" \
  --arg kKey "${KVS_CONFIG[KKey]}" \
  --arg kFactor "$KFACTOR" \
  --argjson kValue "$JSON_FILE_COMPACT" \
  '{kType: $kType, kKey: $kKey, kFactor: $kFactor, kValue: $kValue}')

# 3. text에 파라미터 이름만!
KVSP_TEXT="KVSPut kType kKey kFactor kValue"  # ✅ 이름만!

# 4. POST data 구성
POST_DATA="text=$(printf "%s" "$KVSP_TEXT" | jq -sRr @uri)"
POST_DATA+="&token=$(printf "%s" "$USER_TOKEN" | jq -sRr @uri)"
POST_DATA+="&jsondata=$(printf "%s" "$JSON_PAYLOAD" | jq -sRr @uri)"
```

### ❌ WRONG (절대 금지!)

```bash
# ❌ text에 실제 값 넣기 (규칙 위반!)
KVSP_TEXT="KVSPut lssn 71174 netdiag {...}"

# ❌ jsondata에 구조 없이 파일만 (불완전!)
POST_DATA+="&jsondata=$(printf "%s" "$JSON_FILE_COMPACT" | jq -sRr @uri)"
```

### Why This Design?

**giipApiSk2의 처리 방식**:
1. `text`를 파싱하여 SP 이름과 파라미터 구조 파악
2. `jsondata`에서 파라미터 이름으로 실제 값 추출
3. SP 호출 시 자동 매핑

**장점**:
- 민감 정보(토큰, 비밀번호) `text`에 노출 방지
- 대용량 JSON 데이터 안전하게 전달
- URL encoding 문제 최소화
- 일관된 API 패턴 유지

---

**Last Updated**: October 30, 2025 (v1.2.0)  
**Status**: ✅ giipapi_rules.md 기준 재작성 완료  
**Author**: GIIP Development Team

---

## Validation Checklist

### Before Upload
- ✅ `giipAgent.cnf` exists in correct location
- ✅ `apiaddrv2` points to giipApiSk2
- ✅ `sk` is valid Secret Key
- ✅ `lssn` is **numeric** (not hostname!)
- ✅ JSON file is valid

### After Upload
- ✅ Check response: `RstVal = 200`
- ✅ Verify in DB: `SELECT * FROM tKVS WHERE KFactor = 'your_factor'`
- ✅ Check LSsn matches: `SELECT * FROM tKVS WHERE LSsn = 71174`

---

## Troubleshooting

### Issue: Web UI doesn't show data

**Possible Causes**:
1. ❌ `lssn` is hostname instead of number
   ```ini
   # WRONG
   lssn="cctrank03"
   
   # CORRECT
   lssn="71174"
   ```

2. ❌ `text` contains values instead of parameter names
   ```bash
   # WRONG
   text="KVSPut lssn 71174 kfactor"
   
   # CORRECT
   text="KVSPut lssn kfactor"
   ```

3. ❌ `jsondata` structure doesn't match API expectation
   ```json
   // WRONG
   {"hostname": "cctrank03"}
   
   // CORRECT
   {"lssn": 71174, "kfactor": "test", "data": {"hostname": "cctrank03"}}
   ```

### Issue: "Invalid SK" error

**Check**:
```bash
# Verify SK in config
grep "^sk=" /home/giip/giipAgent.cnf

# Test SK validity
curl -X POST "https://giipfaw.azurewebsites.net/api/giipApiSk2?code=YOUR_CODE" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "text=LServerGet lssn" \
  --data-urlencode "token=YOUR_SK" \
  --data-urlencode "jsondata={}"
```

### Issue: Data uploaded but LSsn is NULL

**Cause**: `lssn` not properly passed in `jsondata`

**Fix**: Ensure `jsondata` includes:
```json
{
  "lssn": 71174,
  "kfactor": "your_factor",
  "data": {...}
}
```

---

## Related Documentation
- [GIIPAPISK2_API_PATTERN.md](../../giipfaw/docs/GIIPAPISK2_API_PATTERN.md) - API 호출 패턴
- [KVSPUT_USAGE_GUIDE.md](KVSPUT_USAGE_GUIDE.md) - 사용법 가이드
- [KVSPUT_TEST_GUIDE.md](KVSPUT_TEST_GUIDE.md) - 테스트 가이드

---

## Version History
- **v1.0.0** (Current): Initial specification - **NEEDS FIX**
  - ❌ `text` parameter includes values
  - ❌ `jsondata` structure incorrect
  - ❌ Web UI not showing data

- **v1.1.0** (Planned): API-compliant implementation
  - ✅ `text` contains parameter names only
  - ✅ `jsondata` includes `lssn`, `kfactor`, `data`
  - ✅ Web UI displays correctly

---

**Last Updated**: October 30, 2025  
**Status**: 🔴 REQUIRES FIX  
**Author**: GIIP Development Team
