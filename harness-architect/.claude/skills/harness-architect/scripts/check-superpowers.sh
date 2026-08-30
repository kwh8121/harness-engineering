#!/usr/bin/env bash
# check-superpowers.sh — harness-architect 가 위임하는 superpowers 스킬이 설치돼 있는지 확인한다.
#
# 사용법:  check-superpowers.sh [--quiet]
# 종료코드: 0 = 필수 스킬 전부 존재 / 1 = 하나 이상 없음
#
# 왜 버전이 아니라 "스킬의 존재"로 판정하는가:
#   같은 플러그인이 서로 다른 마켓플레이스에서 여러 벌 설치될 수 있다 — 실제로 5.1.0 과
#   6.3.0 이 공존하는 환경이 관측됐다. 그때 버전 문자열로 판정하면 엉뚱한 설치본을 보고
#   오판한다. 정작 알아야 하는 것은 "`REQUIRED SUB-SKILL` 호출이 성공하는가"이므로
#   스킬 디렉터리와 그 SKILL.md 의 존재로 직접 판정한다.
#
# 이 목록은 validate-spec.py 의 ALLOWED_SKILLS 에서 내장 `security-review` 를 뺀 것과
# 같아야 한다 (CLAUDE.md 의 불변식 표 참고).
set -uo pipefail

REQUIRED_SKILLS=(
    brainstorming
    writing-plans
    subagent-driven-development
    dispatching-parallel-agents
    using-git-worktrees
    requesting-code-review
    verification-before-completion
    finishing-a-development-branch
    test-driven-development
    receiving-code-review
    systematic-debugging
)

QUIET=0
[[ "${1:-}" == "--quiet" ]] && QUIET=1

# 플러그인이 설치될 수 있는 위치를 전부 모은다. 절대 경로를 박지 않고 환경변수로 찾는다.
roots=()
[[ -n "${CLAUDE_PLUGIN_ROOT:-}" && -d "${CLAUDE_PLUGIN_ROOT}" ]] && roots+=("$CLAUDE_PLUGIN_ROOT")
user_plugins="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins"
[[ -d "$user_plugins" ]] && roots+=("$user_plugins")
[[ -d ".claude/plugins" ]] && roots+=(".claude/plugins")

if [[ "${#roots[@]}" -eq 0 ]]; then
    [[ "$QUIET" -eq 1 ]] || {
        echo "check-superpowers: 플러그인 디렉터리를 찾지 못했습니다." >&2
        echo "  확인한 위치: \$CLAUDE_PLUGIN_ROOT, ${user_plugins}, .claude/plugins" >&2
    }
    exit 1
fi

# 한 번의 find 로 설치된 스킬 이름을 전부 수집한다 (스킬마다 find 를 도는 것보다 훨씬 싸다).
# 관측된 레이아웃은 두 가지다:
#   <root>/cache/<marketplace>/<plugin>/<version>/skills/<name>/SKILL.md   (깊이 6)
#   <root>/marketplaces/<marketplace>/skills/<name>/SKILL.md               (깊이 4)
installed="$(find "${roots[@]}" -maxdepth 7 -type f -name SKILL.md -path '*/skills/*' 2>/dev/null \
             | awk -F/ '{ print $(NF-1) }' | sort -u)"

missing=()
for skill in "${REQUIRED_SKILLS[@]}"; do
    grep -qxF "$skill" <<< "$installed" || missing+=("$skill")
done

if [[ "${#missing[@]}" -eq 0 ]]; then
    [[ "$QUIET" -eq 1 ]] || \
        echo "check-superpowers: 필수 스킬 ${#REQUIRED_SKILLS[@]}종 전부 확인됨."
    exit 0
fi

[[ "$QUIET" -eq 1 ]] || {
    echo "check-superpowers: superpowers 필수 스킬 ${#missing[@]}종을 찾지 못했습니다." >&2
    for m in "${missing[@]}"; do echo "  - $m" >&2; done
    echo "  검색한 위치: ${roots[*]}" >&2
}
exit 1
