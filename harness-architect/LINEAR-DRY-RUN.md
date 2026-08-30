# Linear 추적 리허설 — 눈으로 확인하는 체크리스트

가상의 작업 하나를 끝까지 돌려 **`Triage → Todo → In Progress → In Review → Done`** 전체 경로와
게이트 코멘트가 실제로 어떻게 보이는지 확인한다.

**목적은 두 가지다.**
- 에이전트: 매핑과 상태 전환이 `references/linear-tracking.md` 계약대로 동작하는지
- 사용자: **Linear 화면만 보고 진행과 근거를 실제로 파악할 수 있는지**

각 단계는 `에이전트가 할 일` / `사용자가 화면에서 확인할 것` / `통과 기준` 세 칸으로 되어 있다.
사용자가 확인할 것이 없는 단계는 넣지 않았다 — 그런 단계는 이 리허설의 목적이 아니다.

---

## 시작 전

- [ ] Linear MCP 가 연결되어 있다 (`get_workspace` 가 워크스페이스를 반환한다)
- [ ] 대상 팀을 정했다. 이 문서는 `Koreatimes` 를 예로 쓴다
- [ ] **이 리허설은 실제 워크스페이스에 실제 데이터를 만든다.** 팀원에게 보인다는 것을 알고 있다
- [ ] 모든 제목에 `[DRY-RUN]` 접두사를 붙인다. 정리 단계에서 찾기 위해서다

> 게이트 로그는 `fixtures/dry-run/gates/` 에 준비되어 있다. 실제 프로젝트를 빌드하지 않고도
> 코멘트가 어떻게 보이는지 확인할 수 있다. 리허설 내내 이 픽스처를 쓴다.

---

# 1부 — H1 리허설 (Issue 1건, 필수)

가장 단순한 경로다. **작업 단위가 1개이므로 Project 를 만들지 않는다** (Linear 의 "이슈 하나의
적정 크기" 원칙). 상태 5단계와 게이트 코멘트를 전부 여기서 본다.

## 단계 1 — 이슈 생성 (Triage)

**에이전트**
```
save_issue(
  team: "Koreatimes",
  title: "[DRY-RUN] 프로필 이미지 업로드 추가",
  state: "Triage",
  description: <아래 본문>
)
```

description 본문 — Phase 3 의 spec 요약이 그대로 들어간다:

```markdown
## 하네스 판정
**H1 / pipeline** — FE 폼·업로드 API·스토리지 연동이 하나의 흐름으로 묶여 구현자 한 명이
통째로 들고 가야 하므로 단위는 1개다(STEP 2). H0 은 변경 영역이 3개라 불가.

| 축 | 값 |
|---|---|
| scope | few (frontend / api / storage) |
| coupling | high |
| parallelism | none |
| uncertainty | low |
| risk | medium |
| side_effect | none |

## 에이전트
- `implementer` (sonnet) — 업로드 UI·API·스토리지 연동을 테스트 우선으로 구현
- `reviewer` (opus) — 수용 기준 충족과 검증 로직 회귀를 diff 기준으로 심사

## 검증
- local: `fast`, `feature` / final: `final`
- 리뷰 루프 상한: 2 (blocking = BLOCKER, MAJOR)
- Human Gate: 불필요 (side_effect none, local 환경)

## 수용 기준
- [ ] 이미지를 업로드하면 프로필에 반영된다
- [ ] 허용되지 않은 타입·크기는 4xx 로 거절된다
- [ ] 기존 프로필 저장 테스트가 계속 통과한다
```

**사용자 확인**
- [ ] 이슈가 **`Triage`** 컬럼에 있다 (백로그가 아니다)
- [ ] description 만 읽고 **"무엇을, 왜 이 구조로 하는지"** 가 파악된다
- [ ] "한 단계 아래(H0)가 왜 안 되는지" 가 적혀 있다

**통과 기준**: 이슈 링크를 열었을 때 터미널을 보지 않고도 착수 전 판단이 가능하다.
description 이 무슨 말인지 모르겠다면 그건 spec 요약 포맷의 문제이지 사용자의 문제가 아니다.

## 단계 2 — 승인 (Triage → Todo)

**에이전트**: 사용자 승인을 받은 뒤 `save_issue(id: "KOR-xxx", state: "Todo")`.
**코멘트를 남기지 않는다** — 상태 변경이 곧 기록이다.

**사용자 확인**
- [ ] 이슈가 `Todo` 로 이동했다
- [ ] 승인 사실을 알리는 **중복 코멘트가 없다**

**통과 기준**: 활동 로그의 상태 변경 기록만으로 "언제 승인됐는지" 를 알 수 있다.

## 단계 3 — 착수 (Todo → In Progress)

**에이전트**: `implementer` dispatch 직전에 `save_issue(id: "KOR-xxx", state: "In Progress")`.

**사용자 확인**
- [ ] `In Progress` 로 이동했다
- [ ] 이 시점에 게이트 코멘트가 **아직 없다** (아직 아무것도 검증하지 않았다)

## 단계 4 — 게이트 실패 코멘트 ★ 이 리허설의 핵심

**에이전트**
```
bash .claude/skills/harness-architect/scripts/gate-summary.sh feature fixtures/dry-run/gates
→ 출력을 save_comment(issueId: "KOR-xxx", body: <출력 그대로>)
```

**Linear 에 이렇게 보여야 한다:**

> **게이트 `feature` — 0/1 통과**
>
> | 명령 | 결과 |
> |---|---|
> | `npm run test` | **exit 1** |
>
> 1 건 실패. 전체 출력: `fixtures/dry-run/gates/feature.log`

**사용자 확인**
- [ ] **실행한 명령**과 **exit code** 가 보인다 — "테스트 실패" 같은 요약이 아니라 근거다
- [ ] 실패가 **굵게** 표시되어 훑어볼 때 눈에 띈다
- [ ] **스택트레이스·assertion 메시지가 없다.** `AssertionError: expected 200 to be 413` 같은
      본문이 코멘트에 있으면 **실패다** — 전문은 로그 경로가 가리킨다
- [ ] 이슈 상태가 아직 `In Progress` 다 (게이트가 깨졌으니 리뷰로 넘어가지 않았다)

**통과 기준**: 코멘트 3줄만 보고 "무엇이 실행됐고 무엇이 깨졌는지" 를 안다.
전문이 필요하면 로그 경로로 간다.

> **왜 전문을 안 붙이는가**: 실패 스택트레이스를 이슈에 쏟으면 사람이 코멘트를 읽지 않게 되고,
> 정작 필요할 때 못 찾는다. 이 규칙은 `tests/test-gate-summary.sh` 가 강제한다 —
> 로그 본문이 출력에 새면 테스트가 실패한다.

## 단계 5 — 게이트 통과 (In Progress → In Review)

**에이전트**: 수정 후 `fast`·`feature` 재실행. 전부 통과하면 코멘트 1건 + `state: "In Review"`.

`fast` 코멘트는 이렇게 보인다:

> **게이트 `fast` — 2/2 통과**
>
> | 명령 | 결과 |
> |---|---|
> | `npm run lint` | exit 0 |
> | `npm run typecheck` | exit 0 |
>
> 전체 출력: `fixtures/dry-run/gates/fast.log`

**사용자 확인**
- [ ] 게이트가 통과한 **뒤에** `In Review` 로 넘어갔다 (순서가 뒤바뀌면 실패다)
- [ ] 전부 통과했을 때 코멘트에 **"실패" 라는 단어가 없다**
- [ ] 실패했던 게이트를 재실행한 코멘트가 **새로 1건** 쌓였다 (기존 코멘트를 고치지 않았다)

**통과 기준**: 코멘트를 시간순으로 훑으면 "깨졌다 → 고쳤다 → 통과했다" 가 읽힌다.

## 단계 6 — 리뷰 코멘트

**에이전트**: `reviewer` 종료 시 **코멘트 1건**으로 요약한다. 루프를 돌았어도 종료 시 1건이다.

```markdown
**리뷰 — `VERDICT: PASS`**

수용 기준 3/3 충족. blocking(BLOCKER·MAJOR) 발견 0건.

| 심각도 | 위치 | 요약 |
|---|---|---|
| MINOR | `src/api/avatar.ts:31` | 에러 메시지에 허용 크기를 넣으면 디버깅이 쉬워진다 |

전체 보고서: `_workspace/harness/review/report.md`
```

**사용자 확인**
- [ ] `VERDICT` 한 줄이 맨 위에 있다
- [ ] blocking 발견은 **제목 + 파일:라인** 만 있다 (보고서 본문을 붙이지 않았다)
- [ ] MINOR·NIT 가 **루프를 막지 않았다** (있어도 `In Review` 를 통과한다)
- [ ] 리뷰를 2회 돌았다면 코멘트는 여전히 **1건**이다

**통과 기준**: "고쳐야 하는 것"과 "권고"가 한눈에 구분된다.

## 단계 7 — 완료 (In Review → Done)

**에이전트**: `final` 게이트 → `verification-before-completion` → `state: "Done"` + 코멘트 1건.

> **완료 — 최종 게이트 통과**
>
> **게이트 `final` — 1/1 통과**
>
> | 명령 | 결과 |
> |---|---|
> | `npm run build` | exit 0 |
>
> 전체 출력: `fixtures/dry-run/gates/final.log`
>
> **수용 기준 대응**
> | 기준 | 확인 방법 |
> |---|---|
> | 이미지 업로드가 프로필에 반영 | `feature` 게이트 (`avatar.test.ts`) |
> | 허용되지 않은 타입·크기 4xx | `feature` 게이트 (`avatar.test.ts`) |
> | 기존 저장 테스트 통과 | `feature` 게이트 (전체 스위트) |

**사용자 확인**
- [ ] `Done` 으로 이동했다
- [ ] **수용 기준마다 그것을 확인한 게이트가 적혀 있다** — 어느 기준도 "확인 안 됨" 으로 남지 않았다
- [ ] 게이트로 확인 불가능한 기준이 있었다면 `verification.manual` 항목으로 명시되어 있다

**통과 기준 (1부 전체)**: 이슈 하나를 위에서 아래로 읽으면
**판정 근거 → 승인 → 착수 → 무엇이 깨졌나 → 무엇으로 고쳤나 → 무엇으로 통과를 판정했나**
가 순서대로 읽힌다. 이것이 안 되면 매핑이나 기록 정책을 고쳐야 한다.

---

# 2부 — H2/H3 리허설 (Project + 하위 이슈, 선택)

의존 그래프와 프로젝트 진행률을 보고 싶을 때만 한다. 1부를 통과한 뒤에 진행한다.

## 단계 8 — 프로젝트와 하위 이슈 생성

**에이전트**
```
save_project(name: "[DRY-RUN] 인증 전환 리허설", addTeams: ["Koreatimes"],
             description: <spec 요약>, summary: "하네스 추적 검증용 가상 프로젝트")

save_issue(team, project, title: "[DRY-RUN] 1. 의존성·베이스라인 조사", state: "Triage")
save_issue(team, project, title: "[DRY-RUN] 2. 세션 스키마 이관",   state: "Triage",
           blockedBy: ["KOR-<1번>"])
save_issue(team, project, title: "[DRY-RUN] 3. OAuth 제공자 연동",  state: "Triage",
           blockedBy: ["KOR-<2번>"])
```

**사용자 확인**
- [ ] 프로젝트 하위에 이슈 3건이 보인다
- [ ] **2번 이슈에 "Blocked by 1번" 이 표시된다** — 의존을 글로 적은 게 아니라 Linear 가 안다
- [ ] 3번을 열면 2번이 선행 작업으로 보인다
- [ ] 프로젝트 진행률이 **0%** 다

**통과 기준**: "지금 무엇을 시작할 수 있는가" 를 그래프만 보고 답할 수 있다 (1번뿐이다).

## 단계 9 — 순차 완료와 진행률

**에이전트**: 1번을 `Done` 으로 올린다.

**사용자 확인**
- [ ] 프로젝트 진행률이 **33%** 로 오른다
- [ ] 2번의 blocked 표시가 **풀린다**
- [ ] 3번은 여전히 2번에 막혀 있다

**통과 기준**: 사용자가 "다음에 뭘 해야 하나" 를 묻지 않아도 화면이 답한다.

## 단계 10 — Human Gate

**에이전트**: 되돌릴 수 없는 단계 직전에 `state: "In Review"` + 증거 코멘트.

```markdown
**Human Gate — 승인 대기**

되돌릴 수 없는 작업입니다: 프로덕션 세션 스키마 마이그레이션.

| 항목 | 상태 | 근거 |
|---|---|---|
| 최종 게이트 | 통과 | `_workspace/harness/gates/final.log` |
| 마이그레이션 dry-run | 통과 | `_workspace/harness/deploy.md` |
| 백업 | 확인 | 2026-08-29 14:02 |
| 변경 규모 | — | `git diff --stat`: 12 files, +340 −118 |

**롤백 절차**: `npm run migrate:down -- --to 20260828` (예상 3분)

승인하시면 진행합니다. `human_gate_approval: linear` 면 이 이슈를 `Todo` 로 바꿔 주십시오.
```

**사용자 확인**
- [ ] **무엇을 승인하는지**가 한 문장으로 있다
- [ ] 롤백 절차가 **실행 가능한 명령**이다 (문장 설명이 아니다)
- [ ] 변경 규모(diff 통계)가 있다
- [ ] 하네스가 **여기서 멈춰 있다** — 승인 없이 다음 단계로 가지 않았다

**통과 기준**: 코드를 열지 않고도 승인/거부를 판단할 수 있다.

---

# 정리

**MCP 에는 이슈·프로젝트 삭제 도구가 없다.** 상태로 정리하고, 완전 삭제는 Linear UI 에서 한다.

- [ ] 남은 `[DRY-RUN]` 이슈를 전부 `Canceled` 로 바꿨다
      (`list_issues(query: "[DRY-RUN]")` 로 찾는다)
- [ ] `[DRY-RUN]` 프로젝트 상태를 `Canceled` 로 바꿨다
- [ ] (선택) Linear UI 에서 완전 삭제했다
- [ ] `list_issues(query: "[DRY-RUN]", state: "Todo")` 가 **빈 결과**를 낸다

---

# 리허설 결과 기록

통과 여부를 `evals/results/` 에 남긴다. 실패한 항목은 지우지 말고 사유와 함께 보존한다 —
`03-jwt-to-oauth.v1-FAILED.md` 가 그 선례다.

| 단계 | 통과 | 비고 |
|---|---|---|
| 1 이슈 생성 (Triage) | | |
| 2 승인 (→ Todo) | | |
| 3 착수 (→ In Progress) | | |
| 4 게이트 실패 코멘트 | | 로그 전문이 새지 않았는가 |
| 5 게이트 통과 (→ In Review) | | |
| 6 리뷰 코멘트 | | 루프를 돌아도 1건인가 |
| 7 완료 (→ Done) | | 수용 기준 대응이 있는가 |
| 8 Project + blockedBy | | 선택 |
| 9 진행률·blocked 해제 | | 선택 |
| 10 Human Gate | | 선택 |

**하나라도 실패하면** `references/linear-tracking.md` 의 매핑이나 기록 정책을 고치고
1부부터 다시 돌린다. 코멘트 렌더링 문제라면 `scripts/gate-summary.sh` 와
`tests/test-gate-summary.sh` 를 함께 고친다.
