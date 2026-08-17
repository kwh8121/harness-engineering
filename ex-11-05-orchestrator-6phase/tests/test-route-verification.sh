#!/usr/bin/env bash
# tests/test-route-verification.sh
set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/.claude/skills/code-review-team/scripts/route-verification.sh"
source "$PROJECT_ROOT/tests/lib/assert.sh"

work=$(mktemp -d)
mkdir -p "$work/_workspace/review"
cat > "$work/_workspace/review/04_refactor.md" <<'EOF'
# 리팩토링 patch 제안

## 적용된 patch

### sql-injection-fix.diff
- 발견 출처: 03_security.md [P0] SQL 인젝션 (CWE-89)
- 변경 요지: $queryRawUnsafe → prisma.user.findUnique
- 검증: 대기

### user-hook-shape.diff
- 발견 출처: 02_design.md [P0] 경계면 불일치
- 변경 요지: hook 측 .filter() → .data?.user 직접 접근으로
- 검증: 대기

### lint-cleanup.diff
- 발견 출처: 01_static.md [P1] console.log 잔존
- 변경 요지: console.log 제거
- 검증: 대기

## 다음 PR 권고
- 없음
EOF

(cd "$work" && bash "$SCRIPT")
exit_code=$?
assert_exit_code 0 "$exit_code" "route-verification: exit code"
assert_file_exists "$work/_workspace/verification/queue.tsv" "route-verification: queue.tsv 생성"

expected=$(printf 'sql-injection-fix.diff\tsecurity-auditor\t03_security.md [P0] SQL 인젝션 (CWE-89)\nuser-hook-shape.diff\tdesign-reviewer\t02_design.md [P0] 경계면 불일치\nlint-cleanup.diff\tstatic-analyzer\t01_static.md [P1] console.log 잔존')
actual=$(cat "$work/_workspace/verification/queue.tsv")
assert_eq "$expected" "$actual" "route-verification: queue.tsv 내용 (patch, 에이전트, 발견 3열)"

rm -rf "$work"

# --- 입력 파일 없을 때 ---
work2=$(mktemp -d)
(cd "$work2" && bash "$SCRIPT")
exit_code=$?
assert_exit_code 1 "$exit_code" "route-verification: 04_refactor.md 없으면 exit 1"
rm -rf "$work2"

report_and_exit
