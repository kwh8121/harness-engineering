#!/usr/bin/env bash
# tests/test-apply-patches.sh
set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/.claude/skills/code-review-team/scripts/apply-patches.sh"
source "$PROJECT_ROOT/tests/lib/assert.sh"

# --- 시나리오 1: 성공 patch + 실패 patch + rejected 파일 혼재 ---
work=$(mktemp -d)
(
    cd "$work"
    git init -q -b main
    git config user.email "t@e.com"
    git config user.name "T"
    printf 'line1\nline2\nline3\n' > file.txt
    git add file.txt
    git commit -q -m init
    mkdir -p _workspace/patches

    sed -i 's/line2/line2-changed/' file.txt
    git diff > _workspace/patches/good.diff
    git checkout -q -- file.txt

    cat > _workspace/patches/bad.diff <<'PATCH'
--- a/nonexistent.txt
+++ b/nonexistent.txt
@@ -1,1 +1,1 @@
-old
+new
PATCH

    echo "이미 거절됨" > _workspace/patches/skip.diff.rejected
)

output=$(cd "$work" && bash "$SCRIPT")
exit_code=$?

assert_exit_code 1 "$exit_code" "apply-patches: bad.diff 있으면 exit 1"
assert_contains "$output" "APPLIED:" "apply-patches: 출력에 APPLIED 섹션"
assert_contains "$output" "good.diff" "apply-patches: 출력에 good.diff 나열"
assert_contains "$output" "FAILED:" "apply-patches: 출력에 FAILED 섹션"
assert_contains "$output" "bad.diff" "apply-patches: 출력에 bad.diff 나열"

content=$(cat "$work/file.txt")
assert_contains "$content" "line2-changed" "apply-patches: good.diff가 실제로 working tree에 적용됨"

assert_file_exists "$work/_workspace/patches/bad.diff" "apply-patches: 실패한 patch는 삭제되지 않음"
assert_file_exists "$work/_workspace/patches/skip.diff.rejected" "apply-patches: .rejected 파일은 그대로 남음"

log_count=$(git -C "$work" log --oneline | wc -l | tr -d ' ')
assert_eq "1" "$log_count" "apply-patches: 커밋 호출 없음 (커밋 개수 그대로 1)"

status_output=$(git -C "$work" status --porcelain)
assert_contains "$status_output" "file.txt" "apply-patches: working tree에 uncommitted 변경 존재"

rm -rf "$work"

# --- 시나리오 2: 전부 성공 ---
work2=$(mktemp -d)
(
    cd "$work2"
    git init -q -b main
    git config user.email "t@e.com"
    git config user.name "T"
    printf 'hello\n' > note.txt
    git add note.txt
    git commit -q -m init
    mkdir -p _workspace/patches
    sed -i 's/hello/world/' note.txt
    git diff > _workspace/patches/only.diff
    git checkout -q -- note.txt
)
output2=$(cd "$work2" && bash "$SCRIPT")
exit_code2=$?
assert_exit_code 0 "$exit_code2" "apply-patches: 전부 성공하면 exit 0"
content2=$(cat "$work2/note.txt")
assert_contains "$content2" "world" "apply-patches: 유일한 patch가 적용됨"
rm -rf "$work2"

report_and_exit
