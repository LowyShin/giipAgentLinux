# LSChkdt 업데이트 미실행 - 근본 원인 및 해결 (최종 보고서)

**날짜**: 2025-11-22  
**상태**: 🟢 **원인 규명 및 코드 수정 완료**  
**수정 파일**: `giipAgentLinux/lib/gateway.sh`

---

## 📊 발견 과정

### 1단계: DB 로그 조사

```
❌ tLogSP: pApiRemoteServerSSHTestbyAK 기록 0건
❌ tKVS: remote_ssh_test_api_success 기록 0건
→ 결론: API가 호출되지 않음
```

### 2단계: 로깅 포인트 추적

```
[5.5] 서버 목록 파일 확인 성공: file_size=620
      ↓
      로깅 포인트 [5.6] 미출현 ← 🔴 이상 신호!
      ↓
[5.12] Gateway 사이클 완료
```

### 3단계: 소스 코드 분석

**의문점**: [5.5]와 [5.12] 사이에 왜 아무 로그도 없을까?

**gateway.sh Line 343-344**:
```bash
cat "$server_list_file" | grep -o '{[^}]*}' | while read -r server_json; do
    # 🔴 로깅 포인트 [5.6]
    echo "[gateway.sh] 🟢 [5.6] 서버 JSON 파싱 완료: ..."
```

**분석**:
- while 루프가 **0회 반복**됨
- while 루프 내의 모든 코드가 실행되지 않음
- **grep -o '{[^}]*}'가 0개 매칭**

### 4단계: grep 정규식 검증

**API 응답 형식** (실제):
```json
{
  "data": [
    {
      "hostname": "server1",
      "lssn": 71221
    }
  ]
}
```

**grep -o '{[^}]*}' 문제**:
- 정규식: `{` 다음 `}` 전까지
- **한 줄 내의 `{...}` 패턴만 매칭 가능**
- Multiline JSON은 매칭 불가능
- **결과: 0개 매칭 → while 루프 0회 실행**

---

## 🔴 근본 원인

**파일**: `giipAgentLinux/lib/gateway.sh` Line 343-344

```bash
# 문제: grep -o '{[^}]*}' (한 줄 기반 정규식)
cat "$server_list_file" | grep -o '{[^}]*}' | while read -r server_json; do
```

**원인**:
- API가 반환한 JSON이 **Multiline 형식** (들여쓰기 포함)
- grep 정규식은 **한 줄 내의 중괄호만** 인식 가능
- 파일 크기 620B이지만 0개 서버 추출

**연쇄 효과**:
```
[5.5] 파일 로드 성공 (620B)
  ↓
grep -o '{[^}]*}' → 0개 매칭
  ↓
while read 루프 → 0회 반복
  ↓
[5.6] ~ [5.11] 로깅 포인트 모두 미기록
  ↓
report_ssh_test_result() 미호출
  ↓
RemoteServerSSHTest API 미요청
  ↓
tLogSP 기록 0건
  ↓
pApiRemoteServerSSHTestbyAK SP 미실행
  ↓
tLSvr LSChkdt 미업데이트
  ↓
Web UI에서 표시 안 됨
```

---

## ✅ 해결 방법

### 수정된 코드

**파일**: `giipAgentLinux/lib/gateway.sh` Line 343-380

```bash
# 🔴 [로깅 포인트 #5.5-JSON-DEBUG] 서버 목록 파일 내용 확인
echo "[gateway.sh] 🟢 [5.5-JSON-DEBUG] 파일 내용 (첫 200자): $(head -c 200 "$server_list_file"), timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')" >&2

# Parse JSON and process each server
# Fix: Use jq for robust JSON parsing instead of grep (handles multiline JSON)
# Fallback: Use grep if jq not available
if command -v jq &> /dev/null; then
    # ✅ jq 사용 (권장)
    jq -r '.data[]? // .[]? // .' "$server_list_file" 2>/dev/null | while read -r server_json; do
        [[ -z "$server_json" || "$server_json" == "{}" ]] && continue
        
        hostname=$(echo "$server_json" | jq -r '.hostname // empty' 2>/dev/null)
        lssn=$(echo "$server_json" | jq -r '.lssn // empty' 2>/dev/null)
        # ... 나머지 필드 추출
else
    # ✅ Fallback: grep (jq 없을 때)
    # 먼저 JSON을 한 줄로 정규화
    tr -d '\n' < "$server_list_file" | sed 's/}/}\n/g' | grep -o '{[^}]*}' | while read -r server_json; do
        hostname=$(echo "$server_json" | grep -o '"hostname"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
        # ... 나머지 필드 추출
fi
```

### 주요 개선 사항

| 항목 | 이전 | 개선 후 |
|------|------|--------|
| JSON 파싱 | `grep -o '{[^}]*}'` | `jq` (또는 `tr -d '\n'` + grep) |
| Multiline 지원 | ❌ | ✅ |
| 오류 처리 | 없음 | Fallback 포함 |
| 디버그 로그 | 없음 | `[5.5-JSON-DEBUG]` 추가 |

---

## 🧪 검증 방법

### 배포 전 검증

```bash
# 1. 문법 확인
bash -n lib/gateway.sh

# 2. jq 설치 확인 (Linux Gateway)
which jq

# 3. 로컬 테스트 (JSON 파일로)
echo '{"data":[{"hostname":"test","lssn":1}]}' > /tmp/test.json
jq -r '.data[]?' /tmp/test.json
```

### 배포 후 검증

```bash
# 1. 코드 배포
git pull

# 2. Agent 실행 (Linux Gateway)
cd /path/to/giipAgentLinux
bash giipAgent3.sh 2>&1 | grep -E "\[5\."

# 예상: [5.6], [5.7], ..., [5.10.2] 등이 모두 출력되어야 함

# 3. DB 로그 확인 (Windows)
pwsh .\mgmt\query-splog.ps1 -SPName "pApiRemoteServerSSHTestbyAK" -Top 5

# 예상: RstVal=200인 기록이 있어야 함

# 4. tLSvr 값 확인
# SELECT LSsn, LSChkdt FROM tLSvr WHERE LSsn = 71221
# 예상: LSChkdt가 최근 시간으로 업데이트됨
```

---

## 📋 변경 요약

**파일 변경**: `giipAgentLinux/lib/gateway.sh`

**변경 라인**: 343-477

**변경 내용**:
- ✅ JSON 파싱 방식 개선 (grep → jq with fallback)
- ✅ Multiline JSON 지원
- ✅ 디버그 로그 추가 ([5.5-JSON-DEBUG])
- ✅ 에러 처리 강화

**테스트 필요 항목**:
- [ ] jq가 설치된 시스템에서 테스트
- [ ] jq가 없는 시스템에서 fallback 테스트
- [ ] 다양한 JSON 형식으로 테스트
- [ ] tLogSP에 RstVal=200 기록 확인
- [ ] tLSvr LSChkdt 업데이트 확인

---

## 🎓 교훈

**문제의 핵심**: 로그 포인트의 "점프"가 일어나면 **while 루프 조건 확인** 필요!

```
[5.5] → [5.6] 건너뜀
= while 루프가 0회 반복된 것
= 루프 전의 조건/파이프라인 문제
```

**개선 사항**:
1. 단순한 정규식(grep) 대신 목적에 맞는 도구(jq) 사용
2. Multiline 데이터 처리 시 사전 정규화 필수
3. 파이프 기반 while 루프는 디버그 어려움 → 로깅 강화 필요
