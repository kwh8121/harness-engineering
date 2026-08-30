# Task Profiler — 6축 판정

라우팅 전에 이 6개 축만 판정한다. "복잡해 보인다" 같은 총평은 금지다.
각 축은 **레포에서 확인 가능한 근거 한 줄**과 함께 기록한다 — 근거를 못 쓰면 그 축은 아직 모르는 것이고,
모르는 축이 `uncertainty` 를 올린다.

| 축 | 판정 질문 | 값 | 하네스에 미치는 영향 |
|---|---|---|---|
| `scope` | 변경이 닿는 영역이 몇 개인가? | `single` / `few`(2–3) / `many`(4+) | 에이전트 수 |
| `coupling` | 변경 사이에 의존이 있는가? | `low` / `medium` / `high` | DAG 필요성 |
| `parallelism` | 독립 실행 가능한 작업이 몇 개인가? | `none` / `some`(2–3) / `high`(4+) | Fan-out 여부 |
| `uncertainty` | 기존 구조·동작이 불명확한가? | `low` / `medium` / `high` | dependency-mapper·baseline-tester 필요성 |
| `risk` | auth·DB·결제·보안·배포를 건드리는가? | `low` / `medium` / `high` | reviewer·리뷰 루프 상한 |
| `side_effect` | 프로덕션·외부 시스템을 바꾸는가? | `none` / `reversible` / `irreversible` | Human Gate |

## 축별 판정 규칙

**scope** — 디렉터리 개수가 아니라 **책임 영역** 개수다. `components/Button.tsx` 와 `components/Button.test.tsx`
는 1개다. FE 컴포넌트 + API 핸들러 + 스토리지 연동은 3개다.

**coupling** — "A 를 먼저 끝내지 않으면 B 를 시작할 수 없는가?"가 `high`.
"A 와 B 가 같은 파일을 고치는가?"도 `high` (병합 충돌은 의존과 같은 효과를 낸다).
서로의 존재를 몰라도 되면 `low`.

**parallelism** — `coupling: low` 인 작업 단위의 개수다. `coupling: high` 면 `parallelism` 은 자동으로
`none` 이다. 이 둘이 동시에 높을 수 없다.

> **주의**: `parallelism: none` 은 **작업 단위가 1개라는 뜻이 아니다.** 동시에 못 돌린다는 뜻일 뿐이다.
> 순서 의존으로 묶인 단위 3개도 `parallelism: none` 이고, 그것이 바로 DAG(H3)가 필요한 형태다.
> 단위 개수는 `parallelism` 이 아니라 "구현자 한 명이 한 번에 끝까지 들고 갈 수 있는가"로 센다
> (`routing.md` STEP 2).

**uncertainty** — 다음 중 하나라도 해당하면 최소 `medium`:
- 변경 대상의 현재 동작을 고정하는 테스트가 없다
- 호출부를 전부 열거할 수 없다
- 레거시 코드이고 주석·문서가 실제와 다를 가능성이 있다

`high` 면 **레벨과 무관하게** `dependency-mapper` 와 `baseline-tester` 를 먼저 돌린다.
이 둘은 서로 독립이므로 한 메시지에서 동시에 dispatch 한다 (Fan-out 의 대표 구간).

**risk** — 접촉면으로 판정한다. 추측 금지:
- `high`: 인증·인가, 개인정보, 결제, 스키마 변경, 배포 파이프라인
- `medium`: 서버 측 검증 로직, 공개 API 시그니처, 캐시·세션
- `low`: 표현 계층, 문서, 내부 유틸

**side_effect** — 되돌릴 수 있는가로 판정한다:
- `irreversible`: 프로덕션 DB 마이그레이션, 외부 시스템 상태 변경, 시크릿 회전, 데이터 삭제
- `reversible`: 스테이징 배포, 피처 플래그 토글
- `none`: 로컬 코드 변경만

## 입력이 부족할 때

`task.goal` 만 주어진 것이 정상이다. 나머지 5필드는 레포를 읽어 채운다.
**사용자에게 묻는 것은 답에 따라 레벨 판정이나 Human Gate 여부가 달라지는 항목뿐이다.**

- 물어야 함: "이걸 프로덕션에 반영하나요?" (→ `side_effect`, Human Gate가 뒤집힘)
- 묻지 말 것: "어떤 파일을 고칠까요?" (→ 레포를 읽어서 답할 수 있음)

목표 자체가 불명확해 수용 기준을 쓸 수 없으면 프로파일링을 중단하고
**REQUIRED SUB-SKILL:** Use superpowers:brainstorming 으로 넘어간다.
