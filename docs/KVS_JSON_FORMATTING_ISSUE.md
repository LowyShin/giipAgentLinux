# KVS JSON 포맷팅 문제 해결 (레거시 - KVS_STORAGE_STANDARD.md로 이동)

> ⚠️ **이 문서는 레거시입니다**  
> 👉 **[KVS_STORAGE_STANDARD.md](KVS_STORAGE_STANDARD.md) 참조**

모든 KVS 저장 관련 내용이 중앙 표준 문서로 통합되었습니다.

---

## 빠른 링크

| 주제 | 참조 |
|------|------|
| KVS 저장 표준 | [KVS_STORAGE_STANDARD.md - 핵심 규칙](KVS_STORAGE_STANDARD.md#-핵심-규칙) |
| lib/kvs.sh vs kvsput.sh | [KVS_STORAGE_STANDARD.md - 비교](KVS_STORAGE_STANDARD.md#-libkvvsh-vs-kvsputsh) |
| JSON 포맷팅 | [KVS_STORAGE_STANDARD.md - 올바른 사용법](KVS_STORAGE_STANDARD.md#-올바른-사용법) |
| 문제 해결 | [KVS_STORAGE_STANDARD.md - 문제 해결](KVS_STORAGE_STANDARD.md#-문제-해결) |

---

**최신 정보는 [KVS_STORAGE_STANDARD.md](KVS_STORAGE_STANDARD.md)를 참조하세요.**

---

## 🔴 문제: JSON이 문자열로 저장됨

### 현상
```bash
# 이 코드로 저장하면:
cat > "$JSON_FILE" <<EOF
{
  "status": "success",
  "api_response": $(echo "$RESPONSE" | jq -Rs .)
}
EOF

# KVS에 저장된 값:
{
  "status": "success",
  "api_response": "{\"result\": \"data\"}"  # ❌ 문자열로 저장됨!
}
```

**원인**: `jq -Rs`는 **입력을 문자열로 변환** → 따옴표로 감싼 문자열로 저장

---

## ✅ 해결책: jq -c 로 먼저 변환

### 올바른 패턴

**Step 1**: jq -c로 JSON을 compact 형태로 변환
```bash
API_RESP_ESCAPED=$(echo "$RESPONSE" | jq -c .)
```

**Step 2**: 파일에 **따옴표 없이** 직접 embedded
```bash
cat > "$JSON_FILE" <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "status": "success",
  "api_response": $API_RESP_ESCAPED
}
EOF
```

**결과**: 
```json
{
  "timestamp": "2025-11-25T10:45:00+09:00",
  "status": "success",
  "api_response": {"result": "data"}  # ✅ JSON 객체로 저장됨!
}
```

---

## 📋 jq 옵션 비교

| 옵션 | 용도 | 결과 |
|------|------|------|
| `jq -c` | 포맷 제거 (compact) | `{"a":1}` |
| `jq -Rs` | Raw String (따옴표로 감싸기) | `"{\"a\":1}"` |
| `jq .` | 포맷된 JSON | 여러 줄 |

---

## 🔧 실제 적용: giip-auto-discover.sh

### API 성공 응답 저장 (Line 227-237)

```bash
if [ -f "$KVSPUT_SCRIPT" ]; then
    API_RESPONSE_JSON="${TEMP_JSON%.json}-api-response.json"
    # ✅ jq -c로 JSON 객체로 변환
    API_RESP_ESCAPED=$(echo "$RESPONSE" | jq -c .)
    cat > "$API_RESPONSE_JSON" <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "hostname": "$(hostname)",
  "status": "success",
  "api_response": $API_RESP_ESCAPED,
  "action": "$ACTION"
}
EOF
    bash "$KVSPUT_SCRIPT" "$API_RESPONSE_JSON" autodiscover_api_response >> "$LOG_FILE" 2>&1 || true
    rm -f "$API_RESPONSE_JSON"
fi
```

### API 인증 실패 (Line 241-253)

```bash
if [ -f "$KVSPUT_SCRIPT" ]; then
    ERROR_JSON="${TEMP_JSON%.json}-api-auth-error.json"
    # ✅ jq -c로 JSON 객체로 변환
    API_RESP_ESCAPED=$(echo "$RESPONSE" | jq -c .)
    cat > "$ERROR_JSON" <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "hostname": "$(hostname)",
  "status": "error",
  "error_type": "authentication_failed",
  "rstval": "$RSTVAL",
  "api_response": $API_RESP_ESCAPED
}
EOF
    bash "$KVSPUT_SCRIPT" "$ERROR_JSON" autodiscover_api_error >> "$LOG_FILE" 2>&1 || true
    rm -f "$ERROR_JSON"
fi
```

### API 호출 실패 (Line 305-320)

```bash
if [ -f "$KVSPUT_SCRIPT" ]; then
    ERROR_JSON="${TEMP_JSON%.json}-api-call-error.json"
    # ✅ 호출 실패는 응답이 텍스트일 수 있으므로 -Rs 사용
    API_RESP_ESCAPED=$(echo "$RESPONSE" | jq -Rs .)
    cat > "$ERROR_JSON" <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "hostname": "$(hostname)",
  "status": "error",
  "error_type": "api_call_failed",
  "http_code": $HTTP_CODE,
  "api_url": "$API_URL",
  "response": $API_RESP_ESCAPED
}
EOF
    bash "$KVSPUT_SCRIPT" "$ERROR_JSON" autodiscover_api_call_error >> "$LOG_FILE" 2>&1 || true
    rm -f "$ERROR_JSON"
fi
```

---

## 📚 참조 문서

**API 규칙 및 구현**:
- [`giipAgentLinux/docs/KVSPUT_API_SPECIFICATION.md`](KVSPUT_API_SPECIFICATION.md)
  - **Line 250-286**: Current Implementation - 올바른 JSON 구조
  - **Line 407-440**: Issue 3 - Web UI doesn't show data
  - **Line 482-530**: Summary - kvsput.sh 절대 규칙

**PowerShell 스크립트**:
- [`giipdb/mgmt/SCRIPT_SPECIFICATION.md`](../../giipdb/mgmt/SCRIPT_SPECIFICATION.md)
  - KVS JSON 저장 에러 문제 섹션 추가됨

**Auto-Discovery 구조**:
- [`AUTO_DISCOVERY_ARCHITECTURE.md`](AUTO_DISCOVERY_ARCHITECTURE.md)
  - 문서 간 링크에 KVSPUT_API_SPECIFICATION.md 추가됨

---

## ⚠️ 주의사항

1. **API 호출 실패시만 `-Rs` 사용**: HTTP 에러 등으로 응답이 텍스트일 때만
2. **JSON이 유효한지 사전 확인**: `jq -c` 실패시 대비
3. **큰 데이터는 파일로 전달**: 환경변수 크기 제한 주의

---

## 🧪 테스트

```bash
# 1. 문법 검증
bash -n giip-auto-discover.sh

# 2. 서버에서 실행 후 KVS 확인
pwsh .\mgmt\check-latest.ps1 -kFactor autodiscover_api_response -Count 1

# 3. JSON 구조 확인
# autodiscover_api_response의 kValue가 JSON 객체인지 문자열인지 확인
```

---

**최종 업데이트**: 2025-11-25 10:50  
**상태**: ✅ 완료 및 적용됨
