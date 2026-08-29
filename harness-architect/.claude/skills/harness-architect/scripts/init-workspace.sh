#!/usr/bin/env bash
# init-workspace.sh — 하네스 실행에 쓸 _workspace 골격을 만들고 스택을 감지한다.
#
# 사용법:  init-workspace.sh [프로젝트_디렉터리]     (기본값: 현재 디렉터리)
# 산출물:
#   _workspace/harness/gates.tsv    감지된 결정론적 게이트 (없으면 빈 파일 + 경고)
#   _workspace/harness/gates/       게이트 실행 로그가 쌓일 곳
#   _workspace/harness/research/    dependency-mapper · baseline-tester 보고서
#   _workspace/harness/review/      reviewer 보고서
#
# 종료코드: 0 = 게이트 감지 성공 / 3 = 골격은 만들었으나 스택 미감지 (사람에게 물어야 함)
set -uo pipefail

PROJECT_DIR="${1:-.}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS="_workspace/harness"

mkdir -p "$WS/gates" "$WS/research" "$WS/review"

if bash "$HERE/detect-stack.sh" "$PROJECT_DIR" > "$WS/gates.tsv" 2>"$WS/detect-stack.err"; then
    rm -f "$WS/detect-stack.err"
    echo "init-workspace: $WS 준비 완료. 감지된 게이트 $(wc -l < "$WS/gates.tsv") 개:"
    cat "$WS/gates.tsv"
    exit 0
fi

# 감지 실패 — 빈 gates.tsv 를 남기고, 지어내지 말라는 사유를 그대로 전달한다.
: > "$WS/gates.tsv"
echo "init-workspace: $WS 는 준비했지만 게이트를 감지하지 못했습니다."
cat "$WS/detect-stack.err" >&2
exit 3
