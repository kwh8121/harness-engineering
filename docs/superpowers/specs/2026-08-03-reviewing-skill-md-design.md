# reviewing-skill-md — SKILL.md 실무 리뷰 스킬 설계

## 배경 및 목적

이 저장소(`ex-05-05-separation-signals`, `ex-05-09-context-savings`, `ex-05-12-antipatterns`)에는 SKILL.md를 진단하는 3개의 예제가 이미 존재하지만, 모두 `.claude/agents/*.md` 형태의 **교재 시연용 에이전트**다. 의도적으로 위반을 심어 만든 크래프팅된 샘플 SKILL.md에 대해 `wc -l`/`grep` 기반 휴리스틱으로 dry-run 진단하는 것이 목적이며, 실제 프로젝트의 임의 SKILL.md에 곧바로 적용해 쓰도록 만들어진 것은 아니다.

이번 작업은 위 3개 예제의 진단 기준을 통합하고 Anthropic 공식 스킬 작성 가이드(`superpowers:writing-skills`)의 항목을 보강하여, **실제 프로젝트에 그대로 복사해 쓸 수 있는 실무용 SKILL.md 리뷰 스킬**을 만드는 것이다.

## 배치 위치

`ex-05-13-skill-md-reviewer/` (5장 "스킬 디자인 원리" 챕터의 실무 통합편, 기존 05-05/09/12 넘버링 다음)

```
ex-05-13-skill-md-reviewer/
  README.md
  CLAUDE.md
  .claude/skills/reviewing-skill-md/
    SKILL.md                  # 트리거 조건 + 실행 흐름만, 인라인 기준 없음
    references/
      checklist.md            # 전체 심사 기준 상세 (A~D 4개 카테고리)
    scripts/
      collect-metrics.sh      # 정량 지표 자동 수집 (wc, grep 기반)
  result/
    review-sql-query.md       # ex-05-06/sql-query/SKILL.md 리뷰 결과
    review-csv-summary.md     # ex-05-11/csv-summary/SKILL.md 리뷰 결과
    review-pr-review-orchestrator.md  # ex-06-12 리뷰 결과
```

`.claude/skills/reviewing-skill-md/` 디렉터리는 그 자체로 자기완결적이며, 다른 프로젝트의 `.claude/skills/`에 폴더째 복사하면 그대로 재사용 가능하도록 작성한다 (경로 하드코딩 없음, 이 저장소 특정 파일 참조 없음).

## 파일 구조 및 역할

- **SKILL.md**: frontmatter(`name`, `description`) + 트리거 조건 + 5단계 실행 흐름만 기술. 심사 기준 본문은 포함하지 않고 `references/checklist.md`를 참조하도록 링크. (스킬 자신이 자신의 심사 기준 중 "Progressive Disclosure 준수"를 실제로 지키는 예시가 되도록 함)
- **references/checklist.md**: A~D 4개 카테고리의 전체 심사 기준, 각 항목의 판정 규칙과 근거 산출 방법을 표로 정리.
- **scripts/collect-metrics.sh**: 대상 SKILL.md 경로를 인자로 받아 정량 지표를 고정된 방식으로 수집해 표준출력으로 반환. 실행마다 grep 패턴이 달라지는 것을 방지하기 위해 지표 수집은 전부 이 스크립트로 고정한다.

## 심사 기준 — 4개 카테고리

| 카테고리 | 출처 | 항목 |
|---|---|---|
| **A. Frontmatter & Discovery** | Anthropic 공식 가이드 | `name` 형식(영문/숫자/하이픈만), frontmatter 전체 1024자 이내, `description`이 "Use when..."으로 시작하는지, 워크플로 요약 대신 트리거 조건만 담는지, 3인칭 서술 여부 |
| **B. 구조 & 콘텐츠** | Anthropic 공식 가이드 | Overview/When to Use/Quick Reference/Common Mistakes 등 권장 섹션 존재 여부, flowchart 남용 여부(비결정적 분기 없는데 사용), 코드 예시 다중 언어 남발 여부 |
| **C. 크기 & 분리 신호** | ex-05-05 통합 | 줄 수(500줄 기준), 도메인 분기 키워드 수(2개 이상), 조건부 상세 존재+길이 → 분리 권고 여부 |
| **D. 안티패턴** | ex-05-09 + ex-05-12 통합 | 거대 본문(500줄↑), references 부재(도메인 분기 4개↑인데 위임 없음), 이유 없는 규칙(ALWAYS/NEVER/반드시/절대 ≥5 & 왜냐하면/때문에 =0), 일반 지식 서술(삭제 대상), 팀 고유 도메인 관례 누락 |

각 항목은 **pass/warn/fail** 3단계로 판정하고, 근거(수치 또는 본문 인용)와 권고 1줄을 함께 출력한다. 기존 3예제의 low/med/high 심각도 표기 방식을 pass/warn/fail로 일반화해 임의 파일에도 일관되게 적용할 수 있도록 한다.

## 실행 흐름

1. 사용자가 리뷰 대상 SKILL.md 경로(또는 스킬 디렉터리)를 지정해 스킬 호출
2. `scripts/collect-metrics.sh <path>` 실행 → 줄 수, 단어 수, frontmatter 파싱, 키워드 카운트 등 정량 지표 수집
3. Claude가 정량 지표 + `references/checklist.md` 기준으로 A~D 카테고리를 판정 (정성 항목은 파일 내용을 직접 읽고 판단)
4. 마크다운 리포트 출력

리포트 생성만 하며 자동 수정은 하지 않는다.

## 출력 포맷

```
# SKILL.md 리뷰: <경로>
개요: N줄 / N단어 / frontmatter Xchars

## A. Frontmatter & Discovery
- [pass|warn|fail] <항목> — 근거: <수치/인용> — 권고: <한 줄>
...
## B. 구조 & 콘텐츠
...
## C. 크기 & 분리 신호
...
## D. 안티패턴
...

## 종합 판정: high|med|low|pass
## 우선순위 개선 Top 3
```

종합 판정 기준 (아래 순서로 첫 번째 매칭 규칙 적용):
1. fail 2개 이상 또는 D 카테고리(안티패턴)에 fail 1개 이상 → **high**
2. fail 1개 → **med**
3. fail 0개, warn 1개 이상 → **low**
4. fail 0개, warn 0개(전부 pass) → **pass**

## 검증(테스트) 방법

크래프팅된 위반 샘플이 아니라, 이 저장소에 이미 존재하는 **실제 SKILL.md**에 스킬을 그대로 적용해 결과가 합리적인지 확인한다.

- `ex-05-06-domain-references/.claude/skills/sql-query/SKILL.md`
- `ex-05-11-with-without/.claude/skills/csv-summary/SKILL.md`
- `ex-06-12-pr-review-skill-md/.claude/skills/pr-review-orchestrator/SKILL.md`

각 리뷰 결과를 `result/review-*.md`로 저장하고, README에서 세 결과의 판정 요약을 표로 비교한다. 세 파일은 서로 다른 특성(단순/도메인 분기형/복잡한 오케스트레이션)을 가지고 있어 리뷰 스킬이 카테고리별로 변별력 있게 판정하는지 확인하기에 적합하다.

## README / 인덱스 갱신

- `ex-05-13-skill-md-reviewer/README.md`: 기존 예제 컨벤션(`# ex-05-13 — ...` 제목 + 짧은 설명 + `## 보기` 산출물 목록)을 따른다.
- 저장소 루트 `README.md`의 예제 인덱스 표에 5장 섹션 마지막 행으로 추가.

## 범위 제외 (YAGNI)

- 여러 SKILL.md를 한 번에 스캔하는 배치/디렉터리 순회 기능은 만들지 않는다. 한 번에 하나씩 리뷰하며, 여러 개는 반복 호출한다.
- 자동 수정(코드 편집) 기능은 만들지 않는다. 리포트 전용.
- 스킬 성능/토큰 사용량 측정(A/B 벤치마크) 같은 정량 효과 검증은 포함하지 않는다. 순수 정적 리뷰 기준만 다룬다.
