# harness-architect 체크리스트 리뷰

- 리뷰 일자: 2026-08-29
- 대상: `harness-architect/` 현재 스냅샷 (`48811b5`)
- 기준: `CHECKLIST.md` A-0~A-4, B-1~B-4
- 범위: 스킬, references, schema/examples/scripts, 에이전트 7종, tests/fixtures/evals, README/CLAUDE
- 판정어: `PASS` / `PARTIAL` / `FAIL` / `UNVERIFIED`

## 최종 판정

**REQUEST CHANGES**

- 독립 code-reviewer: `REQUEST CHANGES`
- 독립 architect: `WATCH`
- 결정론적 B-1 명령은 모두 기대 출력으로 통과했지만, 실제 실행 안전성을 막는 HIGH 이슈가 남아 있다.
- 특히 H0에서 `feature` tier 테스트를 실행하지 않는 문제와, `Edit` 제거만으로는 도구 경계를 강제할 수 없다는 문제가 완료 판정을 신뢰하기 어렵게 만든다.

## 요약

| 구간 | 판정 | 요약 |
|---|---|---|
| A-0 시작 전 | PARTIAL | init 성공/미감지 경로는 검증. 실제 작업의 변경 전 게이트 실행은 작업별 확인 필요 |
| A-1 Phase 2 | PASS | eval 3건에서 6축 근거, 최소 레벨 rationale, 카탈로그 제한 확인 |
| A-2 Phase 3 | UNVERIFIED | 승인 전 spawn 금지를 실제 세션으로 검증한 기록 없음 |
| A-3 Phase 4 | PARTIAL | 규칙은 문서화됐으나 실제 dispatch 0회이고, 실패 횟수 규칙도 2회/3회로 충돌 |
| A-4 Phase 5 | UNVERIFIED | 종료 규칙은 있으나 실제 Phase 5 실행 증거 없음 |
| B-1 결정론적 검증 | PARTIAL | 명령은 전부 통과. 도구 경계의 실효성과 스키마 검증은 통과 명령이 보장하지 않음 |
| B-2 eval | PARTIAL | 기대 결과 3건은 일치. routing 수정 후 01 재실행 증거와 blind-eval 재현 정보 부족 |
| B-3 검증 경계 | UNVERIFIED | 기재된 7개 경계가 그대로 남음. `package.json` 한 줄 형식은 실제 실패 확인 |
| B-4 이식 | PARTIAL | 임시 저장소 복사/init smoke는 통과. superpowers 의존성 설명은 사실과 다름 |

## A. 활용 체크리스트 검토

### A-0 시작 전 — PARTIAL

- `init-workspace.sh`를 임시 작업 공간에서 실행했다.
  - Node fixture: exit 0, 게이트 6개 생성
  - unknown fixture: exit 3, 빈 `gates.tsv` 생성
- 스킬이 프로젝트 루트 상대 경로를 요구하는 것은 `SKILL.md:17`에 명시되어 있다.
- 실제 변경 전 게이트를 손으로 실행해 모두 exit 0인지 확인하는 절차는 개별 작업에서만 검증할 수 있으므로 이번 정적 리뷰에서는 `UNVERIFIED`다.

### A-1 Phase 2 — PASS

- eval 결과 3건 모두 6축별 근거가 있다.
- 01/02/03은 각각 H0/H1/H3이며 카탈로그 밖 에이전트를 만들지 않았다.
- 축 모순 검사 결과 `coupling: high` + `parallelism != none` 조합은 없었다.
- 프로덕션·비가역 작업인 03은 `human_gate.required: true`다.
- H3 rationale은 숨은 의존/베이스라인 오류/구현 오류의 3갈래 재라우팅을 명시한다.

주의: 계약 스키마의 rationale 주석은 반대 방향을 요구한다. 자세한 내용은 M-1을 참고한다.

### A-2 Phase 3 — UNVERIFIED

- 승인 게이트 규칙은 `SKILL.md:44-52`, `SKILL.md:74`에 있다.
- eval은 Phase 3의 YAML을 Markdown 코드 블록으로 보존하지만, 실제 `_workspace/harness/spec.yaml` 생성과 승인 전/후 spawn 이벤트 기록은 없다.
- 따라서 “승인 전에 에이전트가 스폰되지 않았다”는 실제 실행 증거가 없다.

### A-3 Phase 4 — PARTIAL

- 게이트 통과 후 reviewer 호출, 모델 명시, 경로 기반 전달, loop 상한, H2 강등 후 재승인 규칙은 문서에 있다.
- 그러나 Phase 4 및 에이전트 dispatch가 한 번도 실행되지 않아 동작 증거가 없다.
- 같은 게이트 반복 실패 전환 기준이 `routing.md:80`에서는 2회, `CHECKLIST.md:53`, `implementer.md:46`, `orchestrator.md:55`에서는 3회다.
- H2 예제의 controller용 스킬이 실제 호출 권한이 없는 worker에게 배정되어 있다. H-3을 참고한다.

### A-4 Phase 5 — UNVERIFIED

- final gate, verification-before-completion, Human Gate 증거, 자동 commit 금지, `_workspace` 보존은 문서화되어 있다.
- 실제 exit code·출력·중단 이벤트를 남긴 Phase 5 실행 기록은 없다.
- H0 경로는 `feature` tier를 건너뛰므로 final 성공만으로 수용 기준을 충족했다고 볼 수 없다. H-1을 참고한다.

## B-1. 결정론적 검증

| 항목 | 결과 | 근거/비고 |
|---|---|---|
| 스크립트 테스트 | PASS | `=== all tests passed ===`; 22 + 13 = 35 checks |
| YAML 파싱 | PASS | H0~H3 예제 + schema, `OK` 5줄 |
| 예제 축 모순 | PASS | `축 모순 없음` |
| 에이전트 frontmatter 4키 | PASS | 7개 모두 `4/4` |
| catalog ↔ frontmatter | PASS | 7개 model/tools 문자열 일치 |
| 도구 경계 grep | PASS(기계적) / FAIL(실효성) | 기대 `OK` 3줄이나 `Write`/`Bash` 우회가 가능 |
| SKILL.md metrics | PASS | 83줄, frontmatter 303자, references 있음, trigger-first 설명 |
| 참조 경로 실존 | PASS | references 4, schema 1, scripts 3 및 설계 문서 모두 존재 |
| README 수치 | PASS | SKILL 83줄, agents 7, fixtures 5, checks 35 |

추가 정적 검증: 모든 shell 파일에 `bash -n` 통과.

## B-2. 판정 품질 eval

| 항목 | 결과 | 근거/비고 |
|---|---|---|
| 결과 3건 기대값 일치 | PASS | 01 H0/0/false, 02 H1/2/false, 03 H3/7/true |
| routing/profiling 수정 후 3건 재실행 | FAIL | git 이력과 `evals/README.md:29-30`은 02·03 재실행만 증명. 01 재실행 기록 없음 |
| 새 eval에 기대값 비공개 | UNVERIFIED | 방법은 적혀 있으나 실행 prompt/model/session 메타데이터가 없어 독립 재현 불가 |
| 실패 기록 보존 | PASS | `03-jwt-to-oauth.v1-FAILED.md:1-10`에 폐기 배너와 원인 보존 |

## B-3. 아직 검증되지 않은 것

| 항목 | 결과 | 이번 리뷰의 추가 확인 |
|---|---|---|
| H2 선택 eval | UNVERIFIED | H2 YAML 예제만 있고 판정 eval은 H0/H1/H3뿐 |
| Phase 4 end-to-end | UNVERIFIED | 실행 기록 없음 |
| 에이전트 7종 실제 dispatch | UNVERIFIED | 실행 기록 없음 |
| 실제 lint/type/test gate | UNVERIFIED | 테스트는 `echo`/의도적 exit 중심 |
| 실제 프로젝트 detect-stack | FAIL(부분 실증) | 유효한 한 줄 `package.json`에서 exit 1 확인 |
| `max_loops` 강제 중단 | UNVERIFIED | 문서 규칙뿐이며 실행/자동 검증 없음 |
| Human Gate 강제 중단 | UNVERIFIED | 문서 규칙뿐이며 실행/자동 검증 없음 |

## B-4. 이식성

| 항목 | 결과 | 근거/비고 |
|---|---|---|
| 두 경로만 복사 | PASS(smoke) | 임시 저장소에 skill + agents만 복사 |
| 절대 경로 없음 | PASS | `.claude/`에서 `/home/`, `/Users/` 검색 결과 없음 |
| 이식 저장소 init | PASS(smoke) | 임시 Node 저장소에서 exit 0, agents 7, gates 6 |
| superpowers 설치/의존성 | FAIL(문서 계약) | 현재 환경의 위임 스킬 12종은 존재하지만, “없어도 H0/H1 동작” 설명은 실제 필수 호출과 충돌 |

## 주요 발견

### [HIGH] H-1. H0가 `feature` tier 테스트를 실행하지 않는다

- `SKILL.md:57`과 `routing.md:75-78`은 H0에서 `fast` 다음 `final`만 실행한다.
- `detect-stack.sh:64-66`은 일반 테스트를 `feature` tier로 분류한다.
- eval 01의 수용 기준은 `npm run test` 통과를 요구하지만(`evals/results/01-button-color.md:62`), 생성된 spec은 `local: [fast]`, `final: [final]`뿐이다(`:91-92`).
- `run-gates.sh:65-67`은 요청 tier에 명령이 없어도 성공 처리한다.

영향: 테스트가 실행되지 않았는데 H0가 완료를 선언할 수 있다.

제안: HarnessSpec에 선언된 필수 tier를 모두 실행하고, 수용 기준에 연결된 gate가 미배정/빈 tier이면 실패시키는 검증기를 추가한다. “feature test만 존재하고 final은 비어 있는 H0” 회귀 테스트를 먼저 추가한다.

### [HIGH] H-2. `Edit` 제거가 쓰기 경계를 강제하지 않는다

- `reviewer`와 `orchestrator`는 `Edit`이 없지만 `Write`와 `Bash`가 있다(`reviewer.md:6`, `orchestrator.md:6`).
- `dependency-mapper`도 `Bash`가 있어 redirection, `sed -i` 등으로 파일을 바꿀 수 있다(`dependency-mapper.md:6`).
- 그런데 catalog와 SKILL은 “Edit 없음”을 도구 수준 강제라고 표현한다(`catalog.md:17-27`, `SKILL.md:82`).

영향: 독립 reviewer와 read-only mapper/orchestrator라는 핵심 안전 경계가 prompt 준수에만 의존한다.

제안: 보고서 저장을 호출자 책임으로 옮겨 worker의 `Write`를 제거하고, Bash를 read-only allowlist wrapper로 좁히거나 PreToolUse hook/권한 규칙으로 소스 경로 쓰기를 차단한다. 각 역할이 소스 쓰기를 시도했을 때 거부되는 negative test를 추가한다.

### [HIGH] H-3. controller용 스킬이 호출 권한 없는 worker에 배정된다

- schema의 `skills`는 에이전트별 주입 구조다(`schemas/harness-spec.yaml:37-39`).
- H2 예제는 `dispatching-parallel-agents`를 `dependency-mapper`에, `subagent-driven-development`를 `implementer`에 배정한다(`examples/h2-fanout.yaml:51-54`).
- 두 에이전트 모두 `Agent` 도구가 없고 implementer는 서브에이전트 금지를 명시한다(`implementer.md:21`).
- 반면 H2 실행 절차는 이 스킬들을 controller가 호출해야 성립한다(`routing.md:99-104`).

영향: H2의 조사 fan-out과 SDD task loop가 HarnessSpec대로는 실행되지 않을 수 있다.

제안: `controller_skills`와 `agent_skills`를 분리하고, controller 스킬은 harness-architect/orchestrator가 소유하도록 schema·예제·catalog를 일치시킨다.

### [HIGH] H-4. superpowers 의존성 설명이 실제 계약보다 약하다

- `CHECKLIST.md:163-164`는 superpowers가 없으면 H2/H3만 끊기고 H0/H1은 동작한다고 한다.
- 그러나 H0도 `verification-before-completion`이 필수다(`routing.md:78`).
- H1은 TDD, code review, verification-before-completion을 요구한다(`routing.md:87-95`).

영향: 이식 후 낮은 레벨도 필수 서브스킬 누락으로 중단될 수 있다.

제안: 모든 레벨의 실제 최소 의존성을 명시하거나, H0/H1에 로컬 fallback 절차를 제공한다. 이식 smoke에서 필수 스킬 discovery까지 검사한다.

### [HIGH] H-5. H3 구성 계약이 서로 다르다

- README는 H3 에이전트를 `≤6`으로 설명한다(`README.md:28`).
- canonical H3 예제는 integrator 없이 6개 역할을 둔다(`examples/h3-orchestrator.yaml:39-57`).
- routing은 H3를 “H2 절차 + orchestrator”로 정의하여 integrator를 상속한다(`routing.md:97-116`).
- 최신 eval은 integrator를 포함한 7개 에이전트를 사용한다(`evals/results/03-jwt-to-oauth.md:126-147`; `evals/README.md:27`).

영향: H3 spec 작성자가 integrator를 빼거나 에이전트 상한을 위반하는 상반된 결과를 낼 수 있다.

제안: “선택 역할 총수”와 “동시 worker 상한”을 분리해 정의하고, H3 example/README/eval 중 하나의 canonical 구성을 선택해 모두 동기화한다.

### [MEDIUM] M-1. rationale 방향이 schema에서 반대로 적혀 있다

- CHECKLIST와 SKILL은 “한 단계 아래가 왜 안 되는지”를 요구한다(`CHECKLIST.md:26`, `SKILL.md:42`).
- schema 주석은 “한 단계 위를 고르지 않은 이유”를 요구한다(`schemas/harness-spec.yaml:30`).

제안: 최소 하네스 원칙에 맞춰 schema를 “선택한 레벨보다 한 단계 아래가 불충분한 이유”로 고친다. H0는 하위 레벨 없음 예외를 명시한다.

### [MEDIUM] M-2. `detect-stack.sh`가 유효한 한 줄 `package.json`을 놓친다

- parser는 `"scripts": {`가 있는 줄을 찾은 뒤 그 줄 전체를 건너뛴다(`detect-stack.sh:22-35`).
- `{"scripts":{"lint":"eslint .","test":"vitest run"}}`을 준 probe는 exit 1이었다.

제안: Python/Node의 표준 JSON parser를 사용하거나 지원 형식을 명확히 제한한다. 한 줄 scripts, scripts 뒤 중첩 객체, brace가 든 command 문자열을 fixture에 추가한다.

### [MEDIUM] M-3. 반복 실패 기준과 risk/Human Gate 설명이 일치하지 않는다

- 같은 gate 실패 기준은 2회와 3회로 나뉜다(`routing.md:80` 대 `CHECKLIST.md:53`).
- `routing.md:49`와 `CHECKLIST.md:37`은 risk가 Human Gate를 바꾼다고 쓰지만 STEP 5는 side effect/production/secret/delete만 본다(`routing.md:36-39`).

제안: 상수와 조건을 schema 한 곳에서 정의하고 모든 문서·agent prompt가 그 값을 참조하게 한다.

### [MEDIUM] M-4. “schema parse PASS”는 계약 검증이 아니다

- `schemas/harness-spec.yaml`은 주석이 달린 예제 YAML이며 unknown agent, 누락 model, 잘못된 enum, 축 모순을 기계적으로 거부하지 않는다.
- 현재 B-1은 `yaml.safe_load` 성공만 확인한다.

제안: 외부 의존성 없이 Python validator를 추가해 enum, 필수키, agent catalog, model, context guard, H0/H1/H2/H3 불변식을 검사한다.

### [MEDIUM] M-5. routing 수정 후 전체 회귀 eval 증거가 없다

- git 이력은 02(`4ed4670`)와 03(`f535fae`) 재실행만 남긴다.
- 01은 H0 과대 오케스트레이션 방지 케이스이므로 routing 수정 후 반드시 함께 재실행해야 한다.

제안: eval 입력, 사용한 skill revision, model, prompt, 원시 출력, 판정 결과를 한 명령으로 재생성하고 세 케이스를 묶어 gate화한다.

### [LOW] L-1. 설명과 성공 수치 표현을 더 정확히 할 수 있다

- SKILL frontmatter description은 trigger로 시작하지만 6축→HarnessSpec→승인 workflow까지 요약한다. 스킬 discovery 지침상 trigger/symptom만 남기는 편이 안전하다.
- README의 “35 assertion”은 helper assertion과 수동 `if` check를 합친 수치다. “35 validation checks”가 더 정확하다.
- README의 “A~D 전 항목 pass”는 현재 PARTIAL/UNVERIFIED 경계와 맞지 않는다(`README.md:83-87`).

## 개선 우선순위

### P0 — 완료 판정과 안전 경계

1. H0 포함 모든 레벨에서 HarnessSpec의 필수 gate tier를 빠짐없이 실행하고 빈 필수 tier를 실패 처리한다.
2. reviewer/mapper/orchestrator의 소스 쓰기를 실제 권한 또는 hook으로 차단한다.
3. controller 스킬과 agent 주입 스킬을 schema에서 분리한다.
4. H3 구성 수와 superpowers 의존성 문서를 하나의 계약으로 동기화한다.

### P1 — 실행 증거

1. H0/H1/H2/H3 각각 Phase 0~5 end-to-end eval을 추가한다.
2. 승인 전 spawn 거부, `max_loops` 중단, Human Gate 중단을 이벤트 로그로 검증한다.
3. 실제 Node/Python 프로젝트에서 detect → fast/feature/final gate를 실행한다.
4. HarnessSpec validator와 malformed-spec negative tests를 추가한다.

### P2 — 견고성·문서 품질

1. `package.json` parsing을 표준 JSON parser로 교체하고 경계 fixture를 추가한다.
2. 실패 횟수/risk/Human Gate/rationale 문구를 단일 source of truth로 정리한다.
3. frontmatter description을 trigger-only로 줄이고 README 수치를 `validation checks`로 표현한다.

## 실행한 검증

```text
bash tests/run-all.sh
  PASS 35 / FAIL 0

YAML parse
  OK h0-single.yaml
  OK h1-pipeline.yaml
  OK h2-fanout.yaml
  OK h3-orchestrator.yaml
  OK harness-spec.yaml

axis invariant
  축 모순 없음

agent frontmatter
  7개 모두 4/4

catalog consistency
  7개 모두 PASS

tool-boundary grep
  OK reviewer / OK orchestrator / OK dependency-mapper

skill metrics
  line_count 83 / frontmatter_chars 303 / has_references_dir yes

bash -n
  PASS

init smoke
  known exit 0, gates 6 / unknown exit 3, gates 0

portable-copy smoke
  exit 0, agents 7, gates 6

one-line package.json probe
  exit 1 (결함 재현)
```

테스트 실행 중 `pyenv` shim 디렉터리 쓰기 경고가 출력됐지만 모든 검증 명령의 exit code와 assertion 결과는 성공이었다. 이 경고는 harness 테스트 실패로 계산하지 않았다.

## 남은 위험

- 실제 Claude agent dispatch와 Human Gate를 실행하지 않았으므로 prompt 준수율은 확인되지 않았다.
- 프로덕션/외부 시스템 동작은 수행하지 않았다.
- 이번 결과는 현재 스냅샷 리뷰이며, 수정 후에는 B-1 전체와 H0~H3 eval을 다시 실행해야 한다.
