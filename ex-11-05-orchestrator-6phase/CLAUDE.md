# ex-11-05 — code-review-team 오케스트레이터

## 하네스: 코드 리뷰 자동화

이 디렉토리는 4 에이전트(static-analyzer / design-reviewer / security-auditor / refactorer) + 1 스킬(code-review-team)로 PR 리뷰를 수행한다. `SKILL.md`는 실제 Claude Code 도구(`Agent`, `Bash`)만으로 동작하며, 반복 로직(diff 확보·검증 라우팅·판정·보고서 병합·patch 적용)은 `scripts/`의 결정적 셸 스크립트 5개가 담당한다.

## 트리거 키워드
- "코드 리뷰", "PR 리뷰", "리뷰 재실행", "다시 실행"
- 위 키워드는 `code-review-team` 스킬에 라우팅

## 구성
- `.claude/skills/code-review-team/SKILL.md` — 오케스트레이터 (6 Phase)
- `.claude/skills/code-review-team/scripts/*.sh` — resolve-diff / route-verification / judge-verdict / merge-reports / apply-patches
- `.claude/agents/*.md` — 워커 4인 정의
- `tests/` — 5개 스크립트의 bash 테스트 하네스 (`tests/run-all.sh`)

## 규칙
- 리더는 리뷰 내용을 읽고 판단하지 않는다 — 라우팅은 스크립트 출력을, 검증은 `VERDICT:` 한 줄만 본다
- 워커 간 peer 통신 없음 — 모든 조정은 리더 경유(리더 허브형)
- 자동 커밋 금지 (git commit 0건, working tree만 `git apply`로 변경)
- workspace 보존 (`_workspace/`는 삭제하지 않음)
- refactorer 생성-검증 루프 ≤ 3회 (patch 단위, `judge-verdict.sh`가 판정)
- 이식성: `.claude/skills/code-review-team/` + `.claude/agents/*.md`를 폴더째 다른 저장소에 복사하면 그대로 동작한다

## 참고
이 스킬은 원래 책 11장 의사코드(`TeamCreate`/`TaskCreate`/`TeamDelete` 등 이 환경에 존재하지 않는 도구를 전제)를 실제 동작 가능한 형태로 재작성한 것이다. 재설계 배경은 `../docs/superpowers/specs/2026-08-17-code-review-team-rewrite-design.md`, 구현 계획은 `../docs/superpowers/plans/2026-08-17-code-review-team-rewrite.md` 참고. `run/*.md`는 재작성 이전(책 의사코드 충실도 검증 시절)의 기록이며 현재 아키텍처를 반영하지 않는다.
