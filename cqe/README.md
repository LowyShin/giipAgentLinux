# CQE

CQE (Queue & Event) 관련 스크립트 및 문서

## 📄 파일 목록

### 실행 스크립트
- `giipCQE.sh` - CQE 메인 스크립트
- `giipCQECtrl.sh` - CQE 제어 스크립트
- `host-probe.cqe.sh` - 호스트 자유 질의 프로브 (GIIP #6233, Linux leg). 질문을 받아 결정적 사실을 수집하고 gair 경유로 조사한 뒤 결과를 tKVS에 저장한다 (`kType="<hostname>.probe"`). 사용법: `bash cqe/host-probe.cqe.sh <ProbeId> <Question>` — 테스트는 `bash tests/test-host-probe.sh` (오프라인, stub 사용)

### 문서
- `CQE_TEST_GUIDE.md` - CQE 테스트 가이드

## 🚀 사용법

```bash
# CQE 실행
bash giipCQE.sh

# CQE 제어 (시작/중지/상태 확인)
bash giipCQECtrl.sh [start|stop|status]
```

## 📖 참고

더 자세한 테스트 방법은 `CQE_TEST_GUIDE.md`를 참고하세요.

테스트 스크립트는 `../tests/test-cqe-queue.sh`에서 찾을 수 있습니다.
