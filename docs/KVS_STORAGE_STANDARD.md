# KVS Storage Standard (KVS 저장 표준)

> **🎯 목표**: KVS 데이터 저장 방식의 중앙 집중식 표준화  
> **상태**: ✅ 공식 표준 문서  
> **최종 판정권**: lib/kvs.sh (소스코드가 진실)

---

## 📌 핵심 규칙

| 규칙 | 설명 |
|------|------|
| **1. lib/kvs.sh가 표준** | 모든 KVS 저장은 이 라이브러리를 기준으로 함 |
| **2. kvs_put() 함수 사용** | **RAW JSON**을 직접 저장하는 저수준 인터페이스 |
| **3. kValue는 RAW JSON만** | **JSON 객체** 그대로 (문자열 감싸기 ❌ 금지) |
| **4. 구 버전 호환성** | kvsput.sh는 레거시, 소스 유지 |

---

## 🔍 lib/kvs.sh vs kvsput.sh

### lib/kvs.sh (✅ 표준)
```bash
source lib/kvs.sh

# 4번째 파라미터는 RAW JSON (JSON 객체 그대로, 문자열이 아님)
kvs_put "lssn" "71240" "autodiscover_raw" '{"hostname":"server01"}'
#                                          ↑ RAW JSON
```

**특징**:
- **RAW JSON**을 **그대로** 저장 (JSON 객체 형태)
- 문자열 래핑 없음 ✅
- 추가 이스케이프 없음 ✅
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

# 4번째 파라미터: kValue = RAW JSON (JSON 객체 그대로)
kvs_put <kType> <kKey> <kFactor> <RAW_JSON_OBJECT>
#                                  ↑ JSON 객체 (따옴표로 감싼 문자열 아님!)
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

# API 호출 (결과는 RAW JSON)
RESPONSE=$(curl -s https://api.example.com/data)
# RESPONSE = {"result":"ok"}

# ✅ 올바른: RAW JSON 그대로 저장
kvs_put "lssn" "71240" "api_response_raw" "$RESPONSE"
#       ^^^^   ^^^^^   ^^^^^^^^^^^^^^^    ^^^^^^^^
#       kType  kKey    kFactor            RAW JSON (변수 그대로)
```

---

## ✅ 올바른 사용법

### ✅ DO: RAW JSON (JSON 객체 그대로)
```bash
# 1. jq로 생성한 RAW JSON
DATA=$(jq -n '{status:"ok",code:200}')
# DATA = {"status":"ok","code":200}  (JSON 객체)
kvs_put "lssn" "71240" "test" "$DATA"
#                                ^^^^ RAW JSON

# 2. 싱글 쿼트로 감싼 RAW JSON
kvs_put "lssn" "71240" "test" '{"status":"ok","code":200}'
#                               ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ RAW JSON

# 3. 변수에 저장된 RAW JSON
API_RESPONSE='{"result":"data"}'
# API_RESPONSE = {"result":"data"}  (JSON 객체)
kvs_put "lssn" "71240" "test" "$API_RESPONSE"
#                                ^^^^^^^^^^^^ RAW JSON
```

### ❌ DON'T: 문자열로 감싼 JSON (절대 금지!)
```bash
# ❌ JSON 문자열로 감싸기 (따옴표로 JSON 객체를 감쌈)
kvs_put "lssn" "71240" "test" '"{\"status\":\"ok\"}"'
#                               ^^^^^^^^^^^^^^^^^^^^^ 문자열 (❌ 금지!)
# DB에 저장: "{\"status\":\"ok\"}" (문자열)
# 결과: 이중 파싱 필요 (❌ 오류)

# ❌ 이스케이프 과다
kvs_put "lssn" "71240" "test" "{\"status\":\"ok\"}"
#                               ^^^^^^^^^^^^^^^^^^^ 문자열 (❌ 금지!)

# ❌ jq -Rs로 문자열화 (절대 금지!)
kvs_put "lssn" "71240" "test" "$(echo '{}' | jq -Rs .)"
#                               ^^^^^^^^^^^^^^^^^^^^ 문자열로 변환됨 (❌ 금지!)
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
| **kValue** | `{"hostname":"server01","os":"linux"}` **← RAW JSON** |
| kRegdt | `2025-11-25 10:45:00` |

### 중요: kValue 저장 형태 (tKVS 테이블에 실제 저장되는 값)

✅ **RAW JSON 객체** (올바름) - 이것이 저장되어야 함:
```json
{"hostname":"server01","os":"linux"}
```
**특징**: JSON 객체 그대로, 따옴표로 감싼 문자열 아님  
**파싱**: 1번 파싱으로 충분 (JSON.parse 1회)

❌ **JSON 문자열** (오류) - 절대 이렇게 저장되면 안 됨:
```json
"{\"hostname\":\"server01\",\"os\":\"linux\"}"
```
**특징**: JSON 객체를 문자열로 감쌈 (따옴표 + 이스케이프)  
**문제**: 이중 파싱 필요 (JSON.parse 2회) ← **오류 유발!**

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

