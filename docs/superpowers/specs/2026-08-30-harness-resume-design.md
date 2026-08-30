# harness-architect 재개(Resume) 설계

- 날짜: 2026-08-30
- 대상: `harness-architect` 스킬
- 관련 문서: [2026-08-29-harness-architect-design.md](./2026-08-29-harness-architect-design.md)

## 문제

개발 세션이 끝나거나 Phase 진행 중 작업이 멈추면, 다음 세션이 **어디까지 했는지 알 방법이 없다.**
산출물은 대부분 살아남는데도 그렇다.

| 살아남는 것 | 재개에 쓸 수 있는 정보 | 빠진 것 |
|---|---|---|
| `spec.yaml` | 승인된 계약 전체 (레벨·에이전트·게이트·`max_loops`) | 진행 위치 |
| `gates/*.log` | 어떤 tier가 어떤 exit code로 끝났는지 | 언제·몇 번째 시도인지 |
| `research/` · `review/` | 에이전트 산출물 | 누가 남았는지 |
| SDD `ledger` | 태스크 단위 진행 | **H2/H3의 Phase 4 안에서만.** Phase 개념을 모름 |
| Linear (선택) | 상태 전이 | 선택 사항이라 없을 수 있음 |

즉 **"Phase 0~5 중 어디였는가"와 "승인을 받았는가"를 아무도 기록하지 않는다.**
새 세션이 그것을 찾아봐야 한다는 사실도 어디에도 적혀 있지 않다. H0·H1은 SDD를 쓰지 않으므로
ledger조차 없다 — 가장 흔한 두 레벨이 비보호 상태다.

## 결정 사항

| 질문 | 결정 |
|---|---|
| 재개의 성격 | **단계별로 다름.** Phase 0~3은 자동 재개, Phase 4~5는 브리핑 후 사람이 결정 |
| 기록 입도 | **Phase 경계 + 단위별 진행.** 에이전트 dispatch·게이트 결과·리뷰 루프 소진 |
| 저장소 불일치 | **자동 재개를 브리핑으로 강등.** Phase 0~3이어도 강등한다 |

경계의 근거: **파일을 쓰기 시작한 뒤부터는 사람이 판단한다.** 승인 요청 자체가 Phase 3의 마지막
단계이므로 "Phase 3 자동 재개"는 곧 "요약을 다시 제시하고 승인을 다시 받는다"가 된다 —
승인이 저절로 부활하는 경로는 없다.

## 설계

### 상태 파일

위치는 `_workspace/harness/state.json`. `scripts/harness-paths.sh` 가 `_workspace` 를
**메인 워크트리 루트**에 고정하므로 H2/H3에서 worktree가 제거돼도 state는 살아남는다.
재개 상태가 정리 대상과 함께 사라지면 안 되므로 이 결합은 의도적이다.

형식은 **JSON**이다. YAML이 아닌 이유는 PyYAML이 이 저장소에서 **선택 의존**이기 때문이다.
`validate-spec.py` 는 PyYAML이 없으면 exit 2로 물러나도 되지만 재개는 그때도 동작해야 한다.
`python3` 은 이미 하드 의존이고 `json` 은 표준 라이브러리다.

```json
{
  "schema_version": 1,
  "updated_at": "2026-08-30T11:20:03Z",
  "phase": "4",
  "level": "H2",
  "approved": true,
  "repo": { "head": "99c47aa", "branch": "feat/x",
            "worktree": "/abs/path|null", "dirty": true },
  "artifacts": { "spec": "_workspace/harness/spec.yaml",
                 "gates_tsv": "_workspace/harness/gates.tsv",
                 "sdd_ledger": ".superpowers/sdd/<slug>/|null" },
  "progress": {
    "agents_done": ["dependency-mapper", "baseline-tester"],
    "agents_pending": ["implementer", "integrator", "reviewer"],
    "gates": [ { "tier": "fast", "exit": 0 } ],
    "review_loops_used": 1,
    "human_gate_passed": false
  },
  "next_action": "implementer dispatch — 작업 단위 2/3"
}
```

두 가지 원칙을 지킨다.

**산출물을 복제하지 않고 경로로만 가리킨다.** 게이트 로그 본문은 `gates/*.log` 에 이미 있으므로
state에는 tier와 exit code만 둔다. 저장소의 "컨텍스트는 경로로 전달한다" 규칙과 같고,
state 파일이 비대해져 스스로 컨텍스트 비용이 되는 것을 막는다.

**`next_action` 한 줄이 이 기능의 핵심이다.** "길을 잃지 않는다"의 실체는 스키마가 아니라
재개한 사람이 처음 읽는 이 한 줄이다.

**크래시 안전성** — 같은 디렉터리에 임시 파일을 쓰고 `mv` 로 원자적으로 교체한다. 중단이 하필
쓰기 도중에 나도 반쪽짜리 JSON이 남지 않는다. 읽을 때 파싱에 실패하면 state가 없는 것이 아니라
**깨진 것**으로 보고 브리핑으로 보낸다 — 깨진 상태를 신뢰하느니 사람에게 넘긴다.

### 기록 시점

A안의 약점은 "스킬이 부르는 것을 잊으면 끝"이라는 점이다. 그래서 **가장 중요한 두 지점은 기존
스크립트에 얹어 자동화**한다.

| 시점 | 누가 쓰는가 | 방식 |
|---|---|---|
| Phase 1 시작 | `init-workspace.sh` | **자동** |
| 게이트 실행 결과 | `run-gates.sh` | **자동** (tier·exit code를 이미 알고 있음) |
| Phase 2 판정 완료 | 스킬 → `checkpoint.sh --phase 2 --level H2` | 규율 |
| Phase 3 승인 | 스킬 → `checkpoint.sh --approved` | 규율 |
| 에이전트 dispatch 완료 | 스킬 → `checkpoint.sh --agent-done implementer` | 규율 |
| 리뷰 루프 소진 | 스킬 → `checkpoint.sh --review-loop` | 규율 |
| Human Gate 통과 | 스킬 → `checkpoint.sh --human-gate-passed` | 규율 |
| Phase 5 완료 | 스킬 → `checkpoint.sh --done` | 규율 |
| 완료된 state 은퇴 | 스킬 → `checkpoint.sh --archive` | 규율 (exit 12 뒤) |

`validate-spec.py` 에는 일부러 얹지 않는다. 검증기가 부수효과를 가지면 "검증만 해보기"가
상태를 오염시킨다.

**`agents_pending` 의 초기값은 `spec.yaml` 의 `agents[].id` 목록이다.** `--phase 3 --approved`
시점에 spec에서 읽어 채운다 — 승인 전에는 에이전트 구성이 확정되지 않았으므로 그 전에 채우면
거짓이 된다. `--agent-done X` 는 `X` 를 `agents_pending` 에서 제거하고 `agents_done` 에 넣는
단일 연산이며, 두 목록의 합집합은 항상 spec의 에이전트 집합과 같아야 한다.

### 재개 판정

`resume-check.sh` 를 Phase 0보다 먼저 실행한다. exit code는 `init-workspace.sh` 의 3·4와
헷갈리지 않도록 10번대를 쓴다.

| exit | 의미 | 스킬의 행동 |
|---|---|---|
| 0 | state 없음 | 평소대로 Phase 0 진행 |
| 10 | 자동 재개 가능 (phase ≤ 3, 불일치 없음) | 브리핑 한 줄만 보이고 이어서 진행 |
| 11 | **사람 판단 필요** | 브리핑 출력 후 **멈춘다** |
| 12 | 완료된 이전 작업이 남아 있음 | 새 작업을 시작할지 묻는다 |

exit 11로 가는 조건은 셋이다 — **Phase 4~5였거나**, **불일치가 감지됐거나**,
**state 파싱에 실패했거나.** 깨진 상태를 추측으로 복구하지 않는다.

`phase` 는 문자열이지만 비교는 정수로 한다(`"10"` 같은 값이 생길 일은 없으나 문자열 비교로
`"4" < "5"` 에 의존하지 않는다). `"done"` 은 정수 비교 대상에서 제외하고 별도로 판정한다.

### 브리핑 규격

exit 10·11·12가 모두 같은 브리핑을 렌더링한다. 다른 것은 **길이**가 아니라 그 뒤 스킬의
행동이다. 브리핑은 `resume-check.sh` 가 state.json에서 생성하며 다음을 이 순서로 낸다.

```
[재개] H2 · Phase 4 · 승인됨 · 2026-08-30 11:20 (3시간 전)
  다음 할 일: implementer dispatch — 작업 단위 2/3
  끝난 것:   dependency-mapper, baseline-tester · 게이트 fast(0)
  남은 것:   implementer, integrator, reviewer · 리뷰 루프 1/2 소진
  불일치:    HEAD 99c47aa → 73cdad9 (커밋 2건 추가됨)
  경로:      spec _workspace/harness/spec.yaml
             SDD  .superpowers/sdd/<slug>/
```

**`다음 할 일` 이 첫 줄 다음에 오는 것이 규격의 핵심이다.** 재개하는 사람이 가장 먼저 읽어야
하는 것은 이력이 아니라 다음 행동이다. 불일치 행은 불일치가 있을 때만 낸다.

### 불일치 판정

기록된 `repo` 와 현재를 비교해 **HEAD SHA · 브랜치 · worktree 존재** 셋 중 하나라도 다르면
exit 11로 강등한다. Phase 0~3이어도 강등한다.

`dirty` 는 강등 조건에서 뺀다. 작업 중이면 항상 바뀌므로 트리거로 쓰면 자동 재개가 사실상
죽는다. 브리핑에 표시만 한다.

### 생명주기

Phase 5가 끝나면 `phase: "done"` 이 되고 다음 실행에서 exit 12가 난다. 사용자가 새 작업 시작을
승인하면 스킬이 `checkpoint.sh --archive` 를 불러 기존 state를 `state.done-<updated_at>.json`
으로 **보존하고** state.json을 지운다. 다음 `init-workspace.sh` 가 새로 만든다. 삭제하지
않는 것은 `_workspace/` 보존 규칙과 같은 이유다.

타임스탬프는 아카이브 시각이 아니라 state의 `updated_at` 을 쓴다 — 파일 이름이 "언제 아카이브
했는가"가 아니라 "언제까지의 작업인가"를 말해야 나중에 찾을 수 있다.

나이 기반 만료는 두지 않는다. 오래됐다는 것이 틀렸다는 뜻은 아니고, 그 역할은 이미 불일치
검사가 한다.

## 기존 자산과의 경계

### SDD ledger — 재구현하지 않는다

`references/catalog.md` 는 *"SDD의 워크스페이스·진행 원장을 그대로 호출하고 재구현하지 않는다"*
고 못박고 있다. 이 설계는 그 선을 지킨다.

state.json은 `artifacts.sdd_ledger` 로 **경로만** 가리킨다. H2/H3의 Phase 4를 재개할 때 태스크
단위 복원은 SDD 자신의 "ledger check"가 하고, 이 설계는 **SDD 진입 전후 구간만** 채운다 —
worktree 생성, 조사 2인 dispatch, `writing-plans`, 그리고 SDD 이후의 integrator·reviewer·최종
게이트. 여기가 지금 아무도 기록하지 않는 공백이다.

### Linear — 재개 판정에 읽지 않는다

**Linear는 관측 수단이지 실행 경로가 아니다**(기존 불변식). 진실의 원천은 state.json 하나이며,
`tracking.provider: none` 으로도 재개가 온전히 동작해야 한다.

브리핑에 Linear 링크는 표시하되, 상태가 어긋나 있어도(state는 `In Progress` 인데 Linear는
`Todo`) 재개를 막지 않는다. 동기화는 재개 후 정상 흐름이 한다. worktree 정리에서 내린 것과
같은 원칙이다.

### worktree — 정리와 충돌하지 않는다

`repo.worktree` 에 경로를 기록하고 재개 시 없으면 불일치로 exit 11이다. 순서상 충돌은 없다 —
정리는 Phase 5의 마지막이고 `--done` 은 그 뒤에 찍히므로 "done + worktree 없음"은 정상이다.
반대로 **정리 도중 중단되면** "phase 5 + worktree 없음"이 되어 브리핑으로 가는데, 이것이
의도한 동작이다.

## 구현 단계

이 저장소(개발)와 `agent-architect`(배포)의 스킬 트리가 **이미 13개 파일 분기해 있다** —
2026-08-30 세션의 worktree 정리 흐름과 superpowers preflight가 배포 저장소에만 들어갔다.
테스트가 자기 저장소의 `.claude/skills/.../scripts/` 를 참조하므로 분기를 먼저 해소해야 한다.

1. **역이식** — 배포 저장소의 변경 13건을 이 저장소로 가져와 둘을 맞춘다.
   가져온 뒤 `tests/run-all.sh` 로 회귀가 없는지 확인한다.
2. **개발** — 이 저장소에서 `checkpoint.sh` · `resume-check.sh` 를 구현하고 테스트를 붙인다.
   `init-workspace.sh` · `run-gates.sh` 에 자동 기록을 얹는다. `SKILL.md` Phase 0에 재개 판정을,
   Phase 1~5에 기록 호출을 넣는다.
3. **이식** — `.claude/skills/harness-architect/` 와 `.claude/agents/*.md` 두 경로만
   배포 저장소로 복사한다 (`CHECKLIST.md` B-4).

## 검증

`tests/` 는 이식 경계 밖이므로 테스트는 이 저장소에만 둔다. 배포 저장소에는 `CLAUDE.md` 의
검증 절차에 항목을 추가한다.

| # | 입력 | 기대 |
|---|---|---|
| 1 | state 없음 | exit 0 |
| 2 | phase 2, 불일치 없음 | exit 10 |
| 3 | phase 4 | exit 11 (Phase 4는 항상 사람) |
| 4 | phase 2 + HEAD 변경 | exit 11 |
| 5 | phase 2 + 브랜치 변경 | exit 11 |
| 6 | worktree 기록됐으나 없음 | exit 11 |
| 7 | 깨진 JSON | exit 11 (처리되지 않은 예외로 죽지 않는다) |
| 8 | phase done | exit 12 |
| 9 | `checkpoint.sh` 원자적 쓰기 | 임시 파일 잔여 없음 |
| 10 | `run-gates.sh` 실행 후 | `gates` 항목이 자동 추가된다 |
| 11 | `init-workspace.sh` 실행 후 | state가 생성된다 |
| 12 | PyYAML 없는 환경 | 재개가 정상 동작한다 |

## 만들지 않는 것 (YAGNI)

동시 작업 여러 개, 별도 이력 저널, 나이 기반 만료, Linear 역동기화는 넣지 않는다. 하네스가
이미 동시 구현 워커를 금지하므로 state 파일 하나로 충분하고, 이력은 `state.done-<ts>.json`
보존으로 갈음한다.

## 새로 생기는 불변식

`CLAUDE.md` 의 불변식 표에 추가한다.

| 개념 | 정의 위치 (전부 일치해야 함) |
|---|---|
| resume exit code 10·11·12 | `scripts/resume-check.sh` · `SKILL.md` Phase 0 · README |
| state 스키마 (`schema_version`) | `scripts/checkpoint.sh` · `scripts/resume-check.sh` |
