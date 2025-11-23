# 📋 사양서 최신화 완료 & 수정 시 주의사항

**작성일**: 2025-11-22  
**상태**: ✅ 사양서 최신화 완료

---

## 📝 사양서 업데이트 내용

### 1. gateway.sh 모듈 설명 최신화 (줄 218-227)

**추가된 내용**:
- [2025-11-22] 추가 로드: `fetch_queue()` from normal.sh 명시
- Gateway 자신의 큐 처리용 (중요!)
- normal.sh 로드가 필수라는 점 강조

**효과**: 개발자가 gateway.sh 파일을 열기 전에 이 섹션 읽으면 normal.sh 로드가 필요하다는 것을 알 수 있음

---

### 2. 에러 원인 & 해결책 상세 문서화 (줄 478-625)

#### 추가된 섹션: "🚨 AI Agent 작업 규칙 (2025-11-22 최신화)"

**3가지 가장 흔한 에러**:

##### 1️⃣ Gateway 큐 체크가 실행 안 됨
- **증상**: LSChkdt 미업데이트
- **원인**: normal.sh 미로드 → fetch_queue() 미정의
- **해결**: gateway.sh 줄 34에 normal.sh 로드 추가
- **검증**: `grep -n "normal.sh" lib/gateway.sh` → 결과 있어야 함

##### 2️⃣ startup 로깅이 2번 이상 발생
- **증상**: tKVS에 같은 시간에 startup 2개 이상
- **원인**: 여러 모듈에서 중복 호출
- **해결**: Gateway/Normal 각각 1곳에서만 호출
- **검증**: `grep -r "save_execution_log.*startup"` → Gateway 1개, Normal 1개만

##### 3️⃣ API 응답 timestamp로 인한 불일치
- **증상**: 클라이언트-서버 시간 차이
- **원인**: JSON에 $(date) 직접 삽입
- **해결**: JSON에서 timestamp 제거, DB의 GETUTCDATE() 사용
- **검증**: `grep -r "timestamp" lib/*.sh` → 주석 제외 없어야 함

---

### 3. 모듈별 체크리스트 추가 (줄 589-650)

**gateway.sh 수정 시 체크리스트**:
```markdown
[ ] 1. normal.sh 로드가 있는가? (줄 34)
[ ] 2. fetch_queue() 함수를 사용하는가?
[ ] 3. KVS 함수 중복이 없는가?
[ ] 4. 문법 오류 확인 (bash -n)
[ ] 5. 사양서 업데이트
```

**normal.sh 수정 시 체크리스트**:
```markdown
[ ] 1. fetch_queue() 함수 정의 확인 (줄 14)
[ ] 2. startup 로깅이 1번만 있는가? (줄 216)
[ ] 3. KVS 함수 중복이 없는가?
[ ] 4. 문법 오류 확인 (bash -n)
[ ] 5. 사양서 업데이트
```

**giipAgent3.sh 수정 시 체크리스트**:
```markdown
[ ] 1. Gateway startup 로깅 위치 (줄 203)
[ ] 2. 모듈 로드 순서 확인
[ ] 3. GIT_COMMIT, FILE_MODIFIED export 확인
[ ] 4. 문법 오류 확인 (bash -n)
[ ] 5. 사양서 업데이트
```

---

### 4. 버전 이력 추가 (줄 756-763)

| 날짜 | 변경 사항 | 영향 범위 |
|------|---------|---------|
| 2025-11-11 | 초안 작성 | 전체 구조 |
| 2025-11-22 | [5.3.1] Gateway 자신의 큐 처리 추가 | gateway.sh, normal.sh |
| 2025-11-22 | 타임스탐프 정책 업데이트 (DB 레벨) | JSON 구조 변경 |
| 2025-11-22 | gateway.sh에 normal.sh 로드 추가 | gateway.sh 줄 34 |
| 2025-11-22 | 에러 원인 & 해결책 상세 문서화 | 🚨 AI Agent 작업 규칙 섹션 신규 |

---

### 5. 최근 수정 요약 추가 (줄 765-823)

**포함 내용**:
- 문제 설명: Gateway LSChkdt 미업데이트
- 근본 원인: normal.sh 미로드
- 해결책: normal.sh 로드 + [5.3.1] 로직
- 기대 효과: LSChkdt 자동 업데이트

---

## 🎯 주의사항 (수정 시 반드시 확인!)

### ⚠️ 가장 중요한 3가지

#### 1. **normal.sh 로드가 gateway.sh에 필수!**

```bash
# gateway.sh 줄 34에 반드시 이 코드가 있어야 함
if [ -f "${SCRIPT_DIR_GATEWAY_SSH}/normal.sh" ]; then
    . "${SCRIPT_DIR_GATEWAY_SSH}/normal.sh"
else
    fetch_queue() { return 1; }  # Stub
fi
```

**검증 명령**:
```bash
grep -n "normal.sh" lib/gateway.sh
# 결과: 줄 34: . "${SCRIPT_DIR_GATEWAY_SSH}/normal.sh"
```

**없으면 에러**:
- [5.3.1] Gateway 큐 체크 미실행
- fetch_queue() 함수 미정의
- Gateway LSChkdt 업데이트 안 됨

---

#### 2. **startup 로깅은 각 모드별 1곳에서만!**

**Gateway 모드** (giipAgent3.sh 줄 203):
```bash
save_execution_log "startup" "$init_details"
```

**Normal 모드** (lib/normal.sh 줄 216):
```bash
save_execution_log "startup" "$init_details"
```

**검증 명령**:
```bash
grep -r "save_execution_log.*startup" .
# 결과:
# giipAgent3.sh: 1줄
# lib/gateway.sh: 0줄 (호출 안 함!)
# lib/normal.sh: 1줄
```

**중복되면 에러**:
- tKVS에 startup 이벤트 중복
- 디버깅 시 혼동
- 로그 분석 어려워짐

---

#### 3. **JSON에 timestamp 필드 금지!**

**❌ 잘못된 코드**:
```bash
# 이런 식으로 timestamp 직접 삽입 금지!
local json="{\"timestamp\":\"$(date '+%Y-%m-%d %H:%M:%S')\",\"status\":\"ok\"}"
```

**✅ 올바른 코드**:
```bash
# timestamp 필드 제거, DB의 GETUTCDATE() 사용
local json="{\"status\":\"ok\",\"lssn\":${lssn}}"
# timestamp는 KVS 자동 처리 (regdate 사용)
```

**검증 명령**:
```bash
grep -r "timestamp" lib/*.sh giipAgent3.sh | grep -v "# " | grep -v "⏰"
# 결과: 없어야 함 (주석, 설명 제외)
```

**timestamp 있으면 에러**:
- 클라이언트-서버 시간 차이
- LSChkdt 업데이트 시점 모호
- 데이터 불일치

---

## 🔍 수정 전 필독 섹션

사양서의 이 섹션들을 반드시 읽고 수정할 것:

1. **"🚨 AI Agent 작업 규칙"** (줄 478)
   - 가장 흔한 3가지 에러
   - 각각의 원인과 해결책
   - 검증 방법

2. **"✅ 모듈 수정 전 체크리스트"** (줄 589)
   - gateway.sh 수정 시 체크리스트
   - normal.sh 수정 시 체크리스트
   - giipAgent3.sh 수정 시 체크리스트

3. **"KVS 로깅 규칙"** (줄 294)
   - startup 로깅 위치 확인
   - 중복 로깅 방지
   - 버전 정보 사용 방법

---

## 📊 사양서 참고 구조

```
GIIPAGENT3_SPECIFICATION.md
├── 📍 개요 & 용어 정의 (줄 1-160)
│   └─ "왜 이 용어가 중요한가" 설명
├── 📍 모듈 구조 (줄 160-290)
│   └─ 각 모듈의 제공 기능, 로드 시점
├── 📍 KVS 로깅 규칙 (줄 294-370)
│   └─ startup 로깅 위치, 중복 방지
├── 📍 실행 흐름 (줄 420-530)
│   └─ Gateway/Normal 모드 플로우
├── 🚨 AI Agent 작업 규칙 (줄 478-655) ← 가장 중요!
│   └─ 3가지 흔한 에러 + 체크리스트
└── 📅 버전 이력 & 최종 요약 (줄 756-833)
    └─ 언제, 어떻게, 왜 수정했는지
```

---

## ✅ 최종 체크

| 항목 | 체크 | 설명 |
|------|------|------|
| **normal.sh 로드** | ✅ | gateway.sh 줄 34에 추가됨 |
| **startup 로깅** | ✅ | 각 모드별 1곳씩 정의 |
| **JSON timestamp** | ✅ | 모든 코드에서 제거됨 |
| **체크리스트** | ✅ | 모든 모듈별 체크리스트 추가 |
| **에러 원인** | ✅ | 3가지 흔한 에러 상세 문서화 |
| **사양서 버전** | ✅ | 변경 이력 명확히 기록 |

---

## 🎯 결론

이제 개발자/AI Agent가 코드 수정 시:

1. **이 사양서를 먼저 읽는다**
2. **"🚨 AI Agent 작업 규칙"에서 주의사항 확인**
3. **해당 모듈의 체크리스트 실행**
4. **수정 후 검증 명령어 실행**
5. **사양서 버전 이력 업데이트**

**결과**: 동일한 에러가 반복되지 않음 ✅

