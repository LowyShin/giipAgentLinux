# CQE (Centralized Queue Engine) 사양서

**문서 버전**: 1.0  
**작성일**: 2025-11-28  
**최종 수정**: 2025-11-28  

---

## 📋 목차

1. [개요](#개요)
2. [queue_get 함수](#queue_get-함수)
3. [입력 사양](#입력-사양)
4. [입력값 처리](#입력값-처리)
5. [출력 사양](#출력-사양)
6. [API 호출 흐름](#api-호출-흐름)
7. [에러 처리](#에러-처리)
8. [사용 예제](#사용-예제)

---

## 개요

**CQE(Centralized Queue Engine)** 는 giipAgent에서 중앙 집중식 큐 서비스를 관리하는 모듈입니다.

**핵심 기능**:
- 원격 서버의 실행 대기 중인 스크립트 큐 조회
- 서버별 실행 환경(OS, 호스트명) 기반 필터링
- 안전한 스크립트 다운로드 및 로컬 실행

**파일 위치**: `lib/cqe.sh`

---

## queue_get 함수

### 함수 시그니처

```bash
queue_get "lssn" "hostname" "os" "output_file"
```

### 함수 설명

CQEQueueGet API를 호출하여 원격 큐에서 대기 중인 스크립트를 가져와 로컬 파일에 저장합니다.

| 항목 | 값 |
|------|-----|
| **반환값** | 0 = 성공, 1 = 실패 |
| **출력** | stdout: 없음, stderr: 에러 메시지 (필요시) |
| **파일 출력** | `output_file`에 스크립트 내용 저장 |

---

## 입력 사양

### 함수 파라미터

#### 1. `lssn` (Logical Server Session Number)
- **타입**: 숫자 (정수)
- **필수여부**: ✅ 필수
- **설명**: 서버를 고유하게 식별하는 ID
- **예시**: `71221`, `12345`
- **제약사항**: 0보다 커야 함

#### 2. `hostname` (서버 호스트명)
- **타입**: 문자열
- **필수여부**: ✅ 필수
- **설명**: 대상 서버의 호스트명
- **예시**: `p-cnsldb01m`, `web-server-01`
- **제약사항**: 특수문자 포함 가능, JSON 이스케이프 필요

#### 3. `os` (운영 체제)
- **타입**: 문자열
- **필수여부**: ✅ 필수
- **설명**: 서버의 운영 체제
- **허용값**: `Linux`, `Windows`, `Darwin`
- **예시**: `Linux`
- **제약사항**: 대소문자 구분

#### 4. `output_file` (출력 파일 경로)
- **타입**: 파일 경로
- **필수여부**: ✅ 필수
- **설명**: 다운로드한 큐 스크립트를 저장할 파일 경로
- **예시**: `/tmp/queue_output_$$.sh`
- **제약사항**: 쓰기 권한 있어야 함

### 전역 변수 (필수)

#### 1. `sk` (Session Key / API Token)
- **설명**: API 인증을 위한 세션 키
- **출처**: `giipAgent.cnf`에서 로드
- **예시**: `abcd1234efgh5678`

#### 2. `apiaddrv2` (API 엔드포인트)
- **설명**: CQEQueueGet API의 URL
- **출처**: `giipAgent.cnf`에서 로드
- **예시**: `https://giipfaw.azurewebsites.net/api/giipApiSk2`

#### 3. `apiaddrcode` (API 코드, 선택사항)
- **설명**: API 호출 시 사용할 인증 코드
- **출처**: `giipAgent.cnf`에서 로드
- **필수여부**: 선택사항 (없으면 생략)
- **예시**: `XYZ123ABC456`

---

## 입력값 처리

### 1. 파라미터 검증

```
INPUT: queue_get "71221" "p-cnsldb01m" "Linux" "/tmp/queue_output_$$.sh"
         ↓
    [1] lssn이 비어있는가?          → YES: 에러 반환
    [2] hostname이 비어있는가?       → YES: 에러 반환
    [3] os가 비어있는가?             → YES: 에러 반환
    [4] output_file이 비어있는가?    → YES: 에러 반환
    [5] sk가 설정되었는가?           → NO: 에러 반환
    [6] apiaddrv2가 설정되었는가?    → NO: 에러 반환
```

**검증 실패 시**: 에러 메시지 출력 후 반환값 1 반환

### 2. API URL 생성

```bash
기본 URL:   ${apiaddrv2}
Optional:   apiaddrcode가 있으면 ?code=${apiaddrcode} 추가

최종 URL: https://giipfaw.azurewebsites.net/api/giipApiSk2?code=XYZ123ABC456
```

### 3. API 요청 데이터 구성 (giipapi_rules.md 준수)

#### text 필드 (파라미터 명칭만)
```
text = "CQEQueueGet lssn hostname os op"
```
- 목적: 요청이 어떤 API 기능을 호출하는지 지정
- 구성: [API명] [파라미터1] [파라미터2] ...

#### jsondata 필드 (실제 값)
```json
{
  "lssn": 71221,
  "hostname": "p-cnsldb01m",
  "os": "Linux",
  "op": "op"
}
```
- 목적: 실제 전달할 데이터
- lssn: 숫자형 (따옴표 없음)
- hostname: 문자열 (따옴표 포함)
- os: 문자열 (따옴표 포함)
- op: 예약된 필드 (기본값 "op")

### 4. API 호출

```bash
curl -X POST "${api_url}" \
     -d "text=${text}&token=${sk}&jsondata=${jsondata}" \
     -H "Content-Type: application/x-www-form-urlencoded" \
     --insecure \
     -o "${temp_response}"
```

**파라미터**:
- `text`: API 기능 지정 (위에서 설명)
- `token`: 인증 토큰 (sk 변수)
- `jsondata`: JSON 형식의 파라미터 값
- `--insecure`: SSL 인증서 검증 무시 (Azure 호환)

---

## 출력 사양

### 성공 (반환값: 0)

#### 파일 출력
```bash
${output_file}에 스크립트 저장
```

**파일 내용 예시**:
```bash
#!/bin/bash
# 이것은 CQE로부터 다운로드받은 스크립트
echo "Hello from Queue"
exit 0
```

**파일 속성**:
- 경로: 함수 호출 시 지정한 경로
- 권한: 기본 umask (보안 권장사항: 추후 chmod 600으로 변경)
- 크기: API 응답에 포함된 스크립트 크기

### 실패 (반환값: 1)

#### stderr 출력

```
[queue_get] ⚠️  Missing required parameters (lssn, hostname, os, output_file)
```

또는

```
[queue_get] ⚠️  Missing required variables (sk, apiaddrv2)
```

또는

```
[queue_get] ❌ API call failed or no response (curl exit code: 28)
```

또는

```
[queue_get] ❌ Failed to extract script from API response
[queue_get] DEBUG: Response content (first 1000 chars):
{"error":"Invalid LSSN","code":400}
[queue_get] DEBUG: API URL: https://...
[queue_get] DEBUG: jsondata: {"lssn":71221,"hostname":"...","os":"Linux","op":"op"}
```

---

## API 호출 흐름

```
┌─ queue_get 호출
│
├─ [Step 1] 입력 파라미터 검증
│  ├─ lssn, hostname, os, output_file 존재 확인
│  └─ sk, apiaddrv2 전역변수 확인
│     ├─ 실패 → stderr 출력, 반환값 1
│     └─ 성공 → Step 2
│
├─ [Step 2] API URL 생성
│  ├─ 기본: apiaddrv2
│  └─ apiaddrcode 있으면 쿼리 파라미터 추가
│
├─ [Step 3] 요청 데이터 생성
│  ├─ text: "CQEQueueGet lssn hostname os op"
│  ├─ token: sk 값
│  └─ jsondata: {"lssn": 71221, "hostname": "...", ...}
│
├─ [Step 4] Temp 파일 준비
│  ├─ 경로: /tmp/queue_response_$$.json
│  └─ 기존 임시 파일 정리: rm -f /tmp/queue_response_*
│
├─ [Step 5] CURL로 API 호출
│  ├─ Method: POST
│  ├─ URL: ${apiaddrv2}?code=...
│  ├─ Data: text & token & jsondata (URL 인코딩)
│  ├─ Header: Content-Type: application/x-www-form-urlencoded
│  └─ SSL: --insecure
│
├─ [Step 6] 응답 검증
│  ├─ Temp 파일 존재 확인
│  ├─ 파일 크기 > 0 확인
│  │  ├─ 실패 → 에러 메시지, 반환값 1
│  │  └─ 성공 → Step 7
│  └─ Curl 종료 코드 확인
│
├─ [Step 7] JSON 파싱 (jq 사용)
│  ├─ 경로 1: .data[0].ms_body
│  ├─ 경로 2: .ms_body
│  │  ├─ 값 추출 성공 → Step 9
│  │  └─ 값 추출 실패 → Step 8
│
├─ [Step 8] 폴백 파싱 (sed/grep 사용)
│  ├─ 정규식: "ms_body"\s*:\s*"([^"]*)
│  ├─ 개행 처리: \\n → \n 변환
│  │  ├─ 성공 → Step 9
│  │  └─ 실패 → 에러 반환
│
├─ [Step 9] 스크립트 저장
│  ├─ 경로: output_file로 지정한 파일
│  ├─ 모드: > (덮어쓰기)
│  └─ 성공 → Step 10
│
├─ [Step 10] 정리
│  ├─ Temp 응답 파일 삭제
│  └─ 임시 파일 정리
│
└─ 반환값: 0 (성공)
```

---

## 에러 처리

### 에러 타입 및 처리

| # | 에러 상황 | 메시지 | 원인 | 해결 방법 |
|---|---------|--------|------|---------|
| 1 | 파라미터 누락 | `Missing required parameters` | lssn, hostname, os, output_file 중 하나 이상 없음 | 함수 호출 시 4개 파라미터 모두 제공 |
| 2 | 전역변수 누락 | `Missing required variables (sk, apiaddrv2)` | giipAgent.cnf 로드 실패 또는 설정 없음 | giipAgent.cnf 확인, sk/apiaddrv2 설정 확인 |
| 3 | API 응답 없음 | `API call failed or no response` | 네트워크 오류, 타임아웃, API 서버 다운 | 네트워크 상태, API 엔드포인트 확인 |
| 4 | JSON 파싱 실패 | `Failed to extract script from API response` | API 응답이 예상 포맷이 아님 | API 응답 형식 확인, 디버그 메시지 확인 |
| 5 | 파일 쓰기 실패 | (암시적, 파일 미생성) | output_file 경로에 쓰기 권한 없음 | 디렉토리 권한 확인, 경로 변경 |

### 디버그 정보

실패 시 다음 정보를 출력하여 문제 파악에 도움:

```
[queue_get] DEBUG: Response content (first 1000 chars):
[queue_get] DEBUG: API URL: 
[queue_get] DEBUG: jsondata:
```

---

## 사용 예제

### 예제 1: 기본 사용

```bash
#!/bin/bash

# Config 로드 (sk, apiaddrv2, apiaddrcode, lssn 설정)
. ./giipAgent.cnf

# CQE 라이브러리 로드
. ./lib/cqe.sh

# 큐에서 스크립트 가져오기
queue_get "71221" "p-cnsldb01m" "Linux" "/tmp/queue_output_$$.sh"

if [ $? -eq 0 ]; then
    echo "✅ 스크립트 다운로드 성공"
    cat /tmp/queue_output_$$.sh
else
    echo "❌ 스크립트 다운로드 실패"
    exit 1
fi
```

### 예제 2: 조건부 실행

```bash
#!/bin/bash

. ./giipAgent.cnf
. ./lib/cqe.sh

# SSH 연결 테스트 후 큐 가져오기
if ssh -o ConnectTimeout=5 root@p-cnsldb01m "echo ok" &>/dev/null; then
    echo "✅ SSH 연결 성공"
    
    queue_get "$lssn" "p-cnsldb01m" "Linux" "/tmp/queue_from_cnsldb01m.sh"
    if [ $? -eq 0 ]; then
        echo "✅ 큐 다운로드 성공"
        bash /tmp/queue_from_cnsldb01m.sh
    else
        echo "❌ 큐 다운로드 실패"
    fi
else
    echo "❌ SSH 연결 실패"
fi
```

### 예제 3: 여러 서버 순회

```bash
#!/bin/bash

. ./giipAgent.cnf
. ./lib/cqe.sh

SERVERS=(
    "71221:p-cnsldb01m:Linux"
    "71222:p-cnsldb02m:Linux"
    "71223:p-web01:Linux"
)

for server in "${SERVERS[@]}"; do
    IFS=':' read -r lssn hostname os <<< "$server"
    
    output_file="/tmp/queue_${hostname}_$$.sh"
    
    if queue_get "$lssn" "$hostname" "$os" "$output_file"; then
        echo "✅ [$hostname] 큐 다운로드 성공"
        bash "$output_file"
        rm -f "$output_file"
    else
        echo "❌ [$hostname] 큐 다운로드 실패"
    fi
done
```

### 예제 4: 에러 처리

```bash
#!/bin/bash

. ./giipAgent.cnf
. ./lib/cqe.sh

queue_get "71221" "p-cnsldb01m" "Linux" "/tmp/queue_output.sh" 2>/tmp/queue_error.log

case $? in
    0)
        echo "✅ 성공"
        ;;
    1)
        echo "❌ 실패"
        echo "에러 내용:"
        cat /tmp/queue_error.log
        exit 1
        ;;
esac
```

---

## 관련 문서

- [API 규칙](giipapi_rules.md) - text/jsondata 포맷 정의
- [테스트 스크립트](../tests/test-queue-get.sh) - 테스트 방법
- [KVS 라이브러리](kvs.sh) - 실행 결과 로깅
- [Common 라이브러리](common.sh) - 공통 유틸리티

---

**작성자**: GIIP Agent Development Team  
**최종 검토**: 2025-11-28
