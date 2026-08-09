# reviewing-skill-md Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 임의의 SKILL.md를 실무에서 바로 리뷰할 수 있는 독립 스킬 `reviewing-skill-md`를 만들고, 저장소 내 실제 SKILL.md 3종에 적용해 검증한다.

**Architecture:** `SKILL.md`(트리거·실행 흐름) + `references/checklist.md`(A~D 4개 카테고리 심사 기준) + `scripts/collect-metrics.sh`(정량 지표 자동 수집)로 구성된 자기완결적 스킬 디렉터리. 정량 지표는 스크립트로 고정 수집하고, 정성 항목은 대상 파일을 직접 읽어 판단한다.

**Tech Stack:** Bash (POSIX 계열 wc/grep/awk/sed), Markdown

## Global Constraints

- 커밋 메시지는 한국어로 작성한다.
- 코드 주석은 한국어로 작성하되, 동작이 비자명한 경우에만 추가한다 (예: `set -o pipefail`와 grep의 "매치 없음=exit 1" 상호작용).
- `.claude/skills/reviewing-skill-md/`는 이 저장소의 특정 경로를 하드코딩하지 않는다 — 다른 프로젝트의 `.claude/skills/`에 폴더째 복사해도 그대로 동작해야 한다.
- 여러 SKILL.md를 한 번에 스캔하는 배치/디렉터리 순회 기능은 만들지 않는다. 자동 수정(코드 편집) 기능도 만들지 않는다 — 리포트 전용.
- 정량 지표는 반드시 `scripts/collect-metrics.sh`를 통해서만 수집한다 (매 실행마다 다른 grep 패턴을 즉석에서 만들지 않는다).
- 각 판정 항목은 `pass`/`warn`/`fail` 3단계를 쓴다. 종합 판정은 아래 4규칙을 순서대로 첫 매칭 적용한다:
  1. fail 2개 이상 또는 D 카테고리(안티패턴)에 fail 1개 이상 → `high`
  2. fail 1개 → `med`
  3. fail 0개, warn 1개 이상 → `low`
  4. fail 0개, warn 0개 → `pass`

---

### Task 1: collect-metrics.sh 스크립트 (TDD)

**Files:**
- Create: `ex-05-13-skill-md-reviewer/.claude/skills/reviewing-skill-md/scripts/tests/fixture-sample-SKILL.md`
- Create: `ex-05-13-skill-md-reviewer/.claude/skills/reviewing-skill-md/scripts/tests/test-collect-metrics.sh`
- Create: `ex-05-13-skill-md-reviewer/.claude/skills/reviewing-skill-md/scripts/collect-metrics.sh`

**Interfaces:**
- Consumes: 없음 (최초 태스크)
- Produces: `collect-metrics.sh <SKILL.md 경로>` 실행 시 아래 순서의 `key: value` 표준출력. 이후 모든 태스크가 이 출력 포맷을 그대로 사용한다.
  ```
  line_count: <int>
  word_count: <int>
  frontmatter_chars: <int>
  name_value: <string>
  description_value: <string>
  branch_keyword_count: <int>
  imperative_count: <int>
  reason_count: <int>
  dot_block_count: <int>
  has_references_dir: yes|no
  headers:
    - <header text>
    - ...
  ```

- [ ] **Step 1: 테스트 픽스처 작성**

`ex-05-13-skill-md-reviewer/.claude/skills/reviewing-skill-md/scripts/tests/fixture-sample-SKILL.md`:

```markdown
---
name: sample-skill
description: Use when testing collect-metrics.sh output values
---

# Sample Skill

## Overview
Sample skill for testing collect-metrics.sh only.

## When to Use
이면 발동한다. 일 때 발동한다. 인 경우 발동한다.

## Rule
ALWAYS validate input. NEVER skip checks. 반드시 확인하라. 절대 무시하지 마라. 절대 안 된다.
왜냐하면 정확성이 중요하기 때문에.
```

파일이 정확히 16줄(마지막 줄 뒤 개행 포함)로 끝나도록 저장한다.

- [ ] **Step 2: 테스트 스크립트 작성**

`ex-05-13-skill-md-reviewer/.claude/skills/reviewing-skill-md/scripts/tests/test-collect-metrics.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COLLECT="$SCRIPT_DIR/../collect-metrics.sh"
FIXTURE="$SCRIPT_DIR/fixture-sample-SKILL.md"

output=$(bash "$COLLECT" "$FIXTURE")

assert_line() {
  local key="$1"
  local expected="$2"
  local actual
  actual=$(printf '%s\n' "$output" | grep "^${key}:" | sed "s/^${key}: *//")
  if [ "$actual" != "$expected" ]; then
    echo "FAIL: $key expected [$expected] got [$actual]"
    exit 1
  fi
  echo "PASS: $key = $actual"
}

assert_contains() {
  local needle="$1"
  if ! printf '%s\n' "$output" | grep -qF -- "$needle"; then
    echo "FAIL: expected output to contain [$needle]"
    exit 1
  fi
  echo "PASS: contains [$needle]"
}

assert_line "line_count" "16"
assert_line "name_value" "sample-skill"
assert_line "description_value" "Use when testing collect-metrics.sh output values"
assert_line "branch_keyword_count" "3"
assert_line "imperative_count" "5"
assert_line "reason_count" "2"
assert_line "dot_block_count" "0"
assert_line "has_references_dir" "no"

# frontmatter_chars는 픽스처의 실제 frontmatter 텍스트로부터 동일한 방식(printf %s | wc -m)으로
# 기대값을 계산해 하드코딩 오차를 없앤다.
expected_fm_chars=$(printf '%s' "$(cat <<'EOF'
name: sample-skill
description: Use when testing collect-metrics.sh output values
EOF
)" | wc -m | tr -d ' ')
assert_line "frontmatter_chars" "$expected_fm_chars"

assert_contains "  - Overview"
assert_contains "  - When to Use"
assert_contains "  - Rule"

echo "ALL TESTS PASSED"
```

- [ ] **Step 3: 실행 권한 부여 및 실패 확인**

```bash
chmod +x ex-05-13-skill-md-reviewer/.claude/skills/reviewing-skill-md/scripts/tests/test-collect-metrics.sh
bash ex-05-13-skill-md-reviewer/.claude/skills/reviewing-skill-md/scripts/tests/test-collect-metrics.sh
```

Expected: `collect-metrics.sh: No such file or directory` 류의 오류로 실패 (아직 구현 전이므로 RED 확인).

- [ ] **Step 4: collect-metrics.sh 구현**

`ex-05-13-skill-md-reviewer/.claude/skills/reviewing-skill-md/scripts/collect-metrics.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "사용법: $0 <SKILL.md 경로>" >&2
  exit 1
fi

FILE="$1"

if [ ! -f "$FILE" ]; then
  echo "파일을 찾을 수 없습니다: $FILE" >&2
  exit 1
fi

DIR="$(dirname "$FILE")"

line_count=$(wc -l < "$FILE" | tr -d ' ')
word_count=$(wc -w < "$FILE" | tr -d ' ')

# frontmatter 블록(첫 --- ~ 두 번째 --- 직전)만 추출한다.
frontmatter=$(awk '/^---$/{c++; if(c==2) exit; next} c==1' "$FILE")
frontmatter_chars=$(printf '%s' "$frontmatter" | wc -m | tr -d ' ')

name_value=$(printf '%s\n' "$frontmatter" | grep -m1 '^name:' | sed 's/^name: *//' || true)
description_value=$(printf '%s\n' "$frontmatter" | grep -m1 '^description:' | sed 's/^description: *//' || true)

# grep은 매치가 없으면 exit 1을 반환한다. set -o pipefail 아래서 파이프라인 전체가
# 실패로 취급되어 set -e에 걸리므로, 매치 0건이 정상 케이스인 아래 항목들은 || true로 보호한다.
branch_keyword_count=$(grep -oE '이면|일 때|인 경우' "$FILE" | wc -l | tr -d ' ' || true)
imperative_count=$(grep -oE 'ALWAYS|NEVER|반드시|절대' "$FILE" | wc -l | tr -d ' ' || true)
reason_count=$(grep -oE '왜냐하면|때문에' "$FILE" | wc -l | tr -d ' ' || true)
dot_block_count=$(grep -c '```dot' "$FILE" | tr -d ' ' || true)

if [ -d "$DIR/references" ]; then
  has_references_dir="yes"
else
  has_references_dir="no"
fi

headers=$(grep -E '^## ' "$FILE" | sed 's/^## //' || true)

echo "line_count: $line_count"
echo "word_count: $word_count"
echo "frontmatter_chars: $frontmatter_chars"
echo "name_value: $name_value"
echo "description_value: $description_value"
echo "branch_keyword_count: $branch_keyword_count"
echo "imperative_count: $imperative_count"
echo "reason_count: $reason_count"
echo "dot_block_count: $dot_block_count"
echo "has_references_dir: $has_references_dir"
echo "headers:"
if [ -n "$headers" ]; then
  echo "$headers" | sed 's/^/  - /'
else
  echo "  (none)"
fi
```

- [ ] **Step 5: 실행 권한 부여 및 통과 확인**

```bash
chmod +x ex-05-13-skill-md-reviewer/.claude/skills/reviewing-skill-md/scripts/collect-metrics.sh
bash ex-05-13-skill-md-reviewer/.claude/skills/reviewing-skill-md/scripts/tests/test-collect-metrics.sh
```

Expected: 모든 `assert_line`/`assert_contains`가 `PASS`로 출력되고 마지막 줄에 `ALL TESTS PASSED`.

- [ ] **Step 6: 커밋**

```bash
git add ex-05-13-skill-md-reviewer/.claude/skills/reviewing-skill-md/scripts
git commit -m "$(cat <<'EOF'
collect-metrics.sh 정량 지표 수집 스크립트 추가

SKILL.md의 줄 수·frontmatter 길이·키워드 카운트 등을 고정된 방식으로
수집해 리뷰마다 다른 grep 패턴을 즉석에서 만들지 않도록 한다.
EOF
)"
```

---

### Task 2: SKILL.md 작성 + 자기 검증

**Files:**
- Create: `ex-05-13-skill-md-reviewer/.claude/skills/reviewing-skill-md/SKILL.md`

**Interfaces:**
- Consumes: Task 1의 `scripts/collect-metrics.sh` (자기 자신을 검증하는 데 사용)
- Produces: SKILL.md 본문 (Task 3의 `references/checklist.md`가 링크 대상으로 참조)

- [ ] **Step 1: SKILL.md 작성**

`ex-05-13-skill-md-reviewer/.claude/skills/reviewing-skill-md/SKILL.md`:

```markdown
---
name: reviewing-skill-md
description: Use when reviewing a SKILL.md file before shipping it, extending an existing skill, or auditing a project's skills for structure, discoverability, size, or anti-patterns.
---

# Reviewing SKILL.md

## Overview
임의의 SKILL.md 파일 하나를 구조·발견성(discoverability)·크기·안티패턴 관점에서 진단하고 pass/warn/fail 리포트를 만든다. 코드를 수정하지 않는 리뷰 전용 스킬이다.

## When to Use
- 새 SKILL.md를 작성해 배포하기 전
- 기존 스킬을 확장한 뒤 품질을 재점검할 때
- 프로젝트의 여러 스킬 중 하나를 감사(audit)할 때

## 실행 흐름
1. 리뷰 대상 SKILL.md 경로를 확인한다.
2. `scripts/collect-metrics.sh <경로>`를 실행해 정량 지표(줄 수, frontmatter 길이, 키워드 카운트 등)를 수집한다.
3. `references/checklist.md`를 읽고 A(Frontmatter & Discovery)/B(구조 & 콘텐츠)/C(크기 & 분리 신호)/D(안티패턴) 4개 카테고리를 판정한다. 정량 지표는 스크립트 결과를 쓰고, 정성 항목은 대상 파일을 직접 읽어 판단한다.
4. 카테고리별 pass/warn/fail과 근거·권고를 정리해 마크다운 리포트로 출력한다.
5. `references/checklist.md`의 종합 판정 규칙에 따라 전체 등급(high/med/low/pass)을 매기고 우선순위 개선 Top 3를 제시한다.

리뷰 기준의 전체 상세는 `references/checklist.md`를 참조한다.
```

- [ ] **Step 2: frontmatter 자기 검증**

```bash
bash ex-05-13-skill-md-reviewer/.claude/skills/reviewing-skill-md/scripts/collect-metrics.sh \
  ex-05-13-skill-md-reviewer/.claude/skills/reviewing-skill-md/SKILL.md
```

출력에서 `name_value: reviewing-skill-md`를 확인한다. 이어서 frontmatter 길이가 1024자 미만인지 스크립트로 검증한다:

```bash
fm_chars=$(bash ex-05-13-skill-md-reviewer/.claude/skills/reviewing-skill-md/scripts/collect-metrics.sh \
  ex-05-13-skill-md-reviewer/.claude/skills/reviewing-skill-md/SKILL.md \
  | grep '^frontmatter_chars:' | sed 's/^frontmatter_chars: *//')
if [ "$fm_chars" -ge 1024 ]; then
  echo "FAIL: frontmatter $fm_chars >= 1024"
  exit 1
fi
echo "PASS: frontmatter_chars=$fm_chars < 1024"
```

Expected: `PASS: frontmatter_chars=<200 내외> < 1024`.

- [ ] **Step 3: 커밋**

```bash
git add ex-05-13-skill-md-reviewer/.claude/skills/reviewing-skill-md/SKILL.md
git commit -m "$(cat <<'EOF'
reviewing-skill-md SKILL.md 작성

트리거 조건과 5단계 실행 흐름만 담고, 심사 기준 본문은
references/checklist.md로 위임한다.
EOF
)"
```

---

### Task 3: references/checklist.md 작성 + 헤더 검증

**Files:**
- Create: `ex-05-13-skill-md-reviewer/.claude/skills/reviewing-skill-md/references/checklist.md`

**Interfaces:**
- Consumes: 없음 (Task 2의 SKILL.md에서 참조 링크만 받음)
- Produces: A~D 4개 카테고리 판정 기준표 + 종합 판정 규칙. Task 5~7이 이 파일의 규칙을 그대로 적용한다.

- [ ] **Step 1: checklist.md 작성**

`ex-05-13-skill-md-reviewer/.claude/skills/reviewing-skill-md/references/checklist.md`:

```markdown
# SKILL.md 리뷰 체크리스트

## A. Frontmatter & Discovery
| 항목 | 판정 규칙 | 근거 소스 |
|---|---|---|
| name 형식 | `name` 값이 영문 소문자/숫자/하이픈만 포함(정규식 `^[a-z0-9-]+$`) 아니면 fail | collect-metrics.sh `name_value` |
| frontmatter 전체 길이 | frontmatter 블록 전체 문자 수가 1024자 초과 시 fail, 800~1024자 warn, 그 외 pass | collect-metrics.sh `frontmatter_chars` |
| 트리거 중심 서술 | description이 트리거 조건(영어 "Use when...", 한국어 "사용자가 ~하면", "~때 호출", "~인 경우" 등) 없이 스킬 기능·워크플로 설명으로만 채워져 있으면 fail. 트리거 조건 문장이 있으나 기능/워크플로 설명이 먼저 나오면 warn. 트리거 조건이 문장 맨 앞에 오면 pass. | description 텍스트 직접 확인 |
| 3인칭 서술 | description에 "I", "저는", "나는" 등 1인칭 표현이 있으면 fail | description 텍스트 직접 확인 |

## B. 구조 & 콘텐츠
| 항목 | 판정 규칙 | 근거 소스 |
|---|---|---|
| 권장 섹션 존재 | 개요 역할 섹션(Overview/개요/목표 등)과 사용 시점 역할 섹션(When to Use/사용 시점/언제 사용 등) 중 하나라도 없으면 warn | collect-metrics.sh `headers` (의미 등가 여부는 직접 판단) |
| flowchart 남용 | ` ```dot ` 블록 수가 2개 초과면 warn | collect-metrics.sh `dot_block_count` |
| 코드 예시 다중 언어 남발 | 동일 개념에 대해 3개 이상 언어의 코드 블록이 나란히 있으면 warn | 텍스트 직접 확인 |

## C. 크기 & 분리 신호
| 항목 | 판정 규칙 | 근거 소스 |
|---|---|---|
| 크기 신호 | 총 줄 수 >= 500 이면 fail, 300~499 warn, 그 외 pass | collect-metrics.sh `line_count` |
| 도메인 분기 신호 | 도메인 분기 키워드 매칭 수가 2 이상인데 `references/` 디렉터리가 없거나 본문에 도메인 상세 내용이 남아있으면: 2~3개는 warn, 4개 이상은 fail. `references/`가 있고 본문에는 위임 안내만 있을 뿐 도메인 상세 내용이 없다면 이미 해결된 것으로 보고 pass. | collect-metrics.sh `branch_keyword_count`, `has_references_dir` + 본문 직접 확인 |
| 조건부 상세 신호 | 조건부 문구("~때만", "~인 경우에만") 뒤에 10줄 이상의 상세 설명이 인라인으로 이어지면 warn (references로 위임 권고) | 텍스트 직접 확인 |

## D. 안티패턴
| 항목 | 판정 규칙 | 근거 소스 |
|---|---|---|
| 거대 본문 | 총 줄 수 >= 500 이면 fail (C의 크기 신호와 동일 지표 — 종합 판정 시 중복 카운트하지 않고 1건으로 취급) | collect-metrics.sh `line_count` |
| references 부재 | `references/` 디렉터리가 없고 도메인 분기 키워드 수 >= 4 이면 fail | collect-metrics.sh `has_references_dir`, `branch_keyword_count` |
| 이유 없는 규칙 | `ALWAYS`/`NEVER`/`반드시`/`절대` 매칭 수 >= 5 이고 `왜냐하면`/`때문에` 매칭 수 == 0 이면 fail | collect-metrics.sh `imperative_count`, `reason_count` |
| 일반 지식 서술 | 표준 언어/라이브러리 문법을 설명하는 문단이 있으면 warn (삭제 권고) | 텍스트 직접 확인 |
| 도메인 관례 누락 | 팀/프로젝트 고유 규칙이 있어야 할 자리가 비어 있으면 warn (추가 권고) | 텍스트 직접 확인 |

## 종합 판정 규칙
1. fail 2개 이상 또는 D 카테고리(안티패턴)에 fail 1개 이상 → **high**
2. fail 1개 → **med**
3. fail 0개, warn 1개 이상 → **low**
4. fail 0개, warn 0개(전부 pass) → **pass**
```

- [ ] **Step 2: 헤더 검증**

```bash
CHECKLIST=ex-05-13-skill-md-reviewer/.claude/skills/reviewing-skill-md/references/checklist.md
count=$(grep -cE '^## [A-D]\.' "$CHECKLIST")
if [ "$count" -ne 4 ]; then
  echo "FAIL: expected 4 categories, got $count"
  exit 1
fi
grep -q '^## 종합 판정 규칙' "$CHECKLIST" || { echo "FAIL: 종합 판정 규칙 섹션 없음"; exit 1; }
echo "PASS: 4개 카테고리 + 종합 판정 규칙 섹션 확인"
```

Expected: `PASS: 4개 카테고리 + 종합 판정 규칙 섹션 확인`.

- [ ] **Step 3: 커밋**

```bash
git add ex-05-13-skill-md-reviewer/.claude/skills/reviewing-skill-md/references/checklist.md
git commit -m "$(cat <<'EOF'
SKILL.md 리뷰 체크리스트 작성

ex-05-05(분리 신호)/ex-05-09(컨텍스트 절약 3원칙)/ex-05-12(안티패턴 3종)의
판정 규칙을 통합하고 Anthropic 공식 가이드의 frontmatter/구조 기준을 보강한다.
EOF
)"
```

---

### Task 4: CLAUDE.md 작성

**Files:**
- Create: `ex-05-13-skill-md-reviewer/CLAUDE.md`

**Interfaces:**
- Consumes: 없음
- Produces: 예제 폴더 제약 조건 (Task 5~8 작업 시 준수)

- [ ] **Step 1: CLAUDE.md 작성**

`ex-05-13-skill-md-reviewer/CLAUDE.md`:

```markdown
# CLAUDE.md — ex-05-13 SKILL.md 실무 리뷰 스킬

- `.claude/skills/reviewing-skill-md/`는 다른 프로젝트에 폴더째 복사해 재사용 가능하도록 이 저장소 특정 경로를 하드코딩하지 않는다.
- 심사 기준(references/checklist.md)은 ex-05-05(분리 신호)/ex-05-09(컨텍스트 절약 3원칙)/ex-05-12(안티패턴 3종)의 판정 규칙을 그대로 보존해 통합한다.
- 정량 지표는 scripts/collect-metrics.sh로만 수집한다 (매 실행마다 다른 grep 패턴을 즉석에서 만들지 않는다).
- 리뷰 대상은 이 저장소에 이미 존재하는 실제 SKILL.md 3종(ex-05-06/sql-query, ex-05-11/csv-summary, ex-06-12/pr-review-orchestrator)이며, 크래프팅된 위반 샘플을 새로 만들지 않는다.
- 리포트는 생성만 하고 대상 파일을 자동 수정하지 않는다.
```

- [ ] **Step 2: 존재 확인**

```bash
test -f ex-05-13-skill-md-reviewer/CLAUDE.md && echo "PASS: CLAUDE.md 존재"
```

- [ ] **Step 3: 커밋**

```bash
git add ex-05-13-skill-md-reviewer/CLAUDE.md
git commit -m "ex-05-13 CLAUDE.md 추가 — 예제 제약 조건 명시"
```

---

### Task 5: sql-query 리뷰 실행

**Files:**
- Create: `ex-05-13-skill-md-reviewer/result/review-sql-query.md`

**Interfaces:**
- Consumes: Task 1 `scripts/collect-metrics.sh` 출력 포맷, Task 3 `references/checklist.md` 판정 규칙
- Produces: `result/review-sql-query.md` (Task 8 README 요약 표에서 참조)

- [ ] **Step 1: 정량 지표 재확인**

```bash
bash ex-05-13-skill-md-reviewer/.claude/skills/reviewing-skill-md/scripts/collect-metrics.sh \
  ex-05-06-domain-references/.claude/skills/sql-query/SKILL.md
```

Expected (스킬 파일이 수정되지 않았다면 아래와 정확히 일치해야 함):
```
line_count: 15
word_count: 71
frontmatter_chars: 162
name_value: sql-query
branch_keyword_count: 2
imperative_count: 0
reason_count: 0
dot_block_count: 0
has_references_dir: yes
headers:
  - 라우팅
```

값이 다르면 `ex-05-06-domain-references/.claude/skills/sql-query/SKILL.md`가 이 플랜 작성 이후 변경된 것이므로, Step 3 리뷰 내용을 실제 값에 맞게 다시 산출한다.

- [ ] **Step 2: 대상 파일 원문 확인**

`ex-05-06-domain-references/.claude/skills/sql-query/SKILL.md` 전체 내용을 Read하여 Step 1 지표와 대조한다 (frontmatter의 description, 본문 "## 라우팅" 섹션 2줄, 마지막 위임 안내 줄 확인).

- [ ] **Step 3: 리뷰 리포트 작성**

`ex-05-13-skill-md-reviewer/result/review-sql-query.md`:

```markdown
# SKILL.md 리뷰: ex-05-06-domain-references/.claude/skills/sql-query/SKILL.md
개요: 15줄 / 71단어 / frontmatter 162자

## A. Frontmatter & Discovery
- [pass] name 형식 — 근거: `sql-query`, 영문 소문자+하이픈만 사용 — 권고: 없음
- [pass] frontmatter 전체 길이 — 근거: 162자 (< 800자) — 권고: 없음
- [warn] 트리거 중심 서술 — 근거: description이 "데이터베이스 쿼리 생성: 매출·재고 도메인 분기."로 시작해 기능 설명이 먼저 나오고, 트리거 조건("사용자가 'Q4 매출', '재고 현황' 등을 언급하면 호출")은 두 번째 문장에 위치 — 권고: 트리거 조건 문장을 맨 앞으로 재배치 (예: "사용자가 'Q4 매출', '재고 현황' 등 도메인 쿼리를 요청하면 호출")
- [pass] 3인칭 서술 — 근거: 1인칭 표현 없음 — 권고: 없음

## B. 구조 & 콘텐츠
- [warn] 권장 섹션 존재 — 근거: 본문 헤더가 `## 라우팅` 하나뿐, Overview/When to Use 역할 섹션 없음 — 권고: 15줄짜리 라우터 스킬이라 필수는 아니나, "이 스킬은 무엇을 라우팅하는가"를 짧게 밝히는 개요 한 줄 추가 권장
- [pass] flowchart 남용 — 근거: dot 블록 0개 — 권고: 없음
- [pass] 코드 예시 다중 언어 남발 — 근거: 코드 블록 없음 — 권고: 없음

## C. 크기 & 분리 신호
- [pass] 크기 신호 — 근거: 15줄 (< 300줄) — 권고: 없음
- [pass] 도메인 분기 신호 — 근거: 분기 키워드 2개("매출 관련 요청이면", "재고 관련 요청이면") 발견되지만 `references/` 디렉터리가 존재하고 본문에는 위임 안내(`→ references/finance.md`, `→ references/inventory.md`)만 있을 뿐 도메인 상세 내용이 없음 — 이미 위임 완료 — 권고: 없음
- [pass] 조건부 상세 신호 — 근거: "도메인 템플릿이 필요할 때만 해당 references를 로드한다"는 조건부 문구는 있으나 뒤따르는 인라인 상세 설명 없음 — 권고: 없음

## D. 안티패턴
- [pass] 거대 본문 — 근거: 15줄 — 권고: 없음
- [pass] references 부재 — 근거: `references/` 디렉터리 존재 — 권고: 없음
- [pass] 이유 없는 규칙 — 근거: ALWAYS/NEVER/반드시/절대 매칭 0건 — 권고: 없음
- [pass] 일반 지식 서술 — 근거: 표준 SQL 문법 설명 문단 없음 — 권고: 없음
- [pass] 도메인 관례 누락 — 근거: 해당 없음 (라우터 역할만 수행) — 권고: 없음

## 종합 판정: low
## 우선순위 개선 Top 3
1. description을 트리거 조건("사용자가 ~하면 호출")으로 시작하도록 재배치
2. 짧은 개요 섹션(예: "## 개요")을 한 줄 추가해 이 스킬의 라우팅 대상을 명시
3. 추가 개선 항목 없음 — 나머지 전 항목 pass
```

- [ ] **Step 4: 구조 검증**

```bash
REVIEW=ex-05-13-skill-md-reviewer/result/review-sql-query.md
for h in "## A." "## B." "## C." "## D." "## 종합 판정:" "## 우선순위 개선 Top 3"; do
  grep -qF "$h" "$REVIEW" || { echo "FAIL: 누락된 섹션 $h"; exit 1; }
done
echo "PASS: 모든 필수 섹션 존재"
```

- [ ] **Step 5: 커밋**

```bash
git add ex-05-13-skill-md-reviewer/result/review-sql-query.md
git commit -m "sql-query SKILL.md 리뷰 결과 추가"
```

---

### Task 6: csv-summary 리뷰 실행

**Files:**
- Create: `ex-05-13-skill-md-reviewer/result/review-csv-summary.md`

**Interfaces:**
- Consumes: Task 1 `scripts/collect-metrics.sh` 출력 포맷, Task 3 `references/checklist.md` 판정 규칙
- Produces: `result/review-csv-summary.md` (Task 8 README 요약 표에서 참조)

- [ ] **Step 1: 정량 지표 재확인**

```bash
bash ex-05-13-skill-md-reviewer/.claude/skills/reviewing-skill-md/scripts/collect-metrics.sh \
  ex-05-11-with-without/.claude/skills/csv-summary/SKILL.md
```

Expected:
```
line_count: 18
word_count: 93
frontmatter_chars: 171
name_value: csv-summary
branch_keyword_count: 1
imperative_count: 0
reason_count: 2
dot_block_count: 0
has_references_dir: no
headers:
  - 사용
  - 규칙 (Why-First)
```

값이 다르면 대상 파일이 변경된 것이므로 Step 3 내용을 실제 값에 맞게 다시 산출한다.

- [ ] **Step 2: 대상 파일 원문 확인**

`ex-05-11-with-without/.claude/skills/csv-summary/SKILL.md` 전체 내용을 Read하여 Step 1 지표와 대조한다 (frontmatter description, "## 사용", "## 규칙 (Why-First)" 2개 규칙 항목 확인).

- [ ] **Step 3: 리뷰 리포트 작성**

`ex-05-13-skill-md-reviewer/result/review-csv-summary.md`:

```markdown
# SKILL.md 리뷰: ex-05-11-with-without/.claude/skills/csv-summary/SKILL.md
개요: 18줄 / 93단어 / frontmatter 171자

## A. Frontmatter & Discovery
- [pass] name 형식 — 근거: `csv-summary`, 영문 소문자+하이픈만 사용 — 권고: 없음
- [pass] frontmatter 전체 길이 — 근거: 171자 (< 800자) — 권고: 없음
- [warn] 트리거 중심 서술 — 근거: description이 "CSV 파일 통계 요약: 행 수, 열별 dtype 추론, ..."으로 시작해 기능 설명이 먼저 나오고, 트리거 조건("사용자가 'CSV 요약', '데이터 통계' 등을 언급하거나 .csv 파일을 첨부하면 호출")은 두 번째 문장에 위치 — 권고: 트리거 조건을 맨 앞으로 재배치
- [pass] 3인칭 서술 — 근거: 1인칭 표현 없음 — 권고: 없음

## B. 구조 & 콘텐츠
- [warn] 권장 섹션 존재 — 근거: 본문 헤더가 `## 사용`, `## 규칙 (Why-First)` 뿐, Overview/When to Use 역할 섹션 없음 — 권고: "## 개요" 또는 "## 사용 시점" 섹션을 짧게 추가
- [pass] flowchart 남용 — 근거: dot 블록 0개 — 권고: 없음
- [pass] 코드 예시 다중 언어 남발 — 근거: bash 코드 블록 1개뿐 — 권고: 없음

## C. 크기 & 분리 신호
- [pass] 크기 신호 — 근거: 18줄 (< 300줄) — 권고: 없음
- [pass] 도메인 분기 신호 — 근거: 분기 키워드 1개(< 2) — 권고: 없음
- [pass] 조건부 상세 신호 — 근거: "그룹 요청이면 GROUP BY 후 집계"는 조건부 문구지만 뒤따르는 설명이 짧은 근거 1줄뿐 — 권고: 없음

## D. 안티패턴
- [pass] 거대 본문 — 근거: 18줄 — 권고: 없음
- [pass] references 부재 — 근거: `references/` 디렉터리는 없지만 분기 키워드가 1개(< 4)라 해당 없음 — 권고: 없음
- [pass] 이유 없는 규칙 — 근거: ALWAYS/NEVER/반드시/절대 매칭 0건, 오히려 "왜냐하면"이 2회 등장해 Why-First 규칙을 모범적으로 준수 — 권고: 없음
- [pass] 일반 지식 서술 — 근거: 표준 문법 설명 문단 없음 — 권고: 없음
- [pass] 도메인 관례 누락 — 근거: "숫자 열만 평균 산출", "그룹 요청 시 GROUP BY" 등 팀 규칙이 이유와 함께 명시됨 — 권고: 없음

## 종합 판정: low
## 우선순위 개선 Top 3
1. description을 트리거 조건으로 시작하도록 재배치
2. 짧은 개요/사용 시점 섹션 추가
3. 추가 개선 항목 없음 — Why-First 규칙(D 카테고리)은 이미 모범적으로 준수됨
```

- [ ] **Step 4: 구조 검증**

```bash
REVIEW=ex-05-13-skill-md-reviewer/result/review-csv-summary.md
for h in "## A." "## B." "## C." "## D." "## 종합 판정:" "## 우선순위 개선 Top 3"; do
  grep -qF "$h" "$REVIEW" || { echo "FAIL: 누락된 섹션 $h"; exit 1; }
done
echo "PASS: 모든 필수 섹션 존재"
```

- [ ] **Step 5: 커밋**

```bash
git add ex-05-13-skill-md-reviewer/result/review-csv-summary.md
git commit -m "csv-summary SKILL.md 리뷰 결과 추가"
```

---

### Task 7: pr-review-orchestrator 리뷰 실행

**Files:**
- Create: `ex-05-13-skill-md-reviewer/result/review-pr-review-orchestrator.md`

**Interfaces:**
- Consumes: Task 1 `scripts/collect-metrics.sh` 출력 포맷, Task 3 `references/checklist.md` 판정 규칙
- Produces: `result/review-pr-review-orchestrator.md` (Task 8 README 요약 표에서 참조)

- [ ] **Step 1: 정량 지표 재확인**

```bash
bash ex-05-13-skill-md-reviewer/.claude/skills/reviewing-skill-md/scripts/collect-metrics.sh \
  ex-06-12-pr-review-skill-md/.claude/skills/pr-review-orchestrator/SKILL.md
```

Expected:
```
line_count: 120
word_count: 545
frontmatter_chars: 316
name_value: pr-review-orchestrator
branch_keyword_count: 0
imperative_count: 0
reason_count: 0
dot_block_count: 0
has_references_dir: no
headers:
  - 목표
  - 입력
  - 산출물
  - Phase 0. 사전 조건
  - Phase 1. 팀 생성
  - Phase 2. 작업 큐 배치
  - Phase 3. 팀원 간 메시지 규칙
  - Phase 4. 통합 게이트
  - Phase 5. 종료
  - 실패 처리
  - 최종 응답 형식
```

값이 다르면 대상 파일이 변경된 것이므로 Step 3 내용을 실제 값에 맞게 다시 산출한다.

- [ ] **Step 2: 대상 파일 원문 확인**

`ex-06-12-pr-review-skill-md/.claude/skills/pr-review-orchestrator/SKILL.md` 전체 내용을 Read하여 Step 1 지표와 대조한다 (frontmatter description, Phase 0~5 구조, 실패 처리 표, 최종 응답 형식 확인).

- [ ] **Step 3: 리뷰 리포트 작성**

`ex-05-13-skill-md-reviewer/result/review-pr-review-orchestrator.md`:

```markdown
# SKILL.md 리뷰: ex-06-12-pr-review-skill-md/.claude/skills/pr-review-orchestrator/SKILL.md
개요: 120줄 / 545단어 / frontmatter 316자

## A. Frontmatter & Discovery
- [pass] name 형식 — 근거: `pr-review-orchestrator`, 영문 소문자+하이픈만 사용 — 권고: 없음
- [pass] frontmatter 전체 길이 — 근거: 316자 (< 800자) — 권고: 없음
- [warn] 트리거 중심 서술 — 근거: description이 "정적 분석, 보안 검토, 테스트 영향 검토를 병렬로 수행하고 하나의 리뷰 리포트로 통합한다"는 워크플로 요약으로 시작하고, 트리거 조건("사용자가 'PR 리뷰', 'diff 점검' ... 요청하면")은 두 번째 문장에 위치 — 권고: 워크플로 요약을 앞세우면 에이전트가 description만 보고 Phase 0~5 절차(팀 생성·작업 큐·메시지 규칙·통합 게이트)를 건너뛸 위험이 있음(SDO 원칙). 트리거 조건 문장을 맨 앞으로 재배치
- [pass] 3인칭 서술 — 근거: 1인칭 표현 없음 — 권고: 없음

## B. 구조 & 콘텐츠
- [warn] 권장 섹션 존재 — 근거: `## 목표`가 개요 역할을 하지만, "언제 사용하는가"를 본문에서 밝히는 사용 시점 섹션이 없음(트리거 정보가 frontmatter description에만 존재) — 권고: "## 사용 시점" 섹션을 추가해 code-reviewer/security-auditor와의 경계를 본문에도 명시
- [pass] flowchart 남용 — 근거: dot 블록 0개 (6-Phase 흐름을 번호 목록과 표로 서술, 다이어그램 남용 없음) — 권고: 없음
- [pass] 코드 예시 다중 언어 남발 — 근거: JSON 메시지 포맷 코드 블록 1개뿐 — 권고: 없음

## C. 크기 & 분리 신호
- [pass] 크기 신호 — 근거: 120줄 (< 300줄) — 권고: 없음
- [pass] 도메인 분기 신호 — 근거: 분기 키워드 0개 — 권고: 없음
- [pass] 조건부 상세 신호 — 근거: "파일 수가 40개를 넘으면..." 조건부 문구가 있으나 뒤따르는 설명이 1줄뿐 — 권고: 없음

## D. 안티패턴
- [pass] 거대 본문 — 근거: 120줄 (500줄 임계값에는 크게 못 미침) — 권고: 없음
- [pass] references 부재 — 근거: `references/` 디렉터리는 없지만 분기 키워드가 0개라 해당 없음 (Phase 오케스트레이션이 본문 핵심이라 애초에 위임 대상 아님) — 권고: 없음
- [pass] 이유 없는 규칙 — 근거: ALWAYS/NEVER/반드시/절대 매칭 0건, Phase별 절차와 실패 처리 표로 규칙을 구체적으로 서술 — 권고: 없음
- [pass] 일반 지식 서술 — 근거: 표준 지식 설명 문단 없음 — 권고: 없음
- [pass] 도메인 관례 누락 — 근거: 실패 처리·메시지 형식·최종 응답 형식까지 팀 고유 규칙이 구체적으로 명시됨 — 권고: 없음

## 종합 판정: low
## 우선순위 개선 Top 3
1. description 워크플로 요약을 줄이고 트리거 조건을 맨 앞으로 재배치 (SDO 위험 방지)
2. 본문에 "## 사용 시점" 섹션 추가
3. 추가 개선 항목 없음 — 120줄 규모에서도 크기·안티패턴 카테고리는 모두 pass
```

- [ ] **Step 4: 구조 검증**

```bash
REVIEW=ex-05-13-skill-md-reviewer/result/review-pr-review-orchestrator.md
for h in "## A." "## B." "## C." "## D." "## 종합 판정:" "## 우선순위 개선 Top 3"; do
  grep -qF "$h" "$REVIEW" || { echo "FAIL: 누락된 섹션 $h"; exit 1; }
done
echo "PASS: 모든 필수 섹션 존재"
```

- [ ] **Step 5: 커밋**

```bash
git add ex-05-13-skill-md-reviewer/result/review-pr-review-orchestrator.md
git commit -m "pr-review-orchestrator SKILL.md 리뷰 결과 추가"
```

---

### Task 8: README 작성 + 루트 인덱스 갱신

**Files:**
- Create: `ex-05-13-skill-md-reviewer/README.md`
- Modify: `README.md:27` (5장 마지막 행 `ex-05-12-antipatterns` 다음, `28`행 `**6장**` 헤더 앞에 새 행 삽입)

**Interfaces:**
- Consumes: Task 5~7의 `result/review-*.md` 종합 판정 값 (low/low/low)
- Produces: 없음 (최종 태스크)

- [ ] **Step 1: 예제 README.md 작성**

`ex-05-13-skill-md-reviewer/README.md`:

```markdown
# ex-05-13 — SKILL.md 실무 리뷰 스킬

ex-05-05(분리 신호)·ex-05-09(컨텍스트 절약 3원칙)·ex-05-12(안티패턴 3종)의 진단 기준을 통합하고 Anthropic 공식 스킬 작성 가이드 항목을 보강해, 임의 프로젝트에 그대로 복사해 쓸 수 있는 실무용 SKILL.md 리뷰 스킬 `reviewing-skill-md`를 만들고 저장소 내 실제 SKILL.md 3종에 적용한다.

## 실행
`bash .claude/skills/reviewing-skill-md/scripts/collect-metrics.sh <SKILL.md 경로>`로 정량 지표를 뽑고, `reviewing-skill-md` 스킬을 호출해 리포트를 생성한다.

## 보기
`.claude/skills/reviewing-skill-md/{SKILL.md,references/checklist.md,scripts/collect-metrics.sh}`, `result/review-{sql-query,csv-summary,pr-review-orchestrator}.md`.

## 결과 요약
| 대상 | 줄 수 | 종합 판정 | 공통 개선 포인트 |
|---|---|---|---|
| ex-05-06 `sql-query` | 15 | low | description 트리거 재배치, 개요 섹션 부재 |
| ex-05-11 `csv-summary` | 18 | low | description 트리거 재배치, 개요 섹션 부재 |
| ex-06-12 `pr-review-orchestrator` | 120 | low | description 워크플로 요약(SDO 위험), 사용 시점 섹션 부재 |

세 스킬 모두 크기·안티패턴(C/D 카테고리)에서는 전부 pass — 실제로 배포된 스킬답게 구조적 결함은 없었다. 공통으로 걸린 것은 A(트리거 중심 서술)와 B(권장 섹션)뿐이며, 이는 크래프팅된 위반 샘플이 아니라 실제 파일을 리뷰했기 때문에 나온 현실적인 결과다.
```

- [ ] **Step 2: 루트 README.md 인덱스에 행 추가**

`README.md`의 27번째 줄(`ex-05-12-antipatterns` 행) 바로 다음, 28번째 줄(`**6장**` 헤더) 앞에 아래 행을 삽입한다:

```markdown
| [`ex-05-13-skill-md-reviewer`](./ex-05-13-skill-md-reviewer) | SKILL.md 실무 리뷰 스킬 | ex-05-05/09/12 진단 기준을 통합하고 공식 가이드로 보강한 reviewing-skill-md 스킬을 실제 SKILL.md 3종(sql-query·csv-summary·pr-review-orchestrator)에 적용해 리포트를 산출합니다. |
```

- [ ] **Step 3: 삽입 확인**

```bash
grep -n "ex-05-13-skill-md-reviewer" README.md
```

Expected: 삽입한 행이 `ex-05-12-antipatterns` 행 다음, `**6장**` 행 이전 줄 번호로 출력됨.

- [ ] **Step 4: 커밋**

```bash
git add ex-05-13-skill-md-reviewer/README.md README.md
git commit -m "$(cat <<'EOF'
ex-05-13 README 작성 및 루트 인덱스 갱신

3개 실제 SKILL.md 리뷰 결과 요약과 함께 예제를 인덱스에 등록한다.
EOF
)"
```
