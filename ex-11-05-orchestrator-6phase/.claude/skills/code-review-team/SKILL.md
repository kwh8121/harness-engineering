---
name: code-review-team
description: PR diff 또는 로컬 git diff에 대해 정적분석·설계·보안 3 리뷰어 + 리팩토러 4인 팀을 운영한다. 트리거 - "코드 리뷰", "PR 리뷰", "리뷰 재실행", "다시 실행", "리뷰 보고서".
allowed-tools: Agent, Bash(resolve-diff.sh, route-verification.sh, judge-verdict.sh, merge-reports.sh, apply-patches.sh, gh pr diff, gh pr comment), Read, Write
---

# code-review-team

> 4인 리뷰어 팀 오케스트레이터. 리더는 판단 없이 호출과 스크립트 실행만 한다 — 보고서 본문은 워커 4인이, 반복 로직은 `scripts/`가 담당한다.

## 사용 시점

- PR 번호가 주어지고 코드 리뷰를 요청받았을 때 → PR 모드
- PR 번호 없이 "코드 리뷰", "리뷰 재실행" 등으로 요청받았을 때 → 로컬 diff 모드 (현재 브랜치의 staged/unstaged/브랜치 base 변경사항을 `resolve-diff.sh`가 자동 판별)
- "리뷰 재실행", "다시 실행" — 동일 입력으로 재구동 (이전 `_workspace/review/*` 결과 덮어쓰기)

## Phase 0 — 입력 확보

1. `Bash: bash .claude/skills/code-review-team/scripts/resolve-diff.sh [PR번호]` 실행
2. exit code가 0이 아니면: 사용자에게 "리뷰할 변경사항이 없습니다"라고 보고하고 **여기서 종료** (워커를 스폰하지 않는다 — 토큰 절약)
3. PR 모드로 호출했는데 stderr에 "로컬 diff로 폴백" 메시지가 있었다면, 그 사실을 사용자에게 알린다

## Phase 1~3 — 병렬 리뷰

한 메시지에서 `Agent` 도구를 3회 호출한다 (병렬 실행, 서로 의존관계 없음):

- `subagent_type: "static-analyzer"` — 프롬프트에 `_workspace/input/diff.patch`, `_workspace/input/files.txt` 경로와 출력 경로 `_workspace/review/01_static.md` 전달
- `subagent_type: "design-reviewer"` — 출력 경로 `_workspace/review/02_design.md`
- `subagent_type: "security-auditor"` — 출력 경로 `_workspace/review/03_security.md`

세 `Agent` 호출이 모두 반환되면 다음 Phase로 진행한다 (Agent 도구는 완료 시 결과를 반환하므로 별도 폴링 불필요).

## Phase 4 — refactorer + 생성-검증 루프

1. `Agent(subagent_type: "refactorer")` 1회 호출. 프롬프트에 세 보고서 경로(`01_static.md`, `02_design.md`, `03_security.md`)와 출력 경로(`_workspace/review/04_refactor.md`, `_workspace/patches/`) 전달.
2. `Bash: bash .claude/skills/code-review-team/scripts/route-verification.sh` 실행 → `_workspace/verification/queue.tsv` 생성. 이 파일이 비어 있으면(=P0 patch 없음) Phase 5로 바로 진행.
3. `queue.tsv`를 한 줄씩(patch파일, 담당에이전트, 발견원문 — 탭 구분 3열) 순회하며, **patch당 시도 횟수를 1로 시작해** 아래를 반복한다:
   1. `Agent(subagent_type: <담당에이전트>)` 호출. 프롬프트: "`_workspace/patches/{patch}`가 `_workspace/review/{원본보고서}`의 다음 발견을 해결했는지만 확인하라: {발견원문}. 전체 재리뷰는 하지 말고 이 patch 하나만 확인한 뒤, 응답 마지막 줄을 반드시 `VERDICT: PASS` 또는 `VERDICT: FAIL - <한 줄 사유>`로 끝내라."
   2. 그 응답 전체를 `Bash: bash .claude/skills/code-review-team/scripts/judge-verdict.sh {patch} {시도횟수}` 에 stdin으로 넘긴다. 결과는 `PASS`/`RETRY`/`REJECTED` 중 하나.
   3. `PASS`면: 이 patch는 통과. 다음 patch로 이동.
   4. `RETRY`면: `Agent(subagent_type: "refactorer")`를 다시 호출해 "patch {patch}가 다음 사유로 거절됨: {검증 응답에서 나온 사유 또는 '응답 형식 위반'}. 이 patch만 재생성하라" 요청하고, 시도 횟수 +1 후 3.1로 돌아간다.
   5. `REJECTED`면: `judge-verdict.sh`가 이미 `_workspace/patches/{patch}` → `{patch}.rejected` 리네임까지 끝낸 상태. 이 patch는 사람 위임 대상으로 두고 다음 patch로 이동 — 리더가 직접 파일을 옮기지 않는다.

## Phase 5 — 통합 · 패치 적용 · 게시

1. `Bash: bash .claude/skills/code-review-team/scripts/merge-reports.sh` → `_workspace/review_report.md`
2. `Bash: bash .claude/skills/code-review-team/scripts/apply-patches.sh` → working tree에 반영(커밋 없음). exit code가 0이 아니면(=실패한 patch 있음) 그 stdout의 `FAILED:` 목록을 `_workspace/review_report.md` 맨 위에 한 줄로 덧붙인다(파일명 나열만, 내용 해석 없음).
3. **PR 모드였다면**: 사용자에게 "PR #{N}에 통합 보고서를 코멘트로 게시할까요?"를 확인하고, 승인 시 `Bash: gh pr comment {N} -F _workspace/review_report.md`
4. **로컬 모드였다면**: 게시 없이 종료. `_workspace/review_report.md` 위치를 사용자에게 안내.

## 불변 규칙

- **리더 무발화**: 리더는 보고서·발견 내용을 읽고 판단하지 않는다. 라우팅은 스크립트 출력을, 검증은 `VERDICT:` 한 줄만 본다.
- **자동 커밋 금지**: 이 스킬은 어떤 단계에서도 `git commit`을 호출하지 않는다. `git apply`로 working tree만 바꾼다.
- **workspace 보존**: 실행 종료 후에도 `_workspace/`는 삭제하지 않는다.
- **생성-검증 루프 ≤3회 (patch 단위)**: 3회 시도 후에도 실패하면 `.rejected`로 격리하고 적용하지 않는다.
- **재실행**: 동일 입력(PR 번호 또는 로컬 diff)으로 다시 실행하면 `_workspace/review/*`를 덮어쓴다.
- **이식성**: 이 폴더(`.claude/skills/code-review-team/` + `.claude/agents/*.md`)를 통째로 다른 저장소에 복사하면 별도 설치 없이 바로 동작한다.
