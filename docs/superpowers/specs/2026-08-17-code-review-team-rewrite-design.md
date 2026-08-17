# code-review-team 실사용화 재설계

- 위치: `ex-11-05-orchestrator-6phase/`
- 날짜: 2026-08-17
- 상태: 승인 대기

## 배경

`ex-11-05-orchestrator-6phase`는 책 11장의 6-Phase 코드 리뷰 팀 오케스트레이터를 의사코드 수준으로 옮긴 예제다. `.claude/skills/code-review-team/SKILL.md`와 4개 워커 정의(`static-analyzer` / `design-reviewer` / `security-auditor` / `refactorer`)로 구성되며, 원래 목적은 "책 의사코드와의 충실도"였다 (`run/skill-fidelity.md` 참조).

이번 작업의 목적은 다르다: **이 팀을 실제로 돌아가는 범용 코드 리뷰 팀으로 만든다.** 충실도 대신 실사용성을 우선한다.

## 실현 가능성 분석 (수정 사유)

현재 환경(`ToolSearch`로 확인)에는 SKILL.md가 전제하는 5개 "공식 도구" 중 3개가 존재하지 않는다:

| SKILL.md가 가정한 도구 | 실제 존재 여부 | 대체 |
|---|---|---|
| `TeamCreate` | 없음 | 불필요 (팀 객체를 안 만듦) |
| `AgentTool` (팀 전용, `isolation: "worktree"`) | 없음 | `Agent` 도구 (subagent_type 지정, 이미 `.claude/agents/*.md`가 named agent로 등록됨) |
| `TaskCreate` (depends_on 포함) | 없음 | Agent 호출 순서로 대체 (병렬 3개 → 완료 후 refactorer 1개) |
| `SendMessage` | **있음** | 유지하되 용도 축소 (워커→리더 보고만, peer 통신 제거) |
| `TeamDelete` | 없음 | 불필요 (애초에 팀을 안 만들므로 정리할 것도 없음) |

추가로 두 가지 구조적 낭비를 확인했다:

1. **워커 간 peer SendMessage 모델**은 실제 `Agent` 도구가 "리더가 병렬 호출 → 완결된 결과 반환" 구조인 것과 맞지 않는다. 이름 붙은 백그라운드 에이전트가 서로를 능동적으로 찾아 메시지를 보내는 흐름은 이 환경에서 구현 비용 대비 이득이 없다.
2. **`parseDiff`/`mergeReports`가 의사 함수로만 존재**해서, 실행 시 매번 Claude가 diff를 직접 파싱하고 4개 보고서를 손으로 병합해야 한다 — 결정적으로 처리 가능한 작업에 토큰을 쓰는 것.

또한 리뷰어 3인은 전부 소스를 편집하지 않고(Bash/Edit 없음이거나 Read-only), refactorer도 `_workspace/patches/`만 쓰므로, `worktree` 격리는 안전상 불필요한 오버헤드다.

## 사용자 결정 사항 (확정)

- **적용 범위**: 이 디렉토리 전용으로 완성하되, 폴더 전체(`​.claude/skills/code-review-team/` + `.claude/agents/*.md`)를 통째로 복사하면 다른 리포에서 바로 동작하도록 이식 가능하게 만든다. (전역 설치 불필요)
- **입력 소스**: `gh pr diff` 기반 PR 리뷰 + 로컬 `git diff` 기반 리뷰 모두 지원.
- **협업 모델**: 리더 허브형으로 단순화. 워커 간 peer SendMessage 제거.
- **패치 적용 수준**: `_workspace/patches/*.diff` 생성 후 `git apply`로 working tree까지 반영. **git commit은 항상 금지.**
- **생성-검증 루프**: "라우팅"과 "판정"을 분리하는 절충안. patch → 원 발견 리뷰어 매핑은 스크립트가 구조화된 메타데이터(`발견 출처: 0X_*.md`)에서 결정적으로 추출한다(리더는 리뷰 내용을 읽지 않음). 실제 "이 patch가 발견을 해결했는가" 판정은 원 리뷰어를 `Agent`로 재호출해 `VERDICT: PASS`/`VERDICT: FAIL - <사유>` 중 하나만 강제로 답하게 하고, 리더는 그 한 줄만 기계적으로 확인해 재시도 여부를 결정한다.

## 아키텍처

```
.claude/skills/code-review-team/
  SKILL.md                 # 재작성 대상 — 실제 Agent/SendMessage + 스크립트 기반 오케스트레이션
  scripts/
    resolve-diff.sh          # 입력 판별 + diff 확보 + 변경 파일 목록 추출
    route-verification.sh    # 04_refactor.md의 "발견 출처" 메타데이터 → patch-리뷰어 매핑 표 추출 (결정적)
    judge-verdict.sh         # 검증 Agent 응답(stdin) + 시도 횟수 → PASS/RETRY/REJECTED 판정 (REJECTED면 .rejected로 리네임까지)
    merge-reports.sh         # 4개 보고서 → P0/P1/P2 정렬 통합 (결정적, LLM 미사용)
    apply-patches.sh         # patch 유효성 검사 후 working tree 반영 (커밋 안 함)
.claude/agents/
  static-analyzer.md         # 소폭 수정 — "PASS/FAIL 판정 전용 재호출" 시 응답 형식 절 추가
  design-reviewer.md         # 소폭 수정 — 동일
  security-auditor.md        # 소폭 수정 — 동일
  refactorer.md               # 수정 — peer SendMessage 절 제거, 검증 사이클을 리더가 중계함을 명시,
                              #   patch 적용도 본인이 아니라 리더가 apply-patches.sh로 수행함을 명시
```

### 컴포넌트별 역할과 변경 사유

**`resolve-diff.sh`** (신규)
- 입력: `$1` = PR 번호(옵션)
- PR 번호가 있으면 `gh pr diff "$1" > _workspace/input/diff.patch`
- 없으면 순서대로 시도: staged(`git diff --cached`) → unstaged(`git diff`) → 브랜치 base 대비 — 첫 번째로 비어있지 않은 결과 채택
  - 브랜치 base 판별 순서: `origin/HEAD`가 있으면 그 가리키는 브랜치를 기준으로, 없으면 로컬 `main` → `master` 순으로 존재하는 첫 브랜치를 기준. 기준 브랜치를 못 찾으면 이 단계는 건너뛴다.
  - 기준이 정해지면 `git merge-base HEAD <기준브랜치>`로 분기점을 구하고 그 커밋과 diff
- 변경 파일 목록을 `git diff --name-only`로 뽑아 `_workspace/input/files.txt`에 별도 저장 (워커가 diff 전체를 되풀이해 파싱하지 않도록)
- 아무 diff도 없으면 non-zero exit + 명확한 stderr 메시지 → 리더는 이 시점에서 워커를 스폰하지 않고 조기 종료 (토큰 절약)
- 사유: "의사 함수 `parseDiff`"를 결정적 셸 로직으로 대체. gh 미설치 시 자동으로 로컬 diff로 폴백.

**`merge-reports.sh`** (신규)
- 입력: `_workspace/review/01_static.md` ~ `04_refactor.md`
- 각 파일에서 `### [P0]` / `[P1]` / `[P2]` 헤더 라인을 grep으로 추출해 우선순위별로 재배열, `_workspace/review_report.md` 생성
- 사유: "의사 함수 `mergeReports`"를 결정적 로직으로 대체. 마크다운 구조가 이미 4개 에이전트 정의에서 통일되어 있으므로 grep 기반으로 충분.

**`route-verification.sh`** (신규)
- 입력: `_workspace/review/04_refactor.md`
- refactorer 보고서 형식에 이미 있는 `- 발견 출처: 0X_*.md [P0] ...` 줄을 grep/sed로 추출해, patch 파일명 → 원본 리뷰 보고서 → 담당 에이전트(파일명 접두사로 결정적 매핑: `01_static→static-analyzer`, `02_design→design-reviewer`, `03_security→security-auditor`)를 TSV 한 줄씩(`patch파일\t담당에이전트\t발견원문`)으로 `_workspace/verification/queue.tsv`에 출력
- 사유: "이 patch를 누구에게 검증받아야 하는가"는 리더가 리뷰 내용을 읽고 판단할 필요 없이, 이미 구조화된 필드에서 결정적으로 뽑을 수 있다. 리더는 이 표를 한 줄씩 순회하며 호출만 한다.

**`judge-verdict.sh`** (신규)
- 입력: `$1`=patch 파일명, `$2`=시도 횟수, stdin=검증 Agent 응답 전체 텍스트
- 응답에서 마지막 비어있지 않은 줄을 뽑아 `VERDICT: PASS`로 시작하는지만 문자열 비교. PASS면 `PASS` 출력. 아니면(FAIL 또는 형식 위반) 시도 횟수 < 3이면 `RETRY` 출력, 3 이상이면 `_workspace/patches/{patch}` → `{patch}.rejected`로 리네임하고 `REJECTED` 출력.
- 사유: 최초 설계에서는 이 판정·리네임 로직이 SKILL.md 안의 자연어 절차로만 존재해, 실제 Agent 호출 없이는 테스트할 방법이 없었다(스펙의 테스트 계획과 불일치 — 플랜 자체 검토 중 발견). 별도 스크립트로 분리해 픽스처만으로 재시도/격리 판정을 검증 가능하게 한다. 리더는 이 스크립트 출력(PASS/RETRY/REJECTED) 세 단어만 보고 분기하면 되므로 "리더 무발화" 원칙도 더 엄격해진다.

**`apply-patches.sh`** (신규)
- 검증 사이클(아래 "생성-검증 루프" 절 참조)에서 3회 시도 끝에 `VERDICT: FAIL`로 남은 patch는 리더가 `_workspace/patches/`에서 `.rejected` 접미사로 이름을 바꿔 이 스크립트의 대상에서 제외한다.
- 남은 `_workspace/patches/*.diff` 각각에 대해 `git apply --check`로 먼저 검증, 통과하는 것만 `git apply`로 working tree에 반영
- 실패한 patch는 건너뛰고 파일명을 stdout에 나열 (리더가 통합 보고서에 "적용 실패 — 수동 검토 필요"로 반영)
- **`git commit`, `git add` 호출 없음** — working tree만 바뀐 상태로 남긴다.
- 사유: patch 파일만 만들고 끝나면 사용자가 매번 수동으로 `git apply`해야 해서 실사용성이 떨어진다. 커밋 없이 working tree까지만 반영하면 `git diff`로 바로 검토 후 사용자가 직접 커밋할 수 있다.

**`SKILL.md`** (재작성)
- Phase 구성은 유지하되 호출을 실제 도구로 교체:
  - Phase 0: `Bash(scripts/resolve-diff.sh [PR번호])`
  - Phase 1~3: 한 메시지에서 `Agent` 도구 3회 병렬 호출 (`subagent_type`: static-analyzer/design-reviewer/security-auditor, isolation 미지정 — worktree 불필요)
  - Phase 4: 3개 보고서 확인 후 `Agent` 1회 호출 (`subagent_type`: refactorer) → 이어서 "생성-검증 루프"(아래 절) 수행
  - Phase 5: `Bash(scripts/merge-reports.sh)` → `Bash(scripts/apply-patches.sh)` → PR 모드면 `gh pr comment` 게시 **전 사용자 확인 필수**(외부 노출 액션, 시스템 규칙상 명시적 승인 필요). 로컬 모드는 파일 저장만 하고 게시 생략.
  - `TeamCreate`/`TeamDelete` 관련 문구 전부 제거 (팀 객체 자체가 없으므로).
- `allowed-tools` frontmatter를 실제 사용 도구로 갱신: `Agent, Bash(resolve-diff.sh, route-verification.sh, judge-verdict.sh, merge-reports.sh, apply-patches.sh, gh pr diff, gh pr comment), Read, Write`.

**`refactorer.md`** (수정)
- "팀 통신 프로토콜 — 발신: patch 생성 후 리뷰어 3인 모두에게 SendMessage" 절 제거 (peer 통신 폐지)
- "patch 적용은 본인이 아니라 리더가 `apply-patches.sh`로 수행한다"는 문구 추가
- "생성-검증 루프 ≤3회"의 **주체가 바뀜을 명시**: 기존엔 본인이 SendMessage로 재검증을 요청하고 루프를 스스로 관리했지만, 이제는 **리더가 루프를 관리**하고 refactorer는 "리더로부터 `VERDICT: FAIL - <사유>`를 받으면 해당 patch 하나만 그 사유를 반영해 재생성한다"는 좁은 역할로 축소. 몇 번째 시도인지는 리더가 세므로 refactorer는 카운트를 관리하지 않는다.

**`static-analyzer.md` / `design-reviewer.md` / `security-auditor.md`** (수정)
- 기존 "발견만 보고" 역할은 유지.
- **"팀 통신 프로토콜" 절 수정**: 세 파일 모두 현재 "발신: 동료 리뷰어에게 SendMessage. 리더 미경유"로 되어 있음(실제 파일 확인 결과 — peer 통신이 실제로 남아 있었음, 이전 버전 스펙의 "이미 리더 보고로 되어 있음" 서술은 오류였으므로 정정) → "발신: 리더에게만 보고. cross-domain 발견은 SendMessage 대신 보고서 안에 cross-domain 태그로 남기고 `merge-reports.sh`가 그대로 통합 보고서에 반영한다"로 교체.
- **새 절 추가**: "검증 응답 모드" — 리더가 `_workspace/patches/{file}.diff`와 자신이 낸 특정 발견을 지정해 "이 patch가 이 발견을 해결했는가"만 물으면, 전체 재리뷰를 하지 않고 그 patch만 확인한 뒤 응답을 **반드시 마지막 줄에 `VERDICT: PASS` 또는 `VERDICT: FAIL - <한 줄 사유>`로 끝낸다.** 이 형식 강제가 리더의 기계적 파싱을 가능하게 한다.

## 생성-검증 루프 (Phase 4 상세)

라우팅(누가 검증하는가)과 판정(진짜 해결됐는가)을 분리한다. 리더는 라우팅에서는 스크립트 출력만 따르고, 판정에서는 강제된 한 줄만 확인한다 — 리뷰 내용 자체를 읽고 해석하지 않는다.

1. 리더가 `Agent(subagent_type: refactorer)` 호출 → `_workspace/review/04_refactor.md` + `_workspace/patches/*.diff` 생성 (1회차 생성)
2. 리더가 `Bash(scripts/route-verification.sh)` 실행 → `_workspace/verification/queue.tsv` (patch파일, 담당 에이전트, 발견 원문 3열)
3. `queue.tsv`를 한 줄씩 순회하며 리더가 `Agent(subagent_type: <담당 에이전트>)`를 좁은 프롬프트로 호출: "`_workspace/patches/{patch}`가 `_workspace/review/{원본보고서}`의 이 발견을 해결했는지만 확인하고 마지막 줄에 VERDICT: PASS 또는 VERDICT: FAIL - <사유>로 답하라"
4. 리더는 그 응답 전체를 `judge-verdict.sh {patch} {시도횟수}`에 stdin으로 넘긴다. 스크립트가 `PASS`/`RETRY`/`REJECTED` 중 하나를 출력한다(REJECTED면 스크립트가 `.rejected` 리네임까지 직접 수행).
5. `PASS`면 이 patch는 통과 — 큐에서 제거하고 다음 patch로.
6. `RETRY`면 리더가 그 patch 이름 + FAIL 사유만 담아 `Agent(subagent_type: refactorer)`를 다시 호출해 **그 patch 하나만** 재생성 요청, 시도 횟수 +1 후 4번으로.
7. `REJECTED`면(patch 1건당 생성 1회 + 재생성 최대 2회 = 최대 3회 시도 소진) 이미 `.rejected`로 격리된 상태이므로 큐에서 제거하고 다음 patch로(사람 위임 대상).
8. 큐가 비면(모든 patch가 PASS 또는 REJECTED) Phase 5로 진행.

리더가 실제로 "읽는" 것은 `queue.tsv`의 구조화된 열과 `judge-verdict.sh`의 출력 한 단어(`PASS`/`RETRY`/`REJECTED`)뿐이다. 발견 원문·patch 내용·검증 응답 전체는 파일 경로 또는 스크립트 stdin으로만 전달되고, 해석은 전부 호출된 서브에이전트와 결정적 스크립트 안에서 일어난다.

## 데이터 흐름

```
[PR번호 or 없음]
    → resolve-diff.sh → _workspace/input/{diff.patch, files.txt}
    → Agent×3 병렬 (병렬 호출 1개 메시지)
        → _workspace/review/{01_static,02_design,03_security}.md
    → Agent×1 (refactorer, 위 3개 완료 후)
        → _workspace/review/04_refactor.md, _workspace/patches/*.diff
    → route-verification.sh → _workspace/verification/queue.tsv
    → [생성-검증 루프, patch별 최대 3회]
        → Agent(담당 리뷰어) → 응답 전체
        → judge-verdict.sh → PASS | RETRY | REJECTED(내부에서 *.diff → *.diff.rejected 리네임)
        → RETRY면 Agent(refactorer) 재호출 → 해당 patch만 재생성
    → merge-reports.sh → _workspace/review_report.md
    → apply-patches.sh → working tree 반영 (커밋 없음, .rejected 제외), 실패 목록 stdout
    → [PR 모드] 사용자 확인 → gh pr comment
    → [로컬 모드] 파일 저장만
```

## 에러 처리

- diff 없음(변경사항 전무): `resolve-diff.sh`가 non-zero exit, 리더는 워커를 스폰하지 않고 사용자에게 상황 보고 후 종료.
- PR 모드 요청인데 `gh` 미설치/미인증: `resolve-diff.sh`가 stderr에 안내 후 로컬 diff로 자동 폴백 — 리더는 폴백 사실을 사용자에게 알린다.
- 리뷰 보고서 3개 중 일부 누락(워커 실패): `merge-reports.sh`는 존재하는 파일만으로 통합하고, 누락된 리뷰어를 보고서 상단에 명시. refactorer는 기존 에러 핸들링(입력 요청, 추측 금지) 유지.
- `git apply --check` 실패: 해당 patch만 건너뛰고 계속 진행, 통합 보고서에 실패 목록 표시.
- 검증 응답이 `VERDICT: PASS`/`VERDICT: FAIL` 둘 다 아님(형식 위반): 리더는 이를 `FAIL - 형식 위반, 재확인 필요`로 취급해 동일한 재시도 카운트에 포함시킨다 (별도 예외 처리 없음 — 3회 상한 로직 재사용).
- patch가 3회 시도 후에도 `VERDICT: FAIL`: `.diff.rejected`로 격리, `apply-patches.sh` 대상에서 자동 제외, 통합 보고서에 "사람 위임 필요" + 마지막 FAIL 사유 기록.

## 테스트 계획

1. **스크립트 단독 테스트**: `resolve-diff.sh`/`route-verification.sh`/`judge-verdict.sh`/`merge-reports.sh`/`apply-patches.sh`를 픽스처(가짜 diff, 가짜 4개 보고서, 가짜 patch, 가짜 검증 응답 텍스트)로 직접 실행해 exit code와 출력 파일을 확인. 이 리포에 실제 소스가 거의 없으므로 스크립트 자체는 셸에서 격리 테스트한다. `route-verification.sh`는 `04_refactor.md` 픽스처에 "발견 출처" 줄을 2~3개 넣어 TSV 매핑이 정확히 나오는지 확인.
2. **생성-검증 루프 테스트**: `judge-verdict.sh`에 `VERDICT: PASS`/`VERDICT: FAIL - ...`/형식 위반 텍스트를 시도 횟수 1·2·3으로 각각 stdin으로 넣어 `PASS`/`RETRY`/`REJECTED` 판정과 3회차 `.diff.rejected` 리네임이 정확히 동작하는지 확인 — 실제 Agent 호출 없이 스크립트만으로 검증 가능.
3. **End-to-end dry-run**: 이번 CLAUDE.md 재작성으로 생긴 실제 로컬 diff(또는 harness-engineering 리포 안의 다른 변경)를 대상으로 로컬 모드 1회 전체 실행 — Agent 호출까지 실제로 발생시켜 보고서·patch·검증·통합 결과를 확인한다.
4. PR 모드는 `gh pr comment` 게시가 외부 노출 액션이라 실제 PR에 대고 테스트하지 않고, `resolve-diff.sh`의 PR 분기 로직만 mock(`GH_TOKEN` 없이 gh 호출 실패 → 폴백 경로 확인)으로 검증한다.

## 범위 밖 (Out of scope)

- 전역 스킬 설치(`~/.claude/skills/`)나 심볼릭 링크 — 이번엔 폴더 복사 이식성까지만 확보.
- CI/CD 파이프라인 통합.
- 워커 모델/도구 변경(예: static-analyzer를 sonnet으로 승격) — 이번 작업은 오케스트레이션 계층 재작성에 집중.
