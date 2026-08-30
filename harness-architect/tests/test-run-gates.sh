#!/usr/bin/env bash
# tests/test-run-gates.sh — run-gates.sh 의 exit code 전파와 실패 출력 보존을 검증한다
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/lib/assert.sh"

SCRIPT="$ROOT/.claude/skills/harness-architect/scripts/run-gates.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- 성공 케이스: fast tier 의 두 명령이 모두 통과 ---
mkdir -p "$TMP/ok"
printf 'fast\techo LINT_OK\nfast\techo TYPE_OK\nfeature\techo TEST_OK\n' > "$TMP/ok/gates.tsv"
out="$(cd "$TMP/ok" && bash "$SCRIPT" fast gates.tsv logs 2>&1)"
rc=$?
assert_exit_code 0 "$rc" "성공: exit 0"
assert_file_exists "$TMP/ok/logs/fast.log" "성공: fast.log 생성"
log="$(cat "$TMP/ok/logs/fast.log")"
assert_contains "$log" "LINT_OK" "성공: 첫 명령 출력이 로그에 남는다"
assert_contains "$log" "TYPE_OK" "성공: 둘째 명령 출력이 로그에 남는다"
if [[ "$log" == *"TEST_OK"* ]]; then
    echo "FAIL: 성공: 다른 tier 명령은 실행되지 않아야 한다"
    FAILURES=$((FAILURES + 1))
else
    echo "PASS: 성공: 다른 tier 명령은 실행되지 않는다"
fi

# --- 실패 케이스: 실패 출력 전문 보존 + non-zero exit ---
mkdir -p "$TMP/fail"
LONG_MARKER="BOOM_LINE_MARKER_42"
printf 'fast\techo BEFORE_OK\n' >  "$TMP/fail/gates.tsv"
printf 'fast\tsh -c "echo %s >&2; exit 3"\n' "$LONG_MARKER" >> "$TMP/fail/gates.tsv"
printf 'fast\techo AFTER_STILL_RUNS\n' >> "$TMP/fail/gates.tsv"
out="$(cd "$TMP/fail" && bash "$SCRIPT" fast gates.tsv logs 2>&1)"
rc=$?
if [[ "$rc" -eq 0 ]]; then
    echo "FAIL: 실패: 게이트가 깨졌는데 exit 0 이면 안 된다"
    FAILURES=$((FAILURES + 1))
else
    echo "PASS: 실패: non-zero exit ($rc)"
fi
log="$(cat "$TMP/fail/logs/fast.log")"
assert_contains "$log" "$LONG_MARKER"    "실패: stderr 원문이 로그에 그대로 보존된다"
assert_contains "$log" "exit 3"          "실패: 실제 exit code 가 로그에 기록된다"
assert_contains "$log" "AFTER_STILL_RUNS" "실패: 첫 실패 후에도 남은 게이트를 모두 실행한다"
assert_contains "$out" "FAILED:"         "실패: stdout 에 FAILED 요약이 나온다"

# --- 빈 tier: 실행할 게 없으면 조용히 성공 ---
out="$(cd "$TMP/ok" && bash "$SCRIPT" final gates.tsv logs 2>&1)"
rc=$?
assert_exit_code 0 "$rc" "빈 tier: exit 0"

# --- gates.tsv 부재: 조용히 넘어가지 않고 실패한다 ---
mkdir -p "$TMP/missing"
out="$(cd "$TMP/missing" && bash "$SCRIPT" fast gates.tsv logs 2>&1)"
rc=$?
if [[ "$rc" -eq 0 ]]; then
    echo "FAIL: gates.tsv 부재: exit 0 이면 안 된다"
    FAILURES=$((FAILURES + 1))
else
    echo "PASS: gates.tsv 부재: non-zero exit"
fi

# --- 잘못된 tier 이름 ---
out="$(cd "$TMP/ok" && bash "$SCRIPT" bogus gates.tsv logs 2>&1)"
rc=$?
if [[ "$rc" -eq 0 ]]; then
    echo "FAIL: 잘못된 tier: exit 0 이면 안 된다"
    FAILURES=$((FAILURES + 1))
else
    echo "PASS: 잘못된 tier: non-zero exit"
fi

# 게이트 실행이 state.json 에 자동 기록된다
WS_AUTO="$(mktemp -d)"
printf 'fast\ttrue\n' > "$WS_AUTO/gates.tsv"
HARNESS_WORKSPACE="$WS_AUTO" bash "$SCRIPT" fast "$WS_AUTO/gates.tsv" "$WS_AUTO/logs" >/dev/null 2>&1
assert_file_exists "$WS_AUTO/state.json" "run-gates 실행 후 state 가 생긴다"
tiers="$(python3 -c 'import json,sys;print(",".join(g["tier"] for g in json.load(open(sys.argv[1]))["progress"]["gates"]))' "$WS_AUTO/state.json")"
assert_contains "$tiers" "fast" "게이트 결과를 자동 기록한다"

# 손상된 state 에서도 게이트 판정은 유지되고, 원본은 보존되며, 경고가 뜬다
printf '{ broken' > "$WS_AUTO/state.json"
before="$(cat "$WS_AUTO/state.json")"
err="$(HARNESS_WORKSPACE="$WS_AUTO" bash "$SCRIPT" fast "$WS_AUTO/gates.tsv" "$WS_AUTO/logs" 2>&1 >/dev/null)"; rc=$?
assert_exit_code 0 "$rc" "checkpoint 실패가 게이트 exit code 를 바꾸지 않는다"
assert_eq "$before" "$(cat "$WS_AUTO/state.json")" "손상된 state 원본이 보존된다"
assert_contains "$err" "checkpoint" "기록 실패를 stderr 로 알린다"
rm -rf "$WS_AUTO"

report_and_exit
