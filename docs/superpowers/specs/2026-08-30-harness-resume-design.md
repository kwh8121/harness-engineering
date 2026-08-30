# harness-architect 재개(Resume) 설계

- 날짜: 2026-08-30
- 개정: 2026-08-30 (리뷰 반영 — [2026-08-30-harness-resume-review.md](./2026-08-30-harness-resume-review.md))
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
| 재개의 성격 | **단계별로 다름.** Phase 0~2는 자동 재개, **Phase 3 이후**는 브리핑 후 사람이 결정 |
| 기록 입도 | **Phase 경계 + 역할 마일스톤.** 에이전트 dispatch·게이트 결과·리뷰 루프 소진 |
| 저장소 불일치 | **자동 재개를 브리핑으로 강등.** Phase 0~2여도 강등한다 |

### 자동 재개 상한이 Phase 2인 이유

초안은 상한을 Phase 3으로 두고 "Phase 3 자동 재개는 곧 승인을 다시 받는 것"이라고 논증했다.
**그 논증은 틀렸다.** state에 `approved: true` 가 이미 저장돼 있으면 Phase 3을 자동 재개할 때
승인 단계는 이미 지난 것으로 읽히고, 곧바로 Phase 4 실행 권한으로 해석된다. 이는 같은 문서가
선언한 "승인이 저절로 부활하는 경로는 없다"와 정면으로 충돌한다.

따라서 두 가지를 함께 건다.

1. **자동 재개 상한은 Phase 2다.** Phase 3에 도달한 state는 승인 여부와 무관하게 사람 판단으로 간다.
2. **`approved` 는 재개 시 실행 권한으로 쓰이지 않는다.** 브리핑에 "이전 세션에서 승인됨"으로
   표시할 뿐이고, 새 세션의 Phase 4 진입은 새 승인을 요구한다.

## 설계

### 상태 파일

위치는 `_workspace/harness/state.json`. `scripts/harness-paths.sh` 가 `_workspace` 를
**메인 워크트리 루트**에 고정하므로 H2/H3에서 worktree가 제거돼도 state는 살아남는다.
재개 상태가 정리 대상과 함께 사라지면 안 되므로 이 결합은 의도적이다.

형식은 **JSON**이다. YAML이 아닌 이유는 PyYAML이 이 저장소에서 **선택 의존**이기 때문이다.
`validate-spec.py` 는 PyYAML이 없으면 exit 2로 물러나도 되지만 재개는 그때도 동작해야 한다.
`python3` 은 이미 하드 의존이고 `json` 은 표준 라이브러리다.

같은 이유로 진입점은 `checkpoint.py` · `resume-check.py` 다. JSON 조작이 본체인데 bash에 python
히어독을 박으면 테스트와 린트가 어렵고, 이 저장소는 이미 `validate-spec.py` · `guard-readonly.py`
로 `.py` 진입점 선례가 있다.

```json
{
  "schema_version": 1,
  "updated_at": "2026-08-30T11:20:03Z",
  "task": { "id": "20260830T110200Z-a3f1",
            "goal": "업로드 API 를 S3 로 이관한다",
            "spec_digest": "sha256:9f2c..." },
  "phase": "4",
  "level": "H2",
  "approved": true,
  "repo": { "head": "99c47aa", "branch": "feat/x",
            "worktree": "/abs/path|null",
            "tree_digest": "sha256:1b7e..." },
  "artifacts": { "spec": "_workspace/harness/spec.yaml",
                 "gates_tsv": "_workspace/harness/gates.tsv",
                 "sdd_ledger": ".superpowers/sdd/<slug>/|null" },
  "progress": {
    "agents_done": ["dependency-mapper", "baseline-tester"],
    "agents_pending": ["implementer", "integrator", "reviewer"],
    "gates": [ { "tier": "fast", "exit": 0, "attempt": 1,
                 "recorded_at": "2026-08-30T11:18:00Z",
                 "log_path": "_workspace/harness/gates/fast.log" } ],
    "review_loops_used": 1,
    "human_gate_passed": false
  },
  "next_action": "implementer dispatch — 작업 단위 2/3"
}
```

두 가지 원칙을 지킨다.

**산출물을 복제하지 않고 경로로만 가리킨다.** 게이트 로그 본문은 `gates/*.log` 에 이미 있으므로
state에는 tier·exit·attempt·경로만 둔다. 저장소의 "컨텍스트는 경로로 전달한다" 규칙과 같고,
state 파일이 비대해져 스스로 컨텍스트 비용이 되는 것을 막는다.

**`next_action` 한 줄이 이 기능의 핵심이다.** "길을 잃지 않는다"의 실체는 스키마가 아니라
재개한 사람이 처음 읽는 이 한 줄이다.

### `task` — 이전 작업과 현재 요청을 구분한다

state가 있다는 사실만으로는 **사용자가 그 작업을 이어가려는지** 알 수 없다. 같은 저장소에서
전혀 다른 새 작업을 요청해도 Phase 0~2 state가 남아 있으면 자동 재개가 걸린다.

- `task.id` — 작업 시작 시각 기반 식별자. 브리핑과 아카이브 파일명에 쓴다.
- `task.goal` — Phase 0에서 정규화한 `goal` 문장 그대로.
- `task.spec_digest` — 승인된 `spec.yaml` 의 sha256. 사람이 spec을 손으로 고쳤는지 잡는다.

**동일성 판정은 스크립트가 하지 않는다.** 두 문장이 같은 작업인지는 의미 판단이고, 그것은
스킬(사용자 요청을 컨텍스트로 가진 쪽)의 몫이다. `resume-check.py` 는 `task.goal` 을 브리핑
맨 위에 **눈에 띄게** 출력하고, `SKILL.md` 가 "이것이 지금 요청과 같은 작업인가"를 판단한다.
같지 않거나 확신할 수 없으면 자동 재개하지 않고 사람에게 묻는다.

**`spec_digest` 는 저장만으로 끝나지 않는다.** `_workspace/` 는 아래 `tree_digest` 에서
제외되므로, 승인된 `spec.yaml` 이 손으로 수정돼도 HEAD·브랜치·작업 트리 지문은 전부 그대로다.
**바뀐 계약으로 재개하는 것이 가장 위험한 실패**이므로 다음을 강제한다.

- `checkpoint.py` 는 `--approved` 시 `artifacts.spec` 이 가리키는 파일을 **직접 읽어 해시한다.**
  스킬이 digest를 계산해 넘기지 않는다 — 넘기게 하면 잊거나 틀릴 수 있다.
- `resume-check.py` 는 같은 파일을 다시 해시해 `task.spec_digest` 와 비교한다.
- **불일치하거나 파일이 사라졌으면 불일치(drift)로 기록하고 exit 11**로 보낸다.

### 손상된 state는 절대 덮어쓰지 않는다 (fail-closed)

초안의 `load()` 는 JSON 파싱 실패·I/O 오류·미지원 schema를 전부 `blank_state()` 로 바꿨다.
그 뒤 `save()` 가 그 빈 상태를 쓰면 **원본 손상 파일이 사라져 복구 근거를 잃는다.** 자동 기록
(`init-workspace.sh` · `run-gates.sh`)이 오류를 숨기고 있으므로 사용자는 알아채지도 못한다.

- `blank_state()` 는 **파일이 없을 때만** 반환한다.
- 파싱 실패와 미지원 `schema_version` 은 오류로 반환하고 **기존 파일을 건드리지 않은 채**
  0이 아닌 exit code로 끝낸다.
- 자동 기록은 본 작업(게이트·초기화)을 막지 않되 **stderr에 한 줄 경고**를 남긴다.
  조용한 실패는 이 기능의 목적 자체를 무너뜨린다.

### 상태 전이 불변식

`checkpoint.py` 는 다음을 거부한다.

| 거부 | 이유 |
|---|---|
| `--approved` 가 `--phase 3` 없이 오는 경우 | 승인은 Phase 3의 산물이다 |
| `--agents` 가 `--phase 3 --approved` 없이 오는 경우 | 에이전트 구성은 승인의 산물이다 |
| `--agents` 가 비었거나 중복 id를 포함 | 같은 역할이 pending에 두 번 들어간다 |
| `--agent-done X` 에서 `X` 가 `agents_pending` 에 없음 | 완료할 수 없는 것을 완료 처리한다 |
| `X` 가 카탈로그 7종 밖 | `validate-spec.py` 의 `CATALOG` 와 같은 집합이어야 한다 |
| `--archive` 인데 `phase != done` | 진행 중인 작업을 은퇴시킨다 |
| 아카이브 파일명 충돌 | 기존 기록을 덮어쓴다 |
| `--phase` 로 **번호를 낮추는** 경우 | 아래 `--replan` 으로만 한다 |

#### Phase 역행은 `--replan` 이라는 전용 문으로만 한다

`references/routing.md` 의 H2 2단계는 dependency-mapper가 "실은 독립이 아니다"라고 보고하면
**H1로 강등하고 spec을 고쳐 재승인**받게 한다. 그때 phase는 4에서 3으로 되돌아가며 이는
정상 경로다. **따라서 역행 자체는 막지 않는다.**

그러나 맨 `--phase 3` 으로 되돌리면 이전 계약의 `approved` · `agents_*` · `gates` ·
`review_loops_used` · `human_gate_passed` · `spec_digest` 가 **그대로 남아 새 계획으로
흘러든다.** 이전 승인이 살아 있고 소진된 리뷰 루프가 이월된다.

`--replan --level <새 레벨>` 을 두고 다음을 초기화한다.

| 초기화 | 유지 |
|---|---|
| `approved` → false | `task.id` · `task.goal` |
| `agents_done` · `agents_pending` → `[]` | `artifacts` |
| `gates` → `[]` | `repo` (재계산) |
| `review_loops_used` → 0 | |
| `human_gate_passed` → false | |
| `task.spec_digest` → null | |
| `phase` → `"3"` (승인 대기) | |

`gates` 를 비우는 것이 증거를 잃는 것은 아니다 — **게이트 로그 전문은 `gates/*.log` 에 그대로
남는다.** state의 `gates` 는 "이번 계약에서 무엇을 통과했나"를 말하므로 계약이 바뀌면 비우는
것이 맞고, `attempt` 도 새 계약 기준으로 1부터 다시 센다.

### 재개 판정

`resume-check.py` 를 Phase 0보다 먼저 실행한다. exit code는 `init-workspace.sh` 의 3·4와
헷갈리지 않도록 10번대를 쓴다.

| exit | 의미 | 스킬의 행동 |
|---|---|---|
| 0 | state 없음 | 평소대로 Phase 0 진행 |
| 10 | 자동 재개 후보 (phase ≤ 2, 불일치 없음) | 브리핑을 보이고 **`task.goal` 이 지금 요청과 같은 작업인지 확인한 뒤** 이어서 진행 |
| 11 | **사람 판단 필요** | 브리핑 출력 후 **멈춘다** |
| 12 | 완료된 이전 작업이 남아 있음 | 새 작업을 시작할지 묻는다 |

exit 11로 가는 조건은 넷이다 — **Phase 3 이상이거나**, **불일치가 감지됐거나**,
**state가 손상됐거나**, **`schema_version` 이 다르거나.** 깨진 상태를 추측으로 복구하지 않는다.

`phase` 는 문자열이지만 비교는 정수로 한다. `"done"` 은 정수 비교 대상에서 제외하고 따로 판정한다.

### 브리핑 규격

exit 10·11·12가 모두 같은 브리핑을 렌더링한다. 다른 것은 길이가 아니라 그 뒤 스킬의 행동이다.

```
[재개] H2 · Phase 4 · 이전 세션에서 승인됨 · 2026-08-30 11:20
  작업:      업로드 API 를 S3 로 이관한다  (20260830T110200Z-a3f1)
  다음 할 일: implementer dispatch — 작업 단위 2/3
  끝난 것:   dependency-mapper, baseline-tester · 게이트 fast(0) 1회
  남은 것:   implementer, integrator, reviewer · 리뷰 루프 1/2 소진
  불일치:    HEAD 99c47aa → 73cdad9 · 작업 트리 변경됨
  경로:      state _workspace/harness/state.json
             spec  _workspace/harness/spec.yaml
             SDD   .superpowers/sdd/<slug>/
```

**`작업` 과 `다음 할 일` 이 헤더 바로 다음에 오는 것이 규격의 핵심이다.** 재개하는 사람이 가장
먼저 확인해야 하는 것은 "이게 내가 지금 하려는 그 작업인가"이고, 그 다음이 "무엇부터 하는가"다.
이력은 그 뒤다. 불일치 행은 불일치가 있을 때만 낸다.

### 불일치 판정

기록된 `repo` 와 현재를 비교해 **HEAD SHA · 브랜치 · worktree 존재 · 작업 트리 digest**,
그리고 **`spec_digest`** 중 하나라도 다르면 exit 11로 강등한다.

#### `tree_digest` 는 파일 **내용** 기반이다

초안은 `git status --porcelain` 의 행을 해시했다. **그것으로는 부족하다.** `git status` 는 경로와
변경 여부만 낼 뿐 내용을 담지 않으므로, 이미 수정된 같은 파일을 다시 다르게 고쳐도 출력이
`M a.txt` 로 동일해 digest가 바뀌지 않는다. 임시 저장소에서 재현했다 — 서로 다른 두 내용이
같은 digest(`b2b4847c…`)를 냈다.

따라서 다음을 해시한다.

- **tracked 변경**: `git diff --binary HEAD` 의 전체 출력. 내용이 바뀌면 digest도 바뀐다.
- **untracked 파일**: 정렬한 상대 경로 + 각 파일 내용의 sha256.

`_workspace/` 제외는 **pathspec으로 한다** (`:(exclude)_workspace/`). 초안의 문자열 필터
(`"_workspace/" not in line`)는 `src/my_workspace/…` 같은 무관한 경로까지 지운다.

초안이 `dirty` boolean을 강등 조건에서 아예 뺀 것도 과했다. 자동 재개가 Phase 0~2로 좁아졌고
그 구간에서 하네스가 쓰는 것은 `_workspace/` 뿐이므로, 제외만 정확하면 digest는 정상 동작 중에
안정적이다 — 바뀌었다면 정말로 바깥에서 무언가 변한 것이다.

### state 내부 구조 검증 (`validate_state`)

최상위가 매핑이고 `schema_version` 이 맞아도 **내부 타입이 깨져 있으면 처리되지 않은 예외로
죽는다.** 예를 들어 아래는 문법과 버전을 통과하지만 `drift()` 의 `recorded.get("head")` 에서
`AttributeError` 를 낸다.

```json
{ "schema_version": 1, "phase": "2", "repo": "broken" }
```

이는 설계가 약속한 "손상된 state는 예외 없이 exit 11"을 어긴다. `validate_state(state) -> list[str]`
을 두어 `task` · `repo` · `artifacts` · `progress` 가 매핑인지, `agents_done`/`agents_pending`/`gates`
가 리스트이고 각 gate 항목이 매핑인지, scalar 필드의 타입이 맞는지 검사한다. 하나라도 어긋나면
**브리핑 가능한 최소 정보와 오류 목록을 출력하고 exit 11**로 끝낸다.

### 진행 입도 — 역할 마일스톤이다

`agents_done` · `agents_pending` 은 **역할 단위 마일스톤**이며 작업 단위 진행이 아니다.
H2/H3에서 같은 `implementer` 역할이 여러 작업 단위를 순차 처리할 때, 첫 단위 완료와 전체 구현
완료를 이 목록은 구별하지 못한다.

**그 구별은 SDD ledger의 몫이다.** 따라서 `--agent-done implementer` 는 **SDD 루프 전체가
끝났을 때만** 호출한다. state에 `units[{id, agent, status}]` 를 추가하지 않는 것은
"SDD의 진행 원장을 재구현하지 않는다"(`references/catalog.md`)는 원칙 때문이다.

### 생명주기

Phase 5가 끝나면 `phase: "done"` 이 되고 다음 실행에서 exit 12가 난다. 사용자가 새 작업 시작을
승인하면 스킬이 `checkpoint.py --archive` 를 불러 기존 state를
`state.done-<task.id>.json` 으로 **보존하고** state.json을 지운다. 파일명이 이미 있으면
덮어쓰지 않고 접미사를 붙인다. 다음 `init-workspace.sh` 가 새로 만든다.

나이 기반 만료는 두지 않는다. 오래됐다는 것이 틀렸다는 뜻은 아니고, 그 역할은 이미 불일치
검사가 한다.

## 기존 자산과의 경계

### SDD ledger — 재구현하지 않는다

`references/catalog.md` 는 *"SDD의 워크스페이스·진행 원장을 그대로 호출하고 재구현하지 않는다"*
고 못박고 있다. state.json은 `artifacts.sdd_ledger` 로 **경로만** 가리키고, 태스크 단위 복원은
SDD 자신의 "ledger check"가 한다. 이 설계가 채우는 것은 **SDD 진입 전후 구간**이다 —
worktree 생성, 조사 2인 dispatch, `writing-plans`, 그리고 SDD 이후의 integrator·reviewer·최종 게이트.

### Linear — 재개 판정에 읽지 않는다

**Linear는 관측 수단이지 실행 경로가 아니다**(기존 불변식). 진실의 원천은 state.json 하나이며,
`tracking.provider: none` 으로도 재개가 온전히 동작해야 한다. 브리핑에 링크는 표시하되 상태가
어긋나 있어도 재개를 막지 않는다.

### worktree — 정리와 충돌하지 않는다

`repo.worktree` 에 경로를 기록하고 재개 시 없으면 불일치로 exit 11이다. 정리는 Phase 5의
마지막이고 `--done` 은 그 뒤에 찍히므로 "done + worktree 없음"은 정상이다. 반대로 **정리 도중
중단되면** "phase 5 + worktree 없음"이 되어 브리핑으로 가는데, 이것이 의도한 동작이다.

## 구현 단계

이 저장소(개발)와 `agent-architect`(배포)의 스킬 트리가 **13개 파일 분기해 있다** — 2026-08-30
세션의 worktree 정리 흐름과 superpowers preflight가 배포 저장소에만 들어갔다. 테스트가 자기
저장소의 스크립트를 참조하므로 분기를 먼저 해소해야 한다.

1. **역이식** — 배포 저장소의 변경을 이 저장소로 가져온다.
2. **개발** — `checkpoint.py` · `resume-check.py` 구현 + 테스트. `init-workspace.sh` ·
   `run-gates.sh` 에 자동 기록. `SKILL.md` 반영.
3. **이식** — 배포 저장소로 복사.

**동기화는 파괴적이어서는 안 된다.** `rsync --delete` 를 바로 실행하지 않고 `-ain` 으로 먼저
목록을 뽑아 확인한다. `git add -A` 를 쓰지 않고 태스크가 소유한 경로만 stage한다. 실제로 배포
저장소에는 이 작업과 무관한 `.gitignore` 변경(`.omx/` 추가)이 있으며, `git add -A` 였다면 그것이
커밋에 섞였을 것이다.

### 이식 경계 — `settings.json` 을 포함한다

`MIGRATION.md` 는 이식 대상을 `skills/` + `agents/*.md` + **`settings.json`** 세 가지로 규정한다
(읽기 전용 가드 훅이 여기 등록된다). `CHECKLIST.md` B-4는 "두 경로만"이라고 적어 서로 모순이며,
이 모순도 함께 정정한다.

또한 `MIGRATION.md` 의 **"정확히 25개 파일"과 검증 명령 `find .claude -type f | wc -l # 25`
는 이미 낡았다.** `harness-paths.sh` · `check-superpowers.sh` 가 늘어 배포본은 27개이며, 이
설계가 `checkpoint.py` · `resume-check.py` 를 더하면 29개가 된다.

## 검증

`tests/` 는 이식 경계 밖이므로 테스트는 이 저장소에만 둔다.

| # | 입력 | 기대 |
|---|---|---|
| 1 | state 없음 | exit 0 |
| 2 | phase 2, 불일치 없음 | exit 10 |
| 3 | **phase 3 + `approved: true`** | **exit 11 — 승인은 부활하지 않는다** |
| 4 | phase 4 | exit 11 |
| 5 | phase 2 + HEAD 변경 | exit 11 |
| 6 | phase 2 + 브랜치 변경 | exit 11 |
| 7 | worktree 기록됐으나 없음 | exit 11 |
| 8 | **phase 2 + 같은 HEAD에서 작업 트리 변경** | **exit 11 — tree_digest 불일치** |
| 9 | 손상된 JSON | exit 11 |
| 10 | 미지원 `schema_version` | exit 11 |
| 11 | phase done | exit 12 |
| 12 | **손상 state + 게이트 실행** | **원본 바이트가 보존된다** |
| 13 | 반복 쓰기 중 reader | **항상 완전한 JSON만 관측된다** |
| 14 | `--archive` 인데 `phase != done` | 거부 |
| 15 | 아카이브 파일명 충돌 | 기존 기록을 덮지 않는다 |
| 16 | 카탈로그 밖 agent id | 거부 |
| 17 | pending에 없는 `--agent-done` | 거부 |
| 18 | `--approved` 가 phase 3 없이 | 거부 |
| 19 | 맨 `--phase` 로 번호 낮추기 | 거부 (`--replan` 으로 유도) |
| 20 | `--replan --level H1` | 승인·에이전트·게이트·루프·Human Gate·spec_digest 초기화, phase 3 |
| 21 | `--agents` 가 `--approved` 없이 | 거부 |
| 22 | `--agents` 에 중복 id | 거부 |
| 23 | **spec.yaml 내용 변경 후 재개** | **exit 11 — spec_digest 불일치** |
| 24 | **spec.yaml 삭제 후 재개** | **exit 11** |
| 25 | spec.yaml 그대로 | 기존 판정 유지 |
| 26 | **이미 수정된 파일을 다시 다르게 수정** | **exit 11 — 내용 기반 tree_digest** |
| 27 | `src/my_workspace/x` 변경 | 강등한다 (`_workspace/` pathspec 제외에 걸리지 않는다) |
| 28 | **`repo: "broken"`** | **exit 11 — 예외로 죽지 않는다** |
| 29 | **`progress: []`** | **exit 11** |
| 30 | **`gates: [null]`** | **exit 11** |
| 31 | `run-gates.sh` 실행 후 | `gates` 항목이 자동 추가된다 |
| 32 | `init-workspace.sh` 실행 후 | state가 생성된다 |
| 33 | checkpoint 실패 | 게이트 exit code는 유지하되 stderr 경고 |
| 34 | `os.replace` 직전 예외 | 기존 state가 그대로 유지된다 (선택) |
| 35 | PyYAML 없는 환경 | 재개가 정상 동작한다 |

**동시 writer는 지원하지 않는다.** 하네스는 구현 워커의 동시 dispatch를 금지하므로 state를 쓰는
주체는 항상 하나다. 이 전제를 불변식으로 명시하고, 위반 시 동작은 정의하지 않는다.

## 만들지 않는 것 (YAGNI)

동시 작업 여러 개, 별도 이력 저널, 나이 기반 만료, Linear 역동기화, `units[]` 작업 단위 추적은
넣지 않는다. 마지막 항목은 SDD ledger의 책임이다.

## 새로 생기는 불변식

`CLAUDE.md` 의 불변식 표에 추가한다.

| 개념 | 정의 위치 (전부 일치해야 함) |
|---|---|
| resume exit code 10·11·12 | `scripts/resume-check.py` · `SKILL.md` Phase −1 · README |
| state 스키마 (`schema_version`) | `scripts/checkpoint.py` · `scripts/resume-check.py` |
| 자동 재개 상한 (`AUTO_MAX_PHASE = 2`) | `scripts/resume-check.py` · `SKILL.md` · 이 설계 문서 |
| 카탈로그 7종 | `scripts/validate-spec.py` · `scripts/checkpoint.py` · `references/catalog.md` · `.claude/agents/*.md` |
| 이식 대상 파일 수 | `MIGRATION.md` · `CHECKLIST.md` B-4 |
