# giipAgent3 변경 이력 (CHANGELOG)

> **📅 문서 메타데이터**  
> - 최초 작성: 2025-11-11  
> - 최종 수정: 2025-12-28  
> - 목적: giipAgent3 주요 변경 사항 기록

---

## 2025-12-28

### Database Check Python 외부 파일 분리
- **변경**: check_managed_databases.sh의 Python 인라인 코드를 외부 파일로 분리
- **파일**: 
  - `lib/parse_managed_db_list.py` (신규)
  - `lib/extract_db_types.py` (신규)
- **이유**: Bash 따옴표 충돌 방지, EOF 에러 해결
- **영향**: Database Check 기능 정상 작동

### Net3D 외부 스크립트화
- **변경**: Net3D 수집을 외부 스크립트로 분리
- **파일**: `scripts/net3d_mode.sh` (신규)
- **이유**: 사용자 설계 원칙 준수 (외부 스크립트 호출만)
- **영향**: Gateway/Normal Mode 정상 실행

---

## 2025-12-04

### 외부 스크립트 호출 구조 상세화
- **변경**: 섹션 5.3 신규 추가
- **내용**: giipAgent3.sh → scripts/ → gateway/ 호출 흐름 명확화
- **문서**: GIIPAGENT3_SPECIFICATION.md

---

## 2025-11-27

### 실행 흐름 확정
- **변경**: Gateway + Normal 독립 실행 규칙 확정
- **구조**: `if` 문 (else ❌)
- **규칙**: Normal Mode 항상 실행, Shutdown log fi 다음 한 번만

### 모듈 통합
- **추가**: kvs.sh, cleanup.sh, target_list.sh
- **변경**: giipAgent3.sh 306 lines
- **영향**: 모듈 로드 순서 변경

---

## 2025-11-22

### Gateway 큐 처리 추가
- **문제**: Gateway LSChkdt 업데이트 안됨
- **해결**: gateway.sh에 normal.sh 로드 추가
- **영향**: Gateway도 자신의 큐 처리 가능

### 타임스탬프 정책 변경
- **변경**: JSON에서 timestamp 필드 제거
- **이유**: 클라이언트-서버 시간 차이
- **해결**: DB 레벨에서 GETUTCDATE() 사용

---

## 2025-11-11

### 초안 작성
- **파일**: GIIPAGENT3_SPECIFICATION.md
- **내용**: 전체 구조 및 모듈 명세

---

**관련 문서**:
- [GIIPAGENT3_SPECIFICATION.md](./GIIPAGENT3_SPECIFICATION.md) - 사양서
- [AI_AGENT_GUIDELINES.md](./AI_AGENT_GUIDELINES.md) - AI 작업 규칙
