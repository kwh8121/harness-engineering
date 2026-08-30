# harness-architect — 적응형 하네스 라우터

## 하네스: 작업에 맞는 하네스를 작업마다 새로 고른다

이 디렉토리는 스킬 1개(`harness-architect`) + 에이전트 카탈로그 7종으로 구성된다.
개발 업무를 자연어로 받으면 6축 프로파일링 → H0~H3 판정 → `HarnessSpec` 산출 → 승인 → 실행 순으로 진행한다.

**Harness Architect 자체는 Agent 가 아니라 Skill 이다.** 분석·판정·구성안 생성은 Skill 이 하고,
실제 작업 수행만 카탈로그의 Agent 가 한다. H3 으로 판정된 경우에만 `orchestrator` 가 활성화된다.

## 트리거 키워드
- "구현해줘", "기능 추가", "리팩터링", "마이그레이션", "이 작업 어떻게 진행", "하네스", "에이전트 구조"
- 위 키워드는 `harness-architect` 스킬에 라우팅

## 구성
- `.claude/skills/harness-architect/SKILL.md` — Phase −1~5 오케스트레이터 (Phase −1 은 세션 재개 판정)
- `.claude/skills/harness-architect/references/*.md` — profiling / routing / catalog / context-budget / linear-tracking
- `.claude/skills/harness-architect/schemas/harness-spec.yaml` — 실행 계약 스키마
- `.claude/skills/harness-architect/examples/*.yaml` — H0~H3 판정 사례 4종
- `.claude/skills/harness-architect/scripts/` — detect-stack / run-gates / init-workspace /
  gate-summary / harness-paths / check-superpowers (셸),
  validate-spec / guard-readonly / checkpoint / resume-check (파이썬)
  - checkpoint / resume-check 는 `_workspace/harness/state.json` 으로 세션 간 재개를 지원한다.
    `checkpoint.py` 의 `CATALOG` 상수는 `validate-spec.py` · `references/catalog.md` 의 7종과 같아야 한다.
- `.claude/settings.json` — guard-readonly 를 PreToolUse 훅으로 등록
- `.claude/agents/*.md` — 카탈로그 7종
- `tests/` — 스크립트 bash 테스트 (`bash tests/run-all.sh`)
- `fixtures/`, `evals/` — 테스트 픽스처와 라우팅 판정 eval 기록

## 규칙
- 최소 하네스 우선 — 안전하게 완료 가능한 가장 단순한 구조를 고른다. 승격에는 근거 문장이 필요하다
- 승인 없이 에이전트를 스폰하지 않는다 (Phase 3 게이트)
- 결정론적 검증은 `run-gates.sh` 의 exit code 가 판정한다 — AI 리뷰어에게 린트·타입·테스트를 시키지 않는다
- 게이트 명령을 지어내지 않는다 — 스택 미감지 시 사용자에게 묻는다
- 역할을 새로 만들지 않는다 — 에이전트는 카탈로그 7종에서만 고르고, 반복 Procedure 는 Skill 로 처리한다
- 컨텍스트는 파일 경로로 전달한다 — 보고서 본문·세션 히스토리를 dispatch 프롬프트에 붙여넣지 않는다
- 구현 워커를 동시에 여러 개 dispatch 하지 않는다 (`max_workers: 3` 은 병합 단위 수)
- 리뷰 루프 상한 2회 (risk: high 만 3회) — 초과 시 고치지 말고 사람에게 넘긴다
- 자동 커밋 금지, `_workspace/` 보존
- 진행을 기록한다 — Phase 전환·역할 완료마다 `checkpoint.py`. 기록 실패는 멈추지 않지만 조용히 넘기지도 않는다
- 승인은 세션을 넘어 상속되지 않는다 — Phase 3 이상에서 재개하면 `resume-check.py` 가 exit 11 로 사람에게 넘기고, 새로 승인받는다
- Linear 쓰기는 컨트롤러만 한다 — 워커·orchestrator 는 상태 토큰만 반환한다
- H0 은 Linear 에 기록하지 않는다. 추적 실패는 하네스를 멈추지 않는다
- 이식성: `.claude/skills/harness-architect/` + `.claude/agents/*.md` 를 폴더째 복사하면 그대로 동작한다

## 참고
설계 근거는 `../docs/guides/harnes-architect.md`(하네스 컴파일러 구조)와
`../docs/guides/multiagent-pattern.md`(Single → Pipeline → Fan-out → Supervisor 승격 원칙),
구현 스펙은 `../docs/superpowers/specs/2026-08-29-harness-architect-design.md` 참고.
절차적 지식은 위임 스킬 12종(superpowers 6.3.0 의 11개 + security-review)에 위임한다 — 매핑표는 `references/catalog.md`.

이 폴더를 다른 저장소로 옮기려면 `MIGRATION.md`, 설치 후 사용법은 `USAGE.md` 참고.
