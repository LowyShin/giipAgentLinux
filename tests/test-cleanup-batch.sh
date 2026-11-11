#!/bin/bash
# Test: lib/cleanup.sh 배치 삭제 (단일 find 패스, 파일별 fork 없음)
#   - 오래된(>10분) + 비어있지 않음 + 패턴 일치 파일 20000+ 개는 삭제된다
#   - 최근 파일(<10분), 현재 PID 가 이름에 들어간 파일, 빈 파일, 패턴 불일치 파일은 그대로
#   - 10초 안에 끝난다
#
# Usage: bash tests/test-cleanup-batch.sh

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CLEANUP="${SCRIPT_DIR}/../lib/cleanup.sh"

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export GIIP_TMP_DIR="$T"
OLD='2 hours ago'
N=20000

echo "[setup] creating $N old matching files in $T ..."
# 대량 생성은 fork 최소화: 한 번의 xargs touch
i=0
{
	while [ $i -lt $N ]; do
		echo "$T/auto_discover_result_$((100000+i)).json"
		i=$((i+1))
	done
} > "$T/.list"
xargs -a "$T/.list" -n 2000 sh -c 'for f; do echo x > "$f"; done' _
xargs -a "$T/.list" -n 2000 touch -d "$OLD"
rm -f "$T/.list"
# 다른 패턴에서도 일부
for p in kvs_put_response_77 giipAgent_gateway_88 db_check_results_99.jsonl; do
	echo x > "$T/$p"; touch -d "$OLD" "$T/$p"
done

# 유지되어야 하는 파일들
echo x > "$T/auto_discover_result_recent.json"                 # 최근
CUR_SHELL_PID=$$
echo x > "$T/auto_discover_result_${CUR_SHELL_PID}.json"; touch -d "$OLD" "$T/auto_discover_result_${CUR_SHELL_PID}.json"
: > "$T/auto_discover_result_empty.json"; touch -d "$OLD" "$T/auto_discover_result_empty.json"   # 빈 파일
echo x > "$T/unrelated_file.json"; touch -d "$OLD" "$T/unrelated_file.json"                     # 패턴 불일치
echo x > "$T/auto_discover_result_x.json.keep"; touch -d "$OLD" "$T/auto_discover_result_x.json.keep"

# cleanup_all_temp_files 는 current_pid=$$ 를 쓴다. 이 서브셸이 아닌 호출 셸의 $$ 와 같도록
# 같은 셸에서 source 해서 호출한다.
. "$CLEANUP"

start=$(date +%s)
out=$(cleanup_all_temp_files 2>&1)
end=$(date +%s)
elapsed=$((end-start))
echo "$out"

# current_pid=$$ 는 서브셸($(...))에서도 부모 PID 를 돌려준다(bash $$ 의미) -> 같은 값
[ -e "$T/auto_discover_result_${CUR_SHELL_PID}.json" ] && ok "PID-in-name file kept" || fail "PID-in-name file deleted"
[ -e "$T/auto_discover_result_recent.json" ] && ok "recent file kept" || fail "recent file deleted"
[ -e "$T/auto_discover_result_empty.json" ] && ok "empty file kept" || fail "empty file deleted"
[ -e "$T/unrelated_file.json" ] && ok "non-matching file kept" || fail "non-matching file deleted"
[ -e "$T/auto_discover_result_x.json.keep" ] && ok "non-matching suffix file kept" || fail "suffix file deleted"

left=$(find "$T" -maxdepth 1 -name 'auto_discover_result_1*.json' ! -name "*_${CUR_SHELL_PID}.json" | wc -l | tr -d ' ')
[ "$left" -eq 0 ] && ok "all $N old matching files deleted" || fail "$left old matching files remain"
for p in kvs_put_response_77 giipAgent_gateway_88 db_check_results_99.jsonl; do
	[ ! -e "$T/$p" ] && ok "$p deleted" || fail "$p remains"
done
echo "$out" | grep -q "Cleaned up $((N+3)) old files" && ok "message reports $((N+3)) files" || fail "count message mismatch"
LIMIT=10
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) LIMIT=60; echo "  NOTE: Windows/MSYS host - NTFS unlink is slow, limit relaxed to ${LIMIT}s (Linux: 10s)";; esac
[ "$elapsed" -lt "$LIMIT" ] && ok "finished in ${elapsed}s (<${LIMIT}s)" || fail "took ${elapsed}s (limit ${LIMIT}s)"

# cleanup_old_temp_files 호환 함수 (단일 패턴)
echo x > "$T/remote_profile_5.json"; touch -d "$OLD" "$T/remote_profile_5.json"
echo x > "$T/remote_profile_6.json"
out2=$(cleanup_old_temp_files "remote_profile_*.json")
[ ! -e "$T/remote_profile_5.json" ] && [ -e "$T/remote_profile_6.json" ] && ok "cleanup_old_temp_files single pattern" || fail "cleanup_old_temp_files behaviour"

echo "RESULT: pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
