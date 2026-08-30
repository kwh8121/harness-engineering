# harness-architect 재개(Resume) 설계·계획 재검토

- 재검토 일자: 2026-08-30
- 검토 대상:
  - `docs/superpowers/specs/2026-08-30-harness-resume-design.md`
  - `docs/superpowers/plans/2026-08-30-harness-resume.md`
- 이전 리뷰: `docs/superpowers/specs/2026-08-30-harness-resume-review.md`
- 반영 커밋:
  - `aed28f4` — 재개 설계 리뷰 반영
  - `e09d418` — 재개 구현 계획 리뷰 반영
- 판정: **REQUEST CHANGES — 기존 지적은 대부분 반영됐으나 구현 전 해결할 HIGH 3건이 남음**
- 신뢰도: 높음

## 1. 결론

이전 리뷰에서 제시한 승인 부활 방지, 손상 state fail-closed, task identity, 안전한 동기화,
역할 마일스톤, gate 메타데이터, checkpoint 실패 노출, settings 이식 경계는 문서에 반영됐다.

그러나 다음 세 계약은 아직 불완전하다.

1. `spec_digest`를 기록하지만 재개 시 현재 spec과 비교하지 않는다.
2. `tree_digest`가 실제 파일 내용이 아니라 `git status` 행만 해시한다.
3. syntactically valid JSON이지만 내부 구조가 손상된 state를 안전하게 거부하지 못한다.

위 세 항목은 재개 지점의 신뢰성을 직접 결정하므로 구현 전에 설계와 계획을 보완해야 한다.

## 2. 이전 리뷰 반영 결과

| 이전 지적 | 상태 | 확인 근거 |
|---|---|---|
| Phase 3 승인 자동 부활 | 해결 | `AUTO_MAX_PHASE = 2`; Phase 3 이상은 exit 11 |
| 손상 state를 빈 상태로 덮어쓰기 | 해결 | 파일이 없을 때만 `blank_state()`, 손상 시 exit 3 |
| 현재 요청과 이전 작업 구분 | 부분 해결 | `task.id`·`goal` 추가, 의미 동일성은 SKILL.md가 판단 |
| 파괴적 sync와 `git add -A` | 해결 | dry-run 선행, 소유 경로만 stage |
| dirty 변경 무시 | 부분 해결 | `tree_digest` 추가했으나 내용 변경을 완전히 포착하지 못함 |
| 역할 목록과 H2/H3 작업 단위 혼동 | 해결 | 역할 마일스톤으로 명시, 작업 단위는 SDD ledger가 소유 |
| 상태 전이 검증 부족 | 부분 해결 | 승인·agent·archive 검증 추가, replan 초기화 계약은 없음 |
| checkpoint 실패 은폐 | 해결 | 본 작업은 계속하되 stderr 경고 |
| gate 시도 정보 부족 | 해결 | `attempt`·`recorded_at`·`log_path` 추가 |
| 원자성 검증 부족 | 부분 해결 | 단일 writer 전제 명시, 실제 중단 fault test는 없음 |
| `.sh`/`.py` 명칭 불일치 | 해결 | 설계와 계획을 `.py` 기준으로 동기화 |
| settings 이식 경계 누락 | 해결 | Task 9에서 settings diff와 병합 절차 추가 |
| Lore Commit Protocol 미반영 | 미해결 | 커밋 예시는 여전히 변경 내용 중심 제목과 본문만 사용 |

## 3. 남은 차단 이슈

### [HIGH] H-1. `spec_digest`가 저장만 되고 검증되지 않는다

#### 증거

- 설계는 `task.spec_digest`가 승인된 `spec.yaml`의 SHA-256이며, 사용자가 spec을 손으로 수정했는지
  감지한다고 설명한다(`harness-resume-design.md:100-112`).
- 계획은 `--spec-digest` 옵션과 state 저장만 구현한다(`harness-resume.md:624`, `:681-682`).
- Phase별 checkpoint 호출 목록에는 spec digest 계산·전달이 없다(`harness-resume.md:1155-1163`).
- `resume-check.py`는 repo fingerprint만 비교하고 현재 spec 파일을 읽거나 해시하지 않는다
  (`harness-resume.md:881-916`).

#### 영향

승인 후 `_workspace/harness/spec.yaml`이 변경돼도 HEAD·branch·tree digest는 그대로일 수 있다.
특히 `_workspace/`는 tree digest에서 제외되므로 변경된 계약으로 잘못 재개할 수 있다.

#### 개선안

1. Phase 3 승인 직후 실제 spec 파일의 SHA-256을 계산해 `--spec-digest`로 기록한다.
2. `resume-check.py`가 `artifacts.spec`을 현재 메인 워크트리 기준으로 해석해 다시 해시한다.
3. 파일 부재 또는 digest 불일치는 drift로 기록하고 exit 11을 반환한다.
4. 다음 회귀 테스트를 추가한다.
   - spec 내용 변경 → exit 11
   - spec 파일 삭제 → exit 11
   - spec 내용 동일 → 기존 판정 유지

### [HIGH] H-2. `tree_digest`가 같은 파일의 추가 내용 변경을 놓친다

#### 증거

계획의 `tree_digest()`는 `git status --porcelain`의 행을 정렬해 SHA-256한다
(`harness-resume.md:369-380`). `git status`는 파일의 변경 여부와 경로를 나타내지만 변경 내용을
포함하지 않는다.

다음 상태는 같은 digest를 만든다.

1. `a.txt`가 이미 `M a.txt`인 상태에서 내용을 `first change`로 변경
2. 같은 파일을 다시 `second different change`로 변경

두 경우 `git status --porcelain`은 모두 동일한 `M a.txt`이므로 digest가 같다. 임시 Git 저장소에서
이를 직접 재현했다.

현재 테스트는 clean 상태에서 untracked 파일을 추가하는 경우만 확인한다
(`harness-resume.md:972-977`). 이 테스트는 경로 집합 변화만 검증하며 동일 경로의 내용 변화는 검증하지 않는다.

#### 영향

같은 HEAD와 같은 modified-file 목록을 유지한 채 코드 내용이 달라져도 자동 재개 후보 exit 10이 나올 수 있다.

#### 개선안

- tracked 변경은 `git diff --binary HEAD` 내용으로 해시한다.
- untracked 파일은 정렬한 상대 경로와 파일 내용 digest를 함께 반영한다.
- `_workspace/`만 정확한 pathspec으로 제외한다. 단순 substring 필터는 다른 경로의
  `_workspace/` 문자열까지 제외할 수 있다.
- “이미 수정된 같은 파일의 내용을 다시 변경 → exit 11” 회귀 테스트를 추가한다.

### [HIGH] H-3. 내부 구조가 손상된 state가 처리되지 않은 예외를 낼 수 있다

#### 증거

`resume-check.py`는 최상위가 dict인지와 `schema_version`만 확인한다
(`harness-resume.md:895-900`). 이후 다음 값을 올바른 타입으로 가정한다.

- `state.repo`는 dict라고 가정하고 `drift()`에서 `.get()` 호출
- `state.progress`는 dict라고 가정하고 `render()`에서 `.get()` 호출
- `progress.gates`의 각 항목은 dict라고 가정
- `task`와 `artifacts`도 dict라고 가정

예를 들어 아래 JSON은 문법과 schema version은 통과하지만 `drift()`에서 실패할 수 있다.

```json
{
  "schema_version": 1,
  "phase": "2",
  "repo": "broken"
}
```

현재 테스트는 깨진 JSON 문법과 미지원 schema version만 다루고 내부 타입 손상은 다루지 않는다
(`harness-resume.md:762-768`).

#### 영향

설계가 약속한 “손상 state는 처리되지 않은 예외 없이 exit 11” 계약을 충족하지 못한다.

#### 개선안

1. `validate_state(state) -> list[str]`를 추가한다.
2. `task`, `repo`, `artifacts`, `progress`의 mapping 타입과 필수 내부 필드를 검증한다.
3. agent/gate 목록과 scalar 필드 타입도 검증한다.
4. 오류가 하나라도 있으면 브리핑 가능한 최소 정보와 오류 목록을 출력하고 exit 11로 끝낸다.
5. `repo: "broken"`, `progress: []`, `gates: [null]` 회귀 테스트를 추가한다.

## 4. 추가 보완사항

### [MEDIUM] M-1. Phase 역행에는 명시적인 reset 계약이 필요하다

설계는 H2→H1 강등을 위해 Phase 4→3 역행을 허용한다(`harness-resume-design.md:126-140`).
그러나 계획의 `--phase 3`은 기존 다음 값을 초기화하지 않는다.

- `approved`
- `agents_done` / `agents_pending`
- `gates`
- `review_loops_used`
- `human_gate_passed`
- `spec_digest`

새 승인에서 agents 목록은 덮어쓰지만 이전 gate·리뷰·Human Gate 기록은 새 계획으로 이어질 수 있다.

**개선안:** 일반적인 phase 역행 대신 `--replan --level H1` 같은 전용 연산을 두고 승인·진행·spec digest를
초기화한다. 과거 기록을 보존해야 한다면 generation을 증가시키고 gate·review 항목에 generation을 붙인다.

### [MEDIUM] M-2. `--agents` 단독 사용과 중복 ID를 거부해야 한다

현재 계획은 `--approved`가 `--phase 3`과 함께인지 확인하지만, `--agents` 자체는 승인/Phase 조건 없이
사용할 수 있다. 중복 ID도 허용해 pending 목록에 같은 역할이 여러 번 들어갈 수 있다.

**개선안:** `--agents`는 `--phase 3 --approved`와 함께일 때만 허용하고, 빈 목록과 중복 ID를 거부한다.

### [MEDIUM] M-3. Lore Commit Protocol이 계획에 반영되지 않았다

Task별 커밋 예시는 여전히 `feat:`/`docs:` 제목과 일반 본문만 사용한다. 저장소 AGENTS.md는 의도 중심
제목과 Lore trailer 형식을 요구한다.

**개선안:** 각 예시를 의도 중심 제목으로 변경하고 최소한 다음 trailer를 포함한다.

```text
Confidence: high
Scope-risk: narrow|moderate
Tested: <실행한 테스트>
Not-tested: <남은 검증 공백>
```

### [LOW] L-1. Task 번호 제목이 중복되어 있다

계획에 `Task 4`와 `Task 5` 제목이 각각 두 번 연속 나타난다(`harness-resume.md:520`, `:710`).
동작에는 영향이 없지만 계획 실행자가 섹션 경계를 혼동할 수 있으므로 한 줄씩 제거한다.

### [LOW] L-2. 실제 원자성 fault test는 여전히 없다

단일 writer 전제가 명시돼 동시 writer 검증은 필수 범위에서 제외할 수 있다. 다만 임시 파일 잔여 없음은
중단 안전성을 직접 증명하지 않는다.

**개선안:** 선택적인 fault injection 테스트로 `os.replace` 전 예외 시 기존 state가 유지되는지만 확인한다.

## 5. 권장 반영 순서

### P0 — 구현 전 해결

1. spec digest 계산·저장·재검증 경로를 연결한다.
2. tree digest를 파일 내용 기반으로 변경한다.
3. state 내부 schema validation을 추가한다.

### P1 — 상태 전이 명확화

1. `--replan` 또는 generation 기반 reset 계약을 정의한다.
2. `--agents`의 호출 조건과 중복 검증을 강화한다.
3. 위 계약에 대응하는 negative test를 추가한다.

### P2 — 문서 품질

1. Lore Commit Protocol 형식으로 커밋 예시를 수정한다.
2. 중복 Task 제목을 제거한다.
3. 선택적인 atomic-write fault test를 추가한다.

## 6. 검증 결과

### 직접 확인

- 기존 `harness-architect/tests/run-all.sh`: `PASS 132 / FAIL 0`
- 현재 문서 diff: `git diff --check` 통과
- 임시 Git 저장소 probe:
  - 같은 파일이 계속 modified인 상태에서 내용만 변경
  - `git status --porcelain` 기반 digest가 동일함을 확인
- `spec_digest` 참조 검색:
  - 필드 정의·CLI 저장은 존재
  - 현재 spec 재해시·비교 경로는 없음
- state 내부 구조 validator 정의: 없음

### 기존 리뷰에서 해결된 항목

- Phase 3 승인 부활 금지
- 손상 state 덮어쓰기 금지
- task ID/goal 추가
- safe sync 및 explicit staging
- 역할 마일스톤/SDD ledger 경계
- checkpoint 오류 경고
- gate attempt/time/path 기록
- settings 이식 경계

### 아직 구현 후 확인해야 하는 항목

- 실제 세션 재시작에서 Phase -1 호출과 브리핑 순서
- 사용자 요청과 `task.goal`의 의미적 동일성 판정 품질
- SDD ledger와 역할 마일스톤의 실제 연결
- linked worktree 제거·재생성 시 경로 처리

## 7. 최종 판정

리뷰 반영으로 설계 품질은 크게 개선됐고 이전 HIGH 항목 대부분은 닫혔다. 그러나 `spec_digest`,
내용 기반 tree digest, state 내부 schema validation이 빠져 있어 현재 계획은 재개 무결성을 완전히
보장하지 못한다.

**최종 판정: REQUEST CHANGES. P0 세 항목을 설계·계획·테스트에 반영한 뒤 구현을 시작한다.**
