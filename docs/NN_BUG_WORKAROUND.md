# MdbStatsUpdate NN 버그 우회 방법

**날짜**: 2025-12-29  
**수정자**: AI Agent  
**목적**: run.ps1의 NN 버그 우회 (run.ps1 수정 금지)

---

## 문제

**증상**:
```sql
exec pApiMdbStatsUpdatebySk '...', NN'[{...}]'
                                   ^^ N이 2개!
```

**원인**: run.ps1 L254, L298에서 N 접두사 중복 추가

---

## 해결 방법

**run.ps1 수정 금지** → Agent에서 우회

### 방법: text에 `0` 사용

**Before**:
```
text=MdbStatsUpdate jsondata
```

**After**:
```
text=MdbStatsUpdate 0
```

**run.ps1 처리**:
1. L247: `0`은 숫자 → `, 0` (N' 없음)
2. L313: `\b0\b` 패턴 매칭 → `N'[{...}]'` 치환
3. 결과: `exec ... N'[{...}]'` ✅

---

## 수정 파일

### 1. Linux Agent
**파일**: `giipAgentLinux/lib/check_managed_databases.sh`  
**라인**: 175

```bash
# Before
local text="MdbStatsUpdate jsondata"

# After
local text="MdbStatsUpdate 0"
```

### 2. Windows Agent
**파일**: `giipAgentWin/giipscripts/modules/DbMonitor.ps1`  
**라인**: 224

```powershell
# Before
$response = Invoke-GiipApiV2 -Config $Config -CommandText "MdbStatsUpdate jsondata" -JsonData $jsonPayload

# After
$response = Invoke-GiipApiV2 -Config $Config -CommandText "MdbStatsUpdate 0" -JsonData $jsonPayload
```

---

## 영향 범위

**변경됨**:
- ✅ Linux Agent (check_managed_databases.sh)
- ✅ Windows Agent (DbMonitor.ps1)

**변경 안됨**:
- ✅ run.ps1 (금지!)
- ✅ SP (pApiMdbStatsUpdatebySK)
- ✅ API 규격

---

## 관련 문서

- [NN_PREFIX_BUG_ANALYSIS.md](../../giipfaw/giipApiSk2/NN_PREFIX_BUG_ANALYSIS.md) - 근본 원인 분석
- [PROHIBITED_ACTION_2_RUN_PS1.md](../../giipdb/docs/PROHIBITED_ACTION_2_RUN_PS1.md) - run.ps1 수정 금지

---

**최종 수정**: 2025-12-29
