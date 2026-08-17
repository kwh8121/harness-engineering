# ex-11-05 — code-review-team 오케스트레이터

> 책 11장 code-review-team 의사코드를, 이 환경에 존재하지 않는 도구(TeamCreate/TaskCreate/TeamDelete 등)를 전제한 상태에서 실제 Claude Code 도구(`Agent`, `Bash`)만으로 동작하는 형태로 재작성했다.

## 구성
- `.claude/skills/code-review-team/SKILL.md` — 오케스트레이터 (6 Phase)
- `.claude/skills/code-review-team/scripts/*.sh` — `resolve-diff` / `route-verification` / `judge-verdict` / `merge-reports` / `apply-patches`. 반복 로직(diff 확보·검증 라우팅·판정·보고서 병합·patch 적용)을 담당하는 결정적 셸 스크립트 5개.
- `.claude/agents/*.md` × 4 — static-analyzer / design-reviewer / security-auditor / refactorer
- `tests/` — 5개 스크립트의 bash 테스트 하네스. `bash tests/run-all.sh`로 전체 실행 (55개 assertion)
- `run/checklist.md`, `run/skill-fidelity.md`, `run/tool-classification.md` — 재작성 이전(책 의사코드 충실도 검증 시절) 기록. 현재 아키텍처를 반영하지 않는다.

## 트리거
"코드 리뷰", "PR 리뷰", "리뷰 재실행", "다시 실행" → `code-review-team` 스킬로 라우팅

## 아키텍처 요약
- 리더(SKILL.md)는 판단 없이 `Agent`/`Bash` 호출만 한다 — 보고서 본문은 워커 4인이, 반복 로직은 `scripts/`가 담당.
- 워커 간 직접 통신 없음 — 모든 조정은 리더 경유(리더 허브형).
- patch 생성-검증 루프는 `judge-verdict.sh`가 `PASS`/`RETRY`/`REJECTED`로 판정하며 patch당 최대 3회 시도.
- `git commit` 호출 없음 — `apply-patches.sh`가 working tree만 `git apply`로 변경한다.
- 이 폴더(`.claude/skills/code-review-team/` + `.claude/agents/*.md`)를 통째로 다른 저장소에 복사하면 별도 설치 없이 동작한다.

## 실행
`bash tests/run-all.sh`로 스크립트 테스트를 먼저 확인한 뒤, "코드 리뷰" 트리거로 스킬을 호출한다. PR 번호 없이 호출하면 로컬 git diff(staged/unstaged/브랜치 base)를 자동 판별해 리뷰한다.

설계 배경은 `../docs/superpowers/specs/2026-08-17-code-review-team-rewrite-design.md`, 구현 계획은 `../docs/superpowers/plans/2026-08-17-code-review-team-rewrite.md` 참고.
