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

## 결과

`results/` 에 각 실행의 판정 근거를 기록한다. 기대와 다르면 `references/routing.md` 의
판정 문구를 조이고 재실행한다.
