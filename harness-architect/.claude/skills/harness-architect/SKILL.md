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

## Phase −1 — 재개 판정 (Phase 0보다 먼저)

`Bash: python3 .claude/skills/harness-architect/scripts/resume-check.py`

- exit 0 → 재개할 것 없음. Phase 0으로 간다.
- exit 10 → **자동 재개 후보.** 브리핑의 `작업:` 줄이 **지금 사용자가 요청한 작업과 같은지
  판단한다.** 같으면 기록된 Phase부터 이어서 진행한다. 같지 않거나 확신할 수 없으면
  exit 11과 똑같이 다룬다 — 남의 작업을 이어받지 않는다.
- exit 11 → **사람 판단.** 브리핑을 제시하고 **멈춘다.** 사용자가 셋 중 하나를 고른다:
  - **재개** — 기록된 Phase 부터 이어서 진행한다. **Phase 3 이상이면 승인이 남아 있어도
    새로 승인받는다.** 이전 세션의 승인은 이번 세션의 실행 권한이 아니다.
  - **재판정** — Phase 2 로 돌아가 6축을 다시 판정한 뒤
    `Bash: python3 .claude/skills/harness-architect/scripts/checkpoint.py --replan --level <새 레벨>`
    으로 승인·진행·게이트·리뷰 루프를 초기화하고 Phase 3(HarnessSpec 재작성)부터 다시 간다.
  - **폐기** — `Bash: python3 .claude/skills/harness-architect/scripts/checkpoint.py --discard`
    로 현재 state 를 `state.discarded-<id>.json` 으로 보존하고 지운 뒤 Phase 0 으로 간다.
- exit 12 → 완료된 이전 작업이 남아 있다. 새 작업을 시작할지 묻고, 승인되면
  `checkpoint.py --archive` 로 보존한 뒤 Phase 0으로 간다.

state가 손상됐다는 브리핑이 나오면 **추측으로 복구하지 않는다.** 파일을 사용자에게 보이고
이어갈지 새로 시작할지 묻는다.

> **하네스 어댑터 결합면.** 이 Phase 는 Claude Code 하네스에 묶여 있다 — `state.json` 경로 규약,
> `Bash` 툴로 스크립트를 부르는 방식, exit code 로 분기하는 흐름. 나중에 Codex·OpenCode 로
> 이식할 때 하네스 어댑터가 대체해야 하는 Claude 결합 표면 중 하나다. **지금은 이식 작업을 하지 않는다.**

## Phase 0 — 입력 정규화

1. `task` 6필드(goal / scope / constraints / acceptance_criteria / known_risks / target_environment)를
   만든다. `goal` 외에는 레포를 읽어 채운다.
2. **답에 따라 레벨 판정이나 Human Gate 가 뒤집히는 것만 질문한다.** 레포를 읽어 알 수 있는 것은 묻지 않는다.
3. `acceptance_criteria` 를 쓸 수 없을 만큼 목표가 불명확하면 여기서 멈추고
   **REQUIRED SUB-SKILL:** Use superpowers:brainstorming.
4. 정규화가 끝나면 기록한다:
   `Bash: python3 .claude/skills/harness-architect/scripts/checkpoint.py --phase 0 --goal "<정규화한 goal>"`

## Phase 1 — 결정론적 게이트 탐지

`Bash: bash .claude/skills/harness-architect/scripts/init-workspace.sh`

- exit 0 → `_workspace/harness/gates.tsv` 가 이번 작업의 검증 명령 전부다.
- exit 3 → 스택 미감지. **명령을 지어내지 말고** 사용자에게 물어 `tier<TAB>command` 로 기록한다.
- exit 4 → superpowers 미설치. **여기서 멈춘다.** 하네스는 H0 조차
  `verification-before-completion` 에 의존하므로 진행할 수 없다.
  1. 사용자에게 설치 여부를 묻는다.
  2. 승인하면 `/plugin install superpowers@claude-plugins-official` 을 **제시한다.**
     슬래시 명령은 스킬이 대신 실행할 수 없다 — 사용자가 입력한다. 재시작은 필요 없다.
  3. 설치 확인 후 **Phase 1 을 처음부터 다시 실행한다** (골격이 아직 없다).
  4. 거부하면 하네스를 중단한다. **미설치 상태로 Phase 2 로 넘어가지 않는다** —
     검증 절차 없이 완료를 선언하게 된다.

## Phase 2 — 프로파일링과 라우팅

1. `references/profiling.md` 6축을 판정한다. 각 축에 **레포에서 확인한 근거 한 줄**을 붙인다.
2. `references/routing.md` 판정 트리 5스텝으로 `level` 과 `human_gate` 를 결정한다.
3. 고른 레벨보다 **한 단계 아래가 왜 안 되는지** 한 문장으로 쓴다. 못 쓰면 아래 레벨이 맞다.
4. 판정이 끝나면 기록한다:
   `Bash: python3 .claude/skills/harness-architect/scripts/checkpoint.py --phase 2 --level <판정> --next "<다음 행동>"`

## Phase 3 — HarnessSpec 산출 + 승인 게이트

1. `schemas/harness-spec.yaml` 형식으로 `_workspace/harness/spec.yaml` 을 쓴다. 에이전트는
   `references/catalog.md` 7종에서만, 스킬은 그 매핑표에서만 고른다.
   `context:` 는 `references/context-budget.md` 기본값을 인스턴스화한다.
2. `Bash: python3 .claude/skills/harness-architect/scripts/validate-spec.py _workspace/harness/spec.yaml --gates _workspace/harness/gates.tsv`
   - exit 1 → **계약 위반이다. 승인을 요청하지 말고 spec 을 고쳐 재검증한다.**
   - exit 2 → 검증기를 돌릴 수 없다(PyYAML 부재 등). 그 사실을 사용자에게 알리고
     README 의 '승인 게이트 확인' 항목을 손으로 확인한다.
3. `tracking.provider: linear` 면 추적 대상을 만든다 (`references/linear-tracking.md`).
   H1 은 Issue 1건, H2/H3 는 Project + 단위별 Issue. 상태는 `Triage`(= 승인 대기),
   description 에 spec 요약. H3 은 DAG 의 `depends_on` 을 `blockedBy` 로 건다.
   **쓰기 실패는 작업을 멈추지 않는다** — 한 줄로 알리고 진행한다.
4. **한 화면 요약**을 제시한다: 레벨 + 근거 / 에이전트와 모델 / 게이트 / 리뷰 루프 상한 /
   Human Gate 여부와 사유 / 병렬도 / 추적 링크. validator 경고가 있으면 함께 보인다.
5. **승인을 받는다.** 승인되면 상태를 `Triage` → `Todo` 로 올리고, 승인 직후 기록한다:
   `Bash: python3 .claude/skills/harness-architect/scripts/checkpoint.py --phase 3 --approved --agents <spec의 agents id 쉼표 목록> --artifact spec=_workspace/harness/spec.yaml`

## Phase 4 — 실행

`references/routing.md` 의 레벨별 절차를 그대로 따른다. 요약:

- **H0** — 직접 구현 → `fast` → `feature` → `final` 게이트. 서브에이전트 0개.
  에이전트 수가 0일 뿐 **검증 tier 는 줄이지 않는다.**
- **H1** — (uncertainty≥medium 이면 dependency-mapper ‖ baseline-tester 동시 dispatch 선행)
  → implementer → 게이트 → reviewer → 루프 ≤ `max_loops`.
- **H2** — worktree 격리 → 조사 2인 동시 dispatch → `superpowers:writing-plans`
  → `superpowers:subagent-driven-development`(워커 순차) → integrator → reviewer
  → **작업 공간 정리**(Phase 5).
- **H3** — H2 + orchestrator 가 DAG 관리와 실패 원인별 재라우팅.

추적 중이면 각 단위의 Linear 상태를 전환한다: 착수 `In Progress` → 게이트 통과 `In Review`
→ 리뷰 `VERDICT: PASS` 시 `Done`. 게이트 실행 뒤에는
`Bash: bash .claude/skills/harness-architect/scripts/gate-summary.sh <tier>` 출력을 코멘트 1건으로 남긴다
(**로그 전문은 붙이지 않는다**). 리뷰는 종료 시 1건으로 요약하고, 루프 상한을 넘긴 미해결
BLOCKER 는 sub-issue 로 승격한다.

실행 중에도 기록한다 (`checkpoint.py`):

- **H2/H3**: `superpowers:writing-plans` 로 SDD 워크스페이스를 만든 직후, 그 원장 경로를 기록한다:
  `--artifact sdd_ledger=<.superpowers/sdd/<slug>/ 경로>`. state 는 태스크 단위 진행을
  재구현하지 않고 **경로로만** 가리킨다 — 단위 복원은 SDD 자신의 ledger check 가 한다.
- 역할 하나가 끝날 때마다: `--agent-done <id> --next "<다음 행동>"`.
  **H2/H3 의 `implementer` 는 SDD 루프 전체가 끝났을 때만** 부른다 — 역할 마일스톤이지
  워커 하나·작업 단위 하나가 아니다.
- 리뷰 루프를 한 번 소진할 때마다: `--review-loop`.
- (`run-gates.sh` 는 tier 실행 시 `--gate <tier>:<exit>` 를 자동으로 기록한다 — 손으로 부르지 않는다.)

## Phase 5 — 종료

1. `Bash: bash .claude/skills/harness-architect/scripts/run-gates.sh final`
2. **REQUIRED SUB-SKILL:** Use superpowers:verification-before-completion.
3. `human_gate.required` 면 증거(게이트 로그 경로 + diff 통계 + 롤백 절차)를 제시하고 멈춘다.
   추적 중이면 상태를 `In Review` 로 두고 같은 증거를 코멘트로 남긴다.
   `tracking.human_gate_approval` 이 `linear`/`both` 면 사용자가 Linear 에서 `Todo` 로 바꿀 때까지
   기다린다 — **무한 대기하지 않는다.** 상한에 닿으면 알리고 멈춘다.
   완료되면 상태를 `Done` 으로 올리고 최종 게이트 결과를 코멘트로 남긴다.
   Human Gate 를 통과하면 기록한다:
   `Bash: python3 .claude/skills/harness-architect/scripts/checkpoint.py --human-gate-passed`
4. **REQUIRED SUB-SKILL:** Use superpowers:finishing-a-development-branch.
   **Phase 4 에서 worktree 를 만들었으면(H2·H3) 이 단계는 필수다** — 격리를 절차에 넣었으면
   해제도 절차에 있어야 한다. H0·H1 은 브랜치에서 작업한 경우에만 호출한다.
   정리 여부는 그 스킬의 통합 선택이 정한다 (로컬 머지 → 제거 / PR·유지 → 보존).
   **Linear 상태는 정리를 트리거하지 않는다** — 상태로는 정리를 억제하기만 한다.
   `In Progress` 면 경고하고 멈추고, `Canceled` 면 폐기 메뉴를 제시만 한다.
   근거와 전체 규칙은 `references/routing.md` 의 "작업 공간 정리".
5. 종료를 기록한다:
   `Bash: python3 .claude/skills/harness-architect/scripts/checkpoint.py --phase done`

## 불변 규칙

- **최소 하네스 우선**: 안전하게 완료 가능한 가장 단순한 하네스를 고른다. 승격에는 근거 문장이 필요하다.
- **승인 없이 스폰 금지**: Phase 3 승인 전에 에이전트를 띄우지 않는다.
- **진행을 기록한다**: Phase 전환과 역할 완료마다 `checkpoint.py` 를 부른다. 기록하지 않으면
  다음 세션이 처음부터 다시 판정하게 되고, 같은 작업에 다른 레벨이 나올 수 있다.
  기록 실패는 하네스를 멈추지 않지만 조용히 넘어가지도 않는다.
- **승인은 세션을 넘어 상속되지 않는다**: 재개 시 `approved: true` 는 사실 기록일 뿐
  실행 권한이 아니다. Phase 3 이상에서 재개하면 반드시 새로 승인받는다.
- **결정론적 판정 분리**: 포맷·린트·타입·테스트·빌드는 `run-gates.sh` 의 exit code 가 판정한다. AI 리뷰어에게 시키지 않고, 게이트 실패를 리뷰어에게 보내지 않는다.
- **게이트 명령을 지어내지 않는다**: 감지 실패 시 추측하지 말고 사용자에게 묻는다.
- **역할을 새로 만들지 않는다**: 에이전트는 카탈로그 7종에서만 고른다. 반복 Procedure 는 Agent 가 아니라 Skill 이다.
- **컨텍스트는 경로로 전달한다**: 보고서 본문·세션 히스토리를 dispatch 프롬프트에 붙여넣지 않는다. dispatch 시 `model` 을 항상 명시한다 (생략하면 세션의 가장 비싼 모델을 상속).
- **구현 워커 동시 dispatch 금지**: `max_workers: 3` 은 병합 단위 수이지 동시 실행 수가 아니다. 동시 dispatch 는 파일을 쓰지 않는 조사 에이전트에만 허용한다.
- **리뷰 루프 상한**: `max_loops`(기본 2, risk: high 만 3) 초과 시 고치지 말고 사람에게 넘긴다. MINOR·NIT 는 루프를 막지 않는다.
- **자동 커밋 금지 / workspace 보존**: `git commit` 을 호출하지 않고, 종료 후에도 `_workspace/` 를 삭제하지 않는다. `_workspace/` 는 `scripts/harness-paths.sh` 가 메인 워크트리 루트에 고정하므로 worktree 를 제거해도 산출물이 남는다.
- **격리와 해제는 쌍이다**: worktree 를 만든 하네스는 반드시 정리 단계까지 절차에 포함한다. 정리 시점은 **통합 결과**가 정하고 Linear 상태가 정하지 않는다 — `Canceled` 는 강등을 포함하고 `Done` 은 통합보다 먼저 찍히기 때문이다.
- **검증되지 않은 spec 으로 실행하지 않는다**: Phase 3 의 `validate-spec.py` 가 exit 1 이면 승인을 요청하지 않는다.
- **Linear 쓰기는 컨트롤러만 한다**: 워커와 orchestrator 는 Linear 를 건드리지 않는다. 상태 토큰만 반환하고 컨트롤러가 번역한다. 추적 실패는 하네스를 멈추지 않는다 — 관측 수단이지 실행 경로가 아니다.
- **H0 은 추적하지 않는다**: 단일 파일·저위험 변경까지 이슈로 만들면 백로그가 오탈자 수정으로 찬다.
- **`allowed-tools` 의 Bash 가 넓은 이유**: 게이트 명령이 프로젝트마다 달라 화이트리스트가 불가능하다. 대신 각 에이전트의 `tools` 로 경계를 좁히고, `guard-readonly.py` 훅이 읽기 전용 역할(reviewer·orchestrator·dependency-mapper)의 소스 쓰기를 실제로 거부한다 — `references/catalog.md` 의 강제 수준 표 참고.
- **이식성**: `.claude/skills/harness-architect/` + `.claude/agents/*.md` 를 통째로 복사하면 별도 설치 없이 다른 저장소에서 동작한다.
