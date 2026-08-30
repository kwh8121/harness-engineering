# Linear 추적 — 진행 상황을 사람이 읽을 수 있는 곳에 남긴다

목적은 하나다: **사용자가 터미널을 보지 않고도 진행 상황과 검증 근거를 정확히 파악하는 것.**
Linear 를 작업 로그 덤프장으로 쓰는 것이 아니다.

## 언제 쓰지 않는가

- **H0 은 기록하지 않는다.** 단일 파일·저위험 변경까지 이슈를 만들면 백로그가 오탈자 수정으로 찬다.
  Linear 문서의 원칙("이슈 하나의 적정 크기")과 어긋난다.
- `tracking.provider: none` 이면 전 레벨에서 아무것도 쓰지 않는다.
- **Linear 쓰기 실패는 작업을 멈추지 않는다.** MCP 미연결·권한 오류·네트워크 실패는 사용자에게
  한 줄로 알리고 하네스는 계속 진행한다. 추적은 관측 수단이지 실행 경로가 아니다.

## 누가 쓰는가 — 컨트롤러만

**워커는 Linear 를 건드리지 않는다.** H3 의 `orchestrator` 도 마찬가지다.
모든 Linear 쓰기는 harness-architect 스킬을 돌리는 세션(컨트롤러)이 한다.

이유는 셋이다.
1. 워커 `tools` 에 MCP 도구를 넣으면 이식성이 깨진다 (Linear 없는 저장소에서 정의가 무효가 된다).
2. 워커가 진행 상황을 자기 관점으로 쓰기 시작하면 같은 사실이 여러 번, 다르게 기록된다.
3. 쓰는 주체가 하나면 경쟁 조건이 없다.

워커는 상태 토큰(`STATUS:` / `VERDICT:` / `INTEGRATION:` …)만 반환하고,
컨트롤러가 그것을 Linear 상태 전환으로 번역한다. H3 에서 `orchestrator` 는 DAG 상태를
`_workspace/harness/dag.md` 에 남기고, 컨트롤러가 그 파일을 읽어 동기화한다.

## 엔티티 매핑

| 하네스 | Linear | 근거 |
|---|---|---|
| H1 작업 전체 | **Issue** 1개 | 작업 단위가 1개다 (판정 트리 STEP 2). 프로젝트로 만들 만한 공유 성과물이 아니다 |
| H2/H3 작업 전체 | **Project** | 여러 이슈를 하나의 성과물로 묶는 것이 Project 의 정의다 |
| H2 워커 단위 / H3 DAG 노드 | Project 하위 **Issue** | 각 단위가 독립적으로 완료 판정된다 |
| 한 단위 안의 세부 갈래 | **Sub-issue** (`parentId`) | "단일 이슈로는 크고 프로젝트로는 작을 때" — Linear 문서 원칙 |
| H3 DAG 의 `depends_on` | **`blockedBy` / `blocks`** | Linear 가 의존을 네이티브로 표현한다. 별도 기술 금지 |
| H3 의 단계 묶음 | **Milestone** | 프로젝트 *안*의 완료 단계 |
| HarnessSpec | Project(또는 Issue) **description** | 레벨·근거·에이전트·게이트·상한을 한 화면에 |
| 게이트 결과 | **Comment** (명령 + exit code + 로그 경로) | 검증 근거 |
| reviewer 발견 | **Comment** (VERDICT + blocking 발견) | 미해결 BLOCKER 는 별도 sub-issue 로 승격 |
| Human Gate | 상태 `In Review` + 증거 Comment | 사람이 무엇을 승인하는지 보이게 |

`Cycle` 과 `Initiative` 는 쓰지 않는다. 하네스는 팀의 계획 주기나 전략 층을 모른다 —
사용자가 나중에 붙일 수 있게 비워 둔다.

## 상태 매핑

Linear 의 `Triage` 는 "백로그에 묻히지 않도록 새 작업을 의도적으로 검토하는" 상태다.
Phase 3 의 승인 게이트와 개념이 같으므로 그대로 쓴다.

| 하네스 시점 | Linear 상태 | 전환 조건 |
|---|---|---|
| Phase 3 — spec 작성·검증 완료, 승인 대기 | `Triage` | `validate-spec.py` exit 0 |
| Phase 3 — 승인됨, 착수 전 | `Todo` | 사용자 승인 |
| Phase 4 — 구현 중 | `In Progress` | implementer dispatch |
| Phase 4 — 게이트 통과, 리뷰 중 | `In Review` | `run-gates.sh` 전부 exit 0 |
| Phase 5 — 완료 | `Done` | 최종 게이트 통과 + `verification-before-completion` |
| 중단·강등 | `Canceled` | 레벨 강등(H2→H1) 또는 사람이 중단 |

**하위 이슈가 전부 Done 이면 부모를 Done 으로 올린다.** 팀 설정에 parent auto-close 가
켜져 있으면 Linear 가 알아서 한다 — 그때는 컨트롤러가 중복으로 올리지 않는다.

**이 상태들은 작업 공간 정리를 트리거하지 않는다.** `Canceled` 는 폐기뿐 아니라 **강등**
(H2→H1, 이때 작업은 계속된다)을 포함하고, `Done` 은 최종 게이트 통과 시점이라 브랜치 통합
(Phase 5 4단계)보다 **먼저** 찍힌다. 정리 시점은 `superpowers:finishing-a-development-branch`
의 통합 선택이 정하고, Linear 상태는 정리를 **억제**하는 가드로만 읽는다 —
`references/routing.md` 의 "작업 공간 정리" 참고.

## 기록 시점 — Phase 전환마다 코멘트 1건

| 시점 | 무엇을 쓰는가 |
|---|---|
| Phase 3 생성 | description 에 spec 요약 (레벨 + 판정 근거 / 에이전트와 모델 / 게이트 / `max_loops` / Human Gate) |
| 승인 | 상태 `Triage`→`Todo`. 코멘트 없음 (상태 변경이 곧 기록) |
| 단위 착수 | 상태 `Todo`→`In Progress` |
| 게이트 실행 | 코멘트 1건: `gate-summary.sh` 출력 (tier / 명령 / exit code / 로그 경로) |
| 리뷰 종료 | 코멘트 1건: `VERDICT` 한 줄 + blocking 발견 목록 (본문 아님, 제목 + 파일:라인) |
| 리뷰 루프 초과 | 코멘트 1건 + 미해결 발견을 sub-issue 로 승격 + 부모는 `In Review` 유지 |
| Human Gate | 코멘트 1건: 게이트 로그 경로 + `git diff --stat` + 롤백 절차 |
| 완료 | 상태 `Done` + 코멘트 1건: 최종 게이트 결과와 수용 기준 대응 |

**노이즈 방지 규칙**
- 게이트 로그 **전문을 붙이지 않는다.** 명령·exit code·로그 경로만. 전문은 `_workspace/` 에 있다.
- 같은 사실을 두 번 쓰지 않는다. 상태 변경으로 표현되는 것은 코멘트로 반복하지 않는다.
- 실패한 시도마다 코멘트를 남기지 않는다. 리뷰 루프는 **종료 시 1건**으로 요약한다.
- 에이전트 프롬프트·세션 히스토리·보고서 본문을 붙이지 않는다 (컨텍스트 예산 규칙과 같다).

## Human Gate 승인 경로

`tracking.human_gate_approval` 이 정한다.

- `terminal` (기본) — 대화에서 승인받는다. Linear 에는 상태와 증거만 남는다.
- `linear` — 상태를 `In Review` 로 두고 사용자가 Linear 에서 `Todo` 로 바꿀 때까지 기다린다.
  컨트롤러가 `list_issues` 로 확인한다. **폴링 간격은 사용자가 정하고, 무한 대기하지 않는다** —
  대기 상한에 도달하면 사용자에게 알리고 멈춘다.
- `both` — 기본은 터미널. 사용자가 자리를 비운다고 말하면 `linear` 로 전환한다.

## 사용자가 진행을 파악하는 방법

이 매핑의 결과로 사용자는 Linear 에서 이것들을 얻는다.

- **지금 어디까지 왔나** — Project 진행률(하위 이슈 Done 비율), 각 이슈의 상태
- **무엇이 막고 있나** — `blockedBy` 그래프. 어떤 노드가 선행 작업을 기다리는지
- **왜 통과라고 하는가** — 게이트 코멘트의 명령과 exit code. 주장이 아니라 증거
- **무엇이 남았나** — 미해결 BLOCKER 가 승격된 sub-issue
- **내가 무엇을 승인해야 하나** — `In Review` 상태 + Human Gate 코멘트
