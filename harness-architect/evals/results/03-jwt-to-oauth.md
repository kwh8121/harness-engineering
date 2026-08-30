# eval 03 — JWT → OAuth 전환 + 세션/DB 마이그레이션 (프로덕션, 실사용자 존재)

## Phase 0 — task 6필드

- **goal**: 운영 중인 Next.js 15 + TypeScript + PostgreSQL 서비스의 인증 방식을 JWT 기반에서 OAuth 기반으로 전환하고, 기존 세션 저장소·`users` 테이블 스키마를 마이그레이션한다. 전환 과정에서 기존 로그인 사용자의 세션이 끊기면 안 된다.
- **scope**: [auth-core(`lib/auth/` JWT 발급·검증·리프레시 제거 및 OAuth 플로우 신설), session-storage(세션 저장소 스키마 마이그레이션), db-schema(`users` 테이블 FK 연관 마이그레이션), production-rollout(배포·헬스체크·롤백)]
- **constraints**:
  - 기존 로그인 사용자의 세션을 끊지 않는다 (무중단 전환)
  - 리프레시 토큰 호출부를 전수 파악한 뒤에만 제거/대체한다 (호출부 전체가 파악되어 있지 않음)
  - 세션 저장소 스키마와 `users` 테이블의 FK 정합성을 마이그레이션 전 구간에서 유지한다
- **acceptance_criteria**:
  1. 신규 OAuth 기반 로그인/로그아웃/토큰 갱신 플로우가 정상 동작한다.
  2. 마이그레이션 도중 및 이후에도 기존 JWT 로그인 사용자의 세션이 끊기지 않는다.
  3. 세션 저장소·`users` 테이블 마이그레이션이 데이터 손실·정합성 오류 없이 완료된다.
  4. 기존 인증 관련 테스트가 계속 통과한다 (baseline 고정 대상).
  5. 리프레시 토큰 관련 호출부가 전수 파악되어 숨은 호출부 없이 전부 대체되었음이 확인된다.
  6. 프로덕션 배포 후 인증 헬스체크가 통과하고, 문제 발생 시 롤백 절차가 실행 가능한 상태로 준비되어 있다.
- **known_risks**:
  - 리프레시 토큰 호출부를 전부 열거하지 못한 상태 (숨은 호출부 존재 가능성)
  - 세션 저장소와 `users` 테이블이 FK로 엮여 있어 스키마 변경 시 정합성 리스크
  - 인증 관련 테스트가 일부만 존재해 현재 동작을 고정하는 안전망이 약함
  - 실사용자가 있는 프로덕션 서비스이며 DB 마이그레이션은 되돌리기 어려움
- **target_environment**: production

## Phase 2 — 6축 프로파일

| 축 | 값 | 근거 |
|---|---|---|
| `scope` | `many` (4+) | JWT 제거/OAuth 신규 구현(auth-core), 세션 저장소 스키마 마이그레이션, `users` 테이블 FK 마이그레이션, 프로덕션 배포·롤백까지 서로 다른 책임 영역 4개가 관련됨 |
| `coupling` | `high` | 세션 저장소 스키마와 `users` 테이블이 FK로 엮여 있어 한쪽만 따로 바꿀 수 없고(같은 마이그레이션에서 함께 다뤄야 함), "기존 세션을 끊지 않는다"는 제약 때문에 JWT 제거는 세션 마이그레이션 호환 계층이 먼저 준비되지 않으면 시작할 수 없음(순서 의존) |
| `parallelism` | `none` | profiling.md 규칙: `coupling: high` 이면 `parallelism` 은 자동으로 `none` (동시에 높을 수 없음) |
| `uncertainty` | `high` | "리프레시 토큰 경로를 어디서 호출하는지 전부 파악되어 있지 않다"(호출부 전부 열거 불가) + "인증 관련 테스트는 일부만 있다"(현재 동작 고정 테스트 부재) — profiling.md `high` 조건 두 가지에 동시 해당 |
| `risk` | `high` | 인증·인가 로직 교체 + DB 스키마 변경(세션 저장소·`users` 테이블) — profiling.md `high` 조건("인증·인가, ... 스키마 변경")에 정확히 해당 |
| `side_effect` | `irreversible` | 프로덕션 DB 마이그레이션(세션 저장소·`users` 테이블) + 실사용자 세션 상태 변경 — profiling.md `irreversible` 조건("프로덕션 DB 마이그레이션")에 해당 |

## Phase 2 — 판정 트리 통과 기록

- **STEP 1** (단일 세션·단일 컨텍스트로 안전 완료?): `scope: many`, `risk: high`, `uncertainty: high` 이므로 세 조건(영역 1개 AND risk≤low AND uncertainty=low) 모두 불충족 → **NO**, STEP 2로.

- **STEP 2** (작업 단위가 1개인가 — "구현자 한 명이 한 번에 끝까지 들고 갈 수 있는가"): **아니다.** 이 작업은 최소 아래 단위로 나뉜다.
  1. 호출부/의존성 전수 조사 (uncertainty: high → dependency-mapper 영역)
  2. 기존 인증·세션 동작 고정 (uncertainty: high → baseline-tester 영역)
  3. OAuth 코어 구현 + 세션 호환(무중단 전환) 계층 구현
  4. 세션 저장소·`users` 테이블 DB 마이그레이션 (risk: high, side_effect: irreversible)

  이는 승격 반례("FE 폼 + 업로드 API + 스토리지 연동처럼 하나의 흐름")에 해당하지 않는다 — 각 단위가 독립적으로 검증 가능한 산출물(조사 보고서 / 고정 테스트 / 구현 diff / 마이그레이션 스크립트)을 내고, 순서 의존 관계로 묶여 있다. routing.md 강등 반례: "coupling 이 high 니까 단위가 1개다"는 오답 — 순서 의존은 "단위가 하나"가 아니라 "DAG가 필요하다"는 뜻이다. → **단위 2개 이상, NO**, STEP 3으로.

  **교차 점검 적용**: `uncertainty: high` AND `risk: high` AND 단위 2개 이상 조합이므로 routing.md의 교차 점검 규칙("이 조합에서 H1은 거의 항상 오답")에 해당함을 확인했다 — 호출부를 다 모르는 상태로 위험한 인증/스키마 변경을 구현자 한 명에게 통째로 맡기는 형태이기 때문에 H1을 배제한다.

- **STEP 3** (단위들이 서로 독립인가): coupling: high 이므로 동시 실행 불가, 순서 의존 있음(NO) → routing.md 규칙에 따라 YES/NO 둘 다 STEP 4로 진행.

- **STEP 4** (작업 간 Dependency 또는 실패 원인별 재라우팅 필요?): **YES.**
  - Dependency: DB 마이그레이션은 호출부 조사(dependency-mapper) 결과 없이 안전하게 설계할 수 없고, OAuth 구현은 baseline-tester 가 고정한 "현재 세션 유지 조건"에 의존한다.
  - 실패 원인별 재라우팅: 통합 검증 실패 시 되돌려 보낼 곳이 원인마다 다르다 — 숨은 호출부 발견 시 `dependency-mapper`, "세션을 끊지 않는다"는 전제가 깨졌을 때 `baseline-tester`, 구현 자체 버그면 `implementer`. 이는 routing.md H3 escalation 표와 정확히 일치하며, 강등 반례("순차로 하면 되니까 pipeline")에도 해당하지 않는다 — 실패 원인에 따라 되돌아갈 곳이 갈리므로 파이프라인(H1/H2 순차)으로 표현할 수 없다. → **H3.**

- **STEP 5** (side_effect ∈ {irreversible} 이거나 target_environment = production 이거나 시크릿·삭제 관련?): `side_effect: irreversible`(프로덕션 DB 마이그레이션) AND `target_environment: production` 둘 다 해당 → **human_gate.required = true.**

## 판정

- **level**: H3
- **pattern**: dag
- **rationale**: STEP 2에서 조사(호출부 전수 파악)·baseline 고정·OAuth+세션 호환 구현·DB 마이그레이션이라는 서로 다른 단위 4개로 나뉘고, STEP 4에서 실패 원인(숨은 호출부 / 전제 오류 / 구현 오류)에 따라 되돌려 보낼 곳이 갈려 재라우팅이 필요하다. **한 단계 아래(H2)가 안 되는 이유**: H2는 실패 시 항상 같은 곳(implementer)으로 돌아가면 충분한 구조인데, 이 작업은 통합 검증 실패 양상이 최소 3가지(숨은 호출부/전제 오류/구현 오류)로 갈리고 각각 다른 역할(dependency-mapper/baseline-tester/implementer)로 되돌아가야 하므로 H2의 "고정된 integrator→reviewer" 파이프라인만으로는 표현할 수 없다. `risk: high` 자체는 레벨을 올리는 근거로 쓰지 않았다(반례 "위험하니까 H3"를 배제) — 승격의 근거는 어디까지나 STEP 4의 재라우팅 필요성이다.
- **agents**: dependency-mapper, baseline-tester, implementer, integrator, reviewer, orchestrator, deployment-agent (카탈로그 7종 전부 사용 — 조사·구현·통합·리뷰·오케스트레이션·배포 준비가 각각 독립된 책임과 완료조건을 가짐)
- **human_gate**: true (STEP 5 — side_effect: irreversible, target_environment: production)

## Phase 3 — HarnessSpec

```yaml
harness_version: 1

task:
  goal: "운영 중인 Next.js 15 + TypeScript + PostgreSQL 서비스의 인증 방식을 JWT 기반에서 OAuth 기반으로 전환하고, 기존 세션 저장소·users 테이블 스키마를 마이그레이션한다. 전환 과정에서 기존 로그인 사용자의 세션이 끊기지 않아야 한다."
  scope: [auth-core, session-storage, db-schema, production-rollout]
  constraints:
    - "기존 로그인 사용자의 세션을 끊지 않는다 (무중단 전환)"
    - "리프레시 토큰 호출부를 전수 파악한 뒤에만 제거/대체한다"
    - "세션 저장소 스키마와 users 테이블의 FK 정합성을 마이그레이션 전 구간에서 유지한다"
  acceptance_criteria:
    - "신규 OAuth 기반 로그인/로그아웃/토큰 갱신 플로우가 정상 동작한다"
    - "마이그레이션 도중 및 이후에도 기존 JWT 로그인 사용자의 세션이 끊기지 않는다"
    - "세션 저장소·users 테이블 마이그레이션이 데이터 손실·정합성 오류 없이 완료된다"
    - "기존 인증 관련 테스트가 계속 통과한다"
    - "리프레시 토큰 관련 호출부가 전수 파악되어 숨은 호출부 없이 전부 대체되었다"
    - "프로덕션 배포 후 인증 헬스체크가 통과하고 롤백 절차가 실행 가능하다"
  known_risks:
    - "리프레시 토큰 호출부를 전부 열거하지 못한 상태 (숨은 호출부 가능성)"
    - "세션 저장소와 users 테이블의 FK 정합성 리스크"
    - "인증 관련 테스트가 일부만 존재 (안전망 약함)"
    - "실사용자 대상 프로덕션 서비스, DB 마이그레이션은 되돌리기 어려움"
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
    단위가 4개(조사/baseline/구현/DB마이그레이션)로 나뉘고(STEP2),
    통합 검증 실패 원인이 숨은 호출부·전제 오류·구현 오류로 갈려 재라우팅이 필요하다(STEP4).
    H2는 실패 시 항상 같은 곳(implementer)으로 돌아가는 구조라 이 재라우팅을 표현할 수 없어
    한 단계 아래로는 불충분하다. risk:high 자체는 승격 근거로 쓰지 않았다(reviewer/max_loops만 변경).
    uncertainty:high + risk:high + 단위 2개 이상 조합에서 H1은 오답이라는 교차 점검을 통과시켜 배제했다.

agents:
  - id: dependency-mapper
    model: sonnet
    responsibility: "lib/auth/ 의 JWT 발급·검증·리프레시 호출부를 전수 조사하고 API 계약을 정리한다"
  - id: baseline-tester
    model: sonnet
    responsibility: "기존 로그인/세션 유지 동작과 현재 통과하는 인증 테스트를 고정한다 (소스 수정 금지, 테스트 파일만 작성)"
  - id: implementer
    model: sonnet
    responsibility: "OAuth 플로우 구현, 세션 호환(무중단 전환) 계층, DB 마이그레이션 스크립트를 DAG 노드 순서대로 작성한다"
  - id: integrator
    model: opus
    responsibility: "OAuth 코어 / 세션 마이그레이션 호환 계층 / DB 스키마 마이그레이션 세 산출물의 인터페이스 불일치·머지 충돌·회귀만 통합한다 (신규 기능 추가 금지)"
  - id: reviewer
    model: opus
    responsibility: "최종 diff 의미적 리뷰 + risk:high 이므로 security-review 관점 포함"
  - id: orchestrator
    model: opus
    responsibility: "DAG 상태 관리, 노드 간 depends_on 추적, 실패 원인별 재라우팅, Human Gate 운영 (코드 미작성)"
  - id: deployment-agent
    model: sonnet
    responsibility: "프로덕션 마이그레이션 실행 계획·헬스체크·롤백 절차 준비 (Human Gate 승인 후에만 실행)"

controller_skills:
  - superpowers:using-git-worktrees
  - superpowers:dispatching-parallel-agents
  - superpowers:writing-plans
  - superpowers:subagent-driven-development
  - superpowers:requesting-code-review
  - superpowers:verification-before-completion
  - superpowers:finishing-a-development-branch

agent_skills:
  implementer:
    - superpowers:test-driven-development
    - superpowers:receiving-code-review
  reviewer:
    - security-review

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
  local: []
  final: []
  manual:
    - "gates.tsv 미확정: 입력에 검증 명령이 명시되지 않아 Phase 1(init-workspace.sh/detect-stack.sh)을 실제 레포에서 재실행하기 전까지 lint/typecheck/test/build 명령을 지어내지 않는다 — 실행 전 반드시 채워야 함"
    - "AC1 (OAuth 로그인/로그아웃/토큰 갱신 정상 동작) — 자동 게이트 미확인, 수동/E2E 검증 필요"
    - "AC2 (기존 세션 유지) — 마이그레이션 리허설(스테이징)에서 세션 보존 여부 수동 확인"
    - "AC3 (DB 마이그레이션 무손실) — 마이그레이션 전/후 데이터 정합성 수동 대조 (자동 게이트 있으면 feature/final로 승격 가능)"
    - "AC4 (기존 인증 테스트 통과) — gates.tsv에 test 명령이 확인되면 feature tier로 승격, 확인 전까지는 manual"
    - "AC5 (숨은 호출부 없음) — dependency-mapper 보고서 검토로 확인 (게이트 아님, 프로세스 산출물 검토)"
    - "AC6 (배포 후 헬스체크 + 롤백 준비) — deployment-agent 산출물 + Human Gate 증거로 확인"

review_policy:
  blocking: [BLOCKER, MAJOR]
  max_loops: 3
  escalation_after: 3

parallelism:
  enabled: true
  max_workers: 3

human_gate:
  required: true
  reason: "side_effect: irreversible (세션 저장소·users 테이블 프로덕션 DB 마이그레이션) + target_environment: production — 실사용자 세션 상태를 되돌리기 어렵게 변경한다"
  before:
    - "세션 저장소·users 테이블 DB 마이그레이션 스크립트를 프로덕션에 적용하기 전"
    - "OAuth 신규 인증 경로로 프로덕션 트래픽을 최종 전환(JWT 경로 폐기)하기 전"

escalation:
  if_hidden_dependency: dependency-mapper
  if_baseline_unknown: baseline-tester
  if_implementation_error: implementer
  if_gate_fails_repeatedly: superpowers:systematic-debugging
```

## 자체 점검

- **한 단계 아래 레벨을 고르지 않은 이유를 썼는가?** 예. `harness.rationale`에 H2가 불충분한 이유(고정된 재라우팅 대상 vs. 이 작업의 3가지 실패 양상별 재라우팅 필요)를 명시했고, STEP2 서술에도 별도로 근거를 남겼다.
- **카탈로그 7종 밖의 에이전트를 만들지 않았는가?** 예. dependency-mapper / baseline-tester / implementer / integrator / reviewer / orchestrator / deployment-agent — 카탈로그 7종만 사용했고 새 역할(예: security-reviewer, migration-agent 등)을 만들지 않았다. 보안 심사는 `reviewer` + `security-review` 스킬 주입으로, 배포는 `deployment-agent`로 처리했다.
- **수용 기준마다 그것을 확인하는 게이트가 verification 에 배정됐는가?** 부분적으로만 — 이번 eval 입력에는 검증 명령이 전혀 적혀 있지 않아(Phase 1 스크립트 실행도 생략) `gates.tsv`에 넣을 수 있는 실제 명령을 지어낼 수 없었다. 그 결과 `verification.local`/`final`은 빈 배열로 두고, AC1~AC6 전부를 `verification.manual`에 명시적으로 나열해 "게이트 없음 = 검증 불필요"로 오해되지 않도록 했다. 다만 이는 실행 전 반드시 실제 레포에서 Phase 1을 재실행해 test/build 명령이 확인되면 AC3·AC4는 `feature`/`final` tier로 승격해야 하는 임시 상태이며, spec에도 그 승격 조건을 manual 항목에 남겨두었다.
- **controller_skills 와 agent_skills 를 올바르게 구분했는가?** 예. Agent 도구가 필요한 절차(worktree 격리, 병렬 조사 dispatch, 계획 수립, SDD 실행, 리뷰 요청, 완료 전 검증, 브랜치 마무리)는 `controller_skills`(H3이므로 orchestrator 소유)에 두었고, 워커가 자기 작업만 수행하는 절차(TDD, 리뷰 피드백 반영, 보안 리뷰)만 `agent_skills`로 implementer/reviewer 프롬프트에 주입했다.
