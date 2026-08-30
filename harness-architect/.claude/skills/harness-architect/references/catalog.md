# 카탈로그 — 에이전트 7종과 스킬 매핑

## 왜 카탈로그인가

작업마다 역할을 새로 설계하면 매번 역할 정의에 토큰을 쓰고 결과도 흔들린다.
**에이전트는 아래 7종에서 고르기만 한다. 새 역할을 만들지 않는다.**

새 역할이 필요해 보이면 먼저 이 판정을 통과해야 한다:

```
반복되는 Procedure 인가?            → Skill (아래 매핑표에서 주입)
독립적인 책임·판단·완료조건인가?     → Agent (7종 중에 없으면 사람에게 물어본다)
```

## 에이전트 7종

정의 파일은 `.claude/agents/*.md` 에 있다. `tools` 가 곧 안전장치이므로 여기 적힌 경계를 넘지 않는다.

| id | model | tools | 책임 | 도구 경계 근거 |
|---|---|---|---|---|
| `implementer` | sonnet | Read, Grep, Glob, Edit, Write, Bash | 일반 구현 | 소스 편집권을 가진 유일한 역할 |
| `reviewer` | opus | Read, Grep, Glob, Bash, Write | 의미적 코드 리뷰 | **Edit 없음** — 리뷰어가 고치면 독립 검증이 무너진다 |
| `dependency-mapper` | sonnet | Read, Grep, Glob, Bash | 영향·의존성 분석 | 조사 전용. 어떤 파일도 쓰지 않는다 |
| `baseline-tester` | sonnet | Read, Grep, Glob, Bash, Write | 기존 동작 고정 | 테스트 파일만 Write. 소스 수정 금지 |
| `integrator` | opus | Read, Grep, Glob, Bash, Edit, Write | 병렬 결과 통합 | 머지 충돌 해소를 위해 Edit 필요 |
| `orchestrator` | opus | Agent, Read, Bash, Write | DAG·상태·재라우팅 | **Edit 없음** — Orchestrator 는 코드를 쓰지 않는다 |

### `tools` 가 실제로 막아주는 것과 막아주지 못하는 것

`Edit` 을 빼면 **기존 파일을 고치는 정식 경로**가 사라진다. 그것이 전부다.
`Write` 는 새 파일을 쓸 수 있고, `Bash` 는 리다이렉션·`sed -i` 로 무엇이든 바꿀 수 있다.
`reviewer`·`orchestrator`(`Write`+`Bash`)와 `dependency-mapper`(`Bash`)가 여기 해당한다.

| 경계 | 강제 수준 |
|---|---|
| reviewer·orchestrator 가 `Edit`/`Write` 로 소스 수정 | **도구 + 훅이 차단** |
| reviewer·orchestrator 가 `Bash` 로 소스 수정 (`sed -i`·리다이렉션·`rm`·`git commit` 등) | **훅이 차단** |
| dependency-mapper 가 어떤 경로로든 파일 생성 | **훅이 차단** (조사 전용) |
| 위 역할이 변수 확장·base64·인터프리터 파이프로 우회 | 프롬프트 준수에만 의존 (미차단) |

`Write` 는 reviewer·orchestrator 가 보고서·DAG 상태를 내는 데 필요하고 `Bash` 는 검색·게이트에
필요해서 `tools` 에서 빼지 않았다. 대신 `scripts/guard-readonly.py` 를 `PreToolUse` 훅으로 걸어
**쓰기 대상 경로**로 판정한다 — reviewer·orchestrator 는 `_workspace/` 아래만,
dependency-mapper 는 아무 데도 쓰지 못한다.

**이것은 샌드박스가 아니다.** 훅은 셸을 파싱하지 않고 쓰기 구문을 패턴으로 찾으므로
변수 확장이나 인터프리터 경유는 잡지 못한다. 규율 장치이지 보안 경계가 아니다.

`implementer`·`integrator` 는 소스를 고치는 것이 일이라 가드 대상이 아니고,
`baseline-tester` 는 특성화 테스트를 레포의 테스트 디렉터리에 써야 해서 제외했다.

설치법은 `../../../../README.md` 의 "훅 설치" 절 참고. 훅을 걸지 않아도 스킬은 동작하지만,
그때 이 표의 "훅이 차단" 행은 전부 "프롬프트 준수에만 의존" 으로 내려간다.
| `deployment-agent` | sonnet | Read, Bash, Write | 배포·헬스체크·롤백 준비 | Human Gate 없이는 실행하지 않는다 |

### 카탈로그에 없는 것과 그 이유

- **security-reviewer 를 만들지 않는다.** `reviewer` + `security-review` 스킬 주입으로 처리한다.
  보안은 별도 책임이 아니라 같은 diff 를 보는 다른 렌즈다. 에이전트를 늘리면 diff 를 두 번 읽게 된다.
- **test-writer 를 만들지 않는다.** 테스트 작성은 `implementer` 의 일이고,
  방법은 `superpowers:test-driven-development` 가 규정한다.
- **planner 를 만들지 않는다.** `superpowers:writing-plans` 가 이미 그 절차다.
- **documentation-agent 를 만들지 않는다.** 문서는 구현의 일부다.

## superpowers 스킬 매핑

절차적 지식은 직접 쓰지 않고 아래로 위임한다. 활성 버전은 **superpowers 6.3.0**.

**두 종류를 섞지 않는다.** 워커에게는 `Agent` 도구가 없다 —
다른 에이전트를 부르는 스킬을 워커 프롬프트에 주입하면 실행되지 않는다.

- `controller_skills` — 하네스를 운전하는 쪽이 직접 호출한다.
  H0~H2 는 harness-architect 스킬 자신이, H3 은 `orchestrator` 가 소유한다.
- `agent_skills` — 워커 프롬프트에 주입한다. 자기 작업만 하는 스킬이어야 한다.

| 상황 | 위임 대상 | 소유 | 적용 레벨 |
|---|---|---|---|
| 목표·수용 기준이 불명확해 프로파일링 불가 | `superpowers:brainstorming` | controller | 전 레벨 (Phase 0) |
| 다단계 작업의 계획 수립 | `superpowers:writing-plans` | controller | H2, H3 |
| 계획을 서브에이전트로 실행 | `superpowers:subagent-driven-development` | controller | H2, H3 |
| 독립 조사 2건 이상을 동시에 | `superpowers:dispatching-parallel-agents` | controller | 전 레벨 |
| reviewer 호출 방법·심사 기준 | `superpowers:requesting-code-review` | controller | H1–H3 |
| 작업 공간 격리 | `superpowers:using-git-worktrees` | controller | H2, H3 (**필수**) |
| 완료 선언 직전 | `superpowers:verification-before-completion` | controller | **전 레벨 필수** |
| 브랜치 마무리 + 작업 공간 정리 | `superpowers:finishing-a-development-branch` | controller | H2·H3 **필수** / H1 은 브랜치 작업 시 |
| implementer 의 기본 작업 방식 | `superpowers:test-driven-development` | agent (implementer) | H1–H3 |
| 리뷰 피드백 수신·반영 | `superpowers:receiving-code-review` | agent (implementer) | H1–H3 |
| 게이트가 반복 실패, 원인 불명 | `superpowers:systematic-debugging` | 양쪽 | 전 레벨 |
| `risk: high` 인 diff 의 보안 심사 | 내장 `security-review` | agent (reviewer) | risk: high |

**표기 관례**: 산문에서 `**REQUIRED SUB-SKILL:** Use superpowers:<name>` 형태로 지시한다
(superpowers 자신의 관례를 그대로 따른다).

## H2/H3 는 superpowers 위임이 본체다

harness-architect 가 H2/H3 에서 직접 하는 일은 네 가지뿐이다:

1. 레벨 판정과 `HarnessSpec` 산출
2. 전문 역할 에이전트 배치 (`dependency-mapper` / `baseline-tester` / `integrator` / `orchestrator`)
3. 결정론적 게이트 실행 (`run-gates.sh`)
4. Human Gate

계획 수립과 태스크 루프는 `superpowers:writing-plans` → `superpowers:subagent-driven-development` 가
담당한다. SDD 의 워크스페이스·진행 원장·`scripts/{sdd-workspace,task-brief,review-package}` 를
**그대로 호출하고 재구현하지 않는다.**
