# eval 02 — 프로필 이미지 업로드 기능 추가 (FE 폼 + API 핸들러 + Storage, 단일 흐름)

## Phase 0 — task 6필드

- **goal**: 사용자 프로필 페이지에서 프로필 이미지를 업로드하면 Supabase Storage에 저장되고 프로필에 반영되는 기능을 추가한다.
- **scope**: [frontend (업로드 폼), api (`app/api/profile/avatar/route.ts`), storage (Supabase Storage 버킷 연동)]
- **constraints**: 기존 프로필 저장 기능과 그 테스트를 깨지 않는다.
- **acceptance_criteria**:
  - 사용자가 프로필 페이지에서 이미지를 선택해 업로드하면 Storage에 저장되고 프로필 화면에 반영된다.
  - `npm run lint`, `npm run typecheck`, `npm run test`, `npm run build` 전부 통과한다.
  - 기존 프로필 저장 기능(및 기존 테스트)이 회귀하지 않는다.
- **known_risks**: 업로드 파일 타입·크기 서버 측 검증 누락 가능성, Storage 버킷 접근 권한 설정 오류 가능성.
- **target_environment**: local (입력에 "로컬 개발 환경에서만 작업한다"고 명시됨)

## Phase 2 — 6축 프로파일

| 축 | 값 | 근거 |
|---|---|---|
| `scope` | few | "업로드는 프론트엔드 폼, `app/api/profile/avatar/route.ts` API 핸들러, Supabase Storage 버킷 세 곳을 거친다" — 책임 영역 3개(FE/API/Storage) |
| `coupling` | high | "세 곳은 하나의 업로드 흐름으로 이어져 있어 한쪽만 먼저 완성해도 동작을 확인할 수 없다" — 순서·검증 의존 명시 |
| `parallelism` | none | profiling.md 규칙: `coupling: high` 면 `parallelism` 자동 `none` |
| `uncertainty` | low | "기존 프로필 저장 기능과 그 테스트가 이미 있다" — 베이스라인 동작이 테스트로 고정되어 있고, 신규 라우트라 미열거 호출부 문제도 없음 |
| `risk` | medium | 신규 공개 API 시그니처(`route.ts`) + 서버 측 업로드 검증(파일 타입·크기) — profiling.md의 `medium` 정의("서버 측 검증 로직, 공개 API 시그니처")에 해당. auth·결제·스키마 변경·배포 파이프라인 접촉 없음 → `high` 아님 |
| `side_effect` | none | "로컬 개발 환경에서만 작업한다" — `target_environment: local`, 프로덕션·외부 시스템 상태 변경 없음 |

## Phase 2 — 판정 트리 통과 기록

STEP 1: 단일 세션·단일 컨텍스트로 안전하게 완료 가능한가? (변경 영역 1개 AND risk≤low AND uncertainty=low)
→ **NO**. `scope: few`(3개 영역)로 "변경 영역 1개" 조건을 충족하지 못함 (risk/uncertainty 조건과 무관하게 이미 탈락).

STEP 2: 작업 단위가 1개인가? ("구현자 한 명이 한 번에 끝까지 들고 갈 수 있는가?")
→ **YES**. `coupling: high`로 세 영역이 하나의 업로드 흐름으로 묶여 있어 한쪽만 먼저 완성해도 동작 확인이 불가능하다 — 중간 산출물을 독립적으로 검증할 수 없으므로 단위는 1개. 이는 routing.md의 "승격을 막는 반례" 항목에 나오는 예시("FE 폼 + 업로드 API + 스토리지 연동")와 정확히 일치한다 → **H1**.

(STEP 2에서 YES가 나왔으므로 STEP 3·4는 평가하지 않음 — H2/H3로 갈 필요가 없다.)

STEP 5: side_effect ∈ {irreversible} 이거나 target_environment = production 이거나 시크릿·데이터 삭제를 건드리는가?
→ **NO**. `side_effect: none`, `target_environment: local`. 따라서 `human_gate.required = false`.

**교차 점검(routing.md)**: `uncertainty: high` AND `risk: high` AND 단위 2개 이상 조합에서만 "H1이 거의 항상 오답"이라는 경고가 적용된다. 이번 건은 `uncertainty: low`, `risk: medium`이라 이 조합에 해당하지 않으므로 교차 점검 경고는 트리거되지 않는다 — H1 유지.

**강등을 막는 반례 교차 점검**: "coupling이 high니까 단위가 1개다"는 오답 패턴이지만, 이번 판정의 근거는 coupling 자체가 아니라 "구현자 한 명이 통째로 들고 가야 검증 가능하다"(routing.md 승격 반례의 정의)는 점 — STEP 2 질문에 직접 답한 것이므로 이 반례에 해당하지 않는다.

## 판정

level: H1
pattern: pipeline
rationale: H0은 변경 영역이 3개(FE/API/Storage)라 "단일 세션·단일 컨텍스트로 안전 완료" 조건(STEP 1: 변경 영역 1개)을 충족하지 못해 불가하다. 반대로 세 영역이 하나의 업로드 흐름으로 강결합되어 있어 중간 산출물을 독립 검증할 수 없으므로 워커를 나누는 H2/H3도 불필요하다 — 구현자 1인이 통째로 들고 가는 pipeline(H1)이 안전하게 완료 가능한 가장 단순한 하네스다.
agents: implementer, reviewer
human_gate: false (side_effect=none, target_environment=local — STEP 5 조건 모두 미해당)

## Phase 3 — HarnessSpec

```yaml
harness_version: 1

task:
  goal: "사용자 프로필 페이지에 프로필 이미지 업로드 기능을 추가한다 (FE 폼 → app/api/profile/avatar/route.ts → Supabase Storage)"
  scope: [frontend, api, storage]
  constraints:
    - "기존 프로필 저장 기능과 그 테스트를 깨지 않는다"
  acceptance_criteria:
    - "프로필 페이지에서 이미지 업로드 시 Storage에 저장되고 화면에 반영된다"
    - "npm run lint / typecheck / test / build 전부 통과한다"
    - "기존 프로필 저장 기능 및 기존 테스트가 회귀하지 않는다"
  known_risks:
    - "업로드 파일 타입·크기 서버 측 검증 누락 가능성"
    - "Supabase Storage 버킷 접근 권한 설정 오류 가능성"
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
    변경 영역이 3개(FE/API/Storage)라 H0(STEP 1: 영역 1개) 불가하나,
    세 영역이 하나의 업로드 흐름으로 강결합되어 있어 구현자 한 명이
    통째로 들고 가야 중간 검증이 가능하므로(routing.md STEP 2 및 승격 반례 예시와 일치)
    워커 분할(H2/H3)도 불필요하다.

agents:
  - id: implementer
    model: sonnet
    responsibility: "FE 업로드 폼 + API 핸들러 + Storage 연동을 하나의 단위로 구현한다"
  - id: reviewer
    model: opus
    responsibility: "게이트 통과 후 diff를 의미적으로 리뷰한다 (BLOCKER/MAJOR 판정)"

skills:
  implementer: [superpowers:test-driven-development]

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
  final: [feature, final]
  manual:
    - "실제 브라우저에서 이미지 선택 → 업로드 → 프로필 반영 플로우 수동 확인 (e2e 게이트 미설정)"

review_policy:
  blocking: [BLOCKER, MAJOR]
  max_loops: 2
  escalation_after: 2

parallelism:
  enabled: false
  max_workers: 1

human_gate:
  required: false
  reason:
  before:

escalation:
  if_hidden_dependency: dependency-mapper
  if_baseline_unknown: baseline-tester
  if_implementation_error: implementer
  if_gate_fails_repeatedly: superpowers:systematic-debugging
```

## 자체 점검

- 한 단계 아래 레벨을 고르지 않은 이유를 썼는가? — 예. H0은 STEP 1의 "변경 영역 1개" 조건을 `scope: few`(3영역)가 충족하지 못해 불가함을 명시했다 (rationale 및 STEP 1 기록).
- 카탈로그 7종 밖의 에이전트를 만들지 않았는가? — 예. `implementer`, `reviewer` 2종만 사용, 둘 다 catalog.md 7종에 포함. uncertainty가 low라 dependency-mapper/baseline-tester는 사전 dispatch 대상이 아니다.
- routing.md의 교차 점검 규칙(uncertainty high + risk high + 단위 2개 이상)을 적용했는가? — 예. `uncertainty: low`, `risk: medium`으로 이 조합에 해당하지 않음을 확인했고, "강등을 막는 반례"(coupling high → 단위 1개로 오판)에도 해당하지 않음을 별도로 교차 확인했다.
