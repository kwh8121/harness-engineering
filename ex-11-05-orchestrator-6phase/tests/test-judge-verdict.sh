#!/usr/bin/env bash
# tests/test-judge-verdict.sh
set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/.claude/skills/code-review-team/scripts/judge-verdict.sh"
source "$PROJECT_ROOT/tests/lib/assert.sh"

work=$(mktemp -d)
mkdir -p "$work/_workspace/patches"
echo "dummy" > "$work/_workspace/patches/foo.diff"

# 1. PASS
result=$(cd "$work" && printf 'some analysis\nVERDICT: PASS\n' | bash "$SCRIPT" foo.diff 1)
assert_eq "PASS" "$result" "judge-verdict: PASS 응답"
assert_file_exists "$work/_workspace/patches/foo.diff" "judge-verdict: PASS면 patch 그대로 존재"

# 2. FAIL, 1회차 -> RETRY
result=$(cd "$work" && printf 'VERDICT: FAIL - 여전히 취약함\n' | bash "$SCRIPT" foo.diff 1)
assert_eq "RETRY" "$result" "judge-verdict: FAIL 1회차는 RETRY"

# 3. FAIL, 2회차 -> RETRY
result=$(cd "$work" && printf 'VERDICT: FAIL - 여전히 취약함\n' | bash "$SCRIPT" foo.diff 2)
assert_eq "RETRY" "$result" "judge-verdict: FAIL 2회차는 RETRY"

# 4. FAIL, 3회차 -> REJECTED + 파일 리네임
result=$(cd "$work" && printf 'VERDICT: FAIL - 여전히 취약함\n' | bash "$SCRIPT" foo.diff 3)
assert_eq "REJECTED" "$result" "judge-verdict: FAIL 3회차는 REJECTED"
assert_file_exists "$work/_workspace/patches/foo.diff.rejected" "judge-verdict: 3회차 REJECTED면 .rejected로 리네임"

# 5. 형식 위반(VERDICT 줄 없음), 3회차 -> REJECTED로 취급
echo "dummy2" > "$work/_workspace/patches/bar.diff"
result=$(cd "$work" && printf '이상한 응답, 형식 안 지킴\n' | bash "$SCRIPT" bar.diff 3)
assert_eq "REJECTED" "$result" "judge-verdict: 형식 위반은 FAIL로 취급되어 3회차에 REJECTED"

rm -rf "$work"
report_and_exit
