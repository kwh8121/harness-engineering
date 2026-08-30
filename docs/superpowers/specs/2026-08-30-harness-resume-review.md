# harness-architect 재개(Resume) 설계·계획 리뷰

- 리뷰 일자: 2026-08-30
- 검토 대상:
  - `docs/superpowers/specs/2026-08-30-harness-resume-design.md`
  - `docs/superpowers/plans/2026-08-30-harness-resume.md`
- 관련 구현: `harness-architect/`
- 판정: **REQUEST CHANGES — 설계 방향은 타당하나 구현 계획은 아직 실행 준비가 되지 않음**
- 신뢰도: 높음

## 1. 요약

`_workspace/harness/state.json`을 단일 재개 상태로 두고, JSON 표준 라이브러리와 원자적 교체를 사용하며,
Phase 4 이후에는 사람 판단으로 강등한다는 큰 방향은 타당하다. 특히 Linear를 진실의 원천으로 삼지 않고
SDD ledger를 재구현하지 않는 경계도 기존 harness-architect 원칙과 일치한다.

다만 현재 계획대로 구현하면 다음 문제가 생길 수 있다.

1. Phase 3의 과거 승인이 다음 세션에서 자동으로 부활할 수 있다.
2. 손상된 state를 자동 checkpoint가 빈 상태로 덮어쓸 수 있다.
3. 현재 사용자 요청과 중단된 과거 작업을 구분할 식별자가 없다.
4. 같은 HEAD에서 발생한 unstaged 변경을 저장소 불일치로 감지하지 못한다.
5. `rsync --delete`와 `git add -A`가 관련 없는 사용자 변경을 덮거나 커밋할 수 있다.
6. 역할 단위 진행 상태가 H2/H3의 실제 작업 단위 진행을 충분히 표현하지 못한다.

따라서 아래 P0 항목을 설계와 계획에 먼저 반영한 뒤 구현을 시작하는 것이 안전하다.

## 2. 타당한 결정

### 2.1 메인 워크트리의 `_workspace`를 진실의 원천으로 사용

**근거:** 설계는 linked worktree가 제거돼도 상태와 로그가 남도록 `_workspace/harness/state.json`을 메인
워크트리에 고정한다(`harness-resume-design.md:38-46`). 배포 저장소에는 이미 이를 위한
`harness-paths.sh`가 존재한다.

**판정:** 타당하다. 작업 코드가 있는 linked worktree와 수명 주기가 긴 운영 산출물을 분리한다.

### 2.2 JSON 및 `os.replace` 사용

**근거:** PyYAML은 선택 의존이고 Python 3은 이미 필수다(`harness-resume-design.md:44-46`). 계획은 같은
디렉터리에 임시 파일을 만든 뒤 `os.replace`로 교체한다(`harness-resume.md:374-389`).

**판정:** 타당하다. 다만 현재 테스트는 임시 파일 잔여만 확인하므로 실제 중단 안전성 검증을 보강해야 한다.

### 2.3 SDD ledger와 Linear의 경계

**근거:** 설계는 H2/H3 작업 단위 복원은 SDD ledger에 맡기고, Linear는 관측 수단으로만 취급한다
(`harness-resume-design.md:166-185`).

**판정:** 타당하다. 중복 상태 머신과 외부 서비스 의존을 피한다.

### 2.4 Phase 4~5의 사람 판단 강등

**근거:** 파일 쓰기와 외부 부작용이 시작되는 Phase 4부터 exit 11로 중단한다
(`harness-resume-design.md:26-34`, `harness-resume.md:682-702`).

**판정:** 안전한 기본값이다. 단, Phase 3 승인 상태의 처리도 같은 원칙에 맞게 수정해야 한다.

## 3. 차단 이슈

### [HIGH] H-1. Phase 3 승인이 자동으로 부활할 수 있다

**증거**

- 설계는 Phase 3 재개 시 요약을 다시 제시하고 승인을 다시 받는다고 명시한다
  (`harness-resume-design.md:32-34`).
- 상태에는 `approved: true`가 저장된다(`harness-resume-design.md:48-68`).
- 계획의 `AUTO_MAX_PHASE = 3`은 Phase 3을 exit 10 자동 재개로 분류한다
  (`harness-resume.md:700-702`, `:774-787`).
- SKILL.md 추가안은 exit 10이면 기록된 Phase부터 그대로 이어서 진행한다고만 한다
  (`harness-resume.md:1057-1066`).

**영향**

이전 세션의 승인이 새 세션에서 재확인 없이 Phase 4 실행 권한으로 해석될 수 있다. 이는 설계가 선언한
“승인이 저절로 부활하는 경로는 없다”는 불변식과 충돌한다.

**개선안**

- 자동 재개 상한을 Phase 2로 낮춘다.
- Phase 3은 항상 승인 대기 상태로 복원하고 `approved`를 재사용하지 않는다.
- 상태를 `3_pending_approval`과 `3_approved`로 분리한다면 두 상태 모두 새 세션에서는 사람 판단으로 보낸다.
- “Phase 3 + approved=true 재개 → exit 11” 회귀 테스트를 추가한다.

### [HIGH] H-2. 손상된 state가 빈 상태로 덮어써질 수 있다

**증거**

- 설계는 파싱 실패를 “state 없음”으로 보지 않고 손상으로 보고 브리핑해야 한다고 규정한다
  (`harness-resume-design.md:80-82`).
- 계획의 `checkpoint.py.load()`는 JSON 파싱 실패, I/O 오류, 알 수 없는 schema를 모두
  `blank_state()`로 바꾼다(`harness-resume.md:357-371`).
- `init-workspace.sh`와 `run-gates.sh` 연동은 checkpoint의 stdout/stderr와 오류를 모두 숨긴다
  (`harness-resume.md:1003-1018`).

**영향**

세션 내 state 손상 뒤 게이트나 초기화가 실행되면 원래 손상 파일이 새 빈 state로 교체되어 복구 근거를
잃을 수 있다.

**개선안**

- 파일이 없을 때만 `blank_state()`를 반환한다.
- 파싱 실패와 미지원 schema는 별도 오류로 반환하고 기존 파일을 절대 교체하지 않는다.
- 자동 연동은 본 작업을 막지 않더라도 stderr에 한 줄 경고를 남긴다.
- “깨진 state + gate 실행 → 원본 바이트 보존” 테스트를 추가한다.

### [HIGH] H-3. 현재 요청과 이전 작업을 구분할 task identity가 없다

**증거**

- state schema에는 phase, level, repo, artifacts, progress만 있고 작업 식별자가 없다
  (`harness-resume-design.md:48-68`).
- resume-check는 현재 사용자 요청을 입력으로 받지 않고 state 존재 여부와 저장소 지문만 비교한다
  (`harness-resume.md:753-787`).

**추론**

사용자가 이전 작업을 이어가려는 것이 아니라 새 작업을 요청해도, 동일 저장소의 Phase 0~3 state가 있으면
이전 작업을 자동 재개할 수 있다.

**개선안**

- state에 `task_id`, 정규화된 `goal`, `spec_digest`를 저장한다.
- Phase -1에서 현재 요청과 저장된 작업의 동일성을 확인한다.
- 동일성을 확정할 수 없으면 exit 11로 보내 “재개 / 보관 후 새 작업 / 폐기”를 선택하게 한다.

### [HIGH] H-4. 이식·커밋 명령이 사용자 변경을 포함할 수 있다

**증거**

- Task 1은 배포본을 `rsync -a --delete`로 개발본 전체에 덮는다(`harness-resume.md:50-56`).
- Task 8과 Task 9는 `git add -A`를 사용한다(`harness-resume.md:1106-1113`, `:1164-1172`).
- 검토 시점에 개발 저장소에는 untracked `ex-11-05-orchestrator-6phase copy/`가 있고,
  배포 저장소에는 수정된 `.gitignore`가 있다.

**영향**

계획과 무관한 파일을 삭제하거나 커밋할 수 있다. 특히 외부 배포 저장소의 `.gitignore` 변경이 Task 9
커밋에 섞일 가능성이 있다.

**개선안**

- `rsync -ain --delete` 결과를 먼저 보존하고 대상 목록을 승인한 뒤 실제 복사를 수행한다.
- `git add -A`를 제거하고 태스크가 소유한 정확한 파일만 stage한다.
- 각 저장소에서 사전·사후 `git status --short`를 기록하고 예상하지 않은 변경이 있으면 중단한다.
- 외부 저장소 수정·커밋은 명시적인 실행 권한이 있을 때만 수행한다.

## 4. 중요 개선사항

### [MEDIUM] M-1. `dirty`를 완전히 무시하면 같은 HEAD의 코드 변화를 놓친다

**증거:** 설계와 테스트는 dirty 상태를 자동 재개 강등 조건에서 제외한다
(`harness-resume-design.md:145-151`, `harness-resume.md:857-863`).

**개선안:** boolean 대신 `_workspace/`를 제외한 `git status --porcelain` 또는 diff digest를 저장한다.
같은 digest는 허용하고, checkpoint 이후 digest가 달라지면 exit 11로 보낸다.

### [MEDIUM] M-2. 역할 목록이 H2/H3 작업 단위를 표현하지 못한다

**증거:** 진행 상태는 `agents_done`/`agents_pending` 역할 ID만 저장하고, `--agent-done implementer`가
implementer 전체를 완료 처리한다(`harness-resume.md:444-455`, `:535-550`).

**영향:** 여러 작업 단위를 같은 implementer 역할이 순차 처리할 때 첫 단위 완료와 전체 구현 완료를
구별할 수 없다.

**개선안:** SDD ledger가 단위 진행을 전담한다면 state를 “역할 마일스톤”으로 명시하고 implementer는
SDD 전체 종료 시에만 완료 처리한다. 직접 표현하려면 `units[{id, agent, status}]`를 추가한다.

### [MEDIUM] M-3. checkpoint CLI가 상태 전이 불변식을 강제하지 않는다

계획의 구현은 다음 입력을 허용한다.

- Phase 3이 아닌 상태에서 `--approved`
- pending에 없는 ID의 `--agent-done`
- Phase 역행
- `phase: done`이 아닌 state의 `--archive`
- 중복 agent ID 또는 카탈로그 밖 ID

**개선안:** 허용 전이표를 정의하고 CLI에서 거부한다. `--agent-done`은 pending에 있는 ID만 허용하고,
archive는 `phase == done`일 때만 허용한다.

### [MEDIUM] M-4. 기록 실패가 사용자에게 보이지 않는다

**증거:** 자동 checkpoint 호출은 `>/dev/null 2>&1 || true`다(`harness-resume.md:1003-1018`).

**개선안:** 게이트의 본래 exit code는 유지하되 checkpoint 실패를 stderr 한 줄로 알리고
`resume_state_healthy: false`를 최종 브리핑에 표시한다.

### [MEDIUM] M-5. gate 기록이 원래 문제를 완전히 해결하지 않는다

문제 정의는 기존 로그에서 “언제·몇 번째 시도인지”를 알 수 없다고 한다
(`harness-resume-design.md:12-18`). 하지만 새 gate 항목도 `tier`와 `exit`만 저장한다
(`harness-resume-design.md:61-64`, `harness-resume.md:551-555`).

**개선안:** 각 gate 항목에 `recorded_at`, tier별 `attempt`, `log_path`를 저장한다.

### [MEDIUM] M-6. 원자적 쓰기 테스트가 실제 원자성을 증명하지 않는다

**증거:** 테스트는 저장 후 임시 파일이 남지 않았는지만 확인한다(`harness-resume.md:232-235`).

**개선안:** 반복 쓰기 중 별도 reader가 항상 완전한 JSON만 읽는지 확인하고, save 직전/교체 직전
fault injection으로 기존 state가 유지되는지 검증한다. 동시 writer를 허용하지 않는다면 그 전제도
불변식으로 명시한다.

## 5. 문서·계획 일관성

### 5.1 `.sh`와 `.py` 명칭

설계는 `checkpoint.sh`/`resume-check.sh`를 사용하지만 계획은 `.py`로 변경한다. 계획은 Task 8에서
설계를 나중에 수정하도록 되어 있다(`harness-resume.md:23-28`, `:1094-1104`).

**개선안:** 구현 시작 전에 설계를 `.py` 기준으로 먼저 갱신한다. 7개 태스크 동안 설계와 구현 이름이
다른 상태를 유지하지 않는다.

### 5.2 이식 경계와 `.claude/settings.json`

Task 9는 skills와 agents 두 경로만 복사한다(`harness-resume.md:1123-1129`). 하지만 현재
`MIGRATION.md:7-24`는 읽기 전용 가드에 필요한 `.claude/settings.json`도 복사 또는 병합 대상으로 둔다.

**개선안:** Task 9에 settings 병합 확인을 포함하거나, 배포 저장소에 이미 동일한 hook이 있음을
사전조건과 테스트로 명시한다.

### 5.3 Lore Commit Protocol

각 Task의 커밋 예시는 변경 내용을 설명하는 `feat:`/`docs:` 제목만 사용하며, 저장소 AGENTS.md의
의도 중심 제목과 Lore trailer 계약을 반영하지 않는다.

**개선안:** 커밋 예시를 의도 중심 제목으로 바꾸고 최소 `Confidence`, `Scope-risk`, `Tested`,
`Not-tested` trailer를 포함한다.

## 6. 권장 수정 순서

### P0 — 구현 전에 설계·상태 계약 수정

1. 자동 재개 상한을 Phase 2로 낮추고 Phase 3 재승인을 강제한다.
2. `task_id`/`goal`/`spec_digest`와 worktree diff digest를 state에 추가한다.
3. 손상 state를 fail-closed로 처리하고 절대 자동 덮어쓰지 않는다.
4. checkpoint 상태 전이와 archive 조건을 정의한다.
5. destructive sync와 `git add -A`를 제거한다.

### P1 — 계획과 테스트 보완

1. SDD ledger와 state의 작업 단위 소유권을 명확히 한다.
2. gate 항목에 시각·attempt·log path를 추가한다.
3. checkpoint 실패를 비차단 경고로 노출한다.
4. `.py` 명칭과 settings 이식 경계를 모든 문서에서 먼저 동기화한다.

### P2 — 추가 회귀 시나리오

- Phase 3 + `approved=true` 재개는 자동 실행되지 않는다.
- 다른 새 작업 요청은 이전 state를 자동 재개하지 않는다.
- 손상 state에서 gate/init 실행 후 원본 바이트가 보존된다.
- 같은 HEAD에서 worktree diff digest가 바뀌면 exit 11이다.
- 미등록 agent, phase 역행, 완료 전 archive가 거부된다.
- archive 파일명 충돌 시 기존 기록이 덮어써지지 않는다.
- checkpoint write 중 reader가 불완전 JSON을 관측하지 않는다.

## 7. 검증 근거와 한계

### 직접 확인한 근거

- 기존 `harness-architect/tests/run-all.sh`: `PASS 132 / FAIL 0`
- 개발/배포 스킬 트리 차이: 13건
- 개발 저장소 상태: untracked 디렉터리 1건
- 배포 저장소 상태: 수정된 `.gitignore` 1건
- 현재 문서는 아직 구현 전 계획이며 checkpoint/resume 스크립트는 개발 저장소에 존재하지 않는다.

### 추론

- Phase 3 자동 재개는 저장된 승인을 실행 권한으로 오인할 가능성이 높다.
- task identity가 없으면 새 사용자 요청을 기존 작업 재개로 오인할 수 있다.
- dirty boolean을 무시하면 unstaged 코드 변경을 저장소 불일치로 검출할 수 없다.

### 아직 확인할 수 없는 것

- 실제 Claude 세션 재시작 후 Phase -1이 올바르게 호출되는지
- SDD ledger 경로와 재개 state의 실제 결합 방식
- concurrent writer가 현실적으로 발생하지 않는다는 운영 보장
- 배포 저장소의 현재 `.gitignore` 변경이 의도된 것인지

이 항목들은 구현 후 통합 테스트 또는 실제 세션 중단 리허설로 확인해야 한다.
