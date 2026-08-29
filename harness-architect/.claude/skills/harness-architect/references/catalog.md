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

| 상황 | 위임 대상 | 적용 레벨 |
|---|---|---|
| 목표·수용 기준이 불명확해 프로파일링 불가 | `superpowers:brainstorming` | 전 레벨 (Phase 0) |
| 다단계 작업의 계획 수립 | `superpowers:writing-plans` | H2, H3 |
| 계획을 서브에이전트로 실행 | `superpowers:subagent-driven-development` | H2, H3 |
| 독립 조사 2건 이상을 동시에 | `superpowers:dispatching-parallel-agents` | 전 레벨 |
| implementer 의 기본 작업 방식 | `superpowers:test-driven-development` | H1–H3 |
| reviewer 호출 방법·심사 기준 | `superpowers:requesting-code-review` | H1–H3 |
| 리뷰 피드백 수신·반영 | `superpowers:receiving-code-review` | H1–H3 |
| 게이트가 반복 실패, 원인 불명 | `superpowers:systematic-debugging` | 전 레벨 |
| 완료 선언 직전 | `superpowers:verification-before-completion` | **전 레벨 필수** |
| 작업 공간 격리 | `superpowers:using-git-worktrees` | H2, H3 |
| 브랜치 마무리 (머지·PR·유지) | `superpowers:finishing-a-development-branch` | H1–H3 |
| `risk: high` 인 diff 의 보안 심사 | 내장 `security-review` 스킬 | reviewer 에 주입 |

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
