#!/usr/bin/env bash
# tests/test-gate-summary.sh — 게이트 로그를 Linear 코멘트용 요약으로 렌더링한다.
# 핵심 계약: 로그 전문을 붙이지 않는다. 명령·exit code·로그 경로만 낸다.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/lib/assert.sh"
SCRIPT="$ROOT/.claude/skills/harness-architect/scripts/gate-summary.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/logs"

SECRETISH="STACKTRACE_LINE_THAT_MUST_NOT_LEAK"
cat > "$TMP/logs/fast.log" <<LOG
=== [fast] npm run lint
--- output
ok
--- exit 0

=== [fast] npm run typecheck
--- output
$SECRETISH
error TS2322: Type 'string'
--- exit 2

LOG

out="$(bash "$SCRIPT" fast "$TMP/logs")"; rc=$?
assert_exit_code 0 "$rc" "요약 렌더링 exit 0"
assert_contains "$out" "npm run lint"       "실행한 명령을 나열한다"
assert_contains "$out" "npm run typecheck"  "실패한 명령도 나열한다"
assert_contains "$out" "exit 0"             "성공 exit code 를 적는다"
assert_contains "$out" "exit 2"             "실패 exit code 를 적는다"
assert_contains "$out" "logs/fast.log"      "전문 로그 경로를 가리킨다"
assert_contains "$out" "1/2"                "통과 건수를 요약한다"

if [[ "$out" == *"$SECRETISH"* ]]; then
    echo "FAIL: 로그 전문이 새어 나왔다 (Linear 코멘트 노이즈 방지 규칙 위반)"
    FAILURES=$((FAILURES + 1))
else
    echo "PASS: 로그 전문을 붙이지 않는다"
fi

# 전부 통과한 경우
cat > "$TMP/logs/final.log" <<'LOG'
=== [final] npm run build
--- output
built
--- exit 0

LOG
out="$(bash "$SCRIPT" final "$TMP/logs")"
assert_contains "$out" "1/1" "전부 통과 시 1/1 로 요약한다"
if [[ "$out" == *"실패"* ]]; then
    echo "FAIL: 전부 통과인데 실패를 언급했다"; FAILURES=$((FAILURES + 1))
else
    echo "PASS: 전부 통과 시 실패를 언급하지 않는다"
fi

# 로그가 없을 때 — 조용히 빈 코멘트를 만들지 않는다
out="$(bash "$SCRIPT" feature "$TMP/logs" 2>&1)"; rc=$?
if [[ "$rc" -eq 0 ]]; then
    echo "FAIL: 없는 로그에 exit 0"; FAILURES=$((FAILURES + 1))
else
    echo "PASS: 로그가 없으면 non-zero exit (빈 코멘트를 만들지 않는다)"
fi

report_and_exit
