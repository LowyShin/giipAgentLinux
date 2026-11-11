#!/bin/bash
# Test: giipAgent3.sh 의 singleton-guard (flock / mkdir 폴백)
#   guard 블록(`# >>> singleton-guard` ~ `# <<< singleton-guard`)을 sed -n 으로 추출해
#   임시 락 경로로 실행한다.
#   (A) flock 경로: 1번 인스턴스가 락 보유 중 2번은 1초 안에 exit 0 + [singleton] 출력, 종료 후 재획득
#   (B) mkdir 폴백(GIIP_FORCE_NO_FLOCK=1): 동일 시나리오 + stale(죽은 PID) 인수
#
# Usage: bash tests/test-single-instance.sh

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
TARGET="${SCRIPT_DIR}/../giipAgent3.sh"

PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS+1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

sed -n '/^# >>> singleton-guard/,/^# <<< singleton-guard/p' "$TARGET" > "$T/guard.sh"
[ -s "$T/guard.sh" ] && ok "guard block extracted ($(wc -l < "$T/guard.sh") lines)" || { fail "guard block not found"; echo "RESULT: pass=$PASS fail=$FAIL"; exit 1; }

# 인스턴스 스크립트: guard + 지정 초 sleep + 'ran' 출력
cat > "$T/inst.sh" <<EOF
#!/bin/bash
. "$T/guard.sh"
echo "acquired pid=\$\$"
sleep "\${HOLD:-0}"
EOF

run_scenario() {
	local label=$1 lock="$T/lock-$1"
	export GIIP_LOCK_FILE="$lock"
	echo "[scenario] $label"

	HOLD=3 bash "$T/inst.sh" > "$T/out1-$label" 2>&1 &
	local p1=$!
	# 인스턴스 1 이 락을 잡을 때까지 대기
	local w=0
	while ! grep -q acquired "$T/out1-$label" 2>/dev/null && [ $w -lt 50 ]; do sleep 0.1; w=$((w+1)); done
	grep -q acquired "$T/out1-$label" && ok "$label: instance 1 acquired" || fail "$label: instance 1 did not acquire"

	local s e rc
	s=$(date +%s%N 2>/dev/null || echo 0)
	bash "$T/inst.sh" > "$T/out2-$label" 2>&1; rc=$?
	e=$(date +%s%N 2>/dev/null || echo 0)
	[ "$rc" -eq 0 ] && ok "$label: instance 2 exit code 0" || fail "$label: instance 2 exit code $rc"
	grep -q '^\[singleton\]' "$T/out2-$label" && ok "$label: instance 2 printed [singleton]" || fail "$label: no [singleton] line"
	grep -q acquired "$T/out2-$label" && fail "$label: instance 2 ran the body" || ok "$label: instance 2 did not run body"
	if [ "$s" != 0 ]; then
		local ms=$(( (e-s)/1000000 ))
		[ "$ms" -lt 1000 ] && ok "$label: instance 2 exited in ${ms}ms (<1s)" || fail "$label: instance 2 took ${ms}ms"
	fi

	wait "$p1"
	bash "$T/inst.sh" > "$T/out3-$label" 2>&1; rc=$?
	grep -q acquired "$T/out3-$label" && [ "$rc" -eq 0 ] && ok "$label: new run acquires after instance 1 ended" || fail "$label: new run did not acquire"
}

if command -v flock >/dev/null 2>&1; then
	unset GIIP_FORCE_NO_FLOCK
	run_scenario flock
else
	SKIP=$((SKIP+1)); echo "  SKIP: flock not installed on this host - flock path not tested"
fi

export GIIP_FORCE_NO_FLOCK=1
run_scenario mkdir

# stale 인수: 존재하지 않는 PID 를 가진 락 디렉터리
export GIIP_LOCK_FILE="$T/lock-stale"
mkdir "$GIIP_LOCK_FILE.d"; echo 999999 > "$GIIP_LOCK_FILE.d/pid"
bash "$T/inst.sh" > "$T/out-stale" 2>&1; rc=$?
grep -q acquired "$T/out-stale" && [ "$rc" -eq 0 ] && ok "mkdir: stale lock (dead PID) taken over" || fail "mkdir: stale lock not taken over"
[ ! -d "$GIIP_LOCK_FILE.d" ] && ok "mkdir: lock dir removed on exit" || fail "mkdir: lock dir left behind"

echo "RESULT: pass=$PASS fail=$FAIL skip=$SKIP"
[ "$FAIL" -eq 0 ]
