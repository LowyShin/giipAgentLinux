# kvsput.sh API Specification

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

# Azure Function Code
apiaddrcode="YOUR_AZURE_FUNCTION_CODE"

# Secret Key (SK) - 인증 토큰
sk="YOUR_SECRET_KEY"

# LSSN - 서버 식별자 (숫자)
lssn="71174"
```

### Field Descriptions

| Field | Type | Purpose | Example | Notes |
|-------|------|---------|---------|-------|
| `apiaddrv2` | URL | giipApiSk2 엔드포인트 | `https://giipfaw.azurewebsites.net/api/giipApiSk2` | Azure Function URL |
| `apiaddrcode` | String | Azure Function 접근 코드 | `abc123xyz...` | Query string: `?code=` |
| `sk` | String | Secret Key (인증 토큰) | `ffd96879858f...` | SK 기반 인증 |
| `lssn` | Number | 서버 LSsn (식별자) | `71174` | **반드시 숫자** |

---

## API Call Structure

### giipApiSk2 Request Format

```
POST https://giipfaw.azurewebsites.net/api/giipApiSk2?code=YOUR_CODE
Content-Type: application/x-www-form-urlencoded

text=KVSPut lssn kfactor
token=YOUR_SECRET_KEY
jsondata={"your":"json","data":"here"}
```

### Parameter Breakdown

#### 1. `text` - Command String
**Format**: `KVSPut lssn kfactor`

- ✅ **파라미터 이름만** 포함
- ❌ **실제 값은 포함하지 않음**

```bash
# ✅ CORRECT
text="KVSPut lssn kfactor"

# ❌ WRONG
text="KVSPut lssn 71174 network_discovery"  # 값이 들어가면 안됨!
```

**Why?**
- giipApiSk2는 `text`를 파싱하여 SP (Stored Procedure) 호출 패턴을 결정
- 실제 값은 `jsondata`에서 추출

#### 2. `token` - Authentication
**Format**: Secret Key 문자열

```bash
token="ffd96879858fe73fc31d923a74ae23b5"
```

- SK 기반 인증
- `giipAgent.cnf`의 `sk` 필드 사용
- `text`에 포함하지 않음 (별도 파라미터)

#### 3. `jsondata` - Actual Data
**Format**: JSON 객체 (compacted)

```json
{
  "lssn": 71174,
  "kfactor": "network_discovery",
  "data": {
    "hostname": "cctrank03",
    "network": [...]
  }
}
```

**Structure**:
- `lssn`: 서버 식별자 (숫자)
- `kfactor`: Factor name (문자열)
- `data`: 실제 업로드할 데이터 (자유 형식)

---

## Backend Processing (giipApiSk2)

### 1. Request Parsing
```powershell
# giipfaw/giipApiSk2/run.ps1
$text = $formData["text"]           # "KVSPut lssn kfactor"
$token = $formData["token"]         # SK value
$jsondata = $formData["jsondata"]   # JSON string

# Parse text
$parts = $text -split " "
$command = $parts[0]                # "KVSPut"
$params = $parts[1..($parts.Length-1)]  # ["lssn", "kfactor"]
```

### 2. SP Call Pattern
```sql
-- Constructed SP name: pApiKvsPutbySk
EXEC pApiKvsPutbySk 
  @sk = 'ffd96879858fe73...',
  @lssn = 71174,
  @kfactor = 'network_discovery',
  @jsondata = '{"hostname":"cctrank03",...}'
```

### 3. SP Implementation (pApiKvsPutbySk)
```sql
CREATE PROCEDURE pApiKvsPutbySk
  @sk NVARCHAR(100),
  @lssn INT,
  @kfactor NVARCHAR(50),
  @jsondata NVARCHAR(MAX)
AS
BEGIN
  -- 1. Validate SK
  IF NOT EXISTS (SELECT 1 FROM tLSvr WHERE LSK = @sk)
  BEGIN
    SELECT 401 AS RstVal, 'Invalid SK' AS RstTxt
    RETURN
  END
  
  -- 2. Get LSsn from SK (if not provided)
  IF @lssn = 0
  BEGIN
    SELECT @lssn = LSsn FROM tLSvr WHERE LSK = @sk
  END
  
  -- 3. Insert to tKVS
  INSERT INTO tKVS (LSsn, KFactor, KData, kRegdt)
  VALUES (@lssn, @kfactor, @jsondata, GETDATE())
  
  -- 4. Return success
  SELECT 200 AS RstVal, 'Success' AS RstTxt, SCOPE_IDENTITY() AS KVSsn
END
```

### 4. Database Result (tKVS Table)
```sql
SELECT * FROM tKVS WHERE KVSsn = 12345
```

| Column | Type | Value | Description |
|--------|------|-------|-------------|
| KVSsn | INT | 12345 | Primary Key (auto-increment) |
| LSsn | INT | 71174 | 서버 식별자 (FK → tLSvr.LSsn) |
| KFactor | NVARCHAR(50) | `network_discovery` | Factor name |
| KData | NVARCHAR(MAX) | `{"hostname":"cctrank03",...}` | JSON 데이터 |
| kRegdt | DATETIME | 2025-10-30 10:40:00 | 등록 시각 |

---

## Current Implementation Issue

### Problem
현재 `kvsput.sh`의 코드:

```bash
# Line 115 (WRONG)
KVSP_TEXT="KVSPut lssn ${KVS_CONFIG[KKey]} $KFACTOR"
# Result: "KVSPut lssn 71174 network_discovery"
#                      ^^^^^ (실제 값이 들어감 - 잘못됨!)
```

### Expected Behavior (API Spec)
```bash
# CORRECT
text="KVSPut lssn kfactor"  # 파라미터 이름만
jsondata='{"lssn":71174,"kfactor":"network_discovery","data":{...}}'
```

### Why It Fails
1. **giipApiSk2 파싱 오류**:
   - `text`에서 `"71174"`를 파라미터 이름으로 인식
   - SP 호출 시 파라미터 매핑 실패

2. **jsondata 구조 불일치**:
   - API는 `jsondata`에서 `lssn`, `kfactor` 추출 예상
   - 현재는 `text`에 하드코딩되어 있음

3. **Web UI 표시 안됨**:
   - `tKVS.LSsn`이 제대로 설정되지 않음
   - 또는 `KFactor`가 매칭되지 않음

---

## Correct Implementation

### Fixed kvsput.sh Code
```bash
# Line 115 수정 필요
# ❌ WRONG (현재):
KVSP_TEXT="KVSPut lssn ${KVS_CONFIG[KKey]} $KFACTOR"

# ✅ CORRECT (수정 후):
KVSP_TEXT="KVSPut lssn kfactor"

# jsondata에 실제 값 포함 (수정 필요)
JSON_PAYLOAD=$(jq -n \
  --argjson lssn "${KVS_CONFIG[lssn]}" \
  --arg kfactor "$KFACTOR" \
  --argjson data "$JSON_FILE_COMPACT" \
  '{lssn: $lssn, kfactor: $kfactor, data: $data}')

POST_DATA="text=$(printf "%s" "$KVSP_TEXT" | jq -sRr @uri)"
POST_DATA+="&token=$(printf "%s" "$USER_TOKEN" | jq -sRr @uri)"
POST_DATA+="&jsondata=$(printf "%s" "$JSON_PAYLOAD" | jq -sRr @uri)"
```

### Expected Request
```
POST /api/giipApiSk2?code=abc123
Content-Type: application/x-www-form-urlencoded

text=KVSPut%20lssn%20kfactor
token=ffd96879858fe73fc31d923a74ae23b5
jsondata=%7B%22lssn%22%3A71174%2C%22kfactor%22%3A%22network_discovery%22%2C%22data%22%3A%7B...%7D%7D
```

Decoded `jsondata`:
```json
{
  "lssn": 71174,
  "kfactor": "network_discovery",
  "data": {
    "hostname": "cctrank03",
    "network": [...]
  }
}
```

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
