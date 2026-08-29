# eval 03 — JWT → OAuth 인증 전환 + 세션/DB 마이그레이션 (운영 서비스, 실사용자 있음)

## Phase 0 — task 6필드

- **goal**: 운영 중인 Next.js/PostgreSQL 서비스의 인증 방식을 JWT 기반에서 OAuth 기반으로 전환하고, 기존 세션 저장소와 `users` 관련 DB 스키마를 마이그레이션한다. 전환 과정에서 기존 로그인 사용자의 세션을 끊지 않는다.
- **scope**: [
  "인증 발급/검증/리프레시 로직 (`lib/auth/` 다수 파일)",
  "세션 저장소 스키마",
  "DB 마이그레이션 (세션 스키마 ↔ `users` 테이블 외래키 연계)",
  "프로덕션 배포/롤백"
  ]
- **constraints**:
  - 기존 로그인 사용자의 세션을 끊으면 안 된다 (전환 기간 중 JWT/OAuth 병행 또는 무중단 마이그레이션 필요)
  - 리프레시 토큰 호출부를 전부 파악하지 못한 상태에서 해당 경로를 건드려야 함
  - `target_environment: production` — 실사용자 영향
- **acceptance_criteria**:
  - OAuth 인증 흐름(로그인/콜백/토큰 갱신)이 정상 동작한다
  - 기존 JWT 세션 보유 사용자가 전환 과정에서 강제 로그아웃되지 않는다
  - 세션 저장소 스키마 및 `users` 테이블 마이그레이션이 데이터 손실·정합성 붕괴 없이 완료된다
  - 인증 관련 게이트(자동 테스트)가 통과한다
  - 롤백 절차가 문서화되고 실행 가능함이 확인된다
- **known_risks**:
  - 리프레시 토큰 호출부 전체 미파악 → 누락된 호출부에서 회귀 발생 가능
  - 세션 스키마-`users` FK 결합 → 마이그레이션 순서를 잘못 잡으면 무결성 붕괴
  - 인증 테스트가 일부만 존재 → 회귀를 자동으로 못 잡을 가능성
  - 프로덕션 DB 마이그레이션은 원칙적으로 되돌리기 어려움 (irreversible)
- **target_environment**: production

## Phase 2 — 6축 프로파일

| 축 | 값 | 근거 |
|---|---|---|
| `scope` | `many` (4+) | 입력에 명시된 책임 영역이 4개: `lib/auth/` 인증 로직(발급·검증·리프레시), 세션 저장소 스키마, `users` FK 연계 DB 마이그레이션, 프로덕션 배포. 단순 FE+API+스토리지 묶음(1 흐름)과 달리 서로 다른 검증 방식(코드 리뷰 vs 스키마 마이그레이션 vs 배포 헬스체크)이 필요한 이질적 영역이다. |
| `coupling` | `high` | "세션 저장소 스키마와 users 테이블이 외래키로 엮여 있다" — 스키마 변경 순서를 어기면 마이그레이션이 깨진다. 또한 "기존 로그인 사용자의 세션을 끊으면 안 된다"는 제약은 인증 로직 교체와 DB 마이그레이션이 동시에 일관된 상태를 유지해야 함을 뜻하며, 이는 순서/상태 의존이다. |
| `parallelism` | `none` | `coupling: high` 이므로 profiling.md 규칙에 따라 자동으로 `none`. (단, 이는 "단위가 1개"라는 뜻이 아니라 "동시에 못 돈다"는 뜻뿐 — routing.md STEP 2 참고) |
| `uncertainty` | `high` | 두 조건 모두 해당: (1) "리프레시 토큰 경로를 어디서 호출하는지 전부 파악되어 있지 않다" → 호출부를 전부 열거 불가, (2) "인증 관련 테스트는 일부만 있다" → 현재 동작을 고정하는 테스트 부재. profiling.md 는 이 중 하나만 있어도 최소 `medium`이라 규정하며, 둘 다 해당하고 대상이 인증·세션 전체라는 넓은 범위임을 고려해 `high`로 판정. |
| `risk` | `high` | profiling.md 의 `high` 기준(인증·인가, 스키마 변경, 배포 파이프라인) 세 가지에 모두 해당 — 인증 시스템 자체를 교체하고, DB 스키마를 바꾸고, 프로덕션에 배포한다. |
| `side_effect` | `irreversible` | "프로덕션 DB 마이그레이션"은 profiling.md 의 irreversible 예시에 정확히 해당. `target_environment: production` 이며 기존 사용자 세션 데이터에 영향을 준다. |

## Phase 2 — 판정 트리 통과 기록

STEP 1: 단일 세션·단일 컨텍스트로 안전하게 완료 가능한가? (변경 영역 1개 AND risk≤low AND uncertainty=low)
→ **NO**. scope=many(4+), risk=high, uncertainty=high — 세 조건 모두 불충족.

STEP 2: 작업 단위가 1개인가? ("구현자 한 명이 한 번에 끝까지 들고 갈 수 있는가?")
→ **NO (단위 2개 이상)**. 이유:
  - 호출부가 다 파악되지 않은 리프레시 토큰 경로를 건드리려면 먼저 `dependency-mapper` 산출물이 있어야 안전하게 손댈 수 있다 — 조사와 구현이 분리된 별도 단위다.
  - "세션을 끊지 않는다"는 제약을 지키려면 현재 세션 동작을 고정하는 baseline(`baseline-tester`)이 구현 전에 별도로 필요하다.
  - 세션 스키마/`users` 마이그레이션은 인증 로직 구현과 **순서 의존**(스키마가 먼저 안전하게 준비돼야 로직 전환이 가능)이면서, 검증 방법이 다르다(마이그레이션은 데이터 무결성 검증, 로직은 기능 테스트) — 한 사람이 중간 산출물 검증 없이 통째로 들고 갈 수 없다.
  - 배포/롤백 준비는 위 모든 단계가 끝난 뒤에만 의미가 있는 별도 단위다.
  → 최소 4개 이상의 order-dependent 단위(조사/베이스라인, 구현, 마이그레이션, 배포)가 존재.
  - **강등을 막는 반례 교차 점검**: "coupling이 high니까 단위가 1개다"라고 결론 내리지 않았음에 유의 — 오히려 high coupling은 순서 의존이 있다는 뜻이고, 이는 DAG(H3) 필요성의 근거로만 사용했다(routing.md "강등을 막는 반례" 1번).

STEP 3: 그 단위들이 서로 독립인가? (동시 실행 가능 AND 동일 파일 충돌 위험 낮음 AND 병렬화로 시간 절약, 세 조건 AND)
→ **NO (순서 의존이 있다)** — 조사(dependency-mapper/baseline-tester)는 서로 독립이라 동시 dispatch 가능하지만, 이후 구현→마이그레이션→배포는 순서 의존. routing.md 에 따라 YES/NO 어느 쪽이든 STEP 4로 진행.

STEP 4: 작업 간 Dependency 가 있거나 실패 원인별 재라우팅이 필요한가?
→ **YES**.
  - Dependency: 구현은 조사 결과에, 마이그레이션은 구현 완료에, 배포는 마이그레이션 검증 완료에 의존 — 선형이 아니라 조건부 재시도가 섞인 DAG.
  - 재라우팅 필요성: 통합 검증 실패 시 원인이 다르면 되돌아갈 곳이 다르다 — "숨은 호출부가 뒤늦게 드러남" → `dependency-mapper`, "기존 세션이 원래 이렇게 동작했다는 전제가 틀림" → `baseline-tester`, "계획대로인데 구현이 틀림" → `implementer`. 이 세 갈래가 모두 현실적으로 가능한 시나리오다(routing.md 의 H3 escalation 표와 정확히 대응).
  → **H3**.
  - **승격을 막는 반례 교차 점검**: "위험하니까 H3"나 "복잡하니까 orchestrator"로 판정하지 않았음 — risk는 reviewer/max_loops/human_gate에만 반영했고, orchestrator 필요성은 위 구체적 재라우팅 3갈래로만 근거를 댔다(routing.md "승격을 막는 반례" 2, 3번).

STEP 5: side_effect ∈ {irreversible} 이거나 target_environment=production 이거나 시크릿·데이터 삭제를 건드리는가?
→ **YES** (irreversible DB 마이그레이션 + target_environment=production) → `human_gate.required = true`, 레벨과 무관하게 적용.

**교차 점검 규칙 적용**: `uncertainty: high` + `risk: high` + 단위 2개 이상 조합 — routing.md 는 "이 조합에서 H1은 거의 항상 오답"이라 명시한다. STEP 2를 재검토했고, 실제로 H1(단일 구현자)로는 호출부를 다 모르는 상태에서 위험한 인증/스키마 변경을 통째로 맡기는 꼴이 되어 오답임을 확인했다. H3 판정이 이 교차 점검과 일치한다.

## 판정

level: **H3**
pattern: **dag**
rationale: H2(고정 fan-out/fan-in)로는 "숨은 호출부 발견 → dependency-mapper", "세션 전제 오류 → baseline-tester", "구현 오류 → implementer"라는 서로 다른 재라우팅 경로를 표현할 수 없고, H2는 실패 시 항상 같은 곳(implementer)으로만 되돌리므로, 실패 원인별로 다른 곳으로 되돌려야 하는 이 작업에는 orchestrator 기반 DAG(H3)가 필요하다.
agents: dependency-mapper, baseline-tester, implementer, integrator, reviewer, orchestrator, deployment-agent
human_gate: true — side_effect=irreversible(프로덕션 DB 마이그레이션) 이고 target_environment=production 이므로, 마이그레이션 실행 직전과 프로덕션 배포 직전에 사람 승인이 필요하다 (routing.md STEP 5, deployment-agent 는 카탈로그 규정상 Human Gate 없이는 실행하지 않음).

## Phase 3 — HarnessSpec

```yaml
harness_version: 1

task:
  goal: >
    운영 중인 Next.js 15 + PostgreSQL 서비스의 인증 방식을 JWT 기반에서
    OAuth 기반으로 전환하고, 기존 세션 저장소와 users 관련 DB 스키마를
    마이그레이션한다. 전환 중 기존 로그인 사용자의 세션을 끊지 않는다.
  scope:
    - "인증 발급/검증/리프레시 로직 (lib/auth/)"
    - "세션 저장소 스키마"
    - "DB 마이그레이션 (세션 스키마 ↔ users 테이블 외래키 연계)"
    - "프로덕션 배포/롤백"
  constraints:
    - "기존 로그인 사용자의 세션을 끊지 않는다"
    - "리프레시 토큰 호출부 전체가 파악되지 않은 상태로 해당 경로를 수정해야 한다"
    - "프로덕션 서비스이며 실사용자가 있다"
  acceptance_criteria:
    - "OAuth 인증 흐름(로그인/콜백/토큰 갱신)이 정상 동작한다"
    - "기존 JWT 세션 보유 사용자가 전환 과정에서 강제 로그아웃되지 않는다"
    - "세션 저장소 스키마 및 users 테이블 마이그레이션이 데이터 손실·정합성 붕괴 없이 완료된다"
    - "인증 관련 게이트(자동 테스트)가 통과한다"
    - "롤백 절차가 문서화되고 실행 가능함이 확인된다"
  known_risks:
    - "리프레시 토큰 호출부 전체 미파악으로 인한 회귀 가능성"
    - "세션 스키마-users FK 결합으로 인한 마이그레이션 무결성 위험"
    - "인증 테스트가 일부만 있어 회귀를 자동으로 못 잡을 가능성"
    - "프로덕션 DB 마이그레이션은 되돌리기 어렵다 (irreversible)"
  target_environment: production

profile:
  scope: many
  coupling: high
  parallelism: none
  uncertainty: high
  risk: high
  side_effect: irreversible

harness:
  level: H3
  pattern: dag
  rationale: >
    H2는 실패 시 항상 같은 곳(implementer)으로만 되돌리는 고정 fan-out/fan-in인데,
    이 작업은 실패 원인에 따라 되돌릴 곳이 다르다 — 숨은 호출부 발견 시
    dependency-mapper, 세션 동작 전제 오류 시 baseline-tester, 구현 오류 시
    implementer로 재라우팅해야 하므로 orchestrator 기반 DAG(H3)가 필요하다.

agents:
  - id: dependency-mapper
    model: sonnet
    responsibility: "lib/auth/ 전역의 JWT 발급·검증·리프레시 호출부와 세션/DB 의존 관계를 전수 조사한다"
  - id: baseline-tester
    model: sonnet
    responsibility: "현재 JWT 기반 로그인/세션 유지 동작을 고정하는 테스트를 작성해 전환 후 회귀 판단 기준을 만든다"
  - id: implementer
    model: sonnet
    responsibility: "OAuth 인증 흐름 구현, 전환 기간 중 기존 세션 호환 로직 구현, 세션/DB 마이그레이션 스크립트 작성 (DAG 노드별로 순차 dispatch)"
  - id: integrator
    model: opus
    responsibility: "여러 구현 단위(인증 로직, 마이그레이션 스크립트) 간 인터페이스 불일치·머지 충돌·회귀를 통합 검증한다"
  - id: reviewer
    model: opus
    responsibility: "인증/세션/스키마 변경 diff에 대한 의미적 코드 리뷰와 보안 심사(risk:high)를 수행한다"
  - id: orchestrator
    model: opus
    responsibility: "DAG 상태 관리, 각 노드 완료/실패 판정, 실패 원인별 재라우팅, Human Gate 시점 관리 (코드 미작성)"
  - id: deployment-agent
    model: sonnet
    responsibility: "DB/세션 마이그레이션 및 프로덕션 배포 실행, 헬스체크, 롤백 준비 (Human Gate 승인 후에만 실행)"

skills:
  implementer: [superpowers:test-driven-development, superpowers:receiving-code-review]
  reviewer: [security-review]

context:
  dependency-mapper:
    required: [task, relevant_module_tree, imports, call_sites, api_contracts]
    optional: [db_schema, config_files]
    forbidden: [full_repository_dump, test_fixtures, unrelated_docs]
  baseline-tester:
    required: [task, existing_tests, current_behavior, api_responses]
    optional: [test_fixtures, ci_history]
    forbidden: [full_repository_dump, implementation_plan]
  implementer:
    required: [task, acceptance_criteria, assigned_unit_only, relevant_source, relevant_tests]
    optional: [dependency_report, baseline_report, architecture_doc, gate_log_path]
    forbidden: [full_repository_dump, unrelated_docs, session_history, other_workers_context]
  integrator:
    required: [task, worker_reports, git_diff, gate_results]
    optional: [dependency_report]
    forbidden: [full_repository_dump, session_history, worker_prompts]
  reviewer:
    required: [task, acceptance_criteria, git_diff, gate_results]
    optional: [architecture_doc, baseline_report]
    forbidden: [full_repository_dump, unrelated_docs, session_history, implementer_reasoning]
  orchestrator:
    required: [task, dag_state, agent_reports, gate_results, harness_spec]
    optional: [human_gate_history]
    forbidden: [full_repository_dump, source_file_contents, session_history]
  deployment-agent:
    required: [release_artifact, migration_script, rollback_plan, health_check_endpoints]
    optional: [deploy_history]
    forbidden: [full_repository_dump, secrets, source_file_contents]

verification:
  gates_tsv: _workspace/harness/gates.tsv
  local: [fast]
  final: [feature, final]
  manual:
    - "스테이징에서 실사용자 로그인 세션 시나리오 재현 — 전환 후 강제 로그아웃 여부 수동 확인"
    - "OAuth 프로바이더(콘솔) 설정값 확인"
    - "마이그레이션 스크립트 dry-run 결과 수동 검토"

review_policy:
  blocking: [BLOCKER, MAJOR]
  max_loops: 3          # risk: high
  escalation_after: 3

parallelism:
  enabled: true          # dependency-mapper ‖ baseline-tester 조사 단계만 동시 dispatch
  max_workers: 3          # 구현 단위(인증 로직 / 세션·DB 마이그레이션 / 정리)는 순차 dispatch, 병합 단위 상한만 3

human_gate:
  required: true
  reason: "프로덕션 DB/세션 마이그레이션 실행과 프로덕션 배포는 되돌리기 어려운 부작용(irreversible)을 가진다"
  before: "세션/DB 마이그레이션 스크립트 실행 직전, 그리고 deployment-agent 의 프로덕션 배포 실행 직전"

escalation:
  if_hidden_dependency: dependency-mapper
  if_baseline_unknown: baseline-tester
  if_implementation_error: implementer
  if_gate_fails_repeatedly: superpowers:systematic-debugging
```

## 자체 점검

- 한 단계 아래 레벨을 고르지 않은 이유를 썼는가? — 예. H2가 왜 안 되는지(고정 경로 vs 원인별 재라우팅 3갈래 필요)를 `harness.rationale`과 STEP 4 기록에 명시했다.
- 카탈로그 7종 밖의 에이전트를 만들지 않았는가? — 예. `dependency-mapper, baseline-tester, implementer, integrator, reviewer, orchestrator, deployment-agent` 전부 카탈로그 7종 내에서만 선택했고, security 심사는 별도 에이전트를 만들지 않고 `reviewer` + `security-review` 스킬 주입으로 처리했다(catalog.md 지침 그대로).
- routing.md 의 교차 점검 규칙(uncertainty high + risk high + 단위 2개 이상)을 적용했는가? — 예. STEP 2 이후 및 STEP 5 다음 단락에서 별도로 명시적으로 재검토했고, 이 조합에서 H1이 오답이라는 규칙과 일치함을 확인했다.
