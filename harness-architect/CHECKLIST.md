# harness-architect 체크리스트

두 가지 용도다.

- **A. 활용** — 실제 작업에 스킬을 쓸 때, 운영자가 각 Phase 에서 확인할 것
- **B. 완성도 점검** — 스킬 자체가 온전한지 검증할 때 (수정 후·이식 후·정기 점검)

A 는 매 작업마다, B 는 스킬을 고친 뒤에 돌린다.

---

# A. 활용 체크리스트

## A-0. 시작 전

- [ ] 작업 디렉터리가 `.claude/` 가 있는 **프로젝트 루트**다 (스킬의 모든 경로가 상대 경로)
- [ ] `bash .claude/skills/harness-architect/scripts/init-workspace.sh` 를 돌렸다
  - exit 0 → `_workspace/harness/gates.tsv` 확보
  - exit 3 → **게이트를 지어내지 않고** 사용자에게 검증 명령을 물어 직접 기록했다
- [ ] `gates.tsv` 의 명령을 **손으로 한 번 돌려봤다**. 전부 exit 0 인가?
      (변경 전부터 깨져 있는 게이트를 모르고 시작하면 나중에 회귀로 오인한다)

## A-1. Phase 2 판정 검토 — 스킬이 낸 판정을 사람이 반증해 본다

- [ ] 6축 각각에 **레포에서 확인한 근거 한 줄**이 붙어 있다 (추측 표현 없음)
- [ ] `rationale` 에 **한 단계 아래를 고르지 않은 이유**가 있다. 없으면 아래 레벨이 맞다
- [ ] 카탈로그 7종 밖의 에이전트가 없다

**거부해야 하는 판정 조합** — 하나라도 걸리면 재판정을 요구한다:

| 증상 | 무엇이 잘못됐나 |
|---|---|
| `coupling: high` 인데 `parallelism ≠ none` | 축 모순 (`profiling.md` 규칙 위반) |
| `uncertainty: high` + `risk: high` + 단위 2개 이상 + `level: H1` | Under-Orchestration. 호출부를 다 모르는 위험한 변경을 한 명에게 통째로 맡기는 꼴 |
| `side_effect: irreversible` 또는 `target_environment: production` 인데 `human_gate: false` | STEP 5 누락 |
| 영역이 여러 개라는 이유만으로 H2 | 영역 개수 ≠ 작업 단위 개수 |
| `risk: high` 가 레벨 승격 근거로 쓰임 | risk 는 reviewer 유무와 `max_loops` 만 바꾼다. Human Gate 는 STEP 5(`side_effect`·환경·시크릿·삭제)가 정한다 |
| H3 인데 재라우팅 시나리오가 구체적이지 않음 | 실패 원인 3갈래를 못 대면 H2 로 충분 |

## A-2. Phase 3 승인 게이트

- [ ] **승인을 요청받기 전에 에이전트가 스폰되지 않았다**
- [ ] `_workspace/harness/spec.yaml` 이 실제 파일로 존재한다 (대화 속 요약이 아니라)
- [ ] 요약에 레벨·에이전트와 모델·게이트·`max_loops`·Human Gate 가 전부 있다
- [ ] **추적 대상이 만들어졌고 상태가 `Triage` 다** (`tracking.provider: linear` 인 경우)
      — H1 은 Issue 1건, H2/H3 는 Project + 단위별 Issue. H3 이면 `depends_on` 이
      `blockedBy` 로 걸려 있는가? 링크를 요약에 보였는가?
      (H0 은 추적하지 않는 것이 정상이다)
- [ ] **수용 기준마다 그것을 확인하는 게이트가 있다** — `verification.local`/`final` 의 tier 를
      합쳤을 때 `gates.tsv` 의 해당 명령이 실제로 포함되는가?
      게이트로 확인 불가능한 항목은 `verification.manual` 에 있는가?
      어느 쪽에도 없는 수용 기준은 **검증되지 않은 채 완료 선언된다**
      (예: "테스트가 통과한다"인데 `feature` tier 가 어디에도 없는 경우)

## A-3. Phase 4 실행 중

- [ ] 게이트 실패를 **reviewer 에게 보내지 않았다** (게이트 통과 후에만 리뷰)
- [ ] 구현 워커를 **동시에 여러 개 dispatch 하지 않았다**
- [ ] 모든 dispatch 에 `model` 이 명시됐다
- [ ] 보고서를 **본문이 아니라 경로로** 넘겼다
- [ ] 리뷰 루프가 `max_loops` 를 넘지 않았다. 넘었으면 고치지 않고 사람에게 넘겼다
- [ ] 같은 게이트가 3회 연속 실패했을 때 추측 수정을 멈추고 `systematic-debugging` 으로 갔다
- [ ] (H2/H3) `dependency-mapper` 가 `INDEPENDENCE: REJECTED` 를 냈다면 레벨을 강등하고 **재승인**받았다
- [ ] **Linear 를 컨트롤러만 썼다** — 워커·orchestrator 의 응답에 Linear 도구 호출이 없다
- [ ] **게이트 코멘트에 로그 전문이 붙지 않았다** — `gate-summary.sh` 출력(명령·exit code·경로)만
- [ ] **Phase 전환마다 코멘트 1건**을 넘지 않았다. 리뷰 루프는 종료 시 1건으로 요약했다

## A-4. Phase 5 종료

- [ ] `run-gates.sh final` 의 **exit code 를 실제로 봤다**
- [ ] 완료 선언에 실행한 명령과 그 출력이 붙어 있다 (`verification-before-completion`)
- [ ] `human_gate.required` 였다면 증거(게이트 로그 경로 + diff 통계 + 롤백 절차)를 제시하고 멈췄다
- [ ] `git commit` 이 호출되지 않았다
- [ ] `_workspace/` 가 남아 있다

---

# B. 완성도 점검 체크리스트

## B-1. 결정론적 검증 — 명령이 판정한다

작업 디렉터리는 `harness-architect/`.

- [ ] **스크립트 테스트** — `bash tests/run-all.sh`
      → 기대: `=== all tests passed ===`, PASS 35 / FAIL 0

- [ ] **YAML 파싱** (스키마 + 예제 4종)
      ```bash
      python3 -c "
      import yaml,glob
      for f in sorted(glob.glob('.claude/skills/harness-architect/examples/*.yaml'))+['.claude/skills/harness-architect/schemas/harness-spec.yaml']:
          yaml.safe_load(open(f)); print('OK', f.split('/')[-1])"
      ```
      → 기대: OK 5줄

- [ ] **예제의 축 모순 없음** — `coupling: high` 면 `parallelism: none` 이어야 한다
      ```bash
      python3 -c "
      import yaml,glob
      for f in sorted(glob.glob('.claude/skills/harness-architect/examples/*.yaml')):
          p=yaml.safe_load(open(f))['profile']
          assert not (p['coupling']=='high' and p['parallelism']!='none'), f
      print('축 모순 없음')"
      ```

- [ ] **에이전트 frontmatter 4필수키** (`name`/`description`/`model`/`tools`)
      ```bash
      for f in .claude/agents/*.md; do
        echo "$(basename $f): $(awk '/^(name|description|model|tools):/{c++} /^---$/{if(++d==2)exit} END{print c}' "$f")/4"
      done
      ```
      → 기대: 7개 파일 전부 `4/4`

- [ ] **카탈로그 표 ↔ 에이전트 frontmatter 일치** — `references/catalog.md` 의 model·tools 열이
      실제 파일과 같은가. 어긋나면 문서가 거짓말을 하는 것이고, 도구 경계 근거가 무의미해진다

- [ ] **도구 경계 유지** — 이 세 가지가 깨지면 설계가 무너진다
      ```bash
      for a in reviewer orchestrator; do
        grep "^tools:" .claude/agents/$a.md | grep -q "Edit" \
          && echo "FAIL $a: tools 에 Edit 이 있다" || echo "OK   $a"
      done
      grep "^tools:" .claude/agents/dependency-mapper.md | grep -q "Write" \
        && echo "FAIL dependency-mapper: tools 에 Write 가 있다" || echo "OK   dependency-mapper"
      ```
      → 기대: OK 3줄. **`tools:` 행만 봐야 한다** — 본문 산문에 "Edit 없음" 같은 설명이 있어서
      파일 전체를 `grep` 하면 반대로 판정된다
      - `reviewer` 에 Edit 없음 (리뷰어가 고치면 독립 검증이 무너진다)
      - `orchestrator` 에 Edit 없음 (Orchestrator 는 코드를 쓰지 않는다)
      - `dependency-mapper` 에 Write 없음 (조사 전용)

      > **이 검사만으로는 부족하다**: `Edit` 제거는 *정식 편집 경로*만 막는다.
      > `Write`·`Bash` 우회는 위의 `guard-readonly.py` 훅이 담당하므로 **두 검사를 함께** 본다.
      > 훅을 걸지 않았다면 이 행들은 "프롬프트 준수에만 의존" 으로 내려간다.
      > 강제 수준 표는 `references/catalog.md` 참고.

- [ ] **HarnessSpec validator 가 정상 spec 4종을 통과시킨다**
      ```bash
      for f in .claude/skills/harness-architect/examples/*.yaml; do
        python3 .claude/skills/harness-architect/scripts/validate-spec.py "$f" | tail -1
      done
      ```
      → 기대: `통과 (경고 0건)` 4줄

- [ ] **게이트 요약이 로그 전문을 흘리지 않는다**
      ```bash
      bash tests/test-gate-summary.sh
      ```
      → 기대: 전부 PASS. 특히 "로그 전문을 붙이지 않는다" 항목

- [ ] **읽기 전용 가드 훅이 소스 쓰기를 거부한다**
      ```bash
      echo '{"hook_event_name":"PreToolUse","agent_type":"reviewer","agent_id":"s1",
             "tool_name":"Write","tool_input":{"file_path":"src/x.ts","content":"y"}}'         | python3 .claude/skills/harness-architect/scripts/guard-readonly.py
      ```
      → 기대: `"permissionDecision": "deny"` 가 포함된 JSON

- [ ] **`.claude/settings.json` 이 훅을 등록하고 있다** — 없으면 가드는 걸리지 않는다
      (`python3 -c "import json;print(json.load(open('.claude/settings.json'))['hooks']['PreToolUse'])"`)

- [ ] **SKILL.md 심사** — `bash ../ex-05-13-skill-md-reviewer/.claude/skills/reviewing-skill-md/scripts/collect-metrics.sh .claude/skills/harness-architect/SKILL.md`
      → 기대: `line_count` < 300, `frontmatter_chars` < 800, `has_references_dir: yes`,
      description 이 트리거 조건으로 시작

- [ ] **SKILL.md 가 참조하는 경로가 실존** — references 4종·schemas·scripts 3종
      (`_workspace/harness/spec.yaml` 은 런타임 산출물이라 없는 게 정상)

- [ ] **README 의 수치가 실측과 일치** — SKILL.md 줄 수 / 에이전트 수 / 픽스처 수 / assertion 수

## B-2. 판정 품질 — eval

- [ ] `evals/results/` 3건이 `evals/README.md` 의 기대값과 일치한다
      (현재: 01 → H0/0/false, 02 → H1/2/false, 03 → H3/7/true)
- [ ] 판정 트리(`routing.md`)나 축 규칙(`profiling.md`)을 고쳤다면 **3건 전부 재실행**했다
      — 한쪽을 고치면 반대 방향으로 틀어질 수 있다 (실제로 1차에서 발생)
- [ ] 새 eval 케이스를 추가할 때 **기대값을 판정자에게 알려주지 않았다**
- [ ] 실패한 실행 기록을 지우지 않고 폐기 배너와 함께 남겼다

## B-3. 아직 검증되지 않은 것 — 여기가 현재 완성도의 실제 경계다

아래는 "안 된다"가 아니라 **"된다고 확인된 적이 없다"** 이다. 실제 작업에 쓰기 전에 채우는 것이 좋다.

- [ ] **H2 경로가 한 번도 선택된 적 없다** — eval 3건이 H0/H1/H3 만 밟았다
      → 확인 방법: 독립 모듈 3개 이관 같은 입력으로 eval 케이스 04 를 추가한다
- [ ] **Phase 4 실행이 끝까지 돌아본 적 없다** — eval 은 Phase 0~3 만 수행한다
      → 확인 방법: 실제 소규모 작업(H0 또는 H1)을 스킬로 처음부터 끝까지 한 번 처리한다
- [ ] **에이전트 7종 중 실제로 dispatch 된 것이 0종이다** — 정의만 있고 실행 이력이 없다
      → 확인 방법: 위 Phase 4 실행에서 `implementer` + `reviewer` 부터 검증한다
- [ ] **`run-gates.sh` 가 실제 린트·타입·테스트 명령으로 검증되지 않았다**
      — 테스트는 `echo` 와 `sh -c 'exit 3'` 으로만 돌렸다
      → 확인 방법: Node 또는 Python 실제 프로젝트에서 `detect-stack` → `run-gates fast` 를 돌려본다
- [ ] **`detect-stack.sh` 가 실제 프로젝트에서 검증되지 않았다** — 픽스처 5종으로만 확인했다
      → 특히 `package.json` 의 `scripts` 블록이 한 줄로 압축된 경우, 중첩 객체가 있는 경우
- [ ] **`max_loops` 상한이 실제로 루프를 끊는지 검증되지 않았다**
- [ ] **Human Gate 가 실제로 실행을 멈추는지 검증되지 않았다**
- [ ] **가드 훅이 실제 서브에이전트 dispatch 에서 거부하는지 검증되지 않았다**
      — `guard-readonly.py` 는 단위 테스트(합성 훅 입력 21건)로만 확인했다.
      실제로 `agent_type` 이 `reviewer` 로 실려 오는지, 훅이 실제 dispatch 를 막는지는 미검증
      → 확인 방법: reviewer 를 실제 dispatch 해 소스 수정을 지시하고 거부되는지 본다
- [ ] **Linear 추적이 실제 워크스페이스에서 한 번도 실행되지 않았다**
      — 매핑·정책·`gate-summary.sh` 렌더링은 확정했지만 실제 Project·Issue 생성,
      상태 전환, `blockedBy` 연결, Human Gate 대기는 미검증
      → 확인 방법: H1 작업 하나를 `tracking.provider: linear` 로 끝까지 돌려
      Issue 가 Triage→Todo→In Progress→In Review→Done 을 밟는지 본다
- [ ] **`human_gate_approval: linear` 의 대기 상한이 정해지지 않았다**
      — 무한 대기 금지는 규칙으로만 있고 기본 상한값이 없다
      → 확인 방법: 실제 대기 모드를 한 번 돌려보고 적정 상한을 정한다
- [ ] **가드 훅의 우회 경로가 열려 있다** (설계상 한계)
      — 셸을 파싱하지 않고 쓰기 구문을 패턴으로 찾으므로 변수 확장, base64,
      인터프리터 파이프는 잡지 못한다. **샌드박스가 아니라 규율 장치다**
      → 강제가 필요하면 OS 수준 권한이나 읽기 전용 마운트를 쓴다
- [ ] **`detect-stack.sh` 의 awk 폴백 경로가 검증되지 않았다**
      — python3·node 가 둘 다 없는 환경에서만 쓰이며, 한 줄 `package.json` 을 인식하지 못한다
      (그 경우 stderr 로 경고한다)

## B-4. 다른 저장소로 이식할 때

- [ ] `.claude/skills/harness-architect/` 와 `.claude/agents/*.md` **두 경로만** 복사했다
      (`tests/` · `fixtures/` · `evals/` 는 이식 경계 밖)
- [ ] 절대 경로 하드코딩이 없다 — `grep -rn "/home/\|/Users/" .claude/` 가 아무것도 내지 않는다
- [ ] 이식한 저장소에서 `init-workspace.sh` 가 게이트를 감지한다.
      감지 못 하면(exit 3) 그 저장소의 검증 명령을 `gates.tsv` 에 기록했다
- [ ] 대상 저장소에서 superpowers 스킬이 **실제로 discovery 되는지** 확인했다
      (`catalog.md` 매핑표의 12종). 설치 여부가 아니라 호출 가능 여부를 본다
      ```bash
      # 각 레벨의 최소 필수 스킬 — 하나라도 없으면 그 레벨은 중간에 끊긴다
      # H0: verification-before-completion
      # H1: + test-driven-development, requesting-code-review, receiving-code-review
      # H2/H3: + using-git-worktrees, writing-plans, subagent-driven-development,
      #          dispatching-parallel-agents
      ```
      **H0 도 superpowers 없이는 완결되지 않는다** — `verification-before-completion` 이
      전 레벨 필수다. superpowers 가 없는 환경으로 이식한다면 `routing.md` 의
      `REQUIRED SUB-SKILL:` 지시를 로컬 절차로 대체해야 한다
