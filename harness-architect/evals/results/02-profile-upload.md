# eval 02 — 프로필 페이지 이미지 업로드 기능 추가 (FE 폼 + API 핸들러 + Storage 연동, 단일 흐름)

## Phase 0 — task 6필드

- `goal`: 프로필 페이지에 프로필 이미지 업로드 기능을 추가한다 (FE 폼 → `app/api/profile/avatar/route.ts` → Supabase Storage 버킷 저장까지 end-to-end 동작).
- `scope`: [frontend(업로드 폼), api(`app/api/profile/avatar/route.ts`), storage(Supabase Storage 버킷 연동)]
- `constraints`:
  - 기존 프로필 저장 기능의 동작과 테스트를 깨지 않는다
  - 로컬 개발 환경에서만 작업한다 (프로덕션 미배포)
- `acceptance_criteria`:
  1. 사용자가 프로필 페이지에서 이미지를 선택해 업로드하면 `app/api/profile/avatar/route.ts` 핸들러가 파일을 받아 Supabase Storage 버킷에 저장한다
  2. 업로드 성공 후 프로필 페이지에 새 이미지가 반영되어 표시된다
  3. 기존 프로필 저장 기능과 그 테스트(`npm run test`)가 계속 통과한다
  4. `npm run lint` / `npm run typecheck` / `npm run build` 가 모두 통과한다
- `known_risks`: [] (입력에 명시된 알려진 위험 없음 — 추측으로 채우지 않음)
- `target_environment`: local

## Phase 2 — 6축 프로파일

| 축 | 값 | 근거 |
|---|---|---|
| `scope` | few | "업로드는 프론트엔드 폼, `app/api/profile/avatar/route.ts` API 핸들러, Supabase Storage 버킷 세 곳을 거친다" — 책임 영역 3개(FE/API/Storage) |
| `coupling` | high | "세 곳은 하나의 업로드 흐름으로 이어져 있어 한쪽만 먼저 완성해도 동작을 확인할 수 없다" — 순서·검증 의존이 강함 |
| `parallelism` | none | profiling.md 규칙: "coupling: high 면 parallelism 은 자동으로 none 이다. 이 둘이 동시에 높을 수 없다" — 별도 근거 불요, coupling=high 로부터 도출 |
| `uncertainty` | low | "기존 프로필 저장 기능과 그 테스트가 이미 있다" — 인접 기존 동작이 테스트로 고정돼 있고, 신규 API 경로(`app/api/profile/avatar/route.ts`)가 이미 지정돼 있어 호출부를 열거 못 하는 상황이 아님. 레거시·문서 불일치 신호도 없음 |
| `risk` | medium | 신규 공개 API 엔드포인트 신설 + 업로드 파일을 받는 서버측 처리(profiling.md "medium: 서버 측 검증 로직, 공개 API 시그니처") — 인증·결제·스키마 변경·배포 파이프라인(high 기준)에는 해당하지 않음 |
| `side_effect` | none | "로컬 개발 환경에서만 작업한다" — target_environment=local, 프로덕션·외부 시스템 상태 변경 없음. 로컬 코드 변경만(profiling.md "none: 로컬 코드 변경만") |

## Phase 2 — 판정 트리 통과 기록

- **STEP 1** (단일 세션 가능?): NO. `scope=few`(3개 영역)이라 "변경 영역 1개" 조건을 만족하지 못함 → H0 제외.
- **STEP 2** (작업 단위가 1개인가 — "구현자 한 명이 한 번에 끝까지 들고 갈 수 있는가"): **YES.**
  근거: 3개 영역이 "하나의 업로드 흐름"으로 결합돼 있고 한쪽만 완성해도 동작을 확인할 수 없음(coupling=high). 이는 routing.md 의 "승격을 막는 반례" 항목과 정확히 일치한다:
  > "영역이 3개니까 워커 3명" — 아니다. 3영역이 하나의 흐름으로 묶여 있어 구현자 한 명이 통째로 들고 가야 하면 단위는 1개고 H1 이다. **(예: FE 폼 + 업로드 API + 스토리지 연동)**
  따라서 단위 1개 → **H1**로 확정. STEP 3/4는 단위가 2개 이상일 때만 진행하므로 여기서 판정 종료.
- **강등 반례 점검**: "coupling 이 high 니까 단위가 1개다"는 오답이라는 강등-반례도 확인했다 — 이 사례는 강등 반례가 말하는 "순서 의존 → 사실은 여러 단위(DAG 필요)"에 해당하지 않는다. 왜냐하면 세 영역은 서로 다른 단계로 순차 진행되는 게 아니라 **하나의 업로드 트랜잭션**(폼 제출 → 핸들러 → 스토리지 저장까지 한 번에 검증되어야 동작 확인 가능)이기 때문이다. 즉 "완성 후 개별 검증 불가"는 촉진 반례(FE+업로드API+스토리지)의 정의 그대로이고, 강등 반례가 말하는 "실패 원인별로 되돌려 보낼 곳이 다른 순차 파이프라인"이 아니다. 따라서 STEP 2 = YES(단위 1개) 판정을 유지한다.
- **교차 점검** (`uncertainty: high` AND `risk: high` AND 단위≥2 → H1 재검토): 미해당. `uncertainty=low`이므로 이 교차 점검 규칙은 발동하지 않는다.
- **STEP 5** (Human Gate): `side_effect=none`, `target_environment=local`, 시크릿·데이터 삭제 없음 → **human_gate.required = false**.

## 판정

- **level**: H1
- **pattern**: pipeline
- **rationale**: STEP 1 불충족(`scope=few`, 3개 책임 영역 — 단일 세션 하네스 H0 의 "변경 영역 1개" 조건 미달) → H0 로는 안전하게 완료 불가. STEP 2: FE 폼·API 핸들러·Storage 연동이 하나의 업로드 흐름으로 결합돼(`coupling=high`) 한쪽만 완성해도 검증 불가능하므로 구현자 한 명이 통째로 들고 가야 하는 단위 1개 작업 → H1. `uncertainty=low`라 dependency-mapper/baseline-tester 선행 조사도 불필요.
  **한 단계 아래(H0)가 안 되는 이유**: 변경 영역이 1개가 아니라 3개(FE/API/Storage)이며 STEP 1 은 "변경 영역 1개 AND risk≤low AND uncertainty=low"를 모두 요구하는데 `scope=few`가 이를 깨뜨린다.
- **agents**: implementer(sonnet), reviewer(opus) — 카탈로그 7종 내. `uncertainty=low`라 dependency-mapper/baseline-tester는 배치하지 않음(H1에서도 선택적으로만 쓰이며 여기선 불필요).
- **human_gate**: false (side_effect=none, target_environment=local)

## Phase 3 — HarnessSpec

```yaml
harness_version: 1

task:
  goal: 프로필 페이지에 프로필 이미지 업로드 기능을 추가한다 (FE 폼 → API 핸들러 → Supabase Storage 저장까지 end-to-end 동작)
  scope: [frontend, api, storage]
  constraints:
    - 기존 프로필 저장 기능의 동작과 테스트를 깨지 않는다
    - 로컬 개발 환경에서만 작업한다 (프로덕션 미배포)
  acceptance_criteria:
    - 사용자가 프로필 페이지에서 이미지를 선택해 업로드하면 app/api/profile/avatar/route.ts 핸들러가 파일을 받아 Supabase Storage 버킷에 저장한다
    - 업로드 성공 후 프로필 페이지에 새 이미지가 반영되어 표시된다
    - 기존 프로필 저장 기능과 그 테스트(npm run test)가 계속 통과한다
    - npm run lint / npm run typecheck / npm run build 가 모두 통과한다
  known_risks: []
  target_environment: local

profile:
  scope: few
  coupling: high
  parallelism: none
  uncertainty: low
  risk: medium
  side_effect: none

harness:
  level: H1
  pattern: pipeline
  rationale: >
    STEP 1 불충족(scope=few, 3개 책임 영역이라 "변경 영역 1개" 조건 미달) → H0 불가.
    STEP 2: FE 폼·API 핸들러·Storage 연동이 하나의 업로드 흐름으로 결합돼(coupling=high)
    한쪽만 완성해도 동작 검증이 불가능하므로 구현자 한 명이 통째로 들고 가야 하는
    단위 1개 작업 → H1 (routing.md 반례: "FE 폼 + 업로드 API + 스토리지 연동"과 정확히 일치).
    uncertainty=low 라 dependency-mapper/baseline-tester 선행 조사도 불필요.

agents:
  - id: implementer
    model: sonnet
    responsibility: FE 업로드 폼, API 핸들러, Storage 연동을 하나의 흐름으로 구현한다
  - id: reviewer
    model: opus
    responsibility: 게이트 전부 통과 후 diff 를 의미적으로 검토한다 (BLOCKER/MAJOR 만 되돌림)

controller_skills:
  - superpowers:requesting-code-review
  - superpowers:verification-before-completion
  - superpowers:finishing-a-development-branch

agent_skills:
  implementer:
    - superpowers:test-driven-development
    - superpowers:receiving-code-review
  reviewer: []

context:
  implementer:
    required: [task, acceptance_criteria, assigned_unit_only, relevant_source, relevant_tests]
    optional: [architecture_doc, gate_log_path]
    forbidden: [full_repository_dump, unrelated_docs, session_history, other_workers_context]
  reviewer:
    required: [task, acceptance_criteria, git_diff, gate_results]
    optional: [architecture_doc]
    forbidden: [full_repository_dump, unrelated_docs, session_history, implementer_reasoning]

verification:
  gates_tsv: _workspace/harness/gates.tsv
  local: [fast, feature]
  final: [final]
  manual:
    - "업로드 후 프로필 페이지에 새 이미지가 실제로 반영되어 표시되는지 수동 확인 (gates.tsv 에 e2e/UI 게이트 없음, acceptance_criteria #2 대응)"

review_policy:
  blocking: [BLOCKER, MAJOR]
  max_loops: 2
  escalation_after: 2

parallelism:
  enabled: false
  max_workers: 1

human_gate:
  required: false
  reason: null
  before: null

escalation:
  if_hidden_dependency: dependency-mapper
  if_baseline_unknown: baseline-tester
  if_implementation_error: implementer
  if_gate_fails_repeatedly: superpowers:systematic-debugging
```

## 자체 점검

- **한 단계 아래 레벨을 고르지 않은 이유를 썼는가?** 예. STEP 1 이 요구하는 "변경 영역 1개" 조건을 `scope=few`(3개 영역)가 깨뜨려 H0 불가함을 명시했다.
- **카탈로그 7종 밖의 에이전트를 만들지 않았는가?** 예. `implementer`, `reviewer` 만 사용했고 둘 다 `references/catalog.md` 7종 안에 있다. dependency-mapper/baseline-tester 는 uncertainty=low 이므로 배치하지 않았을 뿐 새 역할을 만든 것이 아니다.
- **수용 기준마다 그것을 확인하는 게이트가 verification 에 배정됐는가?**
  - acceptance #1(업로드→핸들러→Storage 저장 동작): implementer 가 TDD 로 작성하는 테스트 + `feature` tier(`npm run test`)로 커버, 게이트 통과 후 reviewer 가 diff 로 의미 검토.
  - acceptance #2(프로필 페이지에 이미지 반영 표시): gates.tsv 에 e2e/UI 게이트가 없으므로 자동 게이트로 확인 불가 → `verification.manual` 에 명시 배정.
  - acceptance #3(기존 테스트 회귀 없음): `feature` tier(`npm run test`)가 local 에 배정되어 있어 커버됨.
  - acceptance #4(lint/typecheck/build 통과): `fast` tier(lint, typecheck)는 local 에, `final` tier(build)는 final 에 배정되어 전부 커버됨.
  - 빠짐없이 배정됨 — 어느 수용 기준도 게이트도 manual 도 없이 방치된 것이 없다.
- **controller_skills 와 agent_skills 를 올바르게 구분했는가?** 예. `requesting-code-review`/`verification-before-completion`/`finishing-a-development-branch` 는 Agent 도구가 필요한 controller(=harness-architect 스킬 자신, H1이므로 orchestrator 아님) 소유로 분류했다. `test-driven-development`/`receiving-code-review` 는 워커(`implementer`) 프롬프트에 주입하는 agent_skill 로 분류했다 — 둘 다 "자기 작업만 하는 스킬"이라는 조건을 만족한다. `risk=medium`(high 아님)이라 `security-review` 는 reviewer 에 주입하지 않았다.
