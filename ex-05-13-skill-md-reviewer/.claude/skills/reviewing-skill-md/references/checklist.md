# SKILL.md 리뷰 체크리스트

## A. Frontmatter & Discovery
| 항목 | 판정 규칙 | 근거 소스 |
|---|---|---|
| name 형식 | `name` 값이 영문 소문자/숫자/하이픈만 포함(정규식 `^[a-z0-9-]+$`) 아니면 fail | collect-metrics.sh `name_value` |
| frontmatter 전체 길이 | frontmatter 블록 전체 문자 수가 1024자 초과 시 fail, 800~1024자 warn, 그 외 pass | collect-metrics.sh `frontmatter_chars` |
| 트리거 중심 서술 | description이 트리거 조건(영어 "Use when...", 한국어 "사용자가 ~하면", "~때 호출", "~인 경우" 등) 없이 스킬 기능·워크플로 설명으로만 채워져 있으면 fail. 트리거 조건 문장이 있으나 기능/워크플로 설명이 먼저 나오면 warn. 트리거 조건이 문장 맨 앞에 오면 pass. | description 텍스트 직접 확인 |
| 3인칭 서술 | description에 "I", "저는", "나는" 등 1인칭 표현이 있으면 fail | description 텍스트 직접 확인 |

## B. 구조 & 콘텐츠
| 항목 | 판정 규칙 | 근거 소스 |
|---|---|---|
| 권장 섹션 존재 | 개요 역할 섹션(Overview/개요/목표 등)과 사용 시점 역할 섹션(When to Use/사용 시점/언제 사용 등) 중 하나라도 없으면 warn | collect-metrics.sh `headers` (의미 등가 여부는 직접 판단) |
| flowchart 남용 | ` ```dot ` 블록 수가 2개 초과면 warn | collect-metrics.sh `dot_block_count` |
| 코드 예시 다중 언어 남발 | 동일 개념에 대해 3개 이상 언어의 코드 블록이 나란히 있으면 warn | 텍스트 직접 확인 |

## C. 크기 & 분리 신호
| 항목 | 판정 규칙 | 근거 소스 |
|---|---|---|
| 크기 신호 | 총 줄 수 >= 500 이면 fail, 300~499 warn, 그 외 pass | collect-metrics.sh `line_count` |
| 도메인 분기 신호 | 도메인 분기 키워드 매칭 수가 2 이상인데 `references/` 디렉터리가 없거나 본문에 도메인 상세 내용이 남아있으면: 2~3개는 warn, 4개 이상은 fail. `references/`가 있고 본문에는 위임 안내만 있을 뿐 도메인 상세 내용이 없다면 이미 해결된 것으로 보고 pass. | collect-metrics.sh `branch_keyword_count`, `has_references_dir` + 본문 직접 확인 |
| 조건부 상세 신호 | 조건부 문구("~때만", "~인 경우에만") 뒤에 10줄 이상의 상세 설명이 인라인으로 이어지면 warn (references로 위임 권고) | 텍스트 직접 확인 |

## D. 안티패턴
| 항목 | 판정 규칙 | 근거 소스 |
|---|---|---|
| 거대 본문 | 총 줄 수 >= 500 이면 fail (C의 크기 신호와 동일 지표 — 종합 판정 시 중복 카운트하지 않고 1건으로 취급) | collect-metrics.sh `line_count` |
| references 부재 | `references/` 디렉터리가 없고 도메인 분기 키워드 수 >= 4 이면 fail | collect-metrics.sh `has_references_dir`, `branch_keyword_count` |
| 이유 없는 규칙 | `ALWAYS`/`NEVER`/`반드시`/`절대` 매칭 수 >= 5 이고 `왜냐하면`/`때문에` 매칭 수 == 0 이면 fail | collect-metrics.sh `imperative_count`, `reason_count` |
| 일반 지식 서술 | 표준 언어/라이브러리 문법을 설명하는 문단이 있으면 warn (삭제 권고) | 텍스트 직접 확인 |
| 도메인 관례 누락 | 팀/프로젝트 고유 규칙이 있어야 할 자리가 비어 있으면 warn (추가 권고) | 텍스트 직접 확인 |

## 종합 판정 규칙
1. fail 2개 이상 또는 D 카테고리(안티패턴)에 fail 1개 이상 → **high**
2. fail 1개 → **med**
3. fail 0개, warn 1개 이상 → **low**
4. fail 0개, warn 0개(전부 pass) → **pass**
