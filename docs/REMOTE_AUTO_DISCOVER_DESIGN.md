# 리모트 서버 Auto-Discover 설계 문서

**작성일**: 2025-11-27  
**버전**: 1.0  
**상태**: 제안 (실장 전 검토 필요)

---

## 📋 개요

현재 auto-discover는 로컬 서버(Gateway)에서만 실행되고 있습니다. 이 문서는 Gateway가 관리하는 리모트 서버들의 인프라 정보를 SSH를 통해 수집하는 방법을 제안합니다.

### 목표
- ✅ 기존 로컬 auto-discover 기능 유지 (무영향)
- ✅ 리모트 서버 SSH auto-discover 신규 추가
- ✅ KVS에 리모트 서버 정보 저장
- ✅ 기존 STEP-1~7 구조 재사용

---

## 🏗️ 아키텍처 설계

### 현재 상태
```
Gateway Server (LSSN=X)
    ↓
run_auto_discover() [로컬만]
    ├── STEP-1: 설정 검증
    ├── STEP-2: 스크립트 경로 검증
    ├── STEP-3: KVS 초기화
    ├── STEP-4: auto-discover-linux.sh 실행 [로컬 서버만]
    ├── STEP-5: 결과 검증
    ├── STEP-6: 데이터 추출 및 저장
    └── STEP-7: 완료 마킹
```

### 제안하는 구조
```
Gateway Server (LSSN=X)
    ├── Local Auto-Discover [기존 - 무변경]
    │   └── run_auto_discover() [로컬]
    │
    └── Remote Auto-Discover [신규 - 영향 없음]
        └── run_remote_auto_discover() [리모트 SSH]
            ├── SSH 연결 확인
            ├── auto-discover-linux.sh 전송/실행
            ├── 결과 수집
            └── KVS 저장
```

---

## 📐 상세 설계

### 1. 새로운 함수 구조 (lib/discovery.sh 확장)

#### 1.1 메인 함수: `run_remote_auto_discover()`
```bash
run_remote_auto_discover() {
    local target_lssn="$1"      # 리모트 서버 LSSN
    local ssh_user="$2"          # SSH 사용자 (예: root)
    local ssh_host="$3"          # 리모트 호스트
    local ssh_port="${4:-22}"    # SSH 포트 (기본: 22)
    local ssh_key="${5:-}"       # SSH 개인키 경로
    
    # STEP-1: SSH 연결 검증
    # STEP-2: 스크립트 전송
    # STEP-3: KVS 초기화 (리모트 마커)
    # STEP-4: SSH로 스크립트 실행
    # STEP-5: 결과 검증
    # STEP-6: 데이터 추출 및 저장
    # STEP-7: 완료 마킹
}
```

#### 1.2 헬퍼 함수들
```bash
# SSH 연결 테스트
_remote_auto_discover_step1_ssh_check()

# 스크립트 전송
_remote_auto_discover_step2_transfer_script()

# KVS 초기화
_remote_auto_discover_step3_init_kvs()

# 리모트 스크립트 실행
_remote_auto_discover_step4_execute_remote()

# 결과 수집
_remote_auto_discover_step5_retrieve_result()

# 결과 검증
_remote_auto_discover_step6_validate()

# 데이터 추출 및 KVS 저장
_remote_auto_discover_step7_extract_and_store()

# 완료 마킹
_remote_auto_discover_step8_complete()
```

---

## 🔄 실행 흐름

### Gateway에서의 실행 순서 (lib/gateway.sh 수정)

```bash
# ================================================================
# 게이트웨이 사이클 내 auto-discover 부분
# ================================================================

# 1. 로컬 auto-discover (기존 - 무변경)
log_message "INFO" "Running local auto-discover..."
if run_auto_discover "${lssn}" "${hn}" "${os}" "${SCRIPT_DIR}"; then
    log_message "INFO" "Local auto-discover completed"
else
    log_message "WARN" "Local auto-discover failed"
fi

# 2. 리모트 auto-discover (신규 - 추가)
log_message "INFO" "Running remote auto-discover for managed servers..."

# DB에서 관리 대상 서버 목록 조회
while IFS='|' read -r remote_lssn remote_host remote_user remote_port remote_key; do
    [ -z "$remote_lssn" ] && continue  # 빈 줄 스킵
    
    log_message "INFO" "Auto-discovering remote server: LSSN=$remote_lssn, Host=$remote_host"
    
    if run_remote_auto_discover "$remote_lssn" "$remote_user" "$remote_host" \
                                 "$remote_port" "$remote_key"; then
        log_message "INFO" "Remote auto-discover completed for LSSN=$remote_lssn"
    else
        log_message "WARN" "Remote auto-discover failed for LSSN=$remote_lssn"
    fi
done < <(fetch_managed_servers_for_discovery)
```

---

## 💾 KVS 저장 구조

### 로컬 서버 (기존)
```
kType=lssn, kKey=71240, kFactor=auto_discover_result
kValue: {hostname, os, cpu, memory, networks, services, ...}

kType=lssn, kKey=71240, kFactor=auto_discover_networks
kValue: [{name, ipv4, mac}, ...]

kType=lssn, kKey=71240, kFactor=auto_discover_services
kValue: [{name, status, ...}, ...]
```

### 리모트 서버 (신규)
```
# 리모트 서버도 동일한 구조로 저장됨 (target_lssn 사용)
kType=lssn, kKey=72001, kFactor=auto_discover_result
kValue: {hostname, os, cpu, memory, networks, services, ...}  [리모트 서버 정보]

kType=lssn, kKey=72001, kFactor=auto_discover_remote_metadata
kValue: {
    "remote_host": "192.168.1.100",
    "ssh_port": 22,
    "executed_from": 71240,
    "execution_timestamp": "2025-11-27T10:30:00Z"
}
```

---

## 🔐 보안 고려사항

### SSH 인증 방식
```bash
# 옵션 1: SSH 키 기반 인증 (권장)
ssh -i /path/to/private_key -p 22 root@192.168.1.100 "bash /tmp/auto-discover-linux.sh"

# 옵션 2: sshpass를 사용한 비밀번호 인증 (대체)
sshpass -p "$PASSWORD" ssh -p 22 root@192.168.1.100 "bash /tmp/auto-discover-linux.sh"

# 옵션 3: SSH agent (기존 커넥션 재사용)
# gateway.sh의 ssh_connection.sh에서 이미 구현됨
```

### SSH 키 관리
```bash
# 권장 경로
/root/.ssh/giip_remote_key    # Gateway → Remote 연결용
/root/.ssh/id_rsa              # 기본 키 (대체)

# 권한 설정
chmod 600 /root/.ssh/giip_remote_key
chmod 700 /root/.ssh
```

---

## 📊 구현 단계

### Phase 1: 기본 구조 (1주)
- [ ] `run_remote_auto_discover()` 메인 함수 작성
- [ ] SSH 연결 검증 함수 (`_remote_auto_discover_step1_ssh_check`)
- [ ] 스크립트 전송 함수 (`_remote_auto_discover_step2_transfer_script`)
- [ ] 단위 테스트 (테스트 서버 1대)

### Phase 2: 실행 및 결과 수집 (1주)
- [ ] 리모트 실행 함수 (`_remote_auto_discover_step4_execute_remote`)
- [ ] 결과 수집 함수 (`_remote_auto_discover_step5_retrieve_result`)
- [ ] 검증 함수 (`_remote_auto_discover_step6_validate`)
- [ ] 통합 테스트 (테스트 서버 3대)

### Phase 3: KVS 저장 및 완성 (1주)
- [ ] 데이터 추출 및 저장 (`_remote_auto_discover_step7_extract_and_store`)
- [ ] 완료 마킹 (`_remote_auto_discover_step8_complete`)
- [ ] 에러 처리 및 재시도 로직
- [ ] 성능 테스트 (다중 리모트 동시 실행)

### Phase 4: 기존 코드와 통합 (1주)
- [ ] lib/gateway.sh 수정 (remote auto-discover 호출 추가)
- [ ] KVS 저장 구조 확인
- [ ] 엔드-투-엔드 테스트
- [ ] 문서화 및 배포

---

## 🔗 기존 코드와의 연계

### 영향 받는 파일
- `lib/discovery.sh` - **추가 함수만 추가** (기존 함수 무변경)
- `lib/gateway.sh` - **remote 루프 추가** (기존 로직 무변경)
- `giipAgent3.sh` - **무변경**

### 기존 코드 유지 방법
```bash
# 1. 기존 run_auto_discover() 함수 100% 유지
run_auto_discover() {
    # 기존 코드 그대로 - 변경 없음
}

# 2. 새로운 함수는 완전히 별도
run_remote_auto_discover() {
    # 신규 함수 - 기존과 무관
}

# 3. 호출 위치는 gateway.sh 내에서 분리
# 로컬 auto-discover (기존)
run_auto_discover "${lssn}" "${hn}" "${os}" "${SCRIPT_DIR}"

# 리모트 auto-discover (신규 - 루프)
while read remote_server; do
    run_remote_auto_discover ...
done
```

---

## 📈 기대 효과

| 항목 | 현재 | 향후 |
|------|------|------|
| **Coverage** | Gateway만 | Gateway + 모든 리모트 서버 |
| **KVS 데이터** | 1개 서버 정보 | N개 서버 정보 |
| **모니터링** | 부분적 | 전체 인프라 가시성 |
| **용량 계획** | 불완전 | 완전 자동화 |
| **기존 코드 영향** | - | 0% (완전 독립) |

---

## ⚠️ 고려사항 및 제한사항

### 1. SSH 연결 안정성
- **문제**: 네트워크 지연, 타임아웃
- **대안**: 재시도 로직, 타임아웃 설정 (기존 ssh_connection.sh 활용)

### 2. 리모트 서버의 auto-discover-linux.sh
- **전제**: 리모트 서버에도 bash 3.2+ 필요
- **해결**: /tmp에 스크립트 전송 후 실행

### 3. 대규모 환경 (100+ 서버)
- **문제**: 순차 실행 시 시간 소요
- **대안**: 병렬 처리 (GNU parallel 또는 xargs)
  ```bash
  fetch_managed_servers | parallel -j 5 "run_remote_auto_discover {}"
  ```

### 4. 인증 정보 보안
- **권장**: SSH 키 기반 (암호 없음)
- **피할 것**: 스크립트에 평문 비밀번호 저장
- **방법**: KVS에서 암호화된 키 경로 조회

---

## 🧪 테스트 시나리오

### 단위 테스트
```bash
# 테스트 1: SSH 연결 검증
run_remote_auto_discover 72001 root 192.168.1.100 22 /root/.ssh/giip_remote_key
# 예상: STEP-1 통과, STEP-2부터는 스킵 (테스트용)

# 테스트 2: 스크립트 전송
# 예상: /tmp/auto-discover-linux.sh 전송 확인

# 테스트 3: 리모트 실행
# 예상: SSH 명령 실행, JSON 결과 반환
```

### 통합 테스트
```bash
# 테스트: 3개 리모트 서버 동시 auto-discover
# 예상: 각 서버별 KVS 저장 성공
# 확인: 
#   kType=lssn kKey=72001 kFactor=auto_discover_result
#   kType=lssn kKey=72002 kFactor=auto_discover_result
#   kType=lssn kKey=72003 kFactor=auto_discover_result
```

---

## 📝 구현 예시 (의사 코드)

### 핵심 함수 스켈레톤
```bash
# ============================================================================
# Remote Auto-Discover Main Function
# ============================================================================
run_remote_auto_discover() {
    local target_lssn="$1"
    local ssh_user="$2"
    local ssh_host="$3"
    local ssh_port="${4:-22}"
    local ssh_key="${5:-/root/.ssh/id_rsa}"
    
    log_message "INFO" "Starting remote auto-discover for LSSN=$target_lssn"
    
    # STEP-1: SSH 연결 검증
    _remote_auto_discover_step1_ssh_check "$ssh_user" "$ssh_host" "$ssh_port" "$ssh_key" || return 1
    
    # STEP-2: 스크립트 전송
    _remote_auto_discover_step2_transfer_script "$ssh_user" "$ssh_host" "$ssh_port" "$ssh_key" || return 1
    
    # STEP-3: KVS 초기화 (리모트 마커)
    _remote_auto_discover_step3_init_kvs "$target_lssn" || return 1
    
    # STEP-4: 리모트 스크립트 실행
    local result_file=$(_remote_auto_discover_step4_execute_remote \
        "$ssh_user" "$ssh_host" "$ssh_port" "$ssh_key" "$target_lssn")
    [ -z "$result_file" ] && return 1
    
    # STEP-5: 결과 수집 및 검증
    _remote_auto_discover_step5_retrieve_result "$result_file" || return 1
    
    # STEP-6: 데이터 추출 및 KVS 저장
    _remote_auto_discover_step6_validate "$result_file" || return 1
    _remote_auto_discover_step7_extract_and_store "$result_file" "$target_lssn" || return 1
    
    # STEP-7: 완료 마킹
    _remote_auto_discover_step8_complete "$target_lssn" || return 1
    
    log_message "INFO" "Remote auto-discover completed successfully for LSSN=$target_lssn"
    return 0
}

# ============================================================================
# Helper Functions
# ============================================================================

_remote_auto_discover_step1_ssh_check() {
    local ssh_user="$1"
    local ssh_host="$2"
    local ssh_port="$3"
    local ssh_key="$4"
    
    # SSH 연결 테스트
    ssh -i "$ssh_key" -p "$ssh_port" -o ConnectTimeout=5 \
        "$ssh_user@$ssh_host" "hostname" >/dev/null 2>&1
    
    return $?
}

_remote_auto_discover_step2_transfer_script() {
    local ssh_user="$1"
    local ssh_host="$2"
    local ssh_port="$3"
    local ssh_key="$4"
    
    # auto-discover-linux.sh 전송
    scp -i "$ssh_key" -P "$ssh_port" \
        "$SCRIPT_DIR/giipscripts/auto-discover-linux.sh" \
        "$ssh_user@$ssh_host:/tmp/" >/dev/null 2>&1
    
    return $?
}

_remote_auto_discover_step4_execute_remote() {
    local ssh_user="$1"
    local ssh_host="$2"
    local ssh_port="$3"
    local ssh_key="$4"
    local target_lssn="$5"
    
    local remote_result="/tmp/auto_discover_result_$$.json"
    
    # 리모트에서 스크립트 실행
    ssh -i "$ssh_key" -p "$ssh_port" \
        "$ssh_user@$ssh_host" \
        "bash /tmp/auto-discover-linux.sh $target_lssn $(hostname -f) $(uname -s)" \
        > "$remote_result" 2>&1
    
    echo "$remote_result"
}
```

---

## ✅ 체크리스트

### 설계 검토
- [ ] 기존 코드 무영향 확인
- [ ] SSH 보안 정책 검토
- [ ] KVS 저장 구조 승인
- [ ] 성능 요구사항 정의 (최대 리모트 서버 수)

### 구현 전
- [ ] 테스트 환경 준비 (3개 리모트 서버)
- [ ] SSH 키 생성 및 배포
- [ ] auto-discover-linux.sh 호환성 확인 (리모트 OS)
- [ ] 에러 처리 전략 수립

### 구현 후
- [ ] 단위 테스트 완료
- [ ] 통합 테스트 완료
- [ ] 성능 테스트 완료
- [ ] 문서 업데이트
- [ ] 운영 배포

---

## 📚 참고 자료

- 현재 코드: `lib/discovery.sh` - `run_auto_discover()` 함수 참고
- SSH 연결: `lib/ssh_connection.sh` - SSH 재시도 로직 참고
- KVS 저장: `lib/kvs.sh` - `kvs_put()` 함수 참고
- Gateway 운영: `lib/gateway.sh` - 서버 루프 패턴 참고

---

**다음 단계**: 이 설계 문서를 검토한 후, Phase 1 구현 시작을 승인해주세요.
