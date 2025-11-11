# giipAgentLinux lib/ 함수 참조 가이드

> **📌 AI 작업자를 위한 중요 안내**
> 
> **목적**: 중복 로직 방지 및 파일별 역할 명확화
> 
> **사용 시점**:
> - 새로운 기능을 추가할 때
> - 기존 함수를 수정할 때
> - "이 기능이 어디에 있지?" 찾을 때
> 
> **Golden Rule**:
> - ⚠️ 같은 로직을 여러 파일에 중복 구현 금지!
> - ⚠️ 함수 추가 전 이 문서에서 기존 함수 확인 필수!
> - ⚠️ 새 함수 추가 시 이 문서 업데이트 필수!

---

## 📂 lib/ 디렉토리 구조 및 역할

```
lib/
├── kvs.sh              # KVS 저장 전용 (단일 책임)
├── network.sh          # 네트워크 정보 수집
├── gateway.sh          # Gateway 모드 핵심 로직
├── db_clients.sh       # DB 클라이언트 설치 및 체크 (단일 책임) ⭐
├── remote_execution.sh # SSH 원격 명령 실행
└── utils.sh            # 공통 유틸리티 함수
```

---

## 🚨 중복 방지 규칙

### Rule 1: DB 클라이언트 설치는 **오직 db_clients.sh만**

**❌ 절대 금지**:
```bash
# gateway.sh에서 pyodbc 설치 시도 (2025-11-11 실제 사고)
if ! python3 -c "import pyodbc" 2>/dev/null; then
    echo "Installing pyodbc..."
    pip3 install pyodbc  # ❌ 중복 로직!
fi
```

**✅ 올바른 방법**:
```bash
# gateway.sh에서는 체크만
if ! python3 -c "import pyodbc" 2>/dev/null; then
    echo "⚠️ pyodbc not available"
    # db_clients.sh에서 이미 설치 시도했으므로 여기서는 경고만
fi
```

**이유**:
- `db_clients.sh`가 이미 시스템 패키지 설치, pip 업그레이드 등 모든 과정 수행
- 여러 곳에서 설치 시도하면 버전 충돌, 중복 로그, 디버깅 어려움

---

### Rule 2: KVS 저장은 **오직 kvs.sh의 log_kvs만**

**❌ 절대 금지**:
```bash
# 다른 파일에서 직접 wget 호출
wget --post-data="text=KVSPut..." "${apiaddrv2}"  # ❌ 중복 로직!
```

**✅ 올바른 방법**:
```bash
# lib/kvs.sh 함수 사용
log_kvs "kType" "kKey" "kFactor" "$json_value"
```

---

### Rule 3: SSH 원격 실행은 **remote_execution.sh만**

**❌ 절대 금지**:
```bash
# gateway.sh에서 직접 sshpass 호출
sshpass -p "$password" ssh user@host "command"  # ❌ 중복 로직!
```

**✅ 올바른 방법**:
```bash
# lib/remote_execution.sh 함수 사용
execute_remote_command "$host" "$port" "$user" "$password" "$command"
```

---

## 📚 파일별 함수 상세

### 1️⃣ lib/kvs.sh - KVS 저장 전용

**책임**: KVS API 호출 로직의 단일 소스

**Export 함수**:
```bash
log_kvs()              # KVS에 데이터 저장 (표준 방법)
save_execution_log()   # Gateway 실행 로그 저장 (log_kvs 래퍼)
```

**사용 예시**:
```bash
# giipAgent3.sh에서
source lib/kvs.sh
log_kvs "lssn" "$lssn" "startup" '{"time":"2025-11-11 10:00:00"}'

# gateway.sh에서
save_execution_log "gateway_init" "$json_data" "gateway_status"
```

**주의사항**:
- ⚠️ 다른 파일에서 wget으로 KVSPut 직접 호출 금지
- ⚠️ API 엔드포인트 변경 시 이 파일만 수정

---

### 2️⃣ lib/db_clients.sh - DB 클라이언트 설치 및 체크 ⭐

**책임**: 모든 DB 클라이언트 설치의 단일 소스 (MySQL, PostgreSQL, MSSQL, Oracle)

**Export 함수**:
```bash
check_python_environment()   # Python 환경 체크
check_mysql_client()         # MySQL/MariaDB 클라이언트 체크
check_postgresql_client()    # PostgreSQL 클라이언트 체크
check_mssql_client()         # MSSQL 클라이언트 + pyodbc 설치 ⭐
check_oracle_client()        # Oracle 클라이언트 + cx_Oracle 설치
check_all_db_clients()       # 모든 클라이언트 일괄 체크
```

**중요: pyodbc 설치 로직**

**위치**: Line 203-218

```bash
check_mssql_client() {
	# ... ODBC Driver 설치 ...
	
	# ⭐ pip/setuptools 업그레이드 (2025-11-11 추가)
	python3 -m pip install --upgrade pip setuptools --quiet 2>/dev/null || true
	
	# pyodbc 설치
	pip3 install pyodbc --quiet 2>/dev/null
	
	# 검증
	if python3 -c "import pyodbc" 2>/dev/null; then
		echo "[Gateway-MSSQL] ✅ pyodbc installed successfully"
	else
		echo "[Gateway-MSSQL] ⚠️ pyodbc installation may have failed"
	fi
}
```

**호출 순서**:
```
giipAgent3.sh
  → process_gateway_servers() (lib/gateway.sh)
    → check_all_db_clients() (lib/db_clients.sh)
      → check_mssql_client()
        → pip upgrade
        → pyodbc install
```

**❌ 다른 파일에서 pyodbc 설치 절대 금지!**

---

### 3️⃣ lib/gateway.sh - Gateway 모드 핵심 로직

**책임**: Gateway 서버 목록 조회, 원격 명령 실행, DB 쿼리 관리

**Export 함수**:
```bash
get_gateway_servers()        # API에서 Gateway 대상 서버 목록 조회
get_db_queries()             # API에서 tGatewayDBQuery 목록 조회
get_managed_databases()      # API에서 tManagedDatabase 목록 조회
execute_remote_command()     # SSH 원격 명령 실행 (래퍼)
get_script_by_mssn()         # 특정 스크립트 조회
get_remote_queue()           # 원격 실행 큐 조회
process_gateway_servers()    # Gateway 메인 프로세스
check_managed_databases()    # tManagedDatabase 자동 체크
```

**주의사항**:
- ⚠️ DB 클라이언트 설치는 `db_clients.sh`에 위임
- ⚠️ KVS 저장은 `kvs.sh`의 `save_execution_log()` 사용
- ⚠️ SSH 실행은 `remote_execution.sh` 사용

**예시: check_managed_databases() 함수**

```bash
check_managed_databases() {
	# API에서 DB 목록 조회
	local db_list_file=$(get_managed_databases)
	
	# DB 타입별 처리
	case "$db_type" in
		MSSQL)
			# ✅ 설치는 db_clients.sh에서 이미 완료
			# ✅ 여기서는 체크만
			if ! python3 -c "import pyodbc" 2>/dev/null; then
				echo "⚠️ pyodbc not available"  # 경고만
			else
				# 실제 DB 연결 테스트
			fi
			;;
	esac
	
	# ✅ KVS 저장은 kvs.sh 사용
	save_execution_log "managed_db_check" "$kv_value" "$kv_key"
}
```

---

### 4️⃣ lib/remote_execution.sh - SSH 원격 실행

**책임**: SSH 연결 및 원격 명령 실행의 단일 소스

**Export 함수**:
```bash
execute_remote_command()  # sshpass를 사용한 원격 명령 실행
```

**사용 예시**:
```bash
# gateway.sh에서
execute_remote_command "$host" "$port" "$user" "$password" "df -h"
```

**주의사항**:
- ⚠️ 다른 파일에서 직접 `sshpass` 호출 금지
- ⚠️ 비밀번호 복호화 로직도 이 함수에 포함

---

### 5️⃣ lib/network.sh - 네트워크 정보 수집

**책임**: 네트워크 인터페이스 정보 JSON 생성

**Export 함수**:
```bash
get_network_info()  # 네트워크 정보 JSON 생성
```

---

### 6️⃣ lib/utils.sh - 공통 유틸리티

**책임**: 여러 모듈에서 공통 사용하는 헬퍼 함수

**Export 함수**:
```bash
# (향후 추가될 공통 함수들)
```

---

## 🔄 함수 추가 워크플로

### 1️⃣ 새 함수 추가 시 체크리스트

```markdown
[ ] 1. 이 문서에서 유사 함수 검색
   → grep으로 기능 이름 검색
   → 예: "pyodbc", "mysql", "ssh", "kvs"

[ ] 2. 적절한 파일 선택
   → DB 클라이언트 → db_clients.sh
   → KVS 저장 → kvs.sh
   → SSH 실행 → remote_execution.sh
   → Gateway 로직 → gateway.sh

[ ] 3. 함수 작성 및 export
   → 파일 하단 export -f [함수명] 추가

[ ] 4. 이 문서 업데이트
   → 새 함수를 해당 섹션에 추가
   → 사용 예시 작성

[ ] 5. 테스트
   → 실제 환경에서 함수 호출 확인
```

---

## 📊 함수 호출 관계도

```
giipAgent3.sh (메인)
│
├─ lib/kvs.sh
│  └─ log_kvs()                    # KVS 저장 (모든 곳에서 사용)
│
├─ lib/network.sh
│  └─ get_network_info()
│
└─ lib/gateway.sh
   ├─ process_gateway_servers()    # Gateway 메인 프로세스
   │  │
   │  ├─ check_all_db_clients()    # → lib/db_clients.sh
   │  │  ├─ check_mysql_client()
   │  │  ├─ check_postgresql_client()
   │  │  ├─ check_mssql_client()   # ⭐ pyodbc 설치
   │  │  └─ check_oracle_client()
   │  │
   │  ├─ get_gateway_servers()     # API 호출
   │  ├─ get_db_queries()          # API 호출
   │  │
   │  └─ execute_remote_command()  # → lib/remote_execution.sh
   │
   └─ check_managed_databases()
      ├─ get_managed_databases()   # API 호출
      └─ save_execution_log()      # → lib/kvs.sh
```

---

## 🚨 2025-11-11 실제 사고 사례

**문제**: pyodbc 설치 로직 중복

**발생 위치**:
- ❌ `lib/db_clients.sh` Line 203 (원본)
- ❌ `lib/gateway.sh` Line 342 (중복 추가) ← AI가 잘못 추가

**원인**:
- AI가 이 문서를 확인하지 않음
- `db_clients.sh`에 이미 설치 로직이 있다는 걸 몰랐음

**해결**:
- `lib/gateway.sh`의 중복 로직 제거
- `db_clients.sh`만 남김
- 이 문서 작성 (재발 방지)

**교훈**:
```markdown
⚠️ 새 함수 추가 전 반드시 이 문서 확인!
⚠️ "이미 있는 기능 아닐까?" 항상 의심!
⚠️ 같은 기능이 여러 파일에 있으면 안됨!
```

---

## 📝 문서 업데이트 규칙

**언제 업데이트하나?**
- 새 함수 추가 시
- 함수 책임 변경 시
- 함수 삭제 시
- 중복 로직 발견 시

**업데이트 방법**:
1. 해당 파일 섹션 찾기
2. 함수명 + 설명 추가
3. 사용 예시 작성
4. Git 커밋 시 이 문서도 함께 포함

---

## 🔍 빠른 검색 가이드

**"pyodbc 설치는 어디서?"**
→ `lib/db_clients.sh` - `check_mssql_client()`

**"KVS 저장은 어디서?"**
→ `lib/kvs.sh` - `log_kvs()` 또는 `save_execution_log()`

**"SSH 원격 실행은?"**
→ `lib/remote_execution.sh` - `execute_remote_command()`

**"Gateway 서버 목록은?"**
→ `lib/gateway.sh` - `get_gateway_servers()`

**"DB 쿼리 목록은?"**
→ `lib/gateway.sh` - `get_db_queries()`

**"tManagedDatabase 목록은?"**
→ `lib/gateway.sh` - `get_managed_databases()`

---

**문서 작성일**: 2025-11-11  
**작성자**: AI Assistant  
**버전**: 1.0  
**최종 수정**: 2025-11-11 - 초판 작성 (pyodbc 중복 사고 재발 방지)
