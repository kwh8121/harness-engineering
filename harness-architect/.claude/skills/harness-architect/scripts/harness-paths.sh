#!/usr/bin/env bash
# harness-paths.sh — _workspace 산출물의 위치를 "메인 워크트리 루트"로 고정한다.
#                     (실행용이 아니라 source 전용이다)
#
# 왜 필요한가:
#   H2/H3 은 superpowers:using-git-worktrees 로 격리된 worktree 에 들어가 작업한다
#   (references/routing.md H2 1단계). 그런데 Phase 1~3 — 게이트 감지·spec 작성·승인 —
#   은 그보다 먼저 메인 레포에서 돌아간다. `_workspace` 를 CWD 상대로 해석하면:
#
#     1. worktree 진입 후 run-gates.sh 가 worktree 쪽의 존재하지 않는 gates.tsv 를
#        찾아 exit 2 로 죽는다. Phase 1 이 만든 게이트 목록은 메인 레포에 있다.
#     2. worktree 안에 새로 쌓인 게이트 로그·조사 보고서·리뷰가 정리 단계
#        (`git worktree remove`)에서 통째로 사라진다 — "workspace 보존" 규칙 위반이다.
#
#   그래서 산출물 경로만 메인 워크트리 루트에 고정한다.
#
#   **게이트 명령의 실행 디렉터리는 바꾸지 않는다.** 테스트·린트·빌드는 지금 체크아웃된
#   트리(= worktree)에서 돌아야 검증의 의미가 있다. 고정하는 것은 `_workspace` 경로뿐이다.
#
# 재정의: HARNESS_WORKSPACE 환경변수를 주면 그 값을 그대로 쓴다.

# 메인 워크트리 루트를 출력한다. git 저장소가 아니면 현재 디렉터리로 물러난다.
harness_root() {
    local root
    # `git worktree list` 의 첫 항목이 항상 메인 워크트리다 (linked worktree 는 그 뒤에 온다).
    root="$(git worktree list --porcelain 2>/dev/null \
            | awk '/^worktree /{ print substr($0, 10); exit }')"
    if [[ -n "$root" && -d "$root" ]]; then
        printf '%s\n' "$root"
        return 0
    fi
    pwd -P
}

# _workspace/harness 의 절대 경로를 출력한다.
harness_workspace() {
    if [[ -n "${HARNESS_WORKSPACE:-}" ]]; then
        printf '%s\n' "${HARNESS_WORKSPACE%/}"
        return 0
    fi
    printf '%s/_workspace/harness\n' "$(harness_root)"
}
