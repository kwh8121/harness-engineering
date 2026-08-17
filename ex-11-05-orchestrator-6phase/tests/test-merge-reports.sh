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

# --- 시나리오 2: 04_refactor.md 전문 첨부 + rejected patch 추적 ---
# 04_refactor.md 는 "### [Pn]" 헤더가 아니라 "### {patch}.diff" 형식이므로
# P0/P1/P2 추출 루프를 건너뛰고 전문 그대로 붙어야 한다.
work2=$(mktemp -d)
mkdir -p "$work2/_workspace/review" "$work2/_workspace/patches"

cat > "$work2/_workspace/review/01_static.md" <<'EOF'
# 정적 분석 보고서

## 발견

### [P0] src/c.ts:9 — Error C
내용 C
EOF

cat > "$work2/_workspace/review/04_refactor.md" <<'EOF'
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

## 다음 PR 권고
- P1 N+1 쿼리 (03_security.md): batch fetch로 별도 PR
- P2 console.log (01_static.md): 1줄 cleanup PR
EOF

: > "$work2/_workspace/patches/foo.diff.rejected"

(cd "$work2" && bash "$SCRIPT")
exit_code=$?
assert_exit_code 0 "$exit_code" "merge-reports(refactor): exit code"

report2=$(cat "$work2/_workspace/review_report.md")
assert_contains "$report2" "## 리팩토링 patch 요약" "merge-reports(refactor): 리팩토링 섹션 존재"
assert_contains "$report2" "### sql-injection-fix.diff" "merge-reports(refactor): patch 파일명 전문 포함"
assert_contains "$report2" "- 발견 출처: 03_security.md [P0] SQL 인젝션 (CWE-89)" "merge-reports(refactor): 발견 출처 전문 포함"
assert_contains "$report2" "## 다음 PR 권고" "merge-reports(refactor): 다음 PR 권고 섹션 포함"
assert_contains "$report2" "src/c.ts:9" "merge-reports(refactor): static P0는 여전히 P0 섹션에 포함"
assert_contains "$report2" "## 사람 위임 필요" "merge-reports(refactor): 사람 위임 필요 섹션 존재"
assert_contains "$report2" "foo.diff.rejected" "merge-reports(refactor): rejected patch 나열"

rm -rf "$work2"
report_and_exit
