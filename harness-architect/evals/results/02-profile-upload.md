# eval 02 — 프로필 이미지 업로드 기능 추가 (프론트 폼 + API 핸들러 + Storage 3영역, 흐름 결합)

## Phase 0 — task 6필드

- **goal**: 사용자 프로필 페이지에서 이미지 파일을 업로드하면 `app/api/profile/avatar/route.ts` 핸들러를 거쳐 Supabase Storage 버킷에 저장되고, 프로필에 반영된다.
- **scope**: [frontend(업로드 폼), api(`app/api/profile/avatar/route.ts`), storage(Supabase Storage 버킷)]
- **constraints**: 기존 프로필 저장 기능과 그 테스트를 깨지 않는다.
- **acceptance_criteria**: 업로드 폼에서 이미지 선택 시 API 핸들러 검증을 통과해 Supabase Storage에 저장되고 프로필에 즉시 반영된다; `npm run lint` / `npm run typecheck` / `npm run test` / `npm run build` 전부 통과.
- **known_risks**: 업로드 파일 타입·크기 서버 측 검증 누락 위험, 버킷 접근 권한 설정 오류.
- **target_environment**: local

질문 없이 진행함 — scope/coupling/uncertainty/risk/side_effect 를 뒤집을 만한 답은 입력에 이미 명시돼 있음 (로컬 전용, 3영역이 하나의 흐름으로 결합, 기존 테스트 존재).

## Phase 2 — 6축 프로파일

| 축 | 값 | 근거 |
|---|---|---|
| `scope` | few (3) | "업로드는 프론트엔드 폼, `app/api/profile/avatar/route.ts` API 핸들러, Supabase Storage 버킷 세 곳을 거친다" — 책임 영역 3개(프레젠테이션/API/스토리지). |
| `coupling` | high | "세 곳은 하나의 업로드 흐름으로 이어져 있어 한쪽만 먼저 완성해도 동작을 확인할 수 없다" — profiling.md 규칙 "A 를 먼저 끝내지 않으면 B 를 시작할 수 없는가?"가 `high`에 해당. |
| `parallelism` | none | profiling.md 규칙: "`coupling: high` 면 `parallelism` 은 자동으로 `none`". 위 coupling 판정에서 자동 결정. |
| `uncertainty` | low | "기존 프로필 저장 기능과 그 테스트가 이미 있다" — 인접 기능의 현재 동작을 고정하는 테스트가 존재하고, Next.js 15 표준 구조(App Router `app/api/.../route.ts`)라 레거시 문서 불일치 소지도 없음. uncertainty 상향 트리거(테스트 부재/호출부 미상/레거시) 미해당. |
| `risk` | medium | 업로드 API 핸들러는 "서버 측 검증 로직, 공개 API 시그니처"에 해당(profiling.md `medium` 예시와 직접 일치). 인증/인가·결제·스키마 변경·배포 파이프라인(=`high` 예시)은 언급 없음. |
| `side_effect` | none | "로컬 개발 환경에서만 작업한다" — target_environment: local. profiling.md `none` 정의("로컬 코드 변경만")에 해당, 프로덕션/외부 시스템 상태 변경이나 시크릿·데이터 삭제 없음. |

## Phase 2 — 판정 트리 통과 기록

STEP 1: 단일 세션·단일 컨텍스트로 안전하게 완료 가능한가? (변경 영역 1개 AND risk≤low AND uncertainty=low)
→ **NO** — scope가 few(3영역: frontend/api/storage)라 "변경 영역 1개" 조건부터 불충족.

STEP 2: 순차 분리 + 독립 Reviewer 면 충분한가? (독립 실행 가능 작업 단위 1개 = parallelism: none)
→ **YES** — parallelism이 none(coupling high로 자동 결정)이므로 독립 실행 가능한 작업 단위는 1개. → **H1**.

STEP 5: side_effect ∈ {irreversible} 이거나 target_environment = production 이거나 시크릿·데이터 삭제를 건드리는가?
→ **NO** — side_effect: none, target_environment: local. → human_gate.required = false.

(STEP 3·4는 parallelism: none 단계에서 이미 H1로 확정되어 도달하지 않음.)

## 판정

level: H1
pattern: pipeline
rationale: 한 단계 아래인 H0는 STEP1 조건("변경 영역 1개")을 충족하지 못해 안 된다 — scope가 few(프론트엔드 폼·API 핸들러·Storage 버킷 3영역)이고, 이 3영역이 하나의 업로드 흐름으로 결합돼(coupling: high) 단일 세션에서 영역을 넘나들며 순차 확인해야 하므로 단일 구현자 직접 처리만으로는 리뷰 독립성이 없다; 동시에 parallelism이 none(coupling high가 자동 결정)이라 H2(Fan-out)로 승격할 근거도 없다 — 독립 실행 단위가 1개뿐이라 워커 병렬화의 이득이 없다.
agents: implementer, reviewer
human_gate: false

## Phase 3 — HarnessSpec

```yaml
harness_version: 1

task:
  goal: "사용자 프로필 페이지에서 이미지를 업로드하면 app/api/profile/avatar/route.ts 를 거쳐 Supabase Storage에 저장되고 프로필에 반영된다"
  scope: [frontend, api, storage]
  constraints:
    - "기존 프로필 저장 기능과 그 테스트를 깨지 않는다"
  acceptance_criteria:
    - "업로드 폼에서 이미지 선택 시 API 핸들러 검증(타입·크기)을 통과해 Supabase Storage에 저장된다"
    - "저장된 이미지가 프로필에 반영되어 조회 시 표시된다"
    - "npm run lint / npm run typecheck / npm run test / npm run build 전부 통과"
  known_risks:
    - "업로드 파일 타입·크기 서버 측 검증 누락 위험"
    - "Storage 버킷 접근 권한 설정 오류"
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
  rationale: "scope가 few(3영역)라 H0의 STEP1(변경 영역 1개)을 충족 못해 H0 불가; coupling이 high라 parallelism이 자동 none이 되어 독립 실행 단위가 1개뿐이므로 H2(Fan-out) 승격 근거도 없음 — H1이 최소 안전 하네스."

agents:
  - id: implementer
    model: sonnet
    responsibility: "프론트엔드 업로드 폼 → API 핸들러 → Supabase Storage 연동을 하나의 흐름으로 순차 구현"
  - id: reviewer
    model: opus
    responsibility: "구현 완료 diff에 대한 의미적 코드 리뷰 (업로드 검증 로직, API 시그니처 포함)"

skills:
  implementer: [superpowers:test-driven-development]
  reviewer: []

context:
  implementer:
    required: [task, acceptance_criteria, assigned_unit_only, relevant_source, relevant_tests]
    optional: [gate_log_path]
    forbidden: [full_repository_dump, unrelated_docs, session_history, other_workers_context]
  reviewer:
    required: [task, acceptance_criteria, git_diff, gate_results]
    optional: []
    forbidden: [full_repository_dump, unrelated_docs, session_history, implementer_reasoning]

verification:
  gates_tsv: _workspace/harness/gates.tsv   # Phase 1(init-workspace.sh) 미실행 — 입력에 명시된 검증 명령을 게이트로 간주
  local: [lint, typecheck]
  final: [test, build]
  manual:
    - "업로드 폼에서 실제 파일 선택 → 미리보기 → 저장 흐름 육안 확인 (E2E 자동화 게이트 없음)"

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

- 한 단계 아래 레벨을 고르지 않은 이유를 썼는가? — 예. H0가 안 되는 이유(scope few로 STEP1 불충족)를 `harness.rationale`에 명시했고, 위쪽 H2로 승격하지 않는 이유(parallelism: none → 독립 단위 1개)도 함께 기술함.
- 카탈로그 7종 밖의 에이전트를 만들지 않았는가? — 예. `implementer`, `reviewer`만 사용, 둘 다 `references/catalog.md` 7종 안에 있음. security-reviewer 등 새 역할 생성하지 않음(risk가 high가 아니므로 security-review 스킬 주입도 하지 않음).
