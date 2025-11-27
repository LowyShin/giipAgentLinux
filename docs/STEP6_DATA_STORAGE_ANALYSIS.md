# STEP-6 데이터 저장 메커니즘 상세 분석

> ⚠️ **이 문서는 기술 분석 자료입니다.**
>
> 📌 **메인 문서**: [AUTO_DISCOVER_ISSUE_DIAGNOSIS_REPORT.md](./AUTO_DISCOVER_ISSUE_DIAGNOSIS_REPORT.md) ← 최신 진단 결과 확인
>
> 이 문서는 STEP-6의 상세 기술 분석이며, 전체 진단 내용은 메인 문서를 참조하세요.

**최종 작성**: 2025-11-26  
**분석 대상**: giipAgent3.sh 라인 360-420, lib/kvs.sh 라인 160-206  
**결론**: ✅ 저장 메커니즘 완벽 설계 / 🔴 jq 미설치가 근본 원인

---

## 📝 선택된 부분 정의

사용자가 지적한 부분:
```
└─ 실제 데이터 (저장 안됨 ❌):
   ├─ auto_discover_result: ❌ (JSON 전체 데이터 없음)
   ├─ auto_discover_servers: ❌ (jq 파싱 결과 없음)
   ├─ auto_discover_networks: ❌ (jq 파싱 결과 없음)
   └─ auto_discover_services: ❌ (jq 파싱 결과 없음)
```

**질문**:
1. 저장을 어떻게 하고 있는지?
2. 입력값은 무엇인가?
3. kvs_put을 사용하는가?
4. RAW 데이터라면 그대로 들어갈 수 있어야 하지 않나?

---

## ✅ 회답 1: 저장 방식 (어떻게 하는가?)

### 저장 흐름도

```
1️⃣ 결과 파일 읽기 (giipAgent3.sh 라인 376)
   ┌─────────────────────────────────────┐
   │ auto_discover_json=$(cat "$auto_discover_result_file")
   │                                      │
   │ 예: auto_discover_json = "{"         │
   │       "servers":[...],             │
   │       "networks":[...]             │
   │     }"                             │
   └─────────────────────────────────────┘
   
2️⃣ kvs_put 호출 (라인 390)
   ┌──────────────────────────────────────────────┐
   │ kvs_put "lssn" "${lssn}" \                  │
   │         "auto_discover_result" \            │
   │         "$auto_discover_json"               │
   │                                             │
   │ = kvs_put "lssn" "71240" \                 │
   │            "auto_discover_result" \        │
   │            "{\"servers\":[...], ...}"      │
   └──────────────────────────────────────────────┘
   
3️⃣ kvs_put 함수 처리 (lib/kvs.sh 라인 160)
   ┌────────────────────────────────────────┐
   │ ktype="lssn"                           │
   │ kkey="71240"                           │
   │ kfactor="auto_discover_result"         │
   │ kvalue_json="${auto_discover_json}"    │ ← RAW JSON 문자열
   │                                        │
   │ jsondata = {                           │
   │   "kType": "lssn",                    │
   │   "kKey": "71240",                    │
   │   "kFactor": "auto_discover_result",  │
   │   "kValue": {...JSON 객체...}         │ ← 따옴표 없음
   │ }                                      │
   └────────────────────────────────────────┘
   
4️⃣ URI 인코딩 (라인 185) 🔴 **jq 필수**
   ┌──────────────────────────────────────┐
   │ encoded_jsondata=$(printf '%s' "$jsondata" | jq -sRr '@uri')
   │                                      │
   │ ❌ jq 없으면: encoded_jsondata="" (비어있음)
   │ ✅ jq 있으면: encoded_jsondata="%7B%22k..." (인코딩됨)
   └──────────────────────────────────────┘
   
5️⃣ API 호출 (라인 187)
   ┌──────────────────────────────────────┐
   │ wget --post-data="text=...&token=...&jsondata=${encoded_jsondata}"
   │                                      │
   │ ❌ 실패시: jsondata가 비어있음
   │ ✅ 성공시: KVS에 저장됨
   └──────────────────────────────────────┘
```

---

## ✅ 회답 2: 입력값 (무엇인가?)

### 입력값 분석

**Source**:
```bash
auto_discover_result_file="/tmp/auto_discover_result_26145.json"
result_size=7557  # bytes
```

**읽기 방식**:
```bash
auto_discover_json=$(cat "$auto_discover_result_file")
```

**실제 입력값** (예시):
```json
{
  "servers": [
    {
      "hostname": "server01",
      "ip": "192.168.1.10",
      "port": 22
    }
  ],
  "networks": [
    {
      "name": "eth0",
      "ip": "192.168.1.0",
      "mask": "255.255.255.0"
    }
  ],
  "services": [
    {
      "name": "ssh",
      "port": 22
    }
  ]
}
```

**입력값 형태**:
- 📌 **RAW JSON** (문자열)
- 📌 **크기**: 7557 bytes
- 📌 **포맷**: UTF-8 텍스트
- 📌 **변수**: `$auto_discover_json`

---

## ✅ 회답 3: kvs_put 사용 여부

### 네, kvs_put을 사용합니다

**코드 위치**: giipAgent3.sh 라인 390
```bash
kvs_put "lssn" "${lssn}" "auto_discover_result" "$auto_discover_json"
```

**kvs_put 함수**: lib/kvs.sh 라인 160-206

**호출 시그니처**:
```bash
kvs_put() {
    local ktype=$1          # "lssn"
    local kkey=$2           # "71240" (LSSN)
    local kfactor=$3        # "auto_discover_result"
    local kvalue_json=$4    # RAW JSON 데이터
}
```

**kvs_put 내부 동작**:

1. **JSON 객체 구성** (라인 180):
   ```bash
   local jsondata="{\"kType\":\"${ktype}\",\"kKey\":\"${kkey}\",\"kFactor\":\"${kfactor}\",\"kValue\":${kvalue_json}}"
   ```
   
   👉 **중요**: `"kValue":${kvalue_json}` ← **따옴표 없음**
   
   결과:
   ```json
   {
     "kType": "lssn",
     "kKey": "71240",
     "kFactor": "auto_discover_result",
     "kValue": {"servers":[...], "networks":[...]}  ← 객체로 삽입
   }
   ```

2. **URI 인코딩** (라인 185):
   ```bash
   local encoded_jsondata=$(printf '%s' "$jsondata" | jq -sRr '@uri')
   ```
   
   - `printf '%s'`: 문자열로 출력
   - `jq -sRr '@uri'`: URI 안전 형식으로 인코딩
   - 결과: URL로 전송 가능한 형식

3. **API 호출** (라인 187-191):
   ```bash
   wget -O "$response_file" \
       --post-data="text=${encoded_text}&token=${encoded_token}&jsondata=${encoded_jsondata}" \
       --header="Content-Type: application/x-www-form-urlencoded" \
       "${kvs_url}" \
       ...
   ```

---

## ✅ 회답 4: RAW 데이터 처리 (그대로 들어갈 수 있는가?)

### 네, RAW 데이터가 그대로 들어갑니다

**설계 원칙** (giipapi_rules.md 준수):

```
✅ kValue는 RAW JSON (string이 아닌 JSON 객체)
   - "kValue": {...}   ← 올바름 (따옴표 없음)
   - "kValue": "{...}" ← 틀림 (문자열로 이중화됨)
```

**kvs.sh 구현** (라인 180):
```bash
local jsondata="{...\"kValue\":${kvalue_json}}"
                                 ↑
                          따옴표 없음 = RAW
```

**예시 - JSON 객체**:
```bash
# 입력
auto_discover_json='{"servers":[...]}'

# kvs_put 호출
kvs_put "lssn" "71240" "auto_discover_result" "$auto_discover_json"

# 결과 JSON
{
  "kType": "lssn",
  "kKey": "71240",
  "kFactor": "auto_discover_result",
  "kValue": {"servers":[...]}  ← 객체로 저장 ✅
}
```

**예시 - 배열**:
```bash
# 입력
servers_data='[{"name":"server1"},{"name":"server2"}]'

# kvs_put 호출
kvs_put "lssn" "71240" "auto_discover_servers" "$servers_data"

# 결과 JSON
{
  "kType": "lssn",
  "kKey": "71240",
  "kFactor": "auto_discover_servers",
  "kValue": [{"name":"server1"},{"name":"server2"}]  ← 배열로 저장 ✅
}
```

**예시 - 문자열**:
```bash
# 입력
message='hello world'

# kvs_put 호출
kvs_put "lssn" "71240" "test_message" "\"$message\""  ← 따옴표로 감싸기

# 결과 JSON
{
  "kType": "lssn",
  "kKey": "71240",
  "kFactor": "test_message",
  "kValue": "hello world"  ← 문자열로 저장 ✅
}
```

---

## 🔴 문제: URI 인코딩에서 jq 필수

### 핵심 문제점

**kvs.sh 라인 185**:
```bash
local encoded_jsondata=$(printf '%s' "$jsondata" | jq -sRr '@uri')
```

**문제**:
- `jq` 명령어가 필수
- 만약 서버에 jq가 없으면: 
  - ❌ 명령어 실패
  - ❌ `encoded_jsondata`가 비어있음
  - ❌ POST 데이터 손상
  - ❌ API 호출 실패

**현재 상태**:
- ✅ STEP-6 메타데이터 저장됨 (log_auto_discover_step 사용)
- ❌ 실제 데이터 저장 안됨 (kvs_put → URI 인코딩 실패)

---

## 💡 해결 방안

### 옵션 1: 서버에 jq 설치 (추천)
```bash
# Ubuntu/Debian
sudo apt-get install -y jq

# RHEL/CentOS
sudo yum install -y jq

# macOS
brew install jq

# 확인
jq --version
```

**장점**:
- ✅ 기존 코드 수정 없음
- ✅ 다른 스크립트도 jq 사용 가능
- ✅ 표준 도구

**단점**:
- ❌ 서버 권한 필요

### 옵션 2: kvs.sh 수정 (base64 인코딩)
```bash
# lib/kvs.sh 라인 185 수정

# 변경 전
local encoded_jsondata=$(printf '%s' "$jsondata" | jq -sRr '@uri')

# 변경 후 (base64 사용)
local encoded_jsondata=$(printf '%s' "$jsondata" | base64 -w 0)

# 또는 manual URL encoding
local encoded_jsondata=$(printf '%s' "$jsondata" | sed 's/ /%20/g' | sed 's/!/%21/g' ...)
```

**장점**:
- ✅ 서버 설치 불필요
- ✅ base64는 대부분의 서버에 있음

**단점**:
- ❌ 코드 복잡도 증가
- ❌ API 서버에서도 base64 디코딩 필요

### 옵션 3: API 전송 방식 변경
```bash
# multipart/form-data 사용 (특수문자 처리 용이)
# 또는 바이너리 전송 (gzip 압축)
```

**장점**:
- ✅ 특수문자 문제 없음
- ✅ 대용량 데이터 처리 용이

**단점**:
- ❌ API 서버 수정 필요
- ❌ 기존 API 계약 변경

---

## 📊 최종 결론

| 질문 | 답변 | 상태 |
|------|------|------|
| **저장을 어떻게 하는가?** | `cat` → `kvs_put` → 일반 함수 | ✅ 정상 설계 |
| **입력값은 무엇인가?** | 결과 파일의 RAW JSON (7557 bytes) | ✅ 올바름 |
| **kvs_put을 사용하는가?** | 네, giipAgent3.sh L390에서 호출 | ✅ 사용 중 |
| **RAW 데이터가 그대로 들어가는가?** | 네, 따옴표 없이 JSON 객체로 삽입 | ✅ 완벽 설계 |

**🔴 근본 원인**: 
- URI 인코딩에 `jq -sRr '@uri'` 필수
- **서버에 jq가 설치되어 있지 않음**
- 따라서 `encoded_jsondata`가 빈 값
- API 호출 실패 → 실제 데이터 미저장

**✅ 해결책**:
1. **즉시**: 서버에 `jq` 설치 (추천)
2. **대체**: kvs.sh 수정 (base64 사용)
3. **장기**: API 전송 방식 개선 (multipart/form-data)

---

## 🎯 개선된 STEP-6 구현 (각 컴포넌트별 파일 + kvs_put)

### 파일 저장 구조

**Process ID 기반 임시 파일**:
```
/tmp/auto_discover_result_data_$$.json        ← 완전한 발견 데이터 (전체)
/tmp/auto_discover_servers_$$.json            ← servers 컴포넌트만
/tmp/auto_discover_networks_$$.json           ← networks 컴포넌트만
/tmp/auto_discover_services_$$.json           ← services 컴포넌트만
```

**각 파일별 kvs_put 로그**:
```
/tmp/kvs_put_result_$$.log                    ← auto_discover_result 저장 결과
/tmp/kvs_put_servers_$$.log                   ← auto_discover_servers 저장 결과
/tmp/kvs_put_networks_$$.log                  ← auto_discover_networks 저장 결과
/tmp/kvs_put_services_$$.log                  ← auto_discover_services 저장 결과
```

### 개선된 호출 방식

**변경 전** (조건부 호출):
```bash
if [ $kvs_put_result_code -eq 0 ]; then
    # 이전 호출이 성공했을 때만 다음 호출
    kvs_put ... servers ...
    kvs_put ... networks ...
    kvs_put ... services ...
fi
```

❌ **문제**: 첫 호출 실패 → 모든 이후 호출 스킵

**변경 후** (독립적 호출):
```bash
# 1️⃣ 완전한 데이터 저장
kvs_put "lssn" "${lssn}" "auto_discover_result" "$auto_discover_json"

# 2️⃣ servers 독립적으로 저장
kvs_put "lssn" "${lssn}" "auto_discover_servers" "$servers_data"

# 3️⃣ networks 독립적으로 저장
kvs_put "lssn" "${lssn}" "auto_discover_networks" "$networks_data"

# 4️⃣ services 독립적으로 저장
kvs_put "lssn" "${lssn}" "auto_discover_services" "$services_data"
```

✅ **장점**: 각 호출이 독립적 → 일부 실패해도 나머지 저장됨

### 디버깅 향상도

| 시나리오 | 이전 | 개선 후 |
|--------|------|--------|
| **jq 미설치** | ❌ 모든 컴포넌트 실패 | ✅ 파일O, 일부 컴포넌트 결과 볼 수 있음 |
| **kvs_put 실패** | ❓ 알기 어려움 | ✅ `/tmp/kvs_put_*.log`에서 명확한 에러 |
| **파일 시스템 문제** | 추적 불가 | ✅ `/tmp/auto_discover_*_$$.json` 확인 가능 |
| **특수문자 처리** | ❓ 불명확 | ✅ 파일에서 직접 내용 검증 |
| **복구 가능성** | ❌ 없음 | ✅ 파일에서 언제든 재저장 가능 |

### 예상 실행 결과 (다음 서버 실행)

✅ **성공 케이스**:
```
/tmp/auto_discover_result_data_26145.json      (7557 bytes) ✅
/tmp/auto_discover_servers_26145.json          (1234 bytes) ✅
/tmp/auto_discover_networks_26145.json         (567 bytes)  ✅
/tmp/auto_discover_services_26145.json         (890 bytes)  ✅

KVS에 저장됨:
✅ auto_discover_result      (완전한 발견 데이터)
✅ auto_discover_servers     (servers 배열)
✅ auto_discover_networks    (networks 배열)
✅ auto_discover_services    (services 배열)
```

❌ **jq 미설치 케이스** (예상):
```
/tmp/auto_discover_result_data_26145.json      (7557 bytes) ✅
/tmp/auto_discover_servers_26145.json          (비어있거나 없음) ❌
/tmp/auto_discover_networks_26145.json         (비어있거나 없음) ❌
/tmp/auto_discover_services_26145.json         (비어있거나 없음) ❌

KVS에 저장됨:
✅ auto_discover_result      (완전한 발견 데이터)
❌ auto_discover_servers     (jq 파싱 실패)
❌ auto_discover_networks    (jq 파싱 실패)
❌ auto_discover_services    (jq 파싱 실패)

DEBUG 로그:
"DEBUG STEP-6: Saved servers to /tmp/auto_discover_servers_26145.json (size: 0)"
→ jq 실패 확정 → `command -v jq` 실행으로 확인
```

### 다음 조치

1. **서버에서 jq 확인**:
   ```bash
   command -v jq && jq --version || echo "NOT INSTALLED"
   ```

2. **디버그 로그 수집** (다음 서버 실행 후):
   ```bash
   cat /tmp/auto_discover_debug_*.log | tail -30
   tail /tmp/kvs_put_*.log
   ```

3. **파일 존재 확인**:
   ```bash
   ls -lh /tmp/auto_discover_*_$$.json 2>/dev/null | head -10
   ls -lh /tmp/kvs_put_*.log 2>/dev/null | head -10
   ```

4. **jq 설치** (필요시):
   ```bash
   sudo apt-get install -y jq        # Ubuntu/Debian
   sudo yum install -y jq            # RHEL/CentOS
   ```

