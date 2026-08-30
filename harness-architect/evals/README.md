# 라우팅 판정 eval

`harness-architect` 의 핵심 위험은 **Over-Orchestration**(작은 작업에 큰 하네스)과
**Under-Orchestration**(위험한 작업에 단일 에이전트) 두 방향이다.
이 eval 은 세 개의 대표 작업으로 판정이 양쪽으로 흔들리지 않는지 확인한다.

## 방법

각 작업 입력을 **기대 레벨을 알려주지 않은 채** 서브에이전트에게 주고,
`.claude/skills/harness-architect/` 의 SKILL.md + references 만으로 Phase 0~3 을 수행하게 한다.
산출된 `level` / `agents` / `human_gate` 를 기대값과 대조한다.

## 케이스

| 입력 | 기대 level | 기대 에이전트 | 기대 human_gate |
|---|---|---|---|
| `inputs/01-button-color.md` | H0 | 0개 | false |
| `inputs/02-profile-upload.md` | H1 | implementer + reviewer | false |
| `inputs/03-jwt-to-oauth.md` | H3 | orchestrator 포함 | true |

## 결과 (2026-08-29)

| 케이스 | 기대 | 실측 level | 실측 agents | 실측 human_gate | 판정 |
|---|---|---|---|---|---|
| 01 버튼 색상 | H0 / 0개 / false | H0 | 0 | false | 일치 |
| 02 이미지 업로드 | H1 / implementer+reviewer / false | H1 | 2 (implementer, reviewer) | false | 일치 |
| 03 JWT→OAuth | H3 / orchestrator 포함 / true | H3 | 7 (카탈로그 전체) | true | 일치 |

케이스 03 은 **트리 수정 후 2차 실행** 결과다. 1차는 H1 을 냈다 (아래 참조).
케이스 02 는 트리 수정에 대한 회귀 확인으로 재실행했으며 H1 을 유지했다.

세 케이스 모두 카탈로그 7종 밖의 역할을 만들지 않았고, `rationale` 에 한 단계 아래를 고르지
않은 이유를 포함했다.

`results/` 에 각 실행의 판정 근거를 기록한다. 기대와 다르면 `references/routing.md` 의
판정 문구를 조이고 재실행한다.

### 1차 실행에서 잡힌 결함 (2026-08-29)

케이스 03(JWT→OAuth)이 기대값 H3 대신 **H1** 을 냈다. 에이전트가 규칙을 어긴 것이 아니라
**판정 트리 자체가 틀렸다.**

당시 STEP 2 는 "독립 실행 가능 작업 단위가 1개(= `parallelism: none`)면 H1" 이었고,
`profiling.md` 의 "`coupling: high` 면 `parallelism` 은 자동으로 `none`" 규칙과 맞물려
**순서 의존이 강한 작업이 전부 H1 으로 흡수됐다.** H3 의 조건은 병렬성이 아니라
순서 의존 + 실패 원인별 재라우팅인데, 트리가 그 경로를 막고 있었다.

수정 내용:
- `routing.md` STEP 2 를 "구현자 한 명이 한 번에 끝까지 들고 갈 수 있는가"로 교체
- STEP 3 이 H2 후보 여부만 가르고, 순서 의존이면 STEP 4 로 넘어가도록 경로 추가
- **강등을 막는 반례** 3종과 교차 점검 규칙 추가
  (`uncertainty: high` + `risk: high` + 단위 2개 이상이면 H1 은 거의 항상 오답)
- `profiling.md` 의 `parallelism` 설명에 "none 이 단위 1개를 뜻하지 않는다" 주의 추가

1차 기록은 `results/03-jwt-to-oauth.v1-FAILED.md` 에 폐기 배너와 함께 보존했다.
Over-Orchestration 반례만 적고 Under-Orchestration 반례를 빠뜨리면 반대 방향으로 틀린다는
것이 이 eval 의 실제 수확이다.
