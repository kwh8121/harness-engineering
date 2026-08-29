---
name: harness-architect
description: 개발 업무(버그 수정·기능 추가·리팩터링·마이그레이션)를 자연어로 위임받았을 때 사용한다. 작업을 6축으로 프로파일링해 최소 하네스 H0~H3 를 판정하고, HarnessSpec 계약을 산출해 승인받은 뒤 그 구조대로 실행한다. 트리거 - "구현해줘", "기능 추가", "리팩터링", "마이그레이션", "이 작업 어떻게 진행", "하네스", "에이전트 구조".
allowed-tools: Agent, Bash, Read, Write, Edit, Grep, Glob, Skill
---

# harness-architect

## 개요

> 하네스 컴파일러. 작업을 6축으로 프로파일링해 H0~H3 중 **가장 단순한** 구조를 고르고,
> `HarnessSpec` 계약을 만들어 승인받은 뒤 그대로 실행한다.
> 절차적 지식은 직접 쓰지 않고 superpowers 스킬에 위임한다.

## 사용 시점

> `.claude/` 가 있는 프로젝트 루트를 작업 디렉터리로 실행되어야 한다 (모든 경로가 상대 경로다).

- 개발 업무를 자연어로 위임받았을 때 (버그 수정·기능 추가·리팩터링·마이그레이션 전부)
- 진행 중인 작업의 하네스를 재판정할 때 (`_workspace/harness/spec.yaml` 덮어쓰기)
- **쓰지 않을 때**: 코드 변경이 없는 질문·조사·설명. 하네스는 실행 계약이지 대화 도구가 아니다.

## Phase 0 — 입력 정규화

1. `task` 6필드(goal / scope / constraints / acceptance_criteria / known_risks / target_environment)를
   만든다. `goal` 외에는 레포를 읽어 채운다.
2. **답에 따라 레벨 판정이나 Human Gate 가 뒤집히는 것만 질문한다.** 레포를 읽어 알 수 있는 것은 묻지 않는다.
3. `acceptance_criteria` 를 쓸 수 없을 만큼 목표가 불명확하면 여기서 멈추고
   **REQUIRED SUB-SKILL:** Use superpowers:brainstorming.

## Phase 1 — 결정론적 게이트 탐지

`Bash: bash .claude/skills/harness-architect/scripts/init-workspace.sh`

- exit 0 → `_workspace/harness/gates.tsv` 가 이번 작업의 검증 명령 전부다.
- exit 3 → 스택 미감지. **명령을 지어내지 말고** 사용자에게 물어 `tier<TAB>command` 로 기록한다.

## Phase 2 — 프로파일링과 라우팅

1. `references/profiling.md` 6축을 판정한다. 각 축에 **레포에서 확인한 근거 한 줄**을 붙인다.
2. `references/routing.md` 판정 트리 5스텝으로 `level` 과 `human_gate` 를 결정한다.
3. 고른 레벨보다 **한 단계 아래가 왜 안 되는지** 한 문장으로 쓴다. 못 쓰면 아래 레벨이 맞다.

## Phase 3 — HarnessSpec 산출 + 승인 게이트

1. `schemas/harness-spec.yaml` 형식으로 `_workspace/harness/spec.yaml` 을 쓴다. 에이전트는
   `references/catalog.md` 7종에서만, 스킬은 그 매핑표에서만 고른다.
   `context:` 는 `references/context-budget.md` 기본값을 인스턴스화한다.
2. **한 화면 요약**을 제시한다: 레벨 + 근거 / 에이전트와 모델 / 게이트 / 리뷰 루프 상한 /
   Human Gate 여부와 사유 / 병렬도.
3. **승인을 받는다.**

## Phase 4 — 실행

`references/routing.md` 의 레벨별 절차를 그대로 따른다. 요약:

- **H0** — 직접 구현 → `run-gates.sh fast` → `run-gates.sh final`. 서브에이전트 0개.
- **H1** — (uncertainty≥medium 이면 dependency-mapper ‖ baseline-tester 동시 dispatch 선행)
  → implementer → 게이트 → reviewer → 루프 ≤ `max_loops`.
- **H2** — worktree 격리 → 조사 2인 동시 dispatch → `superpowers:writing-plans`
  → `superpowers:subagent-driven-development`(워커 순차) → integrator → reviewer.
- **H3** — H2 + orchestrator 가 DAG 관리와 실패 원인별 재라우팅.

## Phase 5 — 종료

1. `Bash: bash .claude/skills/harness-architect/scripts/run-gates.sh final`
2. **REQUIRED SUB-SKILL:** Use superpowers:verification-before-completion.
3. `human_gate.required` 면 증거(게이트 로그 경로 + diff 통계 + 롤백 절차)를 제시하고 멈춘다.
4. 브랜치 마무리가 필요하면 **REQUIRED SUB-SKILL:** Use superpowers:finishing-a-development-branch.

## 불변 규칙

- **최소 하네스 우선**: 안전하게 완료 가능한 가장 단순한 하네스를 고른다. 승격에는 근거 문장이 필요하다.
- **승인 없이 스폰 금지**: Phase 3 승인 전에 에이전트를 띄우지 않는다.
- **결정론적 판정 분리**: 포맷·린트·타입·테스트·빌드는 `run-gates.sh` 의 exit code 가 판정한다. AI 리뷰어에게 시키지 않고, 게이트 실패를 리뷰어에게 보내지 않는다.
- **게이트 명령을 지어내지 않는다**: 감지 실패 시 추측하지 말고 사용자에게 묻는다.
- **역할을 새로 만들지 않는다**: 에이전트는 카탈로그 7종에서만 고른다. 반복 Procedure 는 Agent 가 아니라 Skill 이다.
- **컨텍스트는 경로로 전달한다**: 보고서 본문·세션 히스토리를 dispatch 프롬프트에 붙여넣지 않는다. dispatch 시 `model` 을 항상 명시한다 (생략하면 세션의 가장 비싼 모델을 상속).
- **구현 워커 동시 dispatch 금지**: `max_workers: 3` 은 병합 단위 수이지 동시 실행 수가 아니다. 동시 dispatch 는 파일을 쓰지 않는 조사 에이전트에만 허용한다.
- **리뷰 루프 상한**: `max_loops`(기본 2, risk: high 만 3) 초과 시 고치지 말고 사람에게 넘긴다. MINOR·NIT 는 루프를 막지 않는다.
- **자동 커밋 금지 / workspace 보존**: `git commit` 을 호출하지 않고, 종료 후에도 `_workspace/` 를 삭제하지 않는다.
- **`allowed-tools` 의 Bash 가 넓은 이유**: 게이트 명령이 프로젝트마다 달라 화이트리스트가 불가능하다. 대신 각 에이전트의 `tools` 로 경계를 강제한다 (reviewer·orchestrator 에 Edit 없음).
- **이식성**: `.claude/skills/harness-architect/` + `.claude/agents/*.md` 를 통째로 복사하면 별도 설치 없이 다른 저장소에서 동작한다.
