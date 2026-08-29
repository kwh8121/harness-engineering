#!/usr/bin/env bash
# run-gates.sh — 지정한 tier 의 결정론적 게이트를 전부 실행하고 exit code 를 집계한다.
#
# 사용법:  run-gates.sh <tier> [gates.tsv] [로그_디렉터리]
#   tier          fast | feature | final
#   gates.tsv     기본값 _workspace/harness/gates.tsv  (detect-stack.sh 산출물)
#   로그_디렉터리  기본값 _workspace/harness/gates
#
# 종료코드: 0 = 전부 통과 (실행할 게 없어도 0) / 1 = 하나 이상 실패 / 2 = 사용법·입력 오류
#
# 설계 원칙: 이 스크립트의 exit code 가 "코드가 정상인가"에 대한 유일한 진실이다.
# AI 리뷰어에게 "린트 문제 찾아봐"라고 시키지 않는다.
# 그리고 실패 출력은 절대 잘라내지 않는다 — 잘린 스택트레이스는 잘못된 수정을 부른다.
set -uo pipefail

TIER="${1:-}"
GATES_TSV="${2:-_workspace/harness/gates.tsv}"
LOG_DIR="${3:-_workspace/harness/gates}"

case "$TIER" in
    fast|feature|final) ;;
    "")  echo "run-gates: tier 를 지정하십시오 (fast|feature|final)" >&2; exit 2 ;;
    *)   echo "run-gates: 알 수 없는 tier '$TIER' (fast|feature|final 중 하나여야 합니다)" >&2; exit 2 ;;
esac

if [[ ! -f "$GATES_TSV" ]]; then
    echo "run-gates: 게이트 목록이 없습니다: $GATES_TSV" >&2
    echo "  먼저 detect-stack.sh 를 실행해 생성하십시오." >&2
    exit 2
fi

mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/$TIER.log"
: > "$LOG"

total=0
failed=0
failed_cmds=()

while IFS=$'\t' read -r tier cmd; do
    [[ "$tier" == "$TIER" ]] || continue
    [[ -n "${cmd:-}" ]] || continue
    total=$((total + 1))

    {
        echo "=== [$TIER] $cmd"
        echo "--- output"
    } >> "$LOG"

    # stdout·stderr 를 합쳐 통째로 보존한다.
    # 이 스크립트는 errexit(-e)을 켜지 않는다 — 게이트가 실패해도 남은 게이트를 모두 돌려야
    # 실패가 하나인지 여럿인지 알 수 있고, 그래야 원인을 좁힐 수 있다.
    eval "$cmd" >> "$LOG" 2>&1
    rc=$?

    echo "--- exit $rc" >> "$LOG"
    echo >> "$LOG"

    if [[ "$rc" -ne 0 ]]; then
        failed=$((failed + 1))
        failed_cmds+=("$cmd")
    fi
done < "$GATES_TSV"

if [[ "$total" -eq 0 ]]; then
    echo "run-gates: tier '$TIER' 에 실행할 게이트가 없습니다 (통과로 간주)."
    exit 0
fi

if [[ "$failed" -gt 0 ]]; then
    echo "run-gates: $TIER — $failed/$total 실패. 전체 출력: $LOG"
    for c in "${failed_cmds[@]}"; do
        echo "FAILED: $c"
    done
    exit 1
fi

echo "run-gates: $TIER — $total/$total 통과. 로그: $LOG"
exit 0
