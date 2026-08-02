# ex-05-13 — SKILL.md 실무 리뷰 스킬

ex-05-05(분리 신호)·ex-05-09(컨텍스트 절약 3원칙)·ex-05-12(안티패턴 3종)의 진단 기준을 통합하고 Anthropic 공식 스킬 작성 가이드 항목을 보강해, 임의 프로젝트에 그대로 복사해 쓸 수 있는 실무용 SKILL.md 리뷰 스킬 `reviewing-skill-md`를 만들고 저장소 내 실제 SKILL.md 3종에 적용한다.

## 실행
`bash .claude/skills/reviewing-skill-md/scripts/collect-metrics.sh <SKILL.md 경로>`로 정량 지표를 뽑고, `reviewing-skill-md` 스킬을 호출해 리포트를 생성한다.

## 보기
`.claude/skills/reviewing-skill-md/{SKILL.md,references/checklist.md,scripts/collect-metrics.sh}`, `result/review-{sql-query,csv-summary,pr-review-orchestrator}.md`.

## 결과 요약
| 대상 | 줄 수 | 종합 판정 | 공통 개선 포인트 |
|---|---|---|---|
| ex-05-06 `sql-query` | 15 | low | description 트리거 재배치, 개요 섹션 부재 |
| ex-05-11 `csv-summary` | 18 | low | description 트리거 재배치, 개요 섹션 부재 |
| ex-06-12 `pr-review-orchestrator` | 120 | low | description 워크플로 요약(SDO 위험), 사용 시점 섹션 부재 |

세 스킬 모두 크기·안티패턴(C/D 카테고리)에서는 전부 pass — 실제로 배포된 스킬답게 구조적 결함은 없었다. 공통으로 걸린 것은 A(트리거 중심 서술)와 B(권장 섹션)뿐이며, 이는 크래프팅된 위반 샘플이 아니라 실제 파일을 리뷰했기 때문에 나온 현실적인 결과다.
