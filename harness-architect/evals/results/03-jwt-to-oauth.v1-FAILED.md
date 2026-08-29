> **[폐기된 1차 실행 기록 — 2026-08-29]** 이 판정은 기대값 H3 대신 **H1** 을 냈다.
> 에이전트 잘못이 아니라 판정 트리의 결함이었다: 당시 STEP 2 가 "독립 실행 가능 작업 단위가
> 1개(= `parallelism: none`)면 H1" 이었고, `coupling: high` → `parallelism: none` 규칙 때문에
> 순서 의존이 강한 작업이 전부 H1 으로 흡수됐다. H3 의 조건은 병렬성이 아니라
> **순서 의존 + 실패 원인별 재라우팅**이다.
>
> 수정: `references/routing.md` STEP 2 를 "구현자 한 명이 한 번에 끝까지 들고 갈 수 있는가"로
> 바꾸고, 강등을 막는 반례 3종과 교차 점검 규칙을 추가했다. `references/profiling.md` 의
> `parallelism` 설명에도 "none 이 단위 1개를 뜻하지 않는다"는 주의를 넣었다.
> 수정 후 재실행 결과는 `03-jwt-to-oauth.md` 참고.

---

# eval 03 — JWT→OAuth 전환 + 세션/DB 마이그레이션 (운영 서비스, 프로덕션 배포 예정)

## Phase 0 — task 6필드

- **goal**: 운영 중인 서비스의 인증 방식을 JWT 기반에서 OAuth 기반으로 전환하고, 기존 세션 저장소와 DB 스키마(users 테이블 FK 연동 포함)를 마이그레이션한다. 전환 과정에서 기존 로그인 사용자의 세션은 끊기지 않아야 한다.
- **scope**: [`auth-logic (lib/auth/ 의 JWT 발급·검증·리프레시 → OAuth 전환)`, `session-storage/db-schema (세션 저장소 스키마 + users 테이블 FK 마이그레이션)`]
- **constraints**:
  - 기존 로그인 사용자의 세션을 끊지 않는다
  - 세션 저장소 스키마와 users 테이블의 외래키 무결성을 유지한다
  - 결과물은 프로덕션에 배포된다 (실사용자 영향)
- **acceptance_criteria**:
  - OAuth 기반 인증 흐름(발급/검증/기존 리프레시 대체 로직 포함)이 정상 동작한다
  - 세션·DB 마이그레이션이 완료되고 FK 무결성이 유지된다
  - 마이그레이션 전후로 기존 로그인 사용자의 세션이 유효하게 유지된다
  - `run-gates.sh fast` / `feature` / `final` 전부 통과
  - 롤백 절차가 문서화되어 있다 (비가역적 부작용 대응)
- **known_risks**:
  - 리프레시 토큰 호출부를 전부 파악하지 못해, 누락된 호출부에서 회귀가 발생할 수 있다
  - 인증 관련 테스트가 일부만 존재해 기존 동작을 완전히 고정하지 못할 수 있다
  - 세션/users 테이블 FK 마이그레이션 실패 시 실사용자 로그인 장애로 직결된다
- **target_environment**: production

## Phase 2 — 6축 프로파일

| 축 | 값 | 근거 |
|---|---|---|
| `scope` | few (2) | "JWT 발급·검증·리프레시가 lib/auth/ 아래 여러 파일에 흩어져 있으며" (인증 로직 1개 책임영역) + "세션 저장소 스키마와 users 테이블이 외래키로 엮여 있다" (DB/세션 스키마 마이그레이션 1개 책임영역). 두 영역이지만 하나의 전환 흐름으로 묶여 있음 |
| `coupling` | high | 세션을 끊지 않고 OAuth로 전환하려면 인증 로직 변경과 세션/DB 스키마 마이그레이션의 순서·정합이 강제된다 ("세션 저장소 스키마와 users 테이블이 외래키로 엮여 있다" + "기존 로그인 사용자의 세션을 끊으면 안 된다") → "A를 먼저 끝내지 않으면 B를 시작할 수 없는가" 조건 충족 |
| `parallelism` | none | profiling.md 규칙: "coupling: high 면 parallelism 은 자동으로 none 이다" |
| `uncertainty` | high | "리프레시 토큰 경로를 어디서 호출하는지 전부 파악되어 있지 않다" → 규칙의 "호출부를 전부 열거할 수 없다"에 해당 (단독으로 high 판정 조건 충족). "인증 관련 테스트는 일부만 있다" → 기존 동작을 고정하는 테스트 부족도 추가 근거 |
| `risk` | high | "인증 시스템을... 전환" (인증·인가) + "DB 도 마이그레이션" (스키마 변경) — 규칙 상 둘 다 high 항목에 명시됨 |
| `side_effect` | irreversible | "작업 결과는 프로덕션에 배포할 예정이다" + DB/세션 스키마 마이그레이션 — 규칙의 "프로덕션 DB 마이그레이션"에 해당 |

## Phase 2 — 판정 트리 통과 기록

STEP 1: 단일 세션·단일 컨텍스트로 안전하게 완료 가능한가? (scope 1 AND risk≤low AND uncertainty=low)
→ **NO**. scope가 1이 아니라 few(2)이고, risk=high(인증+스키마 변경), uncertainty=high(호출부 미파악, 테스트 일부만 존재) — 세 조건 모두 불충족.

STEP 2: 순차 분리 + 독립 Reviewer 면 충분한가? (독립 실행 가능 작업 단위 1개 = parallelism: none)
→ **YES**. coupling=high로 인해 parallelism이 자동으로 none이 되었고(위 축 판정 근거), 인증 로직 전환과 세션/DB 스키마 마이그레이션이 세션 연속성 보장을 위해 하나의 순차 흐름으로 묶여야 한다 → 독립 작업 단위는 사실상 1개. **→ H1로 판정, STEP 3/4는 평가 불필요** (STEP 2에서 YES가 나오면 트리가 H1로 종결됨).

STEP 5: side_effect ∈ {irreversible} 이거나 target_environment = production 인가? (레벨과 무관하게 항상 평가)
→ **YES**. side_effect=irreversible(프로덕션 DB/세션 마이그레이션) 이고 target_environment=production. → `human_gate.required = true`.

## 판정

level: **H1**
pattern: pipeline
rationale: 한 단계 아래인 H0는 "단일 세션·단일 컨텍스트로 안전 완료 가능(scope=1 AND risk≤low AND uncertainty=low)"을 요구하지만, 이 작업은 risk=high(인증·DB 스키마 변경), uncertainty=high(리프레시 토큰 호출부 미파악, 테스트 일부만 존재), scope=few(인증 로직 + 세션/DB 스키마 2개 책임영역)로 세 조건 모두 위반하므로 최소한 독립 Reviewer가 붙는 H1이 필요하다. 반면 H2로 승격할 근거는 없다 — coupling이 high이므로 parallelism이 자동으로 none이 되어(routing.md 반례: "3영역이 하나의 흐름으로 묶여 있으면 독립 단위는 1개고 H1이다"), fan-out으로 시간을 절약할 독립 작업 단위 자체가 없다.
agents: dependency-mapper, baseline-tester, implementer, reviewer
human_gate: true (side_effect=irreversible 이고 target_environment=production — STEP 5 조건 충족. 프로덕션 배포 및 DB/세션 마이그레이션 실행 전에 사람이 증거를 보고 승인해야 한다)

## Phase 3 — HarnessSpec

```yaml
harness_version: 1

task:
  goal: "운영 중인 서비스의 인증 방식을 JWT 기반에서 OAuth 기반으로 전환하고, 기존 세션 저장소와 DB 스키마(users 테이블 FK 연동 포함)를 마이그레이션한다. 기존 로그인 사용자의 세션은 끊기지 않아야 한다."
  scope:
    - "auth-logic (lib/auth/ 의 JWT 발급·검증·리프레시 → OAuth 전환)"
    - "session-storage/db-schema (세션 저장소 스키마 + users 테이블 FK 마이그레이션)"
  constraints:
    - "기존 로그인 사용자의 세션을 끊지 않는다"
    - "세션 저장소 스키마와 users 테이블의 외래키 무결성을 유지한다"
    - "결과물은 프로덕션에 배포된다"
  acceptance_criteria:
    - "OAuth 기반 인증 흐름(발급/검증/기존 리프레시 대체 로직)이 정상 동작한다"
    - "세션·DB 마이그레이션이 완료되고 FK 무결성이 유지된다"
    - "마이그레이션 전후로 기존 로그인 사용자의 세션이 유효하게 유지된다"
    - "run-gates.sh fast/feature/final 전부 통과한다"
    - "롤백 절차가 문서화되어 있다"
  known_risks:
    - "리프레시 토큰 호출부를 전부 파악하지 못해 누락된 호출부에서 회귀가 발생할 수 있다"
    - "인증 관련 테스트가 일부만 있어 기존 동작을 완전히 고정하지 못할 수 있다"
    - "세션/users 테이블 FK 마이그레이션 실패 시 실사용자 로그인 장애로 직결된다"
  target_environment: production

profile:
  scope: few
  coupling: high
  parallelism: none
  uncertainty: high
  risk: high
  side_effect: irreversible

harness:
  level: H1
  pattern: pipeline
  rationale: >
    H0는 scope=1 AND risk≤low AND uncertainty=low 를 요구하나 이 작업은 셋 다 위반한다
    (scope=few, risk=high, uncertainty=high). H2로 승격할 근거는 없다 —
    coupling=high로 parallelism이 자동 none이 되어 fan-out으로 절약할 독립 작업 단위가 없다.

agents:
  - id: dependency-mapper
    model: sonnet
    responsibility: "lib/auth/ 의 JWT 발급·검증·리프레시 호출부를 전수 조사하고 세션/users 테이블 FK 관계를 매핑한다"
  - id: baseline-tester
    model: sonnet
    responsibility: "현재 JWT 발급·검증·리프레시 동작과 세션 지속성을 테스트로 고정한다"
  - id: implementer
    model: sonnet
    responsibility: "OAuth 전환 로직과 세션/DB 마이그레이션을 TDD로 구현한다"
  - id: reviewer
    model: opus
    responsibility: "diff 의미적 리뷰 및 risk:high 에 따른 보안 심사(security-review)를 수행한다"

skills:
  implementer:
    - superpowers:test-driven-development
    - superpowers:receiving-code-review
  reviewer:
    - superpowers:requesting-code-review
    - security-review

context:
  dependency-mapper:
    required: [task, "relevant_module_tree(lib/auth/)", imports, "call_sites(리프레시 토큰 호출부)", api_contracts]
    optional: ["db_schema(session/users FK)", config_files]
    forbidden: [full_repository_dump, test_fixtures, unrelated_docs]
  baseline-tester:
    required: [task, "existing_tests(인증 관련 일부 테스트)", "current_behavior(JWT 발급/검증/리프레시 및 세션 지속성)", api_responses]
    optional: [test_fixtures, ci_history]
    forbidden: [full_repository_dump, implementation_plan]
  implementer:
    required: [task, acceptance_criteria, assigned_unit_only, "relevant_source(lib/auth/**, session/db migration 코드)", relevant_tests]
    optional:
      - "dependency_report(_workspace/harness/research/dependencies.md)"
      - "baseline_report(_workspace/harness/research/baseline.md)"
      - architecture_doc
      - gate_log_path
    forbidden: [full_repository_dump, unrelated_docs, session_history, other_workers_context]
  reviewer:
    required: [task, acceptance_criteria, git_diff, gate_results]
    optional: [architecture_doc, baseline_report]
    forbidden: [full_repository_dump, unrelated_docs, session_history, implementer_reasoning]

verification:
  gates_tsv: _workspace/harness/gates.tsv
  local: [fast, feature]
  final: [final]
  manual:
    - "기존 로그인 사용자 세션 유지 여부 수동 확인 (자동 게이트로 완전히 검증 불가능한 실사용자 세션 연속성)"
    - "프로덕션 배포 전 롤백 절차 최종 확인"

review_policy:
  blocking: [BLOCKER, MAJOR]
  max_loops: 3
  escalation_after: 3

parallelism:
  enabled: false
  max_workers: 1

human_gate:
  required: true
  reason: "side_effect=irreversible(프로덕션 DB/세션 마이그레이션) 이고 target_environment=production 이다 — 실사용자 세션과 인증 체계에 영향을 미치는 비가역적 변경이므로 배포 전 사람의 승인이 필요하다"
  before: "프로덕션 배포 및 DB/세션 마이그레이션 실행 전"

escalation:
  if_hidden_dependency: dependency-mapper
  if_baseline_unknown: baseline-tester
  if_implementation_error: implementer
  if_gate_fails_repeatedly: superpowers:systematic-debugging
```

## 자체 점검

- 한 단계 아래 레벨을 고르지 않은 이유를 썼는가? → 예. H0의 조건(scope=1 AND risk≤low AND uncertainty=low)이 모두 위반됨을 `harness.rationale`과 STEP 1 기록에 명시했다.
- 카탈로그 7종 밖의 에이전트를 만들지 않았는가? → 예. dependency-mapper, baseline-tester, implementer, reviewer 4종만 사용했으며 모두 `references/catalog.md`의 7종 안에 있다. security-reviewer 같은 별도 역할을 만들지 않고 reviewer에 `security-review` 스킬을 주입하는 방식을 따랐다.
