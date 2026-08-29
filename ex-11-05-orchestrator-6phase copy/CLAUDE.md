# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 하네스: 코드 리뷰 자동화

이 디렉토리는 4 에이전트(static-analyzer / design-reviewer / security-auditor / refactorer) + 1 스킬(code-review-team)로 PR 리뷰를 수행하는 오케스트레이터 예제다. 실행 가능한 애플리케이션 코드가 아니라 `SKILL.md`에 담긴 **6-Phase 의사코드**와 그 충실도를 검증하는 문서로 구성된다 — 빌드·린트·테스트 명령이 없다.

## 트리거 키워드

"코드 리뷰", "PR 리뷰", "리뷰 재실행", "다시 실행" → `.claude/skills/code-review-team/SKILL.md`로 라우팅.

## 구성

- `.claude/skills/code-review-team/SKILL.md` — 오케스트레이터 본체(6 Phase 의사코드)
- `.claude/agents/*.md` × 4 — 워커 정의 (ex-11-03/04에서 복사)
- `run/checklist.md`, `run/skill-fidelity.md`, `run/tool-classification.md` — 셀프 검증 문서

## 아키텍처: 6-Phase 워크플로

`SKILL.md`의 `codeReviewTeam(prNumber)`가 리더다. **리더는 텍스트를 쓰지 않는다** — 도구만 호출하고, 리뷰 본문은 워커 4인이 생산한다.

| Phase | 내용 |
|---|---|
| 0 | `gh pr diff` → `_workspace/input/pr-{N}.diff` 저장, `parseDiff`로 메타 추출 |
| 1 | `TeamCreate` 1회 + `AgentTool` × 4 (`isolation: "worktree"`로 격리) |
| 2 | `TaskCreate` × 4 (for-루프). 4번째(`리팩토링`)만 `depends_on: ["정적 분석","설계 검토","보안 감사"]` |
| 3 | 리뷰어 3인 병렬 팬아웃, `waitForTeamCompletion` 대기 |
| 4 | refactorer 생성-검증 루프 (최대 3회, 이후 사람에게 위임) |
| 5 | `mergeReports`로 4개 보고서를 P0→P1→P2 순 통합 → `gh pr comment`까지만 실행, `TeamDelete` |

### 도구 분류 (구현 시 반드시 구분)

- **공식 5종** (실제 호출 가능): `TeamCreate`, `AgentTool`, `TaskCreate`, `SendMessage`, `TeamDelete`
- **의사 함수 4종** (구현자가 채워야 함, 이 저장소에는 미구현): `parseDiff`, `waitForTeamCompletion`, `mergeReports`, `$`(셸 실행 헬퍼) — `mergeReports`의 실 구현 예시는 ex-11-07의 `built/scripts/merge-reports.ts` 참조.

이 SKILL.md를 다른 환경으로 옮길 때는 의사 함수 4종부터 실제로 구현해야 동작한다.

### 워커 간 통신

4개 워커는 리더를 경유하지 않고 **서로 직접 `SendMessage`한다** (각 `.md`의 "팀 통신 프로토콜" 절 참조). 리더에게는 각 워커가 자신의 최종 보고서만 단일 보고한다. 도메인 교차 발견(예: SQL 인젝션이 설계 경계면과도 관련)은 `cross-domain` 태그로 동료에게 전달한다.

### 워커별 도구 경계 (중요 — 위반하면 스킬 계약 파괴)

| 에이전트 | 도구 | 모델 | 편집 가능 범위 |
|---|---|---|---|
| static-analyzer | Read, Grep, Glob, Bash | haiku | 없음 (발견만 보고, `tsc`/`eslint` 등 도구 출력 인용 필수) |
| design-reviewer | Read, Grep, Glob | opus | 없음 (Bash도 없음 — 두 파일을 동시에 읽어 시그니처 교차 비교) |
| security-auditor | Read, Grep, Glob, Bash | sonnet | 없음 (모든 발견에 CWE 번호 병기 필수) |
| refactorer | Read, Grep, Glob, Edit | opus | **`_workspace/patches/*.diff`만.** `src/` 등 소스 트리는 Read 전용 |

리뷰어 3인은 코드를 절대 편집하지 않는다 — patch 제안이 떠올라도 refactorer에게 `SendMessage`로 넘긴다. refactorer도 소스 파일을 직접 고치지 않고 unified diff 패치 파일만 생성한다.

## 불변 규칙

- **자동 커밋 금지**: 전체 워크플로에서 `git commit` 호출 0건. `SKILL.md`는 `gh pr comment`까지만 실행한다.
- **workspace 보존**: `TeamDelete` 이후에도 `_workspace/`는 삭제하지 않는다 (사람이 재검토할 수 있게).
- **생성-검증 루프 ≤ 3회**: refactorer가 patch를 만들고 원 리뷰어가 재검증해 2회 거절되면 3회째는 사람에게 위임한다.
- **재실행**: "리뷰 재실행" 키워드로 동일 `prNumber`를 같은 팀 정의로 재구동 가능 (이전 `_workspace/review/*` 결과는 덮어쓴다).

## 검증 문서 읽는 법

새 Phase나 워커를 수정했다면 `run/skill-fidelity.md`(책 원본 의사코드 p192-194와의 diff 대조표)와 `run/tool-classification.md`(공식 도구 vs 의사 함수 분류표)를 함께 갱신해 SKILL.md와의 정합성을 유지한다. `run/checklist.md`는 이 예제의 완료 기준 체크리스트다.
