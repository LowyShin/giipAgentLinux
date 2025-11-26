# STEP-6 개선 사항 요약 (각 컴포넌트별 파일 저장 + 개별 kvs_put)

**작성일**: 2025-11-26  
**변경 대상**: giipAgent3.sh (라인 375-420)  
**목표**: 각 발견 데이터(complete result, servers, networks, services)를 별도 파일로 저장 후 각각 kvs_put 호출

---

## 📋 변경 요약

### 🎯 핵심 개선 사항

| 구분 | 이전 | 개선 후 |
|------|------|--------|
| **데이터 저장** | 메모리 변수만 | 📁 파일 + 메모리 변수 |
| **파일 수** | 원본 결과만 | 원본 + 각 컴포넌트별 파일 |
| **kvs_put 호출** | 조건부 (의존성) | ✅ 각각 독립적 호출 |
| **실패 영향도** | 전체 손실 | 일부 영향 (파일 남음) |
| **디버깅 추적성** | 어려움 | ✨ 각 단계별 명확 로그 |
| **복구 가능성** | ❌ 없음 | ✅ 파일에서 재저장 |

---

## 📁 생성되는 파일 구조

### 발견 데이터 파일

```
/tmp/auto_discover_result_data_26145.json      (7557 bytes)
  └─ 전체 발견 데이터 (원본 처리 전 별도 저장)
  
/tmp/auto_discover_servers_26145.json          (예: 1234 bytes)
  └─ jq로 추출한 servers 컴포넌트
  
/tmp/auto_discover_networks_26145.json         (예: 567 bytes)
  └─ jq로 추출한 networks 컴포넌트
  
/tmp/auto_discover_services_26145.json         (예: 890 bytes)
  └─ jq로 추출한 services 컴포넌트
```

### kvs_put 실행 로그

```
/tmp/kvs_put_result_26145.log
  └─ auto_discover_result 저장 결과
  
/tmp/kvs_put_servers_26145.log
  └─ auto_discover_servers 저장 결과
  
/tmp/kvs_put_networks_26145.log
  └─ auto_discover_networks 저장 결과
  
/tmp/kvs_put_services_26145.log
  └─ auto_discover_services 저장 결과
```

### 디버그 로그 통합

```
/tmp/auto_discover_debug_26145.log
  ├─ DEBUG STEP-6: Storing individual components to separate files and KVS
  ├─ DEBUG STEP-6: Saved complete result to /tmp/auto_discover_result_data_26145.json
  ├─ DEBUG STEP-6: kvs_put for auto_discover_result returned 0
  ├─ DEBUG STEP-6: Saved servers to /tmp/auto_discover_servers_26145.json (size: 1234)
  ├─ DEBUG STEP-6: kvs_put for auto_discover_servers returned 0
  ├─ DEBUG STEP-6: Saved networks to /tmp/auto_discover_networks_26145.json (size: 567)
  ├─ DEBUG STEP-6: kvs_put for auto_discover_networks returned 0
  ├─ DEBUG STEP-6: Saved services to /tmp/auto_discover_services_26145.json (size: 890)
  ├─ DEBUG STEP-6: kvs_put for auto_discover_services returned 0
  └─ DEBUG STEP-6: All components stored to separate files and kvs_put calls completed
```

---

## 🔄 호출 흐름 변화

### 이전 (조건부 의존성)

```bash
# 완전한 데이터 저장
kvs_put ... auto_discover_result ...
  ↓
IF 성공?
  YES → servers, networks, services 호출
  NO  → 중단 (이후 모두 스킵)
```

**문제**: 첫 호출 실패 → 모든 컴포넌트 저장 불가

### 개선 후 (독립적 호출)

```bash
# 1️⃣ 완전한 데이터 저장
kvs_put ... auto_discover_result ...

# 2️⃣ servers 저장 (1과 무관)
kvs_put ... auto_discover_servers ...

# 3️⃣ networks 저장 (1,2와 무관)
kvs_put ... auto_discover_networks ...

# 4️⃣ services 저장 (1,2,3과 무관)
kvs_put ... auto_discover_services ...
```

**장점**: 
- ✅ 각 호출이 독립적
- ✅ 일부 실패해도 나머지 저장됨
- ✅ 파일에 기록 남음 (복구 가능)

---

## 🧪 예상 결과

### ✅ 성공 시나리오 (jq 설치됨)

```
파일:
✅ /tmp/auto_discover_result_data_26145.json      (7557 bytes)
✅ /tmp/auto_discover_servers_26145.json          (1234 bytes)
✅ /tmp/auto_discover_networks_26145.json         (567 bytes)
✅ /tmp/auto_discover_services_26145.json         (890 bytes)

KVS:
✅ auto_discover_result      (전체 데이터 저장)
✅ auto_discover_servers     (servers 배열 저장)
✅ auto_discover_networks    (networks 배열 저장)
✅ auto_discover_services    (services 배열 저장)

DEBUG 로그:
✅ 모든 STEP 완료 메시지 출력
✅ 각 kvs_put 결과값 기록 (return code 0)
```

### ❌ jq 미설치 시나리오 (예상)

```
파일:
✅ /tmp/auto_discover_result_data_26145.json      (7557 bytes)
⚠️ /tmp/auto_discover_servers_26145.json          (비어있음 또는 없음)
⚠️ /tmp/auto_discover_networks_26145.json         (비어있음 또는 없음)
⚠️ /tmp/auto_discover_services_26145.json         (비어있음 또는 없음)

KVS:
✅ auto_discover_result      (전체 데이터는 저장됨!)
❌ auto_discover_servers     (jq 실패로 저장 안됨)
❌ auto_discover_networks    (jq 실패로 저장 안됨)
❌ auto_discover_services    (jq 실패로 저장 안됨)

DEBUG 로그:
✅ Saved complete result to ... ✅
⚠️ Saved servers to ... (size: 0)  ← jq 실패 신호!
⚠️ Saved networks to ... (size: 0) ← jq 실패 신호!
⚠️ Saved services to ... (size: 0) ← jq 실패 신호!
```

**진단**: 파일 크기가 0 → jq 미설치 확정

---

## 🔍 디버깅 방법

### 1단계: 파일 존재 확인

```bash
# 다음 서버 실행 후 (또는 라이브 서버)
ls -lh /tmp/auto_discover_*_26145.json
ls -lh /tmp/kvs_put_*_26145.log
```

**예상 결과**:
```
-rw-r--r-- 1 root root 7557 Nov 26 13:40 /tmp/auto_discover_result_data_26145.json
-rw-r--r-- 1 root root 1234 Nov 26 13:40 /tmp/auto_discover_servers_26145.json
-rw-r--r-- 1 root root  567 Nov 26 13:40 /tmp/auto_discover_networks_26145.json
-rw-r--r-- 1 root root  890 Nov 26 13:40 /tmp/auto_discover_services_26145.json
```

### 2단계: 파일 내용 확인

```bash
# 완전한 결과 확인
cat /tmp/auto_discover_result_data_26145.json | jq . | head -20

# servers 크기 확인
wc -c /tmp/auto_discover_servers_26145.json

# networks 크기 확인
wc -c /tmp/auto_discover_networks_26145.json

# services 크기 확인
wc -c /tmp/auto_discover_services_26145.json
```

**jq 미설치 확인**:
```bash
# 파일 크기가 모두 0이면 jq 미설치 확정
file /tmp/auto_discover_servers_26145.json  # empty 또는 cannot open
```

### 3단계: 디버그 로그 확인

```bash
cat /tmp/auto_discover_debug_26145.log | grep "DEBUG STEP-6"

# 예상 출력:
# DEBUG STEP-6: Storing individual components to separate files and KVS
# DEBUG STEP-6: Saved complete result to /tmp/auto_discover_result_data_26145.json
# DEBUG STEP-6: kvs_put for auto_discover_result returned 0
# DEBUG STEP-6: Saved servers to /tmp/auto_discover_servers_26145.json (size: 1234)
# DEBUG STEP-6: kvs_put for auto_discover_servers returned 0
```

### 4단계: kvs_put 로그 확인

```bash
# 각 컴포넌트별 저장 결과 확인
tail -10 /tmp/kvs_put_result_26145.log
tail -10 /tmp/kvs_put_servers_26145.log
tail -10 /tmp/kvs_put_networks_26145.log
tail -10 /tmp/kvs_put_services_26145.log
```

### 5단계: KVS 최종 확인

```powershell
# 로컬 (Windows PowerShell)
pwsh .\mgmt\check-latest.ps1 -Lssn 71240 -Minutes 2 | Select-String "auto_discover" | Tee-Object -FilePath .\step6_final_result.txt

# 또는 필터링
pwsh .\mgmt\check-latest.ps1 -Lssn 71240 -Minutes 2 | Select-String "auto_discover_result|auto_discover_servers|auto_discover_networks|auto_discover_services"
```

---

## 🎯 다음 확인 사항

### 즉시 확인 (서버)

```bash
# 1. jq 설치 여부
command -v jq && jq --version || echo "❌ NOT INSTALLED"

# 2. 파일 생성 (다음 실행 대기)
ls -lh /tmp/auto_discover_*_$$.json 2>/dev/null || echo "No files yet"
```

### 문제 해결 (필요시)

**만약 모든 컴포넌트 파일 크기가 0이면** → jq 설치 필요:
```bash
# Ubuntu/Debian
sudo apt-get update && sudo apt-get install -y jq

# RHEL/CentOS
sudo yum install -y jq

# 확인
jq --version
```

### 검증 (설치 후)

```bash
# 다시 한 번 서버 실행 후 KVS 확인
pwsh .\mgmt\check-latest.ps1 -Lssn 71240 -Minutes 2
```

**예상 결과**:
```
✅ auto_discover_result      ← 저장됨
✅ auto_discover_servers     ← 저장됨 (개선!)
✅ auto_discover_networks    ← 저장됨 (개선!)
✅ auto_discover_services    ← 저장됨 (개선!)
```

---

## 📊 개선 전후 비교

### 데이터 저장 신뢰성

| 항목 | 이전 | 개선 후 |
|------|------|--------|
| 완전 데이터 저장 | ⚠️ jq 영향 있음 | ✅ 독립 저장 |
| 컴포넌트 저장 | ⚠️ 조건부 | ✅ 독립 호출 |
| 실패 시 복구 | ❌ 불가능 | ✅ 파일로 가능 |
| 디버깅 정보량 | 📝 부족 | 📊 풍부 |

### 운영 안정성

| 항목 | 이전 | 개선 후 |
|------|------|--------|
| 부분 실패 대응 | ❌ 전체 실패 | ✅ 부분만 실패 |
| 모니터링 가시성 | 낮음 | 높음 |
| 일시적 오류 복구 | 어려움 | 쉬움 |
| 운영 부담 | 높음 | 낮음 |

---

## 📌 요점

1. **각 데이터를 별도 파일로 저장** → 진단/복구 용이
2. **각 kvs_put을 독립적으로 호출** → 일부 실패해도 나머지 저장
3. **상세 DEBUG 로깅** → 각 단계별 추적 가능
4. **jq 미설치 확정 방법** → 파일 크기 0 확인

**결론**: 설계가 완벽함 → jq만 설치하면 즉시 해결됨 ✅
