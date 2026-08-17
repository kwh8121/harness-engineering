> **[2026-08-17 이후 기록]** 이 문서는 code-review-team 재작성 이전(책 의사코드 충실도 검증 시절)의 기록이다. 현재 아키텍처는 실제 `Agent`/`Bash` 도구 기반이며, 여기 서술된 `TeamCreate`/`TaskCreate`/`TeamDelete`/`AgentTool` 전제는 더 이상 유효하지 않다. 최신 설계는 `../../docs/superpowers/specs/2026-08-17-code-review-team-rewrite-design.md` 참고.

# 셀프 체크 (ex-11-05)

- [x] `.claude/skills/code-review-team/SKILL.md` 작성
- [x] frontmatter: name = code-review-team / description 재실행 키워드 ≥3 (코드 리뷰·PR 리뷰·리뷰 재실행·다시 실행·리뷰 보고서) / allowed-tools 5 공식 + Bash 화이트리스트
- [x] 6 Phase 의사코드 본문 — 책 p192-194 일치 (skill-fidelity.md)
- [x] 공식 5종 vs 의사 4종 분류 (tool-classification.md)
- [x] TaskCreate for-루프 4회, 4번째 depends_on = ["정적 분석", "설계 검토", "보안 감사"]
- [x] AgentTool isolation: "worktree"
- [x] mergeReports priority = ["P0", "P1", "P2"]
- [x] result/dry-run-log.md 6 Phase 호출 로그
- [x] CLAUDE.md에 "하네스: 코드 리뷰 자동화" + 트리거
- [x] 4 에이전트 .md 복사 (ex-11-03/04로부터)
