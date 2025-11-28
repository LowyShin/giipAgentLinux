# Queue Get 함수 문제 분석 보고서

## 현재 상황
테스트 실행 결과: `queue_get` 함수 실행 실패

```
[queue_get] ⚠️  Missing required variables (sk, apiaddrv2)
```

## 문제 분석

### 1️⃣ **근본 원인: 환경 변수 스코프 문제**

**문제의 흐름:**
```
main script (test-queue-get.sh)
    ↓
    source ../giipAgent.cnf  (sk, apiaddrv2 로드)  ✅
    ↓
    test_queue_get() 함수 호출
    ↓
    wrapper_script 생성 및 실행
    ↓
    bash $wrapper_script (새로운 bash 프로세스)  ⚠️
    ↓
    wrapper에서 common.sh, cqe.sh 소스
    ↓
    queue_get 호출 → sk, apiaddrv2 찾을 수 없음 ❌
```

**왜 안 되는가?**
- 메인 스크립트에서 `sk`, `apiaddrv2`를 환경 변수로 로드
- 하지만 `export` 하지 않음 (내부 변수로만 존재)
- `bash wrapper_script` 실행 시 새로운 bash 프로세스 생성
- 새 프로세스는 부모의 내부 변수에 접근 불가능
- export된 환경 변수만 자식 프로세스에 전달됨

### 2️⃣ **기존 시스템의 해결 방법**

**giipAgent3.sh에서는 어떻게 하는가?**

```bash
# common.sh의 load_config() 함수
load_config() {
    . "$config_file"  # 설정 파일 소스
    
    # 유효성 검사 후
    if [ -z "${lssn}" ] || [ -z "${sk}" ] || [ -z "${apiaddrv2}" ]; then
        echo "❌ Error: Missing required configuration"
        return 1
    fi
}
```

→ giipAgent3.sh는 항상 **같은 프로세스**에서 실행되므로 문제 없음
→ 테스트 스크립트는 **새로운 bash 프로세스**를 생성해서 문제 발생

### 3️⃣ **해결책 3가지**

#### **옵션 A: 환경 변수 Export (권장)**
```bash
# test-queue-get.sh에서
export sk
export apiaddrv2
export apiaddrcode

# 그 후 wrapper 실행
```
✅ 가장 간단하고 일반적인 방법
✅ 스크립트 변경 최소화
❌ 보안: 환경 변수로 노출됨

#### **옵션 B: Wrapper에서 config 직접 로드**
```bash
# wrapper_script 내에서
. "../giipAgent.cnf"  # 설정 파일을 직접 로드
queue_get ...
```
✅ 별도 설정 파일 로드 - 명시적이고 안전
✅ 기존 패턴과 일관성
❌ Wrapper가 config 파일 경로를 알아야 함

#### **옵션 C: Wrapper를 서브쉘이 아닌 같은 쉘에서 실행**
```bash
# . wrapper_script 로 source로 실행 (subshell 아님)
```
✅ 부모의 모든 변수 상속
❌ Timeout이 작동하지 않음 (같은 쉘에서 실행되므로)

## 권장 해결책

### **옵션 A + B 조합 (최적)**

**test-queue-get.sh에서:**
```bash
# 1. 환경 변수 export
export sk apiaddrv2 apiaddrcode

# 2. Wrapper도 설정 파일 로드하도록 수정
```

**이유:**
- 보안: 두 가지 방식으로 중복 확보
- 안정성: 설정 파일 로드 실패 시 export된 변수 사용 가능
- 유연성: 어느 한쪽이라도 작동

## 구현 체크리스트

- [ ] test-queue-get.sh에서 설정 로드 후 export
- [ ] wrapper_script도 설정 파일 로드 추가
- [ ] queue_get 실행 전 변수 값 검증 추가
- [ ] 문제 재현 확인
- [ ] 테스트 성공 확인

## 다음 단계

1. **즉시 수정**: export 추가 (1줄)
2. **추가 수정**: wrapper에서 설정 파일 로드 (안정성)
3. **테스트**: 실제 실행하여 검증
4. **문서화**: 해결 방법을 주석으로 기록
