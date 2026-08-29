# harness-architect — 적응형 하네스 라우터

> 개발 업무를 받으면 **작업 복잡도에 맞는 최소 하네스를 매번 새로 고른다.**
> 버튼 색상 변경에 5인 팀을 붙이지 않고, 인증 마이그레이션을 단일 에이전트로 밀지 않는다.

`docs/guides/harnes-architect.md` 와 `docs/guides/multiagent-pattern.md` 가 정리한
`Single → Pipeline → Fan-out → Supervisor` 승격 원칙을 실제로 동작하는 스킬로 구현한 것이다.

## 핵심 아이디어

**Harness Architect 를 Agent 로 만들지 않는다.** 판정은 Skill 이, 실행은 Agent 가 한다.

```
Task ──▶ harness-architect Skill ──▶ HarnessSpec ──┬─▶ Agent Catalog (7종)
         (분석 + 판정 + 구성안)      (실행 계약)     ├─▶ superpowers Skills (12종)
                                                    └─▶ Deterministic Gates (exit code)
```

작업의 대부분은 에이전트 1~2개면 끝난다. 오케스트레이터는 H3 으로 판정됐을 때만 활성화된다.

## 하네스 레벨 4종

| 레벨 | 패턴 | 에이전트 | 적용 |
|---|---|---|---|
| **H0** | Single | 0 | 단일 영역, 동작 변화 없음. 게이트가 회귀를 전부 잡는 경우 |
| **H1** | Pipeline | 2 | 일반적인 기능 개발. implementer → 게이트 → reviewer |
| **H2** | Fan-out / Fan-in | 역할 ≤5 | 진짜 독립적인 작업 단위가 2개 이상일 때만 |
| **H3** | Orchestrator + DAG | 역할 ≤7 | 의존 + 실패 원인별 재라우팅이 필요할 때만 |

> **역할 수 ≠ 동시 실행 수.** 위 열은 하네스가 쓰는 *서로 다른 역할*의 총수이고,
> 동시에 도는 워커는 어느 레벨에서든 `max_workers: 3` 이 상한이다.
> H3 은 H2 의 5역할에 `orchestrator` 와 `deployment-agent` 를 더한 것이다.

판정은 6축 프로파일링(scope / coupling / parallelism / uncertainty / risk / side_effect) 뒤
5스텝 판정 트리로 이루어진다. **한 단계 아래가 왜 안 되는지 쓸 수 없으면 아래 레벨이 맞다.**

## 구성

- `.claude/skills/harness-architect/SKILL.md` — Phase 0~5 오케스트레이터 (83줄)
- `.claude/skills/harness-architect/references/` — 판정 기준 4종
  - `profiling.md` 6축 판정 규칙과 축별 반례
  - `routing.md` 판정 트리 + 레벨별 실행 절차 + 승격을 막는 반례
  - `catalog.md` 에이전트 7종 도구 경계 + superpowers 12종 위임 매핑
  - `context-budget.md` 에이전트별 required / optional / forbidden
- `.claude/skills/harness-architect/schemas/harness-spec.yaml` — 실행 계약 스키마
- `.claude/skills/harness-architect/examples/` — H0~H3 판정 사례 4종 (근거 문장 포함)
- `.claude/skills/harness-architect/scripts/` — `detect-stack` / `run-gates` / `init-workspace`
- `.claude/agents/` × 7 — implementer / reviewer / dependency-mapper / baseline-tester /
  integrator / orchestrator / deployment-agent
- `tests/` — 스크립트 bash 테스트 하네스 (35 assertion)
- `fixtures/` — 스택 감지용 가짜 프로젝트 5종
- `evals/` — 라우팅 판정 eval (H0 / H1 / H3 기대값과 실행 기록)
- `CHECKLIST.md` — 활용 체크리스트(Phase 별 확인 항목·거부해야 하는 판정 조합)와
  완성도 점검 체크리스트(결정론적 검증 명령·eval·**아직 검증되지 않은 영역**·이식 절차)

## 토큰을 아끼는 세 가지 장치

1. **결정론적 게이트 분리** — 포맷·린트·타입·테스트·빌드는 `run-gates.sh` 의 exit code 가 판정한다.
   AI 리뷰어에게 "린트 문제 찾아봐"라고 시키지 않는다. 리뷰어는 게이트를 통과한 diff 만 본다.
2. **컨텍스트 예산** — 에이전트마다 `required` / `optional` / `forbidden` 을 명시한다.
   모든 에이전트의 `forbidden` 에 `full_repository_dump` 가 들어간다. 보고서는 본문이 아니라 경로로 넘긴다.
3. **고정 카탈로그** — 역할 정의를 매번 새로 생성하지 않는다. 7종에서 고르기만 한다.

## 도구 경계는 frontmatter 로 강제한다

- `reviewer` 에 **Edit 이 없다** — 리뷰어가 고치면 독립 검증이 무너지기 때문
- `orchestrator` 에 **Edit 이 없다** — Orchestrator 는 코드를 쓰지 않는다는 규칙을 도구 수준에서 강제
- `dependency-mapper` 에 **Write 가 없다** — 조사 전용

## 실행

```bash
# 1. 스크립트 테스트 (35 assertion)
cd harness-architect && bash tests/run-all.sh

# 2. 스택 감지 확인
bash .claude/skills/harness-architect/scripts/detect-stack.sh fixtures/node-npm
```

그다음 이 디렉토리를 작업 디렉토리로 두고 "구현해줘" 같은 트리거로 스킬을 호출하면
Phase 0~5 가 진행된다. **Phase 3 에서 반드시 승인을 요청하고 멈춘다.**

## 결과 요약

- 스크립트 테스트 검증 항목 43개 전부 통과 (`detect-stack` 30 + `run-gates` 13)
- 라우팅 판정 eval 3건 전부 기대값 일치 (H0 / H1 / H3): `evals/` 참고
- SKILL.md 자체 심사: 레포의 `reviewing-skill-md` 체크리스트(구조·발견성·크기·안티패턴) 전 항목 pass
  — 이는 **문서 품질** 심사이며, 실행 검증 상태는 아래와 `CHECKLIST.md` B-3 을 본다

**아직 검증되지 않은 영역**: H2 경로는 eval 에서 선택된 적이 없고, Phase 4 실행과
에이전트 dispatch 는 한 번도 돌지 않았다. `run-gates.sh` 는 실제 린트·테스트 명령이 아니라
`echo` 로만 검증했다. 전체 목록과 확인 방법은 `CHECKLIST.md` B-3 참고.

설계 근거는 `../docs/guides/harnes-architect.md`, 구현 스펙은
`../docs/superpowers/specs/2026-08-29-harness-architect-design.md` 참고.
