# harness-architect — 적응형 하네스 라우터

> 개발 업무를 받으면 **작업 복잡도에 맞는 최소 하네스를 매번 새로 고른다.**
> 버튼 색상 변경에 5인 팀을 붙이지 않고, 인증 마이그레이션을 단일 에이전트로 밀지 않는다.

`docs/guides/harnes-architect.md` 와 `docs/guides/multiagent-pattern.md` 가 정리한
`Single → Pipeline → Fan-out → Supervisor` 승격 원칙을 실제로 동작하는 스킬로 구현한 것이다.

## 핵심 아이디어

**Harness Architect 를 Agent 로 만들지 않는다.** 판정은 Skill 이, 실행은 Agent 가 한다.

```
Task ──▶ harness-architect Skill ──▶ HarnessSpec ──┬─▶ Agent Catalog (7종)
         (분석 + 판정 + 구성안)      (실행 계약)     ├─▶ 위임 스킬 12종 (superpowers 11 + security-review)
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
> H3 은 H2 의 5역할에 `orchestrator` 가 더해져 최소 6역할이다. `deployment-agent` 는
> H3 이라고 항상 붙는 게 아니라 그 작업이 실제로 배포를 수반할 때만 추가된다 —
> `examples/h3-orchestrator.yaml`(인증 마이그레이션 + 배포)은 7역할이지만, 배포가
> 없는 H3(예: 내부 리팩터링 DAG)는 6역할로 끝난다. `validate-spec.py` 도 H3 에
> `orchestrator` 만 강제하고 `deployment-agent` 는 강제하지 않는다.

판정은 6축 프로파일링(scope / coupling / parallelism / uncertainty / risk / side_effect) 뒤
5스텝 판정 트리로 이루어진다. **한 단계 아래가 왜 안 되는지 쓸 수 없으면 아래 레벨이 맞다.**

## 구성

- `.claude/skills/harness-architect/SKILL.md` — Phase −1~5 오케스트레이터 (재개 판정 + Phase 0~5)
- `.claude/skills/harness-architect/references/` — 판정 기준 5종
  - `profiling.md` 6축 판정 규칙과 축별 반례
  - `routing.md` 판정 트리 + 레벨별 실행 절차 + 승격을 막는 반례
  - `catalog.md` 에이전트 7종 도구 경계 + 위임 스킬 12종(superpowers 11 + security-review) 매핑
  - `context-budget.md` 에이전트별 required / optional / forbidden
  - `linear-tracking.md` Linear 엔티티·상태 매핑과 기록 정책
- `.claude/skills/harness-architect/schemas/harness-spec.yaml` — 실행 계약 스키마
- `.claude/skills/harness-architect/examples/` — H0~H3 판정 사례 4종 (근거 문장 포함)
- `.claude/skills/harness-architect/scripts/` — `detect-stack` / `run-gates` / `init-workspace`
  / `harness-paths.sh` (`_workspace` 경로를 메인 워크트리에 고정) / `check-superpowers.sh` (필수 스킬 preflight)
  / `gate-summary.sh` (게이트 결과를 Linear 코멘트용으로 렌더링)
  / `validate-spec.py` (HarnessSpec 계약 검증) / `guard-readonly.py` (읽기 전용 역할 쓰기 차단 훅)
  / `checkpoint.py` (진행 상태를 `_workspace/harness/state.json` 에 원자적으로 기록)
  / `resume-check.py` (다음 세션에서 이어갈지 판정)
- `.claude/settings.json` — 위 훅을 `PreToolUse` 로 등록한다
- `.claude/agents/` × 7 — implementer / reviewer / dependency-mapper / baseline-tester /
  integrator / orchestrator / deployment-agent
- `tests/` — 스크립트 bash 테스트 하네스 (`bash tests/run-all.sh`, 판정 기준은 `FAIL 0`)
- `fixtures/` — 스택 감지용 가짜 프로젝트 5종
- `evals/` — 라우팅 판정 eval (H0 / H1 / H3 기대값과 실행 기록)
- `MIGRATION.md` — 다른 저장소로 이식하는 절차 (사전 요건·복사·검증·흔한 실패)
- `USAGE.md` — 설치 후 매일 어떻게 쓰는가 (Phase 별로 무엇을 보게 되는지, 문서 지도)
- `CHECKLIST.md` — 활용 체크리스트(Phase 별 확인 항목·거부해야 하는 판정 조합)와
  완성도 점검 체크리스트(결정론적 검증 명령·eval·**아직 검증되지 않은 영역**·이식 절차)
- `LINEAR-DRY-RUN.md` — Linear 추적 리허설. 가상 작업 하나로 `Triage → Todo →
  In Progress → In Review → Done` 전체 경로와 게이트 코멘트를 **사용자가 눈으로** 확인한다
- `fixtures/dry-run/gates/` — 리허설용 게이트 로그 (성공·실패 각 1건)

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

## 승인 게이트 확인

Phase 3 에서 승인을 요청받으면 다음을 확인한다. (`validate-spec.py` 가 exit 2 로 물러났을 때는
이 항목을 사람이 대신 본다.)

- [ ] 승인을 요청받기 전에 에이전트가 스폰되지 않았다
- [ ] 요약에 레벨·근거·에이전트와 모델·게이트·`max_loops`·Human Gate 가 전부 있다
- [ ] **한 단계 아래 레벨이 왜 안 되는지** 근거가 있다. 없으면 그 아래가 맞다
- [ ] `risk: high` 가 레벨 승격 근거로 쓰이지 않았다 (risk 는 reviewer·`max_loops` 만 바꾼다)
- [ ] **수용 기준마다 그것을 확인하는 게이트가 있다** — 게이트로 확인 불가능한 항목은
      `verification.manual` 에 있는가? 어느 쪽에도 없는 수용 기준은 검증되지 않은 채
      완료 선언된다
- [ ] (Linear 추적 시) 추적 대상이 만들어졌고 상태가 `Triage` 다
- [ ] (H2·H3) `controller_skills` 에 `using-git-worktrees` 와
      `finishing-a-development-branch` 가 **둘 다** 있다 — 격리를 만들었으면 해제도 절차에 있어야 한다
- [ ] **Phase 3 이상에서 재개한 세션이면 이전 세션의 승인을 재사용하지 않고 새로 승인받았다**

전체 판정 반증 절차는 `CHECKLIST.md` A-1·A-2 를 본다.

## 중단하면 재개한다

세션이 중간에 끊겨도 처음부터 다시 판정하지 않는다. 각 Phase 전환에서 `checkpoint.py` 가
진행 상태를 `_workspace/harness/state.json` 에 원자적으로 기록하고(`init-workspace.sh` ·
`run-gates.sh` 는 자동으로, 나머지 호출부는 `SKILL.md` 절차대로), 다음 세션은 Phase −1 에서
`resume-check.py` 를 돌려 이어갈지 판정한다.

| exit | 뜻 | 처리 |
|---|---|---|
| `0` | 재개할 것 없음 | Phase 0 으로 간다 |
| `10` | 자동 재개 후보 (Phase ≤ 2, 레포 드리프트 없음) | 브리핑의 `작업:` 이 지금 요청과 같으면 기록된 Phase 부터 잇는다. 아니면 `11` 처럼 다룬다 |
| `11` | 사람이 판단 | 브리핑을 제시하고 멈춘다. 재개·재판정·폐기를 사용자가 고른다 |
| `12` | 완료된 이전 작업이 남아 있다 | 새 작업을 시작할지 묻고, 승인되면 `checkpoint.py --archive` 로 보존한 뒤 Phase 0 |

**왜 자동 재개는 Phase 2 까지인가.** Phase 0~2 는 입력 정규화·프로파일링·라우팅 뿐이다 —
승인된 spec 도, 스폰된 에이전트도, 쓰여진 코드도 없다. 다시 판정해도 비용이 낮고 부작용이 없다.
Phase 3 부터는 사용자 승인과 실행 부작용이 걸려 있어 **사람이 다시 확인**해야 한다.
이전 세션의 `approved: true` 는 사실 기록일 뿐 이번 세션의 실행 권한이 아니다.

state 가 손상되면 `resume-check.py` 는 아무것도 추측하지 않고 `11` 로 사람에게 넘긴다 —
`checkpoint.py` 도 손상된 파일을 덮어쓰지 않고 exit 3 으로 멈춘다(복구 근거 보존).

## 실행

```bash
# 1. 스크립트 테스트 (판정 기준은 FAIL 0)
cd harness-architect && bash tests/run-all.sh

# 2. 스택 감지 확인
bash .claude/skills/harness-architect/scripts/detect-stack.sh fixtures/node-npm
```

그다음 이 디렉토리를 작업 디렉토리로 두고 "구현해줘" 같은 트리거로 스킬을 호출하면
Phase −1(재개 판정)부터 Phase 5 까지 진행된다. **Phase 3 에서 반드시 승인을 요청하고 멈춘다.**

## 결과 요약

- 스크립트 테스트 `bash tests/run-all.sh` 전부 통과 (`FAIL 0`) — `detect-stack` / `run-gates` /
  `validate-spec` / `guard-readonly` / `gate-summary` / `dry-run-doc` / `checkpoint` / `resume-check` /
  `harness-paths` 를 덮는다. 런북의 코멘트 예시가 실제 스크립트 출력과 일치하는지도 테스트가 대조한다.
  (**판정 기준은 `FAIL 0` 과 exit code 이지 PASS 개수가 아니다** — `CHECKLIST.md` B-1)
- 라우팅 판정 eval 3건 전부 기대값 일치 (H0 / H1 / H3): `evals/` 참고
- SKILL.md 자체 심사: 레포의 `reviewing-skill-md` 체크리스트(구조·발견성·크기·안티패턴) 전 항목 pass
  — 이는 **문서 품질** 심사이며, 실행 검증 상태는 아래와 `CHECKLIST.md` B-3 을 본다

**아직 검증되지 않은 영역**: H2 경로는 eval 에서 선택된 적이 없고, Phase 4 실행과
에이전트 dispatch 는 한 번도 돌지 않았다. `run-gates.sh` 는 실제 린트·테스트 명령이 아니라
`echo` 로만 검증했고, 훅의 실제 거부는 단위 테스트로만 확인했다(실제 서브에이전트 dispatch 미검증).
전체 목록과 확인 방법은 `CHECKLIST.md` B-3 참고.

설계 근거는 `../docs/guides/harnes-architect.md`, 구현 스펙은
`../docs/superpowers/specs/2026-08-29-harness-architect-design.md` 참고.
