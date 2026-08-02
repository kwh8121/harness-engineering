# CLAUDE.md — ex-05-13 SKILL.md 실무 리뷰 스킬

- `.claude/skills/reviewing-skill-md/`는 다른 프로젝트에 폴더째 복사해 재사용 가능하도록 이 저장소 특정 경로를 하드코딩하지 않는다.
- 심사 기준(references/checklist.md)은 ex-05-05(분리 신호)/ex-05-09(컨텍스트 절약 3원칙)/ex-05-12(안티패턴 3종)의 판정 규칙을 그대로 보존해 통합한다.
- 정량 지표는 scripts/collect-metrics.sh로만 수집한다 (매 실행마다 다른 grep 패턴을 즉석에서 만들지 않는다).
- 리뷰 대상은 이 저장소에 이미 존재하는 실제 SKILL.md 3종(ex-05-06/sql-query, ex-05-11/csv-summary, ex-06-12/pr-review-orchestrator)이며, 크래프팅된 위반 샘플을 새로 만들지 않는다.
- 리포트는 생성만 하고 대상 파일을 자동 수정하지 않는다.
