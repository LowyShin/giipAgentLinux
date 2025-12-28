# AI Agent 작업 규칙 및 체크리스트

> **📅 문서 메타데이터**  
> - 최초 작성: 2025-11-27
> - 최종 수정: 2025-12-28  
> - 작성자: AI Agent  
> - 목적: giipAgent3 수정 시 AI Agent가 따라야 할 규칙 및 체크리스트

---

## 🚨 가장 흔한 에러 & 해결 방법

### 1️⃣ **"Normal Mode가 실행 안 됨"**

**증상**:
- is_gateway=1인 서버에서 정상 모드가 실행 안 됨
- SSH 테스트만 수행되고 정상 작업(큐 처리) 미실행

**원인**:
- ❌ if-else 구조 사용
- ❌ else 블록에 Normal Mode를 넣음
- ❌ 따라서 is_gateway=1이면 else 블록이 실행 안 됨

**해결**:
- ✅ if 문만 사용 (else ❌)
- ✅ Normal Mode는 if 외부에서 독립적으로 실행
- ✅ 항상 실행되어야 함 (조건 없음)

### 2️⃣ **"Shutdown log가 두 번 기록됨"**

**증상**:
- KVS에 같은 shutdown 로그가 2번 나타남
- JSON의 mode 값이 다름 ("gateway" vs "normal")

**원인**:
- ❌ Gateway 블록 내에 `save_execution_log "shutdown" ...` 있음
- ❌ Normal 블록 내에도 `save_execution_log "shutdown" ...` 있음
- ❌ 두 블록 모두 실행되면서 2번 기록

**해결**:
- ✅ shutdown log를 `fi` 다음에 **한 번만** 작성
- ✅ 모드는 `[ "$gateway_mode" = "1" ]`로 동적 판단
  ```bash
  save_execution_log "shutdown" "{\"mode\":\"$([ "$gateway_mode" = "1" ] && echo "gateway+normal" || echo "normal")\",\"status\":\"normal_exit\"}"
  ```

### 3️⃣ **startup 로깅이 2번 이상 발생**

**증상**:
- tKVS에서 같은 시간에 startup 이벤트 2개 이상
- 디버깅 어려워짐

**원인**:
- ❌ giipAgent3.sh에서 save_execution_log("startup") 호출
- ❌ gateway.sh에서도 save_execution_log("startup") 호출  
- ❌ normal.sh에서도 save_execution_log("startup") 호출

**해결**:
- ✅ startup 로깅은 **각 모드별 1곳에서만** 호출:
  - **Gateway 모드**: giipAgent3.sh에서만
  - **Normal 모드**: lib/normal.sh에서만

**검증**:
```bash
# startup 로깅이 여러 곳에서 호출되는지 확인
grep -r "save_execution_log.*startup" lib/ giipAgent3.sh
```

---

## ⚠️ 절대 규칙

### bash 독립 호출 (2025-11-28)

**모든 모듈은 bash로 독립적으로 호출되어야 함** (실행 권한 부여 금지)

#### 올바른 호출 방식

```bash
# ✅ 올바른 방식: bash로 직접 실행
bash "$script_file"  # 실행 권한 필수 X
```

#### 절대 하면 안 될 것

```bash
# ❌ 잘못된 방식: chmod로 실행 권한 부여
chmod +x "$script_file"  # 금지!
"$script_file"  # 직접 실행 금지!
```

**이유**: 파일 시스템 권한이 불일치할 수 있으므로, bash 인터프리터로 실행하여 독립적 실행 보장

---

## ✅ 모듈 수정 전 체크리스트

### 모든 모듈 공통
```markdown
[ ] 1. ⚠️ bash 독립 호출 확인
       - 호출: bash "$script_file"
       - 금지: chmod +x / 직접 실행
[ ] 2. 파일 존재 여부 확인
       if [ ! -f "$script_file" ]; then ... fi
[ ] 3. 에러 처리 추가
       if bash "$script_file"; then ... else ... fi
[ ] 4. 문법 오류 확인
       bash -n $script_file
[ ] 5. 사양서 업데이트
       GIIPAGENT3_SPECIFICATION.md 수정
```

### gateway.sh 수정 시
```markdown
[ ] 1. normal.sh 로드가 있는가?
       grep -n "normal.sh" lib/gateway.sh
[ ] 2. fetch_queue() 함수를 사용하는가?
       grep -n "fetch_queue" lib/gateway.sh
[ ] 3. KVS 함수 중복이 없는가?
       grep -n "save_execution_log.*startup" lib/gateway.sh → 결과: 0개
[ ] 4. 문법 오류 확인
       bash -n lib/gateway.sh
[ ] 5. 사양서 업데이트
```

### normal.sh 수정 시
```markdown
[ ] 1. fetch_queue() 함수 정의 확인
       grep -n "fetch_queue()" lib/normal.sh
[ ] 2. startup 로깅이 1번만 있는가?
       grep -n "save_execution_log.*startup" lib/normal.sh → 결과: 1개
[ ] 3. KVS 함수 중복이 없는가?
       grep -c "save_execution_log" lib/normal.sh
[ ] 4. 문법 오류 확인
       bash -n lib/normal.sh
[ ] 5. 사양서 업데이트
```

### giipAgent3.sh 수정 시
```markdown
[ ] 1. Gateway startup 로깅 위치 확인
       grep -n "save_execution_log.*startup" giipAgent3.sh
[ ] 2. 모듈 로드 순서 확인
       Gateway: db_clients.sh → gateway.sh
       Normal: normal.sh
[ ] 3. GIT_COMMIT, FILE_MODIFIED export 확인
[ ] 4. 문법 오류 확인
       bash -n giipAgent3.sh
[ ] 5. 사양서 업데이트
```

### KVS 로깅 수정 시
```markdown
[ ] 1. 사양서 먼저 확인
[ ] 2. startup 로깅 위치 확인
[ ] 3. 중복 로깅 방지
[ ] 4. 버전 정보 사용
[ ] 5. 사양서 업데이트
```

---

**관련 문서**:
- [GIIPAGENT3_SPECIFICATION.md](./GIIPAGENT3_SPECIFICATION.md) - 사양서
- [TROUBLESHOOTING_HISTORY.md](./TROUBLESHOOTING_HISTORY.md) - 트러블슈팅 이력
