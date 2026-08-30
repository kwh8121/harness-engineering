#!/usr/bin/env bash
# tests/test-harness-paths.sh — _workspace 위치를 메인 워크트리 루트에 고정한다.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/lib/assert.sh"
SCRIPT="$ROOT/.claude/skills/harness-architect/scripts/harness-paths.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

git init -q "$TMP/repo"
git -C "$TMP/repo" config user.email t@t
git -C "$TMP/repo" config user.name t
echo hi > "$TMP/repo/a.txt"
git -C "$TMP/repo" add -A
git -C "$TMP/repo" commit -qm init
git -C "$TMP/repo" worktree add -q "$TMP/repo/.worktrees/feat" -b feat

main_ws="$(cd "$TMP/repo" && bash "$SCRIPT" --print)"
assert_eq "$TMP/repo/_workspace/harness" "$main_ws" "메인 트리에서 워크스페이스 경로를 낸다"

wt_ws="$(cd "$TMP/repo/.worktrees/feat" && bash "$SCRIPT" --print)"
assert_eq "$TMP/repo/_workspace/harness" "$wt_ws" "worktree 안에서도 메인 루트를 가리킨다"

out="$(cd "$TMP" && bash "$SCRIPT" --print)"
assert_eq "$TMP/_workspace/harness" "$out" "git 저장소가 아니면 현재 디렉터리로 물러난다"

override="$(HARNESS_WORKSPACE=/tmp/custom bash "$SCRIPT" --print)"
assert_eq "/tmp/custom" "$override" "HARNESS_WORKSPACE 가 우선한다"

bash "$SCRIPT" >/dev/null 2>&1; rc=$?
assert_exit_code 2 "$rc" "인자 없이 실행하면 사용법 오류"

report_and_exit
