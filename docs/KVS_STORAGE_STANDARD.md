# KVS Storage Standard (KVS 저장 표준)

> **🎯 목표**: KVS 데이터 저장 방식의 중앙 집중식 표준화  
> **상태**: ✅ 공식 표준 문서  
> **최종 판정권**: lib/kvs.sh (소스코드가 진실)

---

## 📌 핵심 규칙

| 규칙 | 설명 |
|------|------|
| **1. lib/kvs.sh가 표준** | 모든 KVS 저장은 이 라이브러리를 기준으로 함 |
| **2. kvs_put() 함수 사용** | Raw JSON을 직접 저장하는 저수준 인터페이스 |
| **3. kValue는 RAW JSON만** | 문자열로 감싸지 말 것 (이스케이프 금지) |
| **4. 구 버전 호환성** | kvsput.sh는 레거시, 소스 유지 |

---

## 🔍 lib/kvs.sh vs kvsput.sh

### lib/kvs.sh (✅ 표준)
```bash
source lib/kvs.sh

kvs_put "lssn" "71240" "autodiscover_raw" '{"hostname":"server01"}'
```

**특징**:
- Raw JSON을 **그대로** 저장
- 구조 감싸지 않음 (kType, kKey, kFactor 래퍼 없음)
- 진단/디버깅 목적 최적
- 시스템 전역에서 사용 (giipAgent3.sh 등)

### kvsput.sh (🔴 레거시)
```bash
bash kvsput.sh /tmp/data.json autodiscover
```

**특징**:
- JSON을 자동으로 구조로 감쌈: `{kType, kKey, kFactor, kValue}`
- 자동 파일 처리
- **구 버전 호환성 유지를 위해 소스 코드는 유지**
- 새 개발에서는 **lib/kvs.sh 사용 권장**

---

## 📖 사용 방법

### 기본 구문
```bash
source /opt/giipAgentLinux/lib/kvs.sh

kvs_put <kType> <kKey> <kFactor> <kValue_json>
```

### 필수 환경변수
```bash
export sk="your-secret-key"           # SK 토큰
export apiaddrv2="https://..."        # KVS API 주소
export apiaddrcode="YOUR_CODE"        # Azure Function Code (선택)
```

### 실행 예시
```bash
#!/bin/bash
source lib/kvs.sh

# API 호출
RESPONSE=$(curl -s https://api.example.com/data)

# Raw JSON 그대로 저장
kvs_put "lssn" "71240" "api_response_raw" "$RESPONSE"
```

---

## ✅ 올바른 사용법

### ✅ DO: RAW JSON (따옴표 없음)
```bash
# 1. jq로 생성한 JSON
DATA=$(jq -n '{status:"ok",code:200}')
kvs_put "lssn" "71240" "test" "$DATA"

# 2. 싱글 쿼트로 감싼 JSON
kvs_put "lssn" "71240" "test" '{"status":"ok","code":200}'

# 3. 변수가 이미 JSON 형태
API_RESPONSE='{"result":"data"}'
kvs_put "lssn" "71240" "test" "$API_RESPONSE"
```

### ❌ DON'T: 이스케이프된 문자열
```bash
# ❌ 문자열로 감싸기 (따옴표 추가)
kvs_put "lssn" "71240" "test" '"{\"status\":\"ok\"}"'

# ❌ 이스케이프 과다
kvs_put "lssn" "71240" "test" "{\"status\":\"ok\"}"

# ❌ 이중 파싱 유발
kvs_put "lssn" "71240" "test" "$(echo '{...}' | jq -Rs .)"
```

---

## 📋 저장되는 데이터 구조

### tKVS 테이블 (최종 저장 형태)

```sql
SELECT * FROM tKVS
WHERE kType='lssn' AND kKey='71240' AND kFactor='autodiscover_raw'
```

| 컬럼 | 값 |
|------|-----|
| kType | `lssn` |
| kKey | `71240` |
| kFactor | `autodiscover_raw` |
| **kValue** | `{"hostname":"server01","os":"linux"}` (JSON 객체) |
| kRegdt | `2025-11-25 10:45:00` |

### 중요: kValue 형태

✅ **JSON 객체** (올바름):
```json
{"hostname":"server01","os":"linux"}
```

❌ **JSON 문자열** (오류):
```json
"{\"hostname\":\"server01\",\"os\":\"linux\"}"
```

---

## 🔗 관련 문서 (더 이상 별도 생성 금지)

이 문서가 **유일한 KVS 저장 표준**입니다. 다른 문서에서는 **반드시 이 문서를 링크**하세요:

```markdown
# KVS 저장 관련 내용
👉 **[KVS_STORAGE_STANDARD.md](KVS_STORAGE_STANDARD.md) 참조**
```

### 레거시 문서 (참고만 해주세요)
- `KVSPUT_API_SPECIFICATION.md` - kvsput.sh 스펙 (구 버전)
- `KVSPUT_USAGE_GUIDE.md` - kvsput.sh 사용법 (구 버전)
- `KVS_JSON_FORMATTING_ISSUE.md` - 에러 해결 (이 문서로 통합)

---

## 🐛 문제 해결

### 문제: JSON이 문자열로 저장됨
```
❌ 저장됨: "{\"key\":\"value\"}"
✅ 원함: {"key":"value"}
```

**원인**: `jq -Rs` 사용 또는 이스케이프 과다

**해결**:
1. `jq -c` 사용 (compact, 문자열로 감싸지 않음)
2. kValue를 **따옴표 없이** 전달
3. 환경변수 활용으로 이중 해석 피하기

```bash
# ❌ 잘못됨
DATA=$(echo $RESPONSE | jq -Rs .)
kvs_put "lssn" "71240" "test" "$DATA"

# ✅ 올바름
DATA=$(echo $RESPONSE | jq -c .)
kvs_put "lssn" "71240" "test" "$DATA"
```

---

## 📝 체크리스트

새 스크립트에서 KVS를 사용할 때:

- [ ] `lib/kvs.sh` import
- [ ] 환경변수 설정 (`sk`, `apiaddrv2`)
- [ ] kValue가 **RAW JSON** (따옴표 없음)
- [ ] `jq -c` 사용 (이스케이프 방지)
- [ ] 에러 처리 추가
- [ ] 이 문서 링크 추가

---

## 🎓 학습 자료

| 파일 | 목적 |
|------|------|
| `lib/kvs.sh` | 실제 구현 코드 (진실의 원천) |
| `giip-auto-discover.sh` | 실제 사용 예시 |
| `giipAgent3.sh` | 시스템 통합 예시 |

---

**최종 정의**: 2025-11-25  
**권위**: lib/kvs.sh 소스코드  
**상태**: ✅ 공식 표준

