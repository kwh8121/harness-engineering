# Harness Router — 판정 트리와 레벨별 실행 절차

## 최상위 규칙

```
Always choose the least complex harness that can safely complete the task.
```

한 레벨 위를 고르고 싶을 때마다, **아래 레벨이 왜 안 되는지**를 한 문장으로 쓸 수 있어야 한다.
쓸 수 없으면 아래 레벨이 맞다. 이 문장은 `harness.rationale` 에 그대로 들어간다.

## 판정 트리

```
STEP 1  단일 세션·단일 컨텍스트로 안전하게 완료 가능한가?
        (변경 영역 1개 AND risk ≤ low AND uncertainty = low)
        YES → H0
        NO  ↓

STEP 2  작업 단위가 1개인가?
        판정 질문: "구현자 한 명이 한 번에 끝까지 들고 갈 수 있는가?"
        여러 영역을 건드려도, 중간 산출물을 따로 검증할 수 없어 통째로 가야 하면 단위는 1개다.
        YES → H1
        NO  ↓   (단위가 2개 이상 — 병렬이든 순차든)

STEP 3  그 단위들이 서로 독립인가?
        (동시 실행 가능 AND 동일 파일 수정 충돌 위험 낮음 AND 병렬화로 실제 시간 절약)
        세 조건 AND 다.
        YES → STEP 4
        NO (순서 의존이 있다) → STEP 4

STEP 4  작업 간 Dependency 가 있거나 실패 원인별 재라우팅이 필요한가?
        NO  → H2
        YES → H3

STEP 5  side_effect ∈ {irreversible} 이거나 target_environment = production
        이거나 시크릿·데이터 삭제를 건드리는가?
        YES → 레벨과 무관하게 human_gate.required = true
```

**STEP 2 가 판정의 갈림길이다.** `parallelism: none` 은 "단위가 1개"라는 뜻이 아니다.
동시에 못 돌린다는 뜻일 뿐이고, 순서 의존으로 묶인 여러 단위는 여전히 여러 단위다 —
그리고 그것이 바로 DAG(H3)가 필요한 형태다.

### 승격을 막는 반례

- "영역이 3개니까 워커 3명" — **아니다.** 3영역이 하나의 흐름으로 묶여 있어 구현자 한 명이
  통째로 들고 가야 하면 단위는 1개고 H1 이다. (예: FE 폼 + 업로드 API + 스토리지 연동)
- "위험하니까 H3" — **아니다.** risk 는 레벨을 바꾸지 않는다. reviewer 유무와 `max_loops`(high 면 3)만
  바꾼다. **Human Gate 는 risk 가 아니라 STEP 5(`side_effect`·`target_environment`·시크릿·삭제)가 정한다** —
  `risk: high` 인데 로컬 코드 변경만이면 Human Gate 는 false 다.
- "복잡하니까 orchestrator" — **아니다.** orchestrator 는 *재라우팅*이 필요할 때만 값을 한다.
  실패 시 항상 같은 곳(implementer)으로 돌아가면 H2 로 충분하다.
- "uncertainty 가 높으니까 H3" — **아니다.** dependency-mapper·baseline-tester 는 H1 에도 붙일 수 있다.

### 강등을 막는 반례 (Under-Orchestration)

승격만 막으면 반대 방향으로 틀린다. 다음도 똑같이 오답이다.

- "coupling 이 high 니까 단위가 1개다" — **아니다.** 순서 의존은 "단위가 하나"라는 뜻이 아니라
  **DAG 가 필요하다**는 뜻이다. STEP 2 는 "동시에 못 도는가"가 아니라
  "구현자 한 명이 한 번에 끝까지 들고 갈 수 있는가"를 묻는다.
- "parallelism 이 none 이니까 H1" — **아니다.** `parallelism` 은 STEP 3(H2 여부)에만 쓰인다.
  STEP 2 와 STEP 4 는 `parallelism` 을 보지 않는다.
- "순차로 하면 되니까 pipeline" — **아니다.** 순차 실행과 파이프라인은 다르다.
  실패 원인에 따라 되돌려 보낼 곳이 달라지면(숨은 호출부 → dependency-mapper,
  전제 오류 → baseline-tester, 구현 오류 → implementer) 파이프라인으로 표현할 수 없다.

**교차 점검**: `uncertainty: high` 이고 `risk: high` 이고 단위가 2개 이상인데 H1 로 판정했다면,
STEP 2 를 다시 본다. 이 조합에서 H1 은 거의 항상 오답이다 —
호출부를 다 모르는 상태로 위험한 변경을 한 명에게 통째로 맡기는 것이기 때문이다.

## 게이트 실행 규칙 (전 레벨 공통)

`HarnessSpec` 의 `verification.local` 과 `verification.final` 에 선언한 tier 는 **하나도 빠짐없이**
실행한다. 레벨이 낮다고 tier 를 줄이지 않는다.

`run-gates.sh` 는 해당 tier 에 명령이 하나도 없으면 통과로 처리한다 — 이것은 "검증할 게 없다"는
뜻이지 "검증이 필요 없다"는 뜻이 아니다. 따라서 spec 을 쓸 때 다음을 확인한다:

> **수용 기준마다 그것을 확인하는 게이트 명령이 `gates.tsv` 안에 있는가?**
> 없으면 `verification.manual` 에 적는다. 어느 쪽에도 없으면 그 수용 기준은 검증되지 않는다.

예: 수용 기준이 "기존 테스트가 계속 통과한다"인데 `local`·`final` 어디에도 `feature` tier 가
없으면 spec 이 잘못된 것이다. `detect-stack.sh` 는 단위 테스트를 `feature` 로 분류한다.

## 레벨별 실행 절차

### H0 — Single (에이전트 0)

1. 직접 구현한다. 서브에이전트를 스폰하지 않는다.
2. `run-gates.sh fast` → 실패하면 고치고 재실행.
3. `run-gates.sh feature` → 실패하면 고치고 재실행.
   **H0 라고 테스트를 건너뛰지 않는다.** 에이전트 수가 0일 뿐 검증은 다른 레벨과 같다.
4. `run-gates.sh final`.
5. **REQUIRED SUB-SKILL:** Use superpowers:verification-before-completion 후 종료.

같은 게이트가 3회 연속 실패하면 추측으로 고치지 말고
**REQUIRED SUB-SKILL:** Use superpowers:systematic-debugging.

### H1 — Pipeline (implementer + reviewer)

1. `uncertainty ≥ medium` 이면 먼저 `dependency-mapper` 와 `baseline-tester` 를
   **한 메시지에서 동시 dispatch** 한다. 보고서는 `_workspace/harness/research/` 에 남는다.
2. `implementer` 1인 dispatch. 프롬프트에 `superpowers:test-driven-development` 를 주입하고,
   조사 보고서는 **파일 경로로** 넘긴다 (본문 붙여넣기 금지).
3. `run-gates.sh fast` → `run-gates.sh feature`. 실패하면 implementer 에게 로그 경로를 주고 재시도.
   **게이트 실패를 reviewer 에게 보내지 않는다.**
4. 게이트가 전부 통과한 뒤에만 `reviewer` 1인 dispatch.
   컨텍스트는 task + 수용 기준 + `git diff` + 게이트 결과뿐이다.
5. `blocking`(BLOCKER/MAJOR) 발견이 있으면 implementer 로 돌려보낸다. **`max_loops` 회까지만.**
   초과하면 고치지 말고 남은 발견을 정리해 사람에게 넘긴다.
6. `run-gates.sh final` → verification-before-completion → 종료.

### H2 — Fan-out / Fan-in (워커 ≤3 + integrator)

1. **REQUIRED SUB-SKILL:** Use superpowers:using-git-worktrees 로 격리된 작업 공간을 확보한다.
2. `dependency-mapper` ‖ `baseline-tester` 동시 dispatch.
   dependency-mapper 가 "실은 독립이 아니다"라고 보고하면 **H1 로 강등하고 spec 을 고쳐 재승인받는다.**
3. **REQUIRED SUB-SKILL:** Use superpowers:writing-plans 로 작업 단위별 계획을 만든다.
4. **REQUIRED SUB-SKILL:** Use superpowers:subagent-driven-development 로 계획을 실행한다.
   워커 응답은 SDD 의 4상태 계약(`DONE` / `DONE_WITH_CONCERNS` / `NEEDS_CONTEXT` / `BLOCKED`)을 따른다.
   **구현 워커를 동시에 여러 개 dispatch 하지 않는다** — `max_workers: 3` 은 병합 단위 수이지
   동시 실행 수가 아니다. 같은 트리를 동시에 고치면 충돌 복구 비용이 병렬 이득을 넘는다.
5. 각 단위 완료 시 `run-gates.sh fast`.
6. 전 단위 완료 후 `integrator` dispatch — 인터페이스 불일치·의존 충돌·회귀·머지 충돌만 본다.
   **새 기능을 만들지 않는다.**
7. `run-gates.sh feature` → `reviewer` → `run-gates.sh final` (H1 의 4~6단계와 동일).
8. **REQUIRED SUB-SKILL:** Use superpowers:finishing-a-development-branch 로 통합 방식을 정하고
   1단계에서 만든 작업 공간을 정리한다. **1단계에서 worktree 를 만들었으면 이 단계는 필수다** —
   격리를 절차에 넣었으면 해제도 절차에 있어야 한다. 상세는 아래 "작업 공간 정리" 참고.

### H3 — Orchestrator + DAG

H2 절차에 다음을 더한다.

1. `orchestrator` 를 dispatch한다. orchestrator 는 **코드를 쓰지 않는다** —
   `tools` 에 Edit 이 없어 도구 수준에서 막혀 있다. 상태·다음 에이전트 선택·재라우팅·Human Gate 만 한다.
2. 계획을 선형 목록이 아니라 **DAG** 로 만든다. 노드마다 `depends_on` 을 명시한다.
3. 통합 검증 실패 시 원인별로 재라우팅한다 (`escalation` 블록):

   | 실패 양상 | 되돌려 보낼 곳 |
   |---|---|
   | 문서화되지 않은 호출부가 드러남 | `dependency-mapper` |
   | "원래 이렇게 동작했다"는 전제가 틀림 | `baseline-tester` |
   | 계획대로인데 코드가 틀림 | `implementer` |
   | 같은 게이트가 3회 연속 실패 | `superpowers:systematic-debugging` |

4. `human_gate.required` 면 `human_gate.before` 시점마다 **증거를 제시하고 멈춘다.**
   증거 = 게이트 로그 경로 + diff 통계 + 롤백 절차. 승인 없이 다음 노드로 진행하지 않는다.
5. 정리는 H2 8단계와 같다. **Human Gate 를 통과한 뒤에 한다** — 승인 대기 중에 작업 공간을
   치우면 사람이 증거를 확인할 트리가 사라진다.

## 작업 공간 정리 (H2·H3)

### 정리 시점을 정하는 것은 통합 결과다

`superpowers:finishing-a-development-branch` 가 제시하는 통합 선택이 그대로 정리 조건이다.

| 통합 선택 | worktree |
|---|---|
| 로컬 머지 + 머지 결과 게이트 통과 | **제거** |
| PR 생성 | **보존** — PR 피드백을 그 트리에서 고친다 |
| 유지 | **보존** |
| 폐기 (사람이 `discard` 를 직접 입력했을 때만) | 제거 |

### Linear 상태는 정리를 트리거하지 않는다

추적 중이더라도 이슈·프로젝트 상태로 정리를 자동 실행하지 않는다. 두 가지 이유가 있다.

- **`Canceled` 는 폐기가 아니다.** `references/linear-tracking.md` 의 상태 매핑에서 `Canceled`
  는 "레벨 강등(H2→H1) 또는 사람이 중단"이다. H2 2단계에서 dependency-mapper 가 "실은 독립이
  아니다"라고 보고해 H1 로 강등하는 것은 **정상 경로**이며, 그때 작업은 계속된다.
  `Canceled` 를 정리 트리거로 삼으면 진행 중인 작업의 트리를 지운다.
- **`Done` 은 통합보다 먼저 찍힌다.** `Done` 의 전환 조건은 "최종 게이트 통과 +
  `verification-before-completion`" — Phase 5 의 1~2단계다. 브랜치 마무리는 4단계다.
  `Done` 시점에 정리하면 PR 을 만들기 전에 작업 공간을 없앤다.

여기에 더해 추적은 **관측 수단이지 실행 경로가 아니다.** `tracking.provider: none` 으로도
H2/H3 은 정상 동작해야 하므로, 정리 규칙이 Linear 에 의존하면 추적을 끈 하네스에는
정리 규칙이 아예 없는 셈이 된다.

### Linear 는 정리를 **억제**하는 가드로만 쓴다

`tracking.provider: linear` 일 때만, 정리 직전에 상태를 한 번 읽어 다음을 판단한다.

| 읽은 상태 | 행동 |
|---|---|
| `In Progress` | 정리하지 않고 **경고**한다 — 아직 끝나지 않은 단위가 있다는 신호다 |
| `Canceled` | 자동 삭제 금지. 폐기 메뉴를 **제시만** 한다 (커밋이 사라지므로 `discard` 입력 안전장치를 유지) |
| `Done` · `In Review` | 통합 선택 결과대로 진행한다 |
| 읽기 실패 | 한 줄로 알리고 통합 선택 결과대로 진행한다 — 추적 실패는 하네스를 멈추지 않는다 |

### `_workspace/` 는 정리 대상이 아니다

게이트 로그·조사 보고서·리뷰는 worktree 를 제거해도 남아야 한다. `scripts/harness-paths.sh`
가 `_workspace` 를 **메인 워크트리 루트**로 고정하므로, worktree 안에서 `run-gates.sh` 를
돌려도 산출물은 메인 레포에 쌓인다. `git worktree remove` 가 "modified or untracked files"
로 거부하면 `--force` 를 쓰지 말고 무엇이 걸렸는지 사람에게 보여 준다.
