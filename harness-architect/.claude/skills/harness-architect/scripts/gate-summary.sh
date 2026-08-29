#!/usr/bin/env bash
# gate-summary.sh — 게이트 로그를 Linear 코멘트용 Markdown 요약으로 렌더링한다.
#
# 사용법:  gate-summary.sh <tier> [로그_디렉터리]   (기본값: _workspace/harness/gates)
# 출력:    stdout 에 Markdown. 그대로 save_comment 의 body 로 쓴다.
# 종료코드: 0 = 렌더링 성공 / 1 = 해당 tier 로그가 없다
#
# 계약: **로그 전문을 붙이지 않는다.** 명령·exit code·전문 로그 경로만 낸다.
# 실패 스택트레이스를 이슈 코멘트에 쏟으면 사람이 읽지 않게 되고, 정작 필요할 때
# 못 찾는다. 전문은 _workspace/ 에 보존되어 있으므로 경로만 가리키면 된다.
set -uo pipefail

TIER="${1:-}"
LOG_DIR="${2:-_workspace/harness/gates}"

if [[ -z "$TIER" ]]; then
    echo "gate-summary: tier 를 지정하십시오 (fast|feature|final)" >&2
    exit 1
fi

LOG="$LOG_DIR/$TIER.log"
if [[ ! -f "$LOG" ]]; then
    echo "gate-summary: 게이트 로그가 없습니다: $LOG" >&2
    echo "  run-gates.sh 를 먼저 실행하십시오. 로그 없이 코멘트를 만들지 않습니다." >&2
    exit 1
fi

# "=== [tier] 명령" 과 "--- exit N" 을 짝지어 읽는다. run-gates.sh 의 출력 형식이다.
summary="$(awk -v tier="$TIER" '
    /^=== \[/ { cmd = $0; sub(/^=== \[[^]]*\] /, "", cmd); next }
    /^--- exit / { code = $3; if (cmd != "") { printf "%s\t%s\n", code, cmd; cmd = "" } }
' "$LOG")"

total=0; failed=0
while IFS=$'\t' read -r code cmd; do
    [[ -n "${cmd:-}" ]] || continue
    total=$((total + 1))
    [[ "$code" -ne 0 ]] && failed=$((failed + 1))
done <<< "$summary"

passed=$((total - failed))

echo "**게이트 \`$TIER\` — $passed/$total 통과**"
echo
echo "| 명령 | 결과 |"
echo "|---|---|"
while IFS=$'\t' read -r code cmd; do
    [[ -n "${cmd:-}" ]] || continue
    if [[ "$code" -eq 0 ]]; then
        echo "| \`$cmd\` | exit $code |"
    else
        echo "| \`$cmd\` | **exit $code** |"
    fi
done <<< "$summary"
echo

if [[ "$failed" -gt 0 ]]; then
    echo "$failed 건 실패. 전체 출력: \`$LOG\`"
else
    echo "전체 출력: \`$LOG\`"
fi
