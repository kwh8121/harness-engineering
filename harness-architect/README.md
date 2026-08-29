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
- `.claude/skills/harness-architect/references/` — 판정 기준 5종
  - `profiling.md` 6축 판정 규칙과 축별 반례
  - `routing.md` 판정 트리 + 레벨별 실행 절차 + 승격을 막는 반례
  - `catalog.md` 에이전트 7종 도구 경계 + superpowers 12종 위임 매핑
  - `context-budget.md` 에이전트별 required / optional / forbidden
  - `linear-tracking.md` Linear 엔티티·상태 매핑과 기록 정책
- `.claude/skills/harness-architect/schemas/harness-spec.yaml` — 실행 계약 스키마
- `.claude/skills/harness-architect/examples/` — H0~H3 판정 사례 4종 (근거 문장 포함)
- `.claude/skills/harness-architect/scripts/` — `detect-stack` / `run-gates` / `init-workspace`
  / `gate-summary.sh` (게이트 결과를 Linear 코멘트용으로 렌더링)
  / `validate-spec.py` (HarnessSpec 계약 검증) / `guard-readonly.py` (읽기 전용 역할 쓰기 차단 훅)
- `.claude/settings.json` — 위 훅을 `PreToolUse` 로 등록한다
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

## 도구 경계는 frontmatter + 훅으로 강제한다

frontmatter 의 `tools` 가 1차 경계다.

- `reviewer` 에 **Edit 이 없다** — 리뷰어가 고치면 독립 검증이 무너지기 때문
- `orchestrator` 에 **Edit 이 없다** — Orchestrator 는 코드를 쓰지 않는다
- `dependency-mapper` 에 **Write 가 없다** — 조사 전용

하지만 `Edit` 을 빼도 `Write` 로 새 파일을, `Bash` 로 `sed -i`·리다이렉션을 쓸 수 있다.
두 도구는 보고서 작성과 검색·게이트에 필요해서 뺄 수 없으므로, **쓰기 대상 경로로 판정하는
`PreToolUse` 훅**이 2차 경계를 맡는다.

| 역할 | 쓰기 허용 범위 |
|---|---|
| `reviewer` · `orchestrator` | `_workspace/` 아래만 |
| `dependency-mapper` | 없음 (조사 전용) |
| `implementer` · `integrator` · `baseline-tester` · `deployment-agent` | 가드 대상 아님 |

훅은 셸을 파싱하지 않고 쓰기 구문을 패턴으로 찾는다. **샌드박스가 아니라 규율 장치다.**

### 훅 설치

이 폴더에는 `.claude/settings.json` 이 이미 들어 있어 별도 작업이 필요 없다.
다른 저장소로 이식할 때는 그 저장소의 `.claude/settings.json` 에 다음을 병합한다.

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit|NotebookEdit|Bash",
        "hooks": [
          {
            "type": "command",
            "command": "python3 \"$CLAUDE_PROJECT_DIR/.claude/skills/harness-architect/scripts/guard-readonly.py\"",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

훅을 걸지 않아도 스킬은 동작한다. 다만 그때 읽기 전용 경계는 프롬프트 준수에만 의존한다.

## 진행 상황은 Linear 에 남는다

목적은 **사용자가 터미널을 보지 않고도 진행과 검증 근거를 파악하는 것**이다.

| 하네스 | Linear |
|---|---|
| H1 작업 | Issue 1건 (작업 단위가 1개다) |
| H2/H3 작업 | Project + 단위별 Issue |
| H3 DAG 의 `depends_on` | `blockedBy` / `blocks` — Linear 가 의존을 네이티브로 표현한다 |
| Phase 3 승인 대기 | 상태 `Triage` — Linear 의 "의도적 검토" 개념과 같다 |
| 구현 중 / 리뷰 중 / 완료 | `In Progress` / `In Review` / `Done` |
| 게이트 결과 | 코멘트 — 명령 + exit code + 로그 경로 (**전문은 붙이지 않는다**) |
| Human Gate | `In Review` + 증거 코멘트 (로그 경로·diff 통계·롤백 절차) |

**H0 은 추적하지 않는다.** 단일 파일 표현 계층 변경까지 이슈로 만들면 백로그가 오탈자 수정으로
찬다 — Linear 문서의 "이슈 하나의 적정 크기" 원칙과 어긋난다.

**쓰기는 컨트롤러만 한다.** 워커와 `orchestrator` 는 Linear 를 건드리지 않고 상태 토큰만
반환한다. 워커 `tools` 에 MCP 도구를 넣으면 이식성이 깨지고, 여러 주체가 쓰면 같은 사실이
여러 번 다르게 기록된다. 추적 실패는 하네스를 멈추지 않는다 — 관측 수단이지 실행 경로가 아니다.

`tracking.provider: none` 이면 아무것도 쓰지 않는다. 상세는 `references/linear-tracking.md`.

## HarnessSpec 은 실행 전에 기계가 검증한다

Phase 3 은 승인을 요청하기 전에 `validate-spec.py` 를 돌린다. exit 1 이면 승인을 요청하지 않는다.

```bash
python3 .claude/skills/harness-architect/scripts/validate-spec.py \
  _workspace/harness/spec.yaml --gates _workspace/harness/gates.tsv
```

카탈로그 밖 에이전트, `model` 누락, 축 모순(`coupling: high` + `parallelism ≠ none`),
레벨별 에이전트 불변식, controller 스킬의 워커 오배정, **수용 기준에 대응하는 게이트 부재**,
Human Gate 누락, `full_repository_dump` 금지 누락, 루프·워커 상한 초과를 거부한다.
`yaml.safe_load` 성공은 "문법이 YAML 이다" 만 말해 준다는 것이 이 검증기를 만든 이유다.

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

- 스크립트 테스트 검증 항목 102개 전부 통과 (`detect-stack` 30 + `run-gates` 13 + `validate-spec` 28 + `guard-readonly` 20 + `gate-summary` 11)
- 라우팅 판정 eval 3건 전부 기대값 일치 (H0 / H1 / H3): `evals/` 참고
- SKILL.md 자체 심사: 레포의 `reviewing-skill-md` 체크리스트(구조·발견성·크기·안티패턴) 전 항목 pass
  — 이는 **문서 품질** 심사이며, 실행 검증 상태는 아래와 `CHECKLIST.md` B-3 을 본다

**아직 검증되지 않은 영역**: H2 경로는 eval 에서 선택된 적이 없고, Phase 4 실행과
에이전트 dispatch 는 한 번도 돌지 않았다. `run-gates.sh` 는 실제 린트·테스트 명령이 아니라
`echo` 로만 검증했고, 훅의 실제 거부는 단위 테스트로만 확인했다(실제 서브에이전트 dispatch 미검증).
전체 목록과 확인 방법은 `CHECKLIST.md` B-3 참고.

설계 근거는 `../docs/guides/harnes-architect.md`, 구현 스펙은
`../docs/superpowers/specs/2026-08-29-harness-architect-design.md` 참고.
