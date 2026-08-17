#!/usr/bin/env bash
# tests/test-resolve-diff.sh
set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/.claude/skills/code-review-team/scripts/resolve-diff.sh"
source "$PROJECT_ROOT/tests/lib/assert.sh"

setup_repo() {
    local dir
    dir=$(mktemp -d)
    (
        cd "$dir"
        git init -q -b main
        git config user.email "test@example.com"
        git config user.name "Test"
        echo "line1" > file.txt
        git add file.txt
        git commit -q -m "initial"
    )
    echo "$dir"
}

# --- 시나리오 1: staged diff ---
repo=$(setup_repo)
(
    cd "$repo"
    echo "line2" >> file.txt
    git add file.txt
    bash "$SCRIPT"
)
exit_code=$?
assert_exit_code 0 "$exit_code" "staged diff: exit code"
assert_file_exists "$repo/_workspace/input/diff.patch" "staged diff: diff.patch 생성"
diff_content=$(cat "$repo/_workspace/input/diff.patch" 2>/dev/null || echo "")
assert_contains "$diff_content" "+line2" "staged diff: diff 내용에 +line2 포함"
files_content=$(cat "$repo/_workspace/input/files.txt" 2>/dev/null || echo "")
assert_contains "$files_content" "file.txt" "staged diff: files.txt에 file.txt 포함"
rm -rf "$repo"

# --- 시나리오 2: unstaged diff ---
repo=$(setup_repo)
(
    cd "$repo"
    echo "line3" >> file.txt
    bash "$SCRIPT"
)
exit_code=$?
assert_exit_code 0 "$exit_code" "unstaged diff: exit code"
diff_content=$(cat "$repo/_workspace/input/diff.patch" 2>/dev/null || echo "")
assert_contains "$diff_content" "+line3" "unstaged diff: diff 내용에 +line3 포함"
rm -rf "$repo"

# --- 시나리오 3: 브랜치 base diff (staged/unstaged 없음) ---
repo=$(setup_repo)
(
    cd "$repo"
    git checkout -q -b feature
    echo "line4" >> file.txt
    git add file.txt
    git commit -q -m "feature change"
    bash "$SCRIPT"
)
exit_code=$?
assert_exit_code 0 "$exit_code" "브랜치 base diff: exit code"
diff_content=$(cat "$repo/_workspace/input/diff.patch" 2>/dev/null || echo "")
assert_contains "$diff_content" "+line4" "브랜치 base diff: diff 내용에 +line4 포함"
rm -rf "$repo"

# --- 시나리오 4: 변경사항 전무 ---
repo=$(setup_repo)
(
    cd "$repo"
    bash "$SCRIPT"
)
exit_code=$?
assert_exit_code 1 "$exit_code" "변경사항 없음: exit code 1"
rm -rf "$repo"

# --- 시나리오 5: PR 모드 실패 시 로컬 diff로 폴백 ---
repo=$(setup_repo)
(
    cd "$repo"
    echo "line5" >> file.txt
    git add file.txt
    bash "$SCRIPT" 999999 2>/dev/null
)
exit_code=$?
assert_exit_code 0 "$exit_code" "PR 폴백: exit code"
diff_content=$(cat "$repo/_workspace/input/diff.patch" 2>/dev/null || echo "")
assert_contains "$diff_content" "+line5" "PR 폴백: 로컬 staged diff로 대체됨"
rm -rf "$repo"

report_and_exit
