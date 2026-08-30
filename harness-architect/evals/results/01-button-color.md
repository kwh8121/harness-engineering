# eval 01 — 프로필 저장 버튼 색상을 회색 → brand.blue 로 변경

## Phase 0 — task 6필드

- **goal**: 프로필 페이지 저장 버튼(`components/profile/SaveButton.tsx`)의 색상을 회색에서
  `tailwind.config.ts` 에 이미 정의된 `brand.blue` 토큰으로 변경한다.
- **scope**: `[frontend]` — `components/profile/SaveButton.tsx` 한 파일뿐. 이 버튼을 쓰는 다른 화면 없음.
- **constraints**:
  - 새 색상 값을 하드코딩하지 않고 기존 `brand.blue` 토큰을 사용한다.
  - 버튼의 다른 스타일(크기·레이아웃·상호작용)은 건드리지 않는다.
- **acceptance_criteria**:
  1. `SaveButton.tsx` 의 배경/텍스트 색상 클래스가 회색 계열에서 `brand.blue` 계열로 바뀐다.
  2. 저장 버튼이 실제로 브랜드 파란색으로 렌더링된다 (시각 확인).
  3. 기존 `lint` / `typecheck` / `test` / `build` 가 모두 통과한다.
  4. 이 버튼을 사용하는 다른 화면에 회귀가 없다 (사용처가 이 파일 하나뿐이므로 구조적으로 자동 충족).
- **known_risks**: 없음. 표현 계층 변경만이고 단일 파일·단일 사용처.
- **target_environment**: `local` — 입력에 배포·마이그레이션·스테이징 언급이 전혀 없고, 검증 수단이
  로컬 게이트(lint/typecheck/test/build) 뿐이다. "이걸 프로덕션에 반영하나요?"는 레벨·Human Gate를
  뒤집을 수 있는 질문이지만, 이 작업 자체(코드 변경)는 로컬 워킹 카피에서 완결되고 배포는 별도
  후속 단계이므로 여기서 사람에게 물을 필요가 없다고 판단했다 (Auto Mode 하에서의 합리적 기본값).

## Phase 2 — 6축 프로파일

| 축 | 값 | 근거 |
|---|---|---|
| `scope` | `single` | 입력에 "저장 버튼은 `components/profile/SaveButton.tsx` 한 파일에만 있다"고 명시됨 — 책임 영역 1개(FE 표현 계층뿐, API·스토리지 연동 없음). |
| `coupling` | `low` | 입력에 "이 버튼을 쓰는 다른 화면은 없다"고 명시됨 — 다른 변경과 동시 진행하거나 순서를 맞출 필요가 없음. |
| `parallelism` | `none` | 작업 단위가 1개(단일 파일 클래스 교체)라서 병렬화 대상 자체가 없음. |
| `uncertainty` | `low` | 색상 토큰(`brand.blue`)이 `tailwind.config.ts`에 이미 정의되어 있고, 대상 파일과 유일한 사용처가 모두 확인됨 — 호출부를 전부 열거 가능, 레거시/문서 불일치 소지 없음. |
| `risk` | `low` | profiling.md 기준 "표현 계층" 변경 — auth·DB·결제·보안·배포 접촉 없음. |
| `side_effect` | `none` | 로컬 코드 변경만이며 `target_environment: local`. 프로덕션 DB·외부 시스템·시크릿·데이터 삭제와 무관. |

## Phase 2 — 판정 트리 통과 기록

- **STEP 1**: "변경 영역 1개 AND risk ≤ low AND uncertainty = low" → scope=single(1개), risk=low,
  uncertainty=low → 세 조건 모두 충족 → **YES → H0**. (STEP 2~4는 STEP 1이 YES이므로 진행하지 않음.)
- **STEP 5** (레벨과 무관하게 항상 별도 확인): side_effect=none(irreversible 아님), target_environment=local
  (production 아님), 시크릿·데이터 삭제 없음 → 셋 다 해당 없음 → **human_gate.required = false**.

**승격 반례 교차 점검**:
- "위험하니까 H3" 반례 — 해당 없음. risk가 애초에 low이고, 설령 risk가 high였더라도 그 자체로는
  레벨을 올리지 않는다(reviewer 유무·max_loops만 바뀜). 여기선 risk 자체가 low라 논쟁의 여지 없음.
- "영역이 여러 개니까 워커 여러 명" 반례 — 해당 없음. 영역이 애초에 1개(single)이므로 이 반례가
  적용될 상황 자체가 아님.
- **교차 점검(uncertainty high & risk high & 단위 2개 이상 → H1 의심)**: 해당 없음 — uncertainty·risk
  모두 low이고 단위도 1개이므로 이 교차 점검 대상 조합 자체가 성립하지 않는다.
- **강등 반례**: "parallelism이 none이니 H1" 같은 강등 오류는 애초에 이 사례가 STEP 1에서 H0으로
  끝나므로 해당하지 않는다. coupling=low이고 순서 의존(묶인 단위)도 없으므로 DAG가 필요한 형태(H3)로
  잘못 강등/승격될 여지가 없다.

## 판정

- **level**: H0
- **pattern**: single
- **rationale**: STEP 1의 세 조건(변경 영역 1개, risk ≤ low, uncertainty = low)을 모두 만족한다.
  단일 파일의 CSS 클래스 교체이며 대상 색상 토큰이 이미 존재하고 유일한 사용처까지 확인되어,
  구현자 없이(에이전트 0개) 직접 구현 후 결정론적 게이트만으로 안전하게 완료할 수 있다.
  H0은 최하위 레벨이므로 "한 단계 아래" 비교 대상이 없다.
- **agents**: 0개
- **human_gate**: false — STEP 5의 세 조건(side_effect=irreversible, target_environment=production,
  시크릿/데이터 삭제) 중 어느 것도 해당하지 않는다.

## Phase 3 — HarnessSpec

```yaml
harness_version: 1

task:
  goal: "프로필 페이지 저장 버튼(components/profile/SaveButton.tsx) 색상을 회색에서 tailwind.config.ts 의 brand.blue 토큰으로 변경한다"
  scope: [frontend]
  constraints:
    - "새 색상 값을 하드코딩하지 않고 기존 brand.blue 토큰을 사용한다"
    - "버튼의 색상 외 다른 스타일(크기·레이아웃·상호작용)은 변경하지 않는다"
  acceptance_criteria:
    - "SaveButton.tsx 의 배경/텍스트 색상 클래스가 회색 계열에서 brand.blue 계열로 바뀐다"
    - "저장 버튼이 실제로 브랜드 파란색으로 렌더링된다 (시각 확인)"
    - "기존 lint / typecheck / test / build 가 모두 통과한다"
    - "이 버튼을 사용하는 다른 화면에 회귀가 없다 (사용처가 이 파일 하나뿐이므로 구조적으로 충족)"
  known_risks: []
  target_environment: local

profile:
  scope: single
  coupling: low
  parallelism: none
  uncertainty: low
  risk: low
  side_effect: none

harness:
  level: H0
  pattern: single
  rationale: >
    STEP 1의 세 조건(변경 영역 1개, risk ≤ low, uncertainty = low)을 모두 만족한다.
    단일 파일 CSS 클래스 교체이고 대상 토큰이 이미 존재하며 유일한 사용처까지 확인되어
    단일 세션·단일 컨텍스트로 안전하게 완료 가능하다. H0은 최하위 레벨이라 아래 단계 비교 대상이 없다.

agents: []

controller_skills:
  - superpowers:verification-before-completion

agent_skills: {}

context: {}

verification:
  gates_tsv: _workspace/harness/gates.tsv
  local: [fast, feature]
  final: [final]
  manual:
    - "저장 버튼이 시각적으로 brand.blue 색상으로 렌더링되는지 육안 확인 — lint/typecheck/test/build 어느 게이트도 실제 렌더링 색상을 검증하지 않으므로 수용 기준 2번은 게이트로 커버되지 않는다"

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

- **한 단계 아래 레벨을 고르지 않은 이유를 썼는가?** H0은 최하위 레벨이라 해당 없음 — schema 주석대로
  "STEP 1 세 조건을 전부 만족한다"로 갈음했다(위 rationale 참조).
- **카탈로그 7종 밖의 에이전트를 만들지 않았는가?** 예. agents 는 빈 배열이며 새 역할을 만들지 않았다.
- **수용 기준마다 그것을 확인하는 게이트가 verification 에 배정됐는가?** 확인함. 수용 기준 1·3·4는
  `fast`(lint/typecheck) + `feature`(test) + `final`(build) 게이트로 커버된다. 다만 수용 기준 2번
  ("실제로 브랜드 파란색으로 렌더링된다")은 어떤 자동화 게이트도 시각적 색상을 검증하지 않으므로
  `verification.manual` 에 명시적으로 옮겼다 — routing.md의 "게이트 실행 규칙"이 요구하는 대로,
  게이트에 없으면 manual 에 적어 검증 공백을 남기지 않았다.
- **controller_skills 와 agent_skills 를 올바르게 구분했는가?** 예. H0은 에이전트를 스폰하지 않으므로
  agent_skills 는 비어 있다({}). `superpowers:verification-before-completion`은 "전 레벨 필수"이고
  H0~H2에서는 harness-architect 스킬 자신(=controller)이 직접 호출하는 것이 맞으므로 controller_skills
  에 넣었다.

EVAL_VERDICT: level=H0 agents=0 human_gate=false tiers=local:fast,feature|final:final
