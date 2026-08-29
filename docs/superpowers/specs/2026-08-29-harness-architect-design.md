# harness-architect — 적응형 하네스 라우터 설계

- 위치: `harness-architect/`
- 날짜: 2026-08-29
- 상태: 구현 완료

## 배경 및 목적

`docs/guides/harnes-architect.md`(816줄)와 `docs/guides/multiagent-pattern.md`(646줄)는
"작업 복잡도보다 오케스트레이션 구조가 크면 감독·전달·중복 분석에 토큰이 더 많이 쓰인다"는
문제의식과 `Single → Pipeline → Fan-out → Supervisor` 승격 원칙을 정리해 두었으나,
실행 가능한 산출물이 없었다. 레포 루트의 `harness-architect/` 디렉터리는 비어 있었다.

두 문서가 공통으로 지적하는 실패 모드는 양방향이다:

- **Over-Orchestration** — 버튼 색상 변경에 Supervisor + 5인 팀. 실제 일을 하지 않는 에이전트가
  가장 많은 토큰을 쓴다.
- **Under-Orchestration** — 인증 마이그레이션을 단일 에이전트로 밀다 숨은 의존성에서 깨진다.

이 스펙의 목적은 두 문서의 결론을 **스킬 1개 + 에이전트 카탈로그 7종**으로 구현해,
작업마다 최소 하네스를 판정하고 그 구조대로 실제 작업까지 수행하는 것이다.

## 핵심 설계 결정

### 1. Harness Architect 를 Agent 가 아니라 Skill 로 둔다

```
Harness Architect Skill      = 분석 + 판정 + 구성안 생성
Implementer / Reviewer / ... = 실제 작업 실행
```

**사유**: 별도 Orchestrator Agent 를 항상 띄우면 대부분의 작업(에이전트 1~2개면 충분한)에서
감독 비용만 발생한다. `orchestrator` Agent 는 H3 으로 판정된 경우에만 활성화한다.

### 2. 역할을 매번 생성하지 않고 고정 카탈로그에서 고른다

에이전트 7종(`implementer` / `reviewer` / `dependency-mapper` / `baseline-tester` /
`integrator` / `orchestrator` / `deployment-agent`)만 둔다.

**사유**: 작업마다 LLM 이 역할 7개를 새로 설계하면 역할 정의에 토큰을 소비하고 결과도 흔들린다.
`security-reviewer` 를 만들지 않고 `reviewer` + `security-review` 스킬 주입으로 처리하는 것도
같은 이유다 — 보안은 별도 책임이 아니라 같은 diff 를 보는 다른 렌즈이고,
에이전트를 늘리면 diff 를 두 번 읽게 된다.

### 3. 절차적 지식은 superpowers 6.3.0 에 위임한다

| 상황 | 위임 대상 |
|---|---|
| 목표 불명확 | `superpowers:brainstorming` |
| 계획 수립 | `superpowers:writing-plans` |
| 계획 실행 | `superpowers:subagent-driven-development` |
| 독립 조사 병렬 | `superpowers:dispatching-parallel-agents` |
| 구현 방식 | `superpowers:test-driven-development` |
| 리뷰 요청·수신 | `superpowers:requesting-code-review` / `receiving-code-review` |
| 원인 불명 반복 실패 | `superpowers:systematic-debugging` |
| 완료 선언 직전 | `superpowers:verification-before-completion` (전 레벨 필수) |
| 작업 공간 격리 | `superpowers:using-git-worktrees` |
| 브랜치 마무리 | `superpowers:finishing-a-development-branch` |

**사유**: 가이드 §9 의 "반복 Procedure → Skill, 독립 책임/판단 → Agent" 규칙.
superpowers 가 이미 검증된 형태로 갖고 있는 절차를 재작성하면 중복이고 품질이 떨어진다.
harness-architect 의 부가가치는 **어떤 것을 언제 로드할지 판정**하는 것이다.

H2/H3 는 사실상 superpowers 위임이 본체다. 계획은 `writing-plans`, 실행은
`subagent-driven-development` 가 담당하고 harness-architect 는 그 위에 레벨 판정,
전문 역할 에이전트, 결정론적 게이트, Human Gate 만 얹는다.
SDD 의 워크스페이스·진행 원장·`scripts/{sdd-workspace,task-brief,review-package}` 는 재구현하지 않는다.

### 4. 결정론적 검증을 Agent 에서 분리한다

포맷·린트·타입·테스트·빌드는 `run-gates.sh` 의 exit code 가 판정한다.
리뷰어는 **게이트를 통과한 diff 만** 받는다.

**사유**: 가이드 §10. "Lint 문제 찾아봐"를 Reviewer 에게 시키면 토큰을 쓰고도 신뢰할 수 없다.
게이트 실패를 리뷰어에게 보내지 않는 것도 같은 이유다 — 리뷰어가 판정할 수 없는 것이다.

### 5. 도구 경계를 frontmatter 로 강제한다

- `reviewer` 에 Edit 없음 — 리뷰어가 고치면 독립 검증이 무너진다
- `orchestrator` 에 Edit 없음 — "Orchestrator 는 코드를 쓰지 않는다"(가이드 §6)를 도구 수준에서 강제
- `dependency-mapper` 에 Write 없음 — 조사 전용

**사유**: 산문으로 쓴 금지는 우회된다. `tools` 는 우회할 수 없다.

## 아키텍처

```text
harness-architect/
├── README.md                       # 예제 소개 + 실행법 + 결과 요약
├── CLAUDE.md                       # 이 폴더의 하네스 규칙
├── .claude/
│   ├── skills/harness-architect/
│   │   ├── SKILL.md                # Phase 0~5 오케스트레이터 (83줄)
│   │   ├── references/             # profiling / routing / catalog / context-budget
│   │   ├── schemas/harness-spec.yaml
│   │   ├── examples/               # h0-single / h1-pipeline / h2-fanout / h3-orchestrator
│   │   └── scripts/                # detect-stack / run-gates / init-workspace
│   └── agents/                     # 카탈로그 7종
├── tests/                          # 스크립트 bash 테스트 (이식 경계 밖)
├── fixtures/                       # 스택 감지 픽스처 5종
└── evals/                          # 라우팅 판정 eval (inputs / results)
```

**이식 경계**: `.claude/skills/harness-architect/` + `.claude/agents/*.md` 를 통째로 복사하면
별도 설치 없이 다른 저장소에서 동작한다. `tests/` · `fixtures/` · `evals/` 는 경계 밖.

### 컴포넌트별 역할과 변경 사유

**`scripts/detect-stack.sh`** — 입력: 프로젝트 디렉터리. 동작: `package.json` 스크립트 키 파싱
(패키지 매니저는 락파일로 판별), `pyproject.toml`/`requirements.txt` 의 도구 선언 grep,
`go.mod`/`Cargo.toml`/`pom.xml`/`build.gradle` 존재 확인. 출력: `tier<TAB>command` TSV.
**사유**: 존재하지 않는 스크립트를 게이트로 내보내면 항상 실패하고, 에이전트는 그 실패를
코드 문제로 오인한다. 그래서 미감지 시 exit 1 로 실패시키고 "추측하지 말고 사용자에게 물어라"를
stderr 로 안내한다.

**`scripts/run-gates.sh`** — 입력: tier + TSV + 로그 디렉터리. 동작: 해당 tier 명령을 순차 실행,
stdout·stderr 를 합쳐 로그에 **전문 보존**, exit code 를 각 명령마다 기록. 첫 실패 후에도 남은
게이트를 전부 실행한다. **사유**: 잘린 스택트레이스는 잘못된 수정을 부른다. 그리고 실패가
하나만 있는지 여러 개인지 알아야 원인을 좁힐 수 있다.

**`references/routing.md`** — 판정 트리 5스텝과 레벨별 실행 절차. **승격을 막는 반례 4종**을
명시적으로 포함한다("영역이 3개니까 워커 3명" / "위험하니까 H3" / "복잡하니까 orchestrator" /
"uncertainty 가 높으니까 H3"). **사유**: LLM 의 기본 실패 모드가 Over-Orchestration 이므로
승격 조건을 적는 것만으로는 부족하고, 자주 나오는 잘못된 승격 논리를 직접 반박해야 한다.

**`references/context-budget.md`** — 에이전트별 `required`/`optional`/`forbidden`.
**사유**: 하네스 레벨을 낮게 유지해도 모든 에이전트에게 레포 전체를 읽히면 절약분이 사라진다.
`baseline-tester` 의 `forbidden` 에 `implementation_plan` 이 들어간 것이 대표적이다 —
앞으로 어떻게 바뀔지 알면 그쪽에 맞춰 현재 동작을 기술하게 된다.

## 데이터 흐름

```text
사용자 요청
  → Phase 0  task 6필드 정규화 (goal 외에는 레포 탐색으로 채움)
  → Phase 1  init-workspace.sh → _workspace/harness/gates.tsv
  → Phase 2  6축 프로파일 → 판정 트리 5스텝 → level + human_gate
  → Phase 3  _workspace/harness/spec.yaml + 한 화면 요약 → ★사용자 승인
  → Phase 4  레벨별 실행 (H0 직접 / H1 파이프라인 / H2 fan-out / H3 DAG)
  → Phase 5  run-gates.sh final → verification-before-completion → Human Gate
```

에이전트 간 산출물은 항상 **파일 경로**로 전달된다:
`_workspace/harness/research/{dependencies,baseline}.md`, `_workspace/harness/review/*.md`,
`_workspace/harness/gates/<tier>.log`.

## 에러 처리

- **스택 미감지**: `init-workspace.sh` exit 3. 게이트를 지어내지 않고 사용자에게 묻는다.
- **게이트 반복 실패**: 같은 게이트 3회 연속 실패 시 추측 수정을 멈추고
  `superpowers:systematic-debugging` 으로 전환한다.
- **리뷰 루프 초과**: `max_loops`(기본 2, `risk: high` 만 3) 초과 시 고치지 않고 사람에게 넘긴다.
  `MINOR`·`NIT` 는 루프를 막지 않는다 — Verify–Generate Deadlock 방지.
- **독립성 판정 번복**: `dependency-mapper` 가 `INDEPENDENCE: REJECTED` 를 반환하면
  H2 → H1 으로 강등하고 spec 을 고쳐 재승인받는다.
- **워커 `BLOCKED`**: 같은 워커에게 재시도하지 않고 재라우팅 표에 따라 다른 에이전트로 보낸다.
- **DAG 순환 의존**: 실행 중단 후 사람에게 넘긴다. 계획 자체가 잘못된 것이다.

## 테스트 계획

1. `detect-stack.sh` — 픽스처 5종(node-npm / node-pnpm / python-uv / go-mod / unknown)에 대해
   tier 매핑, 패키지 매니저 판별, **없는 스크립트를 지어내지 않음**, 미감지 시 exit 1 + 빈 stdout,
   출력 형식(2열 TSV, tier 3종) 검증. 22 assertion.
2. `run-gates.sh` — 성공 시 exit 0, 실패 시 non-zero + **실패 출력 전문 보존** + 첫 실패 후에도
   남은 게이트 실행, 다른 tier 미실행, 빈 tier 통과, TSV 부재·잘못된 tier 실패. 13 assertion.
3. 라우팅 eval — 기대값을 알려주지 않은 서브에이전트 3인에게 대표 작업 3건을 주고
   `level` / `agents` / `human_gate` 를 기대값과 대조 (`evals/`).
4. 레포 자체 심사 — `ex-05-13-skill-md-reviewer` 의 A~D 체크리스트로 SKILL.md 를 진단.

## 범위 밖 (YAGNI)

- **HarnessSpec 스키마 검증기**: 스키마는 사람과 LLM 이 읽는 계약이다. 검증 스크립트는
  실제로 형식 오류가 문제를 일으키는 것을 관측한 뒤에 만든다.
- **레벨 자동 승격**: 실행 중 검증 실패로 H1 → H2 → H3 를 자동 재판정하는 기능.
  예측 가능성이 떨어지고 토큰 비용이 크다. 현재는 강등(H2 → H1)만 명시적으로 다룬다.
- **DAG 실행 엔진**: `orchestrator` 가 `dag.md` 로 상태를 관리한다. 별도 스케줄러를 만들지 않는다.
- **Linear·이슈 트래커 연동**: 입력은 자연어 하나면 충분하다.
