#!/usr/bin/env bash
# tests/test-merge-reports.sh
set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/.claude/skills/code-review-team/scripts/merge-reports.sh"
source "$PROJECT_ROOT/tests/lib/assert.sh"

work=$(mktemp -d)
mkdir -p "$work/_workspace/review"

cat > "$work/_workspace/review/01_static.md" <<'EOF'
# 정적 분석 보고서

## 발견

### [P0] src/a.ts:1 — Error A
내용 A

### [P1] src/a.ts:2 — Warn A
내용 A2
EOF

cat > "$work/_workspace/review/03_security.md" <<'EOF'
# 보안 감사 보고서

## 발견

### [P0] src/b.ts:5 — SQLi (CWE-89)
내용 B
EOF

(cd "$work" && bash "$SCRIPT")
exit_code=$?
assert_exit_code 0 "$exit_code" "merge-reports: exit code"
assert_file_exists "$work/_workspace/review_report.md" "merge-reports: review_report.md 생성"

report=$(cat "$work/_workspace/review_report.md")
assert_contains "$report" "## [P0]" "merge-reports: P0 섹션 존재"
assert_contains "$report" "src/a.ts:1" "merge-reports: static P0 포함"
assert_contains "$report" "src/b.ts:5" "merge-reports: security P0 포함"
assert_contains "$report" "## [P1]" "merge-reports: P1 섹션 존재"
assert_contains "$report" "src/a.ts:2" "merge-reports: static P1 포함"
assert_contains "$report" "## [P2]" "merge-reports: P2 섹션 존재"
assert_contains "$report" "_해당 없음_" "merge-reports: P2는 해당 없음 표시"
assert_contains "$report" "설계 검토 (design-reviewer) 보고서 없음 (02_design.md)" "merge-reports: 누락 표시(design)"
assert_contains "$report" "리팩토링 (refactorer) 보고서 없음 (04_refactor.md)" "merge-reports: 누락 표시(refactor)"

rm -rf "$work"
report_and_exit
