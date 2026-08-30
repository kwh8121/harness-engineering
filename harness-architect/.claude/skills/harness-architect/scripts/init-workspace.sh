#!/usr/bin/env bash
# init-workspace.sh — 하네스 실행에 쓸 _workspace 골격을 만들고 스택을 감지한다.
#
# 사용법:  init-workspace.sh [프로젝트_디렉터리]     (기본값: 현재 디렉터리)
# 산출물 (전부 메인 워크트리 루트 기준 — harness-paths.sh 참고):
#   _workspace/harness/gates.tsv    감지된 결정론적 게이트 (없으면 빈 파일 + 경고)
#   _workspace/harness/gates/       게이트 실행 로그가 쌓일 곳
#   _workspace/harness/research/    dependency-mapper · baseline-tester 보고서
#   _workspace/harness/review/      reviewer 보고서
#
# 종료코드:
#   0 = 게이트 감지 성공
#   3 = 골격은 만들었으나 스택 미감지 (사람에게 물어야 함)
#   4 = superpowers 미설치 — 아무것도 만들지 않고 즉시 중단 (SKILL.md Phase 1 이 받는다)
set -uo pipefail

PROJECT_DIR="${1:-.}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=harness-paths.sh
. "$HERE/harness-paths.sh"

# ── Preflight: superpowers 가 없으면 하네스는 H0 조차 돌지 않는다 ──────────────────
# verification-before-completion 이 전 레벨 필수라(validate-spec.py 의 E-SKILL-OWNER)
# 미설치 상태로는 Phase 3 의 승인 게이트를 통과할 수 없다. 골격을 만들기 전에 막아
# 사용자가 Phase 3 까지 가서야 원인 모를 계약 위반을 만나는 일을 없앤다.
if ! bash "$HERE/check-superpowers.sh"; then
    cat >&2 <<'GUIDE'

init-workspace: superpowers 플러그인이 없어 하네스를 시작할 수 없습니다.
  harness-architect 는 절차적 지식을 직접 쓰지 않고 superpowers 에 위임합니다 —
  H0 조차 verification-before-completion 이 필수입니다.

  설치 (Claude Code 에서 직접 입력하십시오. 슬래시 명령은 스킬이 대신 실행할 수 없습니다):

      /plugin install superpowers@claude-plugins-official

  공식 마켓플레이스 경로이며 재시작이 필요 없습니다. 대안:

      /plugin marketplace add obra/superpowers-marketplace
      /plugin install superpowers@superpowers-marketplace

  설치 후 이 스크립트를 다시 실행하십시오.
GUIDE
    exit 4
fi

# H2/H3 이 worktree 로 옮겨 가도 산출물은 한곳에 남아야 한다.
WS="$(harness_workspace)"

mkdir -p "$WS/gates" "$WS/research" "$WS/review"

# Phase 1 진입을 기록한다. 이후 세션이 "어디까지 했나"를 물을 때의 출발점이다.
if ! python3 "$HERE/checkpoint.py" --phase 1 \
        --next "게이트 감지 결과 확인 후 Phase 2 프로파일링" \
        --artifact "gates_tsv=$WS/gates.tsv" >/dev/null; then
    echo "init-workspace: checkpoint 기록에 실패했습니다 (워크스페이스 준비는 계속합니다)." >&2
fi

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
