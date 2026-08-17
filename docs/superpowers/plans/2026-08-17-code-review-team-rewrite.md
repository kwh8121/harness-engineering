# code-review-team 실사용화 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `ex-11-05-orchestrator-6phase`의 book 의사코드 기반 code-review-team을, 이 환경에 실제 존재하는 도구(`Agent`, `Bash`, `SendMessage`)만으로 동작하는 범용 코드 리뷰 팀으로 재작성한다.

**Architecture:** 리더(SKILL.md)는 판단 없이 호출만 한다. 반복 로직(diff 확보, 검증 라우팅, 보고서 병합, patch 적용)은 4개의 결정적 셸 스크립트가 처리하고, 리뷰·판단이 필요한 부분만 `Agent` 도구로 4개 서브에이전트에 위임한다. patch 생성-검증 루프는 "라우팅(스크립트)"과 "판정(서브에이전트, VERDICT 한 줄 강제)"을 분리해 리더가 내용을 읽지 않고도 중계할 수 있게 한다.

**Tech Stack:** Bash(POSIX 호환), git CLI, gh CLI(PR 모드 한정, 선택), Claude Code `Agent` 도구. 외부 패키지/런타임 설치 없음(이식성).

**Spec:** `docs/superpowers/specs/2026-08-17-code-review-team-rewrite-design.md`

## Global Constraints

- git commit 호출 금지 — 전 구간 어디서도 `git commit`을 호출하지 않는다.
- 리더는 리뷰 내용을 읽고 해석하지 않는다 — 라우팅은 스크립트 출력을, 검증은 강제된 `VERDICT:` 한 줄만 파싱한다.
- 워커 간 peer SendMessage 없음 — 모든 통신은 리더 경유(리더 허브형).
- 스크립트는 bash + git(+gh, PR 모드 한정)만으로 동작해야 한다 — 추가 패키지 설치 불필요(이식성).
- `.claude/skills/code-review-team/` + `.claude/agents/*.md`는 폴더째로 다른 저장소에 복사해도 그대로 동작해야 한다. `tests/`는 이 이식 경계 밖(개발/검증 전용).
- 도구 경계 유지: static-analyzer/design-reviewer/security-auditor는 Edit 없음(발견만 보고), refactorer는 `_workspace/patches/*.diff`만 Edit(소스 트리는 Read 전용).

---

### Task 1: 테스트 하네스 (assert 헬퍼 + 러너)

**Files:**
- Create: `ex-11-05-orchestrator-6phase/tests/lib/assert.sh`
- Create: `ex-11-05-orchestrator-6phase/tests/run-all.sh`

**Interfaces:**
- Produces: `assert_eq(expected, actual, msg)`, `assert_file_exists(path, msg)`, `assert_contains(haystack, needle, msg)`, `assert_exit_code(expected, actual, msg)`, `report_and_exit()` — 전역 `FAILURES` 카운터를 증가시키고 PASS/FAIL을 stdout에 출력. 이후 모든 `tests/test-*.sh`가 `source tests/lib/assert.sh`로 사용.

- [ ] **Step 1: assert.sh 작성**

```bash
#!/usr/bin/env bash
# tests/lib/assert.sh — 프레임워크 없는 최소 assertion 헬퍼

FAILURES=0

assert_eq() {
    local expected="$1" actual="$2" msg="${3:-assert_eq}"
    if [[ "$expected" != "$actual" ]]; then
        echo "FAIL: $msg"
        echo "  expected: $expected"
        echo "  actual:   $actual"
        FAILURES=$((FAILURES + 1))
    else
        echo "PASS: $msg"
    fi
}

assert_file_exists() {
    local path="$1" msg="${2:-assert_file_exists $path}"
    if [[ ! -f "$path" ]]; then
        echo "FAIL: $msg (file not found: $path)"
        FAILURES=$((FAILURES + 1))
    else
        echo "PASS: $msg"
    fi
}

assert_contains() {
    local haystack="$1" needle="$2" msg="${3:-assert_contains}"
    if [[ "$haystack" != *"$needle"* ]]; then
        echo "FAIL: $msg"
        echo "  expected to contain: $needle"
        FAILURES=$((FAILURES + 1))
    else
        echo "PASS: $msg"
    fi
}

assert_exit_code() {
    local expected="$1" actual="$2" msg="${3:-assert_exit_code}"
    if [[ "$expected" -ne "$actual" ]]; then
        echo "FAIL: $msg (expected exit $expected, got $actual)"
        FAILURES=$((FAILURES + 1))
    else
        echo "PASS: $msg"
    fi
}

report_and_exit() {
    if [[ "$FAILURES" -gt 0 ]]; then
        echo "=== $FAILURES failure(s) ==="
        exit 1
    fi
    echo "=== all tests passed ==="
    exit 0
}
```

- [ ] **Step 2: run-all.sh 작성**

```bash
#!/usr/bin/env bash
# tests/run-all.sh — tests/test-*.sh 를 전부 실행하고 결과를 집계한다
set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
overall=0

for t in "$PROJECT_ROOT"/test-*.sh; do
    [[ -f "$t" ]] || continue
    echo "=== $(basename "$t") ==="
    bash "$t"
    rc=$?
    if [[ $rc -ne 0 ]]; then
        overall=1
    fi
    echo
done

exit $overall
```

- [ ] **Step 3: 문법 검증**

Run: `bash -n ex-11-05-orchestrator-6phase/tests/lib/assert.sh && bash -n ex-11-05-orchestrator-6phase/tests/run-all.sh && echo OK`
Expected: `OK` 출력 (문법 오류 없음). 이 시점엔 `test-*.sh`가 없으므로 `run-all.sh`를 직접 실행하면 아무것도 안 하고 exit 0 — 그것도 정상.

- [ ] **Step 4: Commit**

```bash
git add ex-11-05-orchestrator-6phase/tests/lib/assert.sh ex-11-05-orchestrator-6phase/tests/run-all.sh
git commit -m "test: code-review-team 스크립트용 최소 assertion 하네스 추가"
```

---

### Task 2: `resolve-diff.sh`

**Files:**
- Create: `ex-11-05-orchestrator-6phase/.claude/skills/code-review-team/scripts/resolve-diff.sh`
- Test: `ex-11-05-orchestrator-6phase/tests/test-resolve-diff.sh`

**Interfaces:**
- Consumes: `tests/lib/assert.sh`의 `assert_exit_code`, `assert_file_exists`, `assert_contains`, `report_and_exit` (Task 1)
- Produces: `scripts/resolve-diff.sh [PR번호]` — 실행 성공 시 `_workspace/input/diff.patch`, `_workspace/input/files.txt` 생성, exit 0. 리뷰할 변경사항이 전혀 없으면 exit 1. (다른 스크립트/SKILL.md가 이 산출물 경로를 그대로 소비함)

- [ ] **Step 1: 실패하는 테스트 작성**

```bash
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
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run: `bash ex-11-05-orchestrator-6phase/tests/test-resolve-diff.sh`
Expected: FAIL (스크립트 파일이 아직 없어 `bash: .../resolve-diff.sh: No such file or directory` 및 관련 assertion 다수 FAIL)

- [ ] **Step 3: `resolve-diff.sh` 구현**

```bash
#!/usr/bin/env bash
# resolve-diff.sh [PR_NUMBER]
# PR 번호가 있으면 gh pr diff, 없으면 로컬 diff(staged → unstaged → 브랜치 base)를
# 순서대로 시도해 _workspace/input/diff.patch, _workspace/input/files.txt를 만든다.
# 아무 diff도 찾지 못하면 exit 1.
set -euo pipefail

OUT_DIR="_workspace/input"
mkdir -p "$OUT_DIR"
DIFF_FILE="$OUT_DIR/diff.patch"
FILES_FILE="$OUT_DIR/files.txt"
PR_NUMBER="${1:-}"

try_pr_diff() {
    local pr="$1"
    if ! command -v gh >/dev/null 2>&1; then
        echo "resolve-diff: gh CLI가 설치되어 있지 않습니다. 로컬 diff로 폴백합니다." >&2
        return 1
    fi
    if ! gh pr diff "$pr" > "$DIFF_FILE" 2>/dev/null; then
        echo "resolve-diff: gh pr diff $pr 실패(인증/네트워크/PR 없음). 로컬 diff로 폴백합니다." >&2
        return 1
    fi
    gh pr diff "$pr" --name-only > "$FILES_FILE" 2>/dev/null || : > "$FILES_FILE"
    return 0
}

find_branch_base() {
    local ref
    ref=$(git symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null | sed 's#^refs/remotes/##') || true
    if [[ -z "$ref" ]]; then
        if git show-ref --verify -q refs/heads/main; then
            ref="main"
        elif git show-ref --verify -q refs/heads/master; then
            ref="master"
        fi
    fi
    echo "$ref"
}

try_local_diff() {
    if git diff --cached --quiet; then
        : # staged 없음
    else
        git diff --cached > "$DIFF_FILE"
        git diff --cached --name-only > "$FILES_FILE"
        return 0
    fi

    if git diff --quiet; then
        : # unstaged 없음
    else
        git diff > "$DIFF_FILE"
        git diff --name-only > "$FILES_FILE"
        return 0
    fi

    local base
    base=$(find_branch_base)
    if [[ -n "$base" ]]; then
        local merge_base
        if merge_base=$(git merge-base HEAD "$base" 2>/dev/null); then
            if ! git diff --quiet "$merge_base" HEAD; then
                git diff "$merge_base" HEAD > "$DIFF_FILE"
                git diff --name-only "$merge_base" HEAD > "$FILES_FILE"
                return 0
            fi
        fi
    fi

    return 1
}

if [[ -n "$PR_NUMBER" ]] && try_pr_diff "$PR_NUMBER"; then
    exit 0
fi

if try_local_diff; then
    exit 0
fi

echo "resolve-diff: 리뷰할 변경사항을 찾지 못했습니다 (staged/unstaged/브랜치 base 모두 비어있음)." >&2
exit 1
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `bash ex-11-05-orchestrator-6phase/tests/test-resolve-diff.sh`
Expected: 5개 시나리오 모두 PASS, 마지막 줄 `=== all tests passed ===`

- [ ] **Step 5: Commit**

```bash
git add ex-11-05-orchestrator-6phase/.claude/skills/code-review-team/scripts/resolve-diff.sh ex-11-05-orchestrator-6phase/tests/test-resolve-diff.sh
git commit -m "feat: resolve-diff.sh로 PR/로컬 diff 자동 판별 구현"
```

---

### Task 3: `route-verification.sh`

**Files:**
- Create: `ex-11-05-orchestrator-6phase/.claude/skills/code-review-team/scripts/route-verification.sh`
- Test: `ex-11-05-orchestrator-6phase/tests/test-route-verification.sh`

**Interfaces:**
- Consumes: `_workspace/review/04_refactor.md` 파일의 `### {patch}.diff` + `- 발견 출처: {report}.md ...` 쌍 (refactorer.md 출력 형식, Task 7에서 확정)
- Produces: `_workspace/verification/queue.tsv` — 한 줄당 `{patch파일}\t{담당 에이전트}\t{발견 원문}` (탭 구분 3열). SKILL.md Phase 4(Task 9)가 이 파일을 한 줄씩 순회.

- [ ] **Step 1: 실패하는 테스트 작성**

```bash
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
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run: `bash ex-11-05-orchestrator-6phase/tests/test-route-verification.sh`
Expected: FAIL (스크립트 없음)

- [ ] **Step 3: `route-verification.sh` 구현**

```bash
#!/usr/bin/env bash
# route-verification.sh
# _workspace/review/04_refactor.md의 "### {patch}.diff" + "- 발견 출처: {report}.md ..." 쌍을 파싱해
# _workspace/verification/queue.tsv (patch파일\t담당에이전트\t발견원문)를 만든다.
set -euo pipefail

REFACTOR_REPORT="_workspace/review/04_refactor.md"
OUT_DIR="_workspace/verification"
OUT_FILE="$OUT_DIR/queue.tsv"

if [[ ! -f "$REFACTOR_REPORT" ]]; then
    echo "route-verification: $REFACTOR_REPORT 가 없습니다." >&2
    exit 1
fi

mkdir -p "$OUT_DIR"

awk '
    /^### .+\.diff[[:space:]]*$/ {
        line = $0;
        sub(/^### /, "", line);
        sub(/[[:space:]]*$/, "", line);
        current_patch = line;
        next;
    }
    /^- 발견 출처: / && current_patch != "" {
        line = $0;
        sub(/^- 발견 출처: /, "", line);
        report_file = line;
        sub(/[[:space:]].*$/, "", report_file);

        agent = "";
        if (report_file == "01_static.md") agent = "static-analyzer";
        else if (report_file == "02_design.md") agent = "design-reviewer";
        else if (report_file == "03_security.md") agent = "security-auditor";

        if (agent != "") {
            print current_patch "\t" agent "\t" line;
        }
        current_patch = "";
    }
' "$REFACTOR_REPORT" > "$OUT_FILE"

exit 0
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `bash ex-11-05-orchestrator-6phase/tests/test-route-verification.sh`
Expected: 모두 PASS

- [ ] **Step 5: Commit**

```bash
git add ex-11-05-orchestrator-6phase/.claude/skills/code-review-team/scripts/route-verification.sh ex-11-05-orchestrator-6phase/tests/test-route-verification.sh
git commit -m "feat: route-verification.sh로 patch-리뷰어 매핑 결정적 추출 구현"
```

---

### Task 4: `merge-reports.sh`

**Files:**
- Create: `ex-11-05-orchestrator-6phase/.claude/skills/code-review-team/scripts/merge-reports.sh`
- Test: `ex-11-05-orchestrator-6phase/tests/test-merge-reports.sh`

**Interfaces:**
- Consumes: `_workspace/review/{01_static,02_design,03_security,04_refactor}.md` (일부 누락 가능)
- Produces: `_workspace/review_report.md` — P0→P1→P2 순 통합, 누락 리뷰는 상단에 명시. SKILL.md Phase 5(Task 9)가 이 파일을 그대로 `gh pr comment`에 사용.

- [ ] **Step 1: 실패하는 테스트 작성**

```bash
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
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run: `bash ex-11-05-orchestrator-6phase/tests/test-merge-reports.sh`
Expected: FAIL (스크립트 없음)

- [ ] **Step 3: `merge-reports.sh` 구현**

```bash
#!/usr/bin/env bash
# merge-reports.sh
# _workspace/review/01_static.md ~ 04_refactor.md 를 P0 → P1 → P2 순으로 재배열해
# _workspace/review_report.md 를 만든다. 존재하지 않는 리포트는 건너뛰고 상단에 명시한다.
set -euo pipefail

REVIEW_DIR="_workspace/review"
OUT_FILE="_workspace/review_report.md"

ORDER=(01_static.md 02_design.md 03_security.md 04_refactor.md)
declare -A LABELS=(
    [01_static.md]="정적 분석 (static-analyzer)"
    [02_design.md]="설계 검토 (design-reviewer)"
    [03_security.md]="보안 감사 (security-auditor)"
    [04_refactor.md]="리팩토링 (refactorer)"
)

present=()
missing=()
for f in "${ORDER[@]}"; do
    if [[ -f "$REVIEW_DIR/$f" ]]; then
        present+=("$f")
    else
        missing+=("$f")
    fi
done

extract_section() {
    local file="$1" priority="$2"
    awk -v target="### [$priority]" '
        substr($0, 1, length(target)) == target { printing = 1; print; next }
        /^### \[/ { printing = 0; next }
        printing { print }
    ' "$file"
}

{
    echo "# 코드 리뷰 통합 보고서"
    echo

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "## 누락된 리뷰"
        for f in "${missing[@]}"; do
            echo "- ${LABELS[$f]} 보고서 없음 ($f)"
        done
        echo
    fi

    for priority in P0 P1 P2; do
        echo "## [$priority]"
        echo
        any=0
        for f in "${present[@]}"; do
            section=$(extract_section "$REVIEW_DIR/$f" "$priority")
            if [[ -n "$section" ]]; then
                echo "$section"
                echo
                any=1
            fi
        done
        if [[ "$any" -eq 0 ]]; then
            echo "_해당 없음_"
            echo
        fi
    done
} > "$OUT_FILE"

exit 0
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `bash ex-11-05-orchestrator-6phase/tests/test-merge-reports.sh`
Expected: 모두 PASS

- [ ] **Step 5: Commit**

```bash
git add ex-11-05-orchestrator-6phase/.claude/skills/code-review-team/scripts/merge-reports.sh ex-11-05-orchestrator-6phase/tests/test-merge-reports.sh
git commit -m "feat: merge-reports.sh로 4개 리뷰 보고서 P0/P1/P2 결정적 통합 구현"
```

---

### Task 5: `apply-patches.sh`

**Files:**
- Create: `ex-11-05-orchestrator-6phase/.claude/skills/code-review-team/scripts/apply-patches.sh`
- Test: `ex-11-05-orchestrator-6phase/tests/test-apply-patches.sh`

**Interfaces:**
- Consumes: `_workspace/patches/*.diff` (`.diff.rejected`는 대상 제외 — `judge-verdict.sh`(Task 6)가 3회 실패 patch를 리네임)
- Produces: working tree에 유효한 patch 반영(커밋 없음). stdout에 `APPLIED:`/`FAILED:` 섹션. 실패 patch가 하나라도 있으면 exit 1.

- [ ] **Step 1: 실패하는 테스트 작성**

```bash
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
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run: `bash ex-11-05-orchestrator-6phase/tests/test-apply-patches.sh`
Expected: FAIL (스크립트 없음)

- [ ] **Step 3: `apply-patches.sh` 구현**

```bash
#!/usr/bin/env bash
# apply-patches.sh
# _workspace/patches/*.diff (.rejected 제외)를 git apply --check로 검증 후
# 통과하는 것만 working tree에 반영한다. git add/commit은 절대 호출하지 않는다.
set -uo pipefail  # -e는 의도적으로 뺀다: 개별 patch 실패가 스크립트 전체를 죽이면 안 됨

PATCH_DIR="_workspace/patches"
applied=()
failed=()

shopt -s nullglob
for patch in "$PATCH_DIR"/*.diff; do
    if git apply --check "$patch" 2>/dev/null && git apply "$patch"; then
        applied+=("$(basename "$patch")")
    else
        failed+=("$(basename "$patch")")
    fi
done
shopt -u nullglob

echo "APPLIED:"
for f in "${applied[@]:-}"; do
    [[ -n "$f" ]] && echo "  - $f"
done
echo "FAILED:"
for f in "${failed[@]:-}"; do
    [[ -n "$f" ]] && echo "  - $f"
done

if [[ ${#failed[@]} -gt 0 ]]; then
    exit 1
fi
exit 0
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `bash ex-11-05-orchestrator-6phase/tests/test-apply-patches.sh`
Expected: 모두 PASS

- [ ] **Step 5: Commit**

```bash
git add ex-11-05-orchestrator-6phase/.claude/skills/code-review-team/scripts/apply-patches.sh ex-11-05-orchestrator-6phase/tests/test-apply-patches.sh
git commit -m "feat: apply-patches.sh로 검증된 patch만 working tree에 반영 (커밋 없음)"
```

---

### Task 6: `judge-verdict.sh` — 재시도/격리 판정 분리

**Files:**
- Create: `ex-11-05-orchestrator-6phase/.claude/skills/code-review-team/scripts/judge-verdict.sh`
- Test: `ex-11-05-orchestrator-6phase/tests/test-judge-verdict.sh`

**Interfaces:**
- Consumes: `$1`=patch 파일명, `$2`=시도 횟수, stdin=검증 Agent 응답 전체 텍스트
- Produces: stdout에 `PASS` / `RETRY` / `REJECTED` 중 하나만 출력. `REJECTED`면 `_workspace/patches/{patch}` → `{patch}.rejected`로 직접 리네임까지 수행. SKILL.md Phase 4(Task 9)가 이 세 단어만 보고 분기한다 — 응답 원문을 직접 파싱하지 않는다.

> 이 스크립트는 원래 계획에 없었으나, 자체 검토 중 "생성-검증 루프를 실제 Agent 없이 픽스처로 테스트한다"는 스펙 요구사항(테스트 계획 2번)이 SKILL.md 안의 자연어 절차만으로는 지켜질 수 없다는 것을 발견해 추가했다. 판정·리네임 로직을 스크립트로 뽑아내야 Agent 호출 없이도 재시도/격리 분기를 검증할 수 있다.

- [ ] **Step 1: 실패하는 테스트 작성**

```bash
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
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run: `bash ex-11-05-orchestrator-6phase/tests/test-judge-verdict.sh`
Expected: FAIL (스크립트 없음)

- [ ] **Step 3: `judge-verdict.sh` 구현**

```bash
#!/usr/bin/env bash
# judge-verdict.sh <patch_filename> <attempt_number>
# stdin으로 검증 Agent의 응답 전체를 받는다. 마지막 비어있지 않은 줄이 "VERDICT: PASS"로
# 시작하면 PASS. 아니면(FAIL 또는 형식 위반) attempt_number < 3이면 RETRY, 3 이상이면
# _workspace/patches/{patch}를 {patch}.rejected로 리네임하고 REJECTED를 출력한다.
set -euo pipefail

PATCH="$1"
ATTEMPT="$2"
PATCH_DIR="_workspace/patches"

response=$(cat)
last_line=$(printf '%s\n' "$response" | grep -v '^[[:space:]]*$' | tail -n 1)

if [[ "$last_line" == "VERDICT: PASS"* ]]; then
    echo "PASS"
    exit 0
fi

if [[ "$ATTEMPT" -lt 3 ]]; then
    echo "RETRY"
    exit 0
fi

if [[ -f "$PATCH_DIR/$PATCH" ]]; then
    mv "$PATCH_DIR/$PATCH" "$PATCH_DIR/$PATCH.rejected"
fi
echo "REJECTED"
exit 0
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `bash ex-11-05-orchestrator-6phase/tests/test-judge-verdict.sh`
Expected: 모두 PASS

- [ ] **Step 5: Commit**

```bash
git add ex-11-05-orchestrator-6phase/.claude/skills/code-review-team/scripts/judge-verdict.sh ex-11-05-orchestrator-6phase/tests/test-judge-verdict.sh
git commit -m "feat: judge-verdict.sh로 재시도/격리 판정을 스크립트로 분리 (Agent 없이 테스트 가능)"
```

---

### Task 7: `refactorer.md` 수정 — 검증 루프 주체를 리더로 이전

**Files:**
- Modify: `ex-11-05-orchestrator-6phase/.claude/agents/refactorer.md`

**Interfaces:**
- Consumes: 없음 (독립적인 문서 수정)
- Produces: refactorer가 출력하는 `_workspace/review/04_refactor.md`의 `### {patch}.diff` / `- 발견 출처: {report}.md ...` 형식은 **그대로 유지** — Task 3(`route-verification.sh`)이 이 형식에 의존하므로 형식 자체는 바꾸지 않는다. 리더로부터 `VERDICT: FAIL - <사유>` + patch 파일명을 받으면 그 patch 1건만 재생성한다는 계약을 명시.

- [ ] **Step 1: "작업 원칙" 3번 항목 교체**

`ex-11-05-orchestrator-6phase/.claude/agents/refactorer.md`에서 다음을 찾아:

```
3. **생성-검증 루프 3회 상한**: 본인이 patch 만들고 리뷰어가 재검증해 거절하면 최대 2회 재시도. 3회째 거절이면 사람에게 위임.
```

다음으로 교체:

```
3. **재생성 요청 대응**: 리더가 특정 patch에 대해 `VERDICT: FAIL - <사유>`를 전달하며 재생성을 요청하면, 그 patch 하나만 사유를 반영해 다시 만든다. 몇 번째 시도인지, 언제 사람에게 위임할지는 리더가 관리한다(생성-검증 루프 상한 3회) — 본인은 재시도 횟수를 세지 않는다.
```

- [ ] **Step 2: "자동 커밋 금지" 다음에 적용 책임 항목 추가**

다음을 찾아:

```
5. **자동 커밋 금지**: `git commit` 호출 0건. patch 파일 생성만.
```

다음으로 교체(6번 항목 추가):

```
5. **자동 커밋 금지**: `git commit` 호출 0건. patch 파일 생성만.
6. **적용은 본인 책임이 아님**: patch를 working tree에 반영하는 것은 리더가 `apply-patches.sh`로 수행한다. 본인 역할은 `_workspace/patches/*.diff` 파일 생성까지.
```

- [ ] **Step 3: "팀 통신 프로토콜" 절 교체**

다음을 찾아:

```
## 팀 통신 프로토콜

- **수신**: 앞 3 리뷰어로부터 보고서 + SendMessage(추가 메모).
- **발신**: patch 생성 후 리뷰어 3인 모두에게 SendMessage("재검증 부탁"). 리더 미경유.
- 거절 2회째: 리더에게 "사람 위임 필요" 단일 보고.
```

다음으로 교체:

```
## 팀 통신 프로토콜

- **수신**: 리더로부터 3 리뷰어 보고서 경로. 재생성 요청 시에는 리더로부터 특정 patch 파일명 + `VERDICT: FAIL - <사유>`만 받는다.
- **발신**: 없음. patch 생성이 끝나면 파일(`_workspace/review/04_refactor.md`, `_workspace/patches/*.diff`)로 결과를 남기고 종료한다 — SendMessage로 동료를 직접 부르지 않는다. 검증은 리더가 해당 리뷰어를 재호출해 중계한다.
```

- [ ] **Step 4: 자체 검증 체크리스트 항목 수정**

다음을 찾아:

```
- [ ] 생성-검증 루프 ≤ 3회인가
```

다음으로 교체:

```
- [ ] 재생성 요청을 받으면 지정된 patch 1건만 사유를 반영해 재작성했는가 (횟수 관리는 리더 책임)
```

- [ ] **Step 5: 문법/구조 확인**

Run: `grep -c "SendMessage" ex-11-05-orchestrator-6phase/.claude/agents/refactorer.md`
Expected: `0` (peer SendMessage 문구가 완전히 제거되었는지 확인)

- [ ] **Step 6: Commit**

```bash
git add ex-11-05-orchestrator-6phase/.claude/agents/refactorer.md
git commit -m "refactor: refactorer.md — 검증 루프 관리 주체를 리더로 이전"
```

---

### Task 8: 리뷰어 3인 agent — peer SendMessage 제거 + 검증 응답 모드 추가

**Files:**
- Modify: `ex-11-05-orchestrator-6phase/.claude/agents/static-analyzer.md`
- Modify: `ex-11-05-orchestrator-6phase/.claude/agents/design-reviewer.md`
- Modify: `ex-11-05-orchestrator-6phase/.claude/agents/security-auditor.md`

**Interfaces:**
- Consumes: 없음
- Produces: 세 에이전트 모두 "검증 응답 모드"에서 응답 마지막 줄을 `VERDICT: PASS` 또는 `VERDICT: FAIL - <사유>`로 강제 — `judge-verdict.sh`(Task 6)와 SKILL.md Phase 4(Task 9)의 생성-검증 루프가 이 형식을 그대로 파싱한다.

- [ ] **Step 1: `static-analyzer.md` — 팀 통신 프로토콜 교체 + 검증 응답 모드 추가**

다음을 찾아:

```
## 팀 통신 프로토콜

- **수신**: 오케스트레이터(code-review-team)로부터 PR diff 위치.
- **발신**: 동료 리뷰어(design-reviewer / security-auditor / refactorer)에게 SendMessage. 리더 미경유.
- 같은 발견이 동료에게도 보이면 cross-domain 태그를 단다.
```

다음으로 교체:

```
## 팀 통신 프로토콜

- **수신**: 리더로부터 diff 위치. 검증 요청 시에는 특정 patch 파일 경로 + 자신이 낸 발견 1건만 받는다.
- **발신**: 리더에게만 보고. 같은 발견이 동료 영역에도 걸치면 SendMessage로 직접 알리지 않고, 보고서 안에 cross-domain 태그를 남긴다 — `merge-reports.sh`가 통합 보고서에 그대로 반영한다.

## 검증 응답 모드

리더가 "`_workspace/patches/{file}`가 자신의 발견 하나를 해결했는가"라고 좁게 물으면, 전체 재리뷰를 하지 않는다:

1. 지정된 patch 파일과 지정된 발견 1건만 다시 확인한다. diff 전체를 재분석하지 않는다.
2. 응답의 **마지막 줄은 반드시** `VERDICT: PASS` 또는 `VERDICT: FAIL - <한 줄 사유>` 중 하나로 끝낸다. 이 형식을 벗어나면 리더가 결과를 파싱할 수 없다.
3. 이 모드에서는 새 발견을 만들지 않는다 — 지정된 발견의 해결 여부만 판정한다.
```

- [ ] **Step 2: `design-reviewer.md` — 팀 통신 프로토콜 교체 + 검증 응답 모드 추가**

다음을 찾아:

```
## 팀 통신 프로토콜

- **수신**: 오케스트레이터로부터 PR diff.
- **발신**: 동료 리뷰어에게 SendMessage. 리더 미경유.
- 경계면 불일치는 static-analyzer·security-auditor 누구도 보지 못할 수 있다 — 본인이 발견하면 cross-domain 태그.
```

다음으로 교체:

```
## 팀 통신 프로토콜

- **수신**: 리더로부터 diff. 검증 요청 시에는 특정 patch 파일 경로 + 자신이 낸 발견 1건만 받는다.
- **발신**: 리더에게만 보고. 경계면 불일치는 static-analyzer·security-auditor 누구도 보지 못할 수 있다 — 본인이 발견하면 SendMessage 대신 보고서 안에 cross-domain 태그를 남긴다.

## 검증 응답 모드

리더가 "`_workspace/patches/{file}`가 자신의 발견 하나를 해결했는가"라고 좁게 물으면, 전체 재리뷰를 하지 않는다:

1. 지정된 patch 파일과 지정된 발견 1건만 다시 확인한다. diff 전체를 재분석하지 않는다.
2. 응답의 **마지막 줄은 반드시** `VERDICT: PASS` 또는 `VERDICT: FAIL - <한 줄 사유>` 중 하나로 끝낸다. 이 형식을 벗어나면 리더가 결과를 파싱할 수 없다.
3. 이 모드에서는 새 발견을 만들지 않는다 — 지정된 발견의 해결 여부만 판정한다.
```

- [ ] **Step 3: `security-auditor.md` — 팀 통신 프로토콜 교체 + 검증 응답 모드 추가**

다음을 찾아:

```
## 팀 통신 프로토콜

- **수신**: 오케스트레이터로부터 PR diff.
- **발신**: 동료 리뷰어에게 SendMessage. 리더 미경유. 예: SQL 인젝션 발견을 design-reviewer에게 "의존성 방향(API → DB)에서도 짚어달라" 요청.
```

다음으로 교체:

```
## 팀 통신 프로토콜

- **수신**: 리더로부터 diff. 검증 요청 시에는 특정 patch 파일 경로 + 자신이 낸 발견 1건만 받는다.
- **발신**: 리더에게만 보고. 다른 영역과 걸치는 발견(예: SQL 인젝션이 의존성 방향 문제와도 관련)은 SendMessage 대신 보고서 안에 cross-domain 태그로 남긴다.

## 검증 응답 모드

리더가 "`_workspace/patches/{file}`가 자신의 발견 하나를 해결했는가"라고 좁게 물으면, 전체 재리뷰를 하지 않는다:

1. 지정된 patch 파일과 지정된 발견 1건만 다시 확인한다. diff 전체를 재분석하지 않는다.
2. 응답의 **마지막 줄은 반드시** `VERDICT: PASS` 또는 `VERDICT: FAIL - <한 줄 사유>` 중 하나로 끝낸다. 이 형식을 벗어나면 리더가 결과를 파싱할 수 없다.
3. 이 모드에서는 새 발견을 만들지 않는다 — 지정된 발견의 해결 여부만 판정한다.
```

- [ ] **Step 4: peer SendMessage 완전 제거 확인**

Run: `grep -rc "동료 리뷰어에게 SendMessage" ex-11-05-orchestrator-6phase/.claude/agents/static-analyzer.md ex-11-05-orchestrator-6phase/.claude/agents/design-reviewer.md ex-11-05-orchestrator-6phase/.claude/agents/security-auditor.md`
Expected: 세 파일 모두 `:0`

- [ ] **Step 5: Commit**

```bash
git add ex-11-05-orchestrator-6phase/.claude/agents/static-analyzer.md ex-11-05-orchestrator-6phase/.claude/agents/design-reviewer.md ex-11-05-orchestrator-6phase/.claude/agents/security-auditor.md
git commit -m "refactor: 리뷰어 3인 — peer SendMessage 제거, VERDICT 기반 검증 응답 모드 추가"
```

---

### Task 9: `SKILL.md` 재작성 — 실제 도구 기반 오케스트레이션

**Files:**
- Modify (전면 재작성): `ex-11-05-orchestrator-6phase/.claude/skills/code-review-team/SKILL.md`

**Interfaces:**
- Consumes: `scripts/resolve-diff.sh`(Task 2), `scripts/route-verification.sh`(Task 3), `scripts/merge-reports.sh`(Task 4), `scripts/apply-patches.sh`(Task 5), `scripts/judge-verdict.sh`(Task 6)의 정확한 입출력 경로. `refactorer`/`static-analyzer`/`design-reviewer`/`security-auditor`의 `VERDICT:` 계약(Task 7, 8).
- Produces: 이 스킬을 "코드 리뷰"/"PR 리뷰"/"리뷰 재실행" 트리거로 호출했을 때 실제로 실행 가능한 절차.

- [ ] **Step 1: SKILL.md 전체 교체**

`ex-11-05-orchestrator-6phase/.claude/skills/code-review-team/SKILL.md`의 전체 내용을 다음으로 교체:

```markdown
---
name: code-review-team
description: PR diff 또는 로컬 git diff에 대해 정적분석·설계·보안 3 리뷰어 + 리팩토러 4인 팀을 운영한다. 트리거 - "코드 리뷰", "PR 리뷰", "리뷰 재실행", "다시 실행", "리뷰 보고서".
allowed-tools: Agent, Bash(resolve-diff.sh, route-verification.sh, judge-verdict.sh, merge-reports.sh, apply-patches.sh, gh pr diff, gh pr comment), Read, Write
---

# code-review-team

> 4인 리뷰어 팀 오케스트레이터. 리더는 판단 없이 호출과 스크립트 실행만 한다 — 보고서 본문은 워커 4인이, 반복 로직은 `scripts/`가 담당한다.

## 사용 시점

- PR 번호가 주어지고 코드 리뷰를 요청받았을 때 → PR 모드
- PR 번호 없이 "코드 리뷰", "리뷰 재실행" 등으로 요청받았을 때 → 로컬 diff 모드 (현재 브랜치의 staged/unstaged/브랜치 base 변경사항을 `resolve-diff.sh`가 자동 판별)
- "리뷰 재실행", "다시 실행" — 동일 입력으로 재구동 (이전 `_workspace/review/*` 결과 덮어쓰기)

## Phase 0 — 입력 확보

1. `Bash: bash .claude/skills/code-review-team/scripts/resolve-diff.sh [PR번호]` 실행
2. exit code가 0이 아니면: 사용자에게 "리뷰할 변경사항이 없습니다"라고 보고하고 **여기서 종료** (워커를 스폰하지 않는다 — 토큰 절약)
3. PR 모드로 호출했는데 stderr에 "로컬 diff로 폴백" 메시지가 있었다면, 그 사실을 사용자에게 알린다

## Phase 1~3 — 병렬 리뷰

한 메시지에서 `Agent` 도구를 3회 호출한다 (병렬 실행, 서로 의존관계 없음):

- `subagent_type: "static-analyzer"` — 프롬프트에 `_workspace/input/diff.patch`, `_workspace/input/files.txt` 경로와 출력 경로 `_workspace/review/01_static.md` 전달
- `subagent_type: "design-reviewer"` — 출력 경로 `_workspace/review/02_design.md`
- `subagent_type: "security-auditor"` — 출력 경로 `_workspace/review/03_security.md`

세 `Agent` 호출이 모두 반환되면 다음 Phase로 진행한다 (Agent 도구는 완료 시 결과를 반환하므로 별도 폴링 불필요).

## Phase 4 — refactorer + 생성-검증 루프

1. `Agent(subagent_type: "refactorer")` 1회 호출. 프롬프트에 세 보고서 경로(`01_static.md`, `02_design.md`, `03_security.md`)와 출력 경로(`_workspace/review/04_refactor.md`, `_workspace/patches/`) 전달.
2. `Bash: bash .claude/skills/code-review-team/scripts/route-verification.sh` 실행 → `_workspace/verification/queue.tsv` 생성. 이 파일이 비어 있으면(=P0 patch 없음) Phase 5로 바로 진행.
3. `queue.tsv`를 한 줄씩(patch파일, 담당에이전트, 발견원문 — 탭 구분 3열) 순회하며, **patch당 시도 횟수를 1로 시작해** 아래를 반복한다:
   1. `Agent(subagent_type: <담당에이전트>)` 호출. 프롬프트: "`_workspace/patches/{patch}`가 `_workspace/review/{원본보고서}`의 다음 발견을 해결했는지만 확인하라: {발견원문}. 전체 재리뷰는 하지 말고 이 patch 하나만 확인한 뒤, 응답 마지막 줄을 반드시 `VERDICT: PASS` 또는 `VERDICT: FAIL - <한 줄 사유>`로 끝내라."
   2. 그 응답 전체를 `Bash: bash .claude/skills/code-review-team/scripts/judge-verdict.sh {patch} {시도횟수}` 에 stdin으로 넘긴다. 결과는 `PASS`/`RETRY`/`REJECTED` 중 하나.
   3. `PASS`면: 이 patch는 통과. 다음 patch로 이동.
   4. `RETRY`면: `Agent(subagent_type: "refactorer")`를 다시 호출해 "patch {patch}가 다음 사유로 거절됨: {검증 응답에서 나온 사유 또는 '응답 형식 위반'}. 이 patch만 재생성하라" 요청하고, 시도 횟수 +1 후 3.1로 돌아간다.
   5. `REJECTED`면: `judge-verdict.sh`가 이미 `_workspace/patches/{patch}` → `{patch}.rejected` 리네임까지 끝낸 상태. 이 patch는 사람 위임 대상으로 두고 다음 patch로 이동 — 리더가 직접 파일을 옮기지 않는다.

## Phase 5 — 통합 · 패치 적용 · 게시

1. `Bash: bash .claude/skills/code-review-team/scripts/merge-reports.sh` → `_workspace/review_report.md`
2. `Bash: bash .claude/skills/code-review-team/scripts/apply-patches.sh` → working tree에 반영(커밋 없음). exit code가 0이 아니면(=실패한 patch 있음) 그 stdout의 `FAILED:` 목록을 `_workspace/review_report.md` 맨 위에 한 줄로 덧붙인다(파일명 나열만, 내용 해석 없음).
3. **PR 모드였다면**: 사용자에게 "PR #{N}에 통합 보고서를 코멘트로 게시할까요?"를 확인하고, 승인 시 `Bash: gh pr comment {N} -F _workspace/review_report.md`
4. **로컬 모드였다면**: 게시 없이 종료. `_workspace/review_report.md` 위치를 사용자에게 안내.

## 불변 규칙

- **리더 무발화**: 리더는 보고서·발견 내용을 읽고 판단하지 않는다. 라우팅은 스크립트 출력을, 검증은 `VERDICT:` 한 줄만 본다.
- **자동 커밋 금지**: 이 스킬은 어떤 단계에서도 `git commit`을 호출하지 않는다. `git apply`로 working tree만 바꾼다.
- **workspace 보존**: 실행 종료 후에도 `_workspace/`는 삭제하지 않는다.
- **생성-검증 루프 ≤3회 (patch 단위)**: 3회 시도 후에도 실패하면 `.rejected`로 격리하고 적용하지 않는다.
- **재실행**: 동일 입력(PR 번호 또는 로컬 diff)으로 다시 실행하면 `_workspace/review/*`를 덮어쓴다.
- **이식성**: 이 폴더(`.claude/skills/code-review-team/` + `.claude/agents/*.md`)를 통째로 다른 저장소에 복사하면 별도 설치 없이 바로 동작한다.
```

- [ ] **Step 2: frontmatter 파싱 확인**

Run: `head -5 ex-11-05-orchestrator-6phase/.claude/skills/code-review-team/SKILL.md`
Expected: `---`로 시작하는 YAML frontmatter가 깨지지 않고 출력됨(`name`, `description`, `allowed-tools` 라인 확인)

- [ ] **Step 3: Commit**

```bash
git add ex-11-05-orchestrator-6phase/.claude/skills/code-review-team/SKILL.md
git commit -m "feat: SKILL.md를 실제 Agent/Bash 기반 오케스트레이션으로 재작성"
```

---

### Task 10: 전체 테스트 + End-to-end dry-run 검증

**Files:**
- (코드 변경 없음 — 검증 전용 태스크)

**Interfaces:**
- Consumes: Task 1~9의 모든 산출물
- Produces: 실행 가능함을 확인한 로그. 이 태스크는 새 파일을 커밋하지 않는다(생성된 `_workspace/`는 검증 후 그대로 두거나 사용자 확인 후 정리).

- [ ] **Step 1: 스크립트 전체 테스트 실행**

Run: `bash ex-11-05-orchestrator-6phase/tests/run-all.sh`
Expected: `test-resolve-diff.sh`, `test-route-verification.sh`, `test-judge-verdict.sh`, `test-merge-reports.sh`, `test-apply-patches.sh` 5개 파일 모두 `=== all tests passed ===`, 스크립트 exit code 0

- [ ] **Step 2: 로컬 diff 모드 End-to-end dry-run**

이 태스크는 **일반 subagent에 위임하지 말고, 이 스킬을 실제로 트리거할 수 있는 메인 세션에서 직접 수행한다** — `Agent` 도구로 4개 서브에이전트를 실제 호출해야 하므로 순수 셸 명령으로는 재현할 수 없다.

1. `harness-engineering` 저장소에 실제 로컬 diff가 있는 상태를 만든다(이번 작업 중 생긴 CLAUDE.md/스펙/플랜 변경 등 기존 diff를 그대로 사용해도 됨).
2. "코드 리뷰" 트리거로 `code-review-team` 스킬을 호출한다.
3. Phase 0~5가 실제로 진행되는지 관찰: `_workspace/input/`, `_workspace/review/`, (P0 발견이 있다면) `_workspace/verification/queue.tsv`, `_workspace/patches/`, `_workspace/review_report.md`가 생성되는지 확인.
4. 리더가 검증/판정 과정에서 보고서 원문을 그대로 인용하거나 해석하는 발화를 하지 않는지 확인 (라우팅=스크립트 출력, 판정=`VERDICT:` 한 줄만 참조).
5. `git status`로 working tree에 커밋되지 않은 patch 적용 결과가 있는지(P0 발견이 있었던 경우) 확인.

Expected: 위 산출물이 모두 실제로 생성되고, 어떤 단계에서도 `git commit`이 호출되지 않으며, 리더 발화가 호출/보고 중계 수준을 벗어나지 않는다.

- [ ] **Step 3: 결과 기록**

dry-run 중 스크립트 로직에 실제 버그가 발견되면(예: awk 파싱이 특정 마크다운 변형에서 깨짐) 해당 스크립트로 돌아가 테스트 케이스를 추가하고 수정한 뒤 이 태스크를 재실행한다. 문제 없으면 사용자에게 dry-run 결과를 간단히 보고한다 (커밋 없음, 이 태스크는 검증 전용).
