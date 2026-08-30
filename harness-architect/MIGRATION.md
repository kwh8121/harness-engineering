# harness-architect 이전 가이드 — 다른 저장소로 옮기기

이 스킬을 처음 설치하는 사람을 위한 문서다. 이미 설치했고 매일 쓰는 방법이 궁금하면
`USAGE.md` 를 본다. 판정 결과를 반증하는 방법은 `CHECKLIST.md`, Linear 연동 상세는
`.claude/skills/harness-architect/references/linear-tracking.md` 를 본다.

## 이식 경계 — 옮길 것과 옮기지 않을 것

```
harness-architect/
├── .claude/
│   ├── skills/harness-architect/   ← 옮긴다 (스킬 본체)
│   ├── agents/*.md                 ← 옮긴다 (카탈로그 7종)
│   └── settings.json               ← 옮긴다 (읽기 전용 가드 훅) 또는 병합한다
│
├── tests/       ← 옮기지 않는다 (이 스킬 자체를 검증하는 테스트다. 대상 저장소를 검증하지 않는다)
├── fixtures/    ← 옮기지 않는다 (테스트용 가짜 프로젝트)
├── evals/       ← 옮기지 않는다 (판정 eval 기록)
└── *.md         ← 옮기지 않는다 (README/CLAUDE.md/CHECKLIST.md/USAGE.md/MIGRATION.md 는
                    이 예제 폴더 자체를 설명하는 문서다)
```

**옮기는 것의 구성**: SKILL.md 1 + references 5 + examples 4 + schemas 1 + scripts N +
agents 7 + settings.json 1. `scripts/` 는 계속 늘어나므로(현재: detect-stack · run-gates ·
init-workspace · gate-summary · harness-paths · check-superpowers · validate-spec ·
guard-readonly · checkpoint · resume-check) **고정 숫자를 박지 않는다** — 예전에 "25개"로
못박아 둔 탓에 트리가 커지는 동안 아무도 눈치채지 못했다. `examples/` 는 필수는 아니지만
(SKILL.md 실행에 쓰이지 않는다) 판정 사례 4종이 새 저장소에서 판정 근거를 쓸 때 참고
자료로 유용해 이식 경계 안에 둔다. 아래 명령으로 실측해 확인한다 —
**이식 후 값이 원본과 같으면 된다.**

```bash
find .claude -type f -not -path '*/__pycache__/*' | wc -l   # 원본과 대상이 같아야 한다
```

경로 하드코딩이 없어 통째로 복사하면 그대로 동작한다. 스크립트는 전부 `.claude/skills/harness-architect/scripts/` 를 기준으로 상대 경로를 쓰고, 훅은 `$CLAUDE_PROJECT_DIR` 환경 변수를 쓴다.

## 사전 요건

| 요건 | 없으면 무엇이 끊기는가 |
|---|---|
| Claude Code (스킬·서브에이전트·훅 지원 버전) | 스킬 자체가 로드되지 않는다 |
| Bash, `awk`, `grep` (POSIX 표준) | `detect-stack.sh`·`run-gates.sh`·`gate-summary.sh` |
| Python 3 | `validate-spec.py`, `guard-readonly.py`, `checkpoint.py`, `resume-check.py` |
| **PyYAML** (`pip install pyyaml`) — 선택 | 없으면 `validate-spec.py` 가 exit 2 로 "검증 불가"를 알린다. **하네스는 계속 동작하지만 Phase 3 의 계약 검증을 건너뛴다** — `CHECKLIST.md` A-2(=README "승인 게이트 확인")를 손으로 확인해야 한다. 세션 재개(`checkpoint.py`·`resume-check.py`)는 표준 라이브러리 `json` 만 쓰므로 PyYAML 없이도 동작한다 |
| superpowers 플러그인 (6.3.0 기준, `references/catalog.md` 매핑표 12종) | H0 도 `verification-before-completion` 이 필수라 완전히 끊긴다. 없으면 각 `REQUIRED SUB-SKILL:` 지시를 로컬 절차로 대체해야 한다 |
| Linear MCP — 선택 | `tracking.provider: linear` 을 쓸 수 없다. `none` 으로 두면 하네스는 그대로 동작한다 |

## 절차

### 1. 파일 복사

```bash
# 대상 저장소 루트에서 실행
SRC=/path/to/harness-architect
cp -r "$SRC/.claude/skills/harness-architect" .claude/skills/
cp "$SRC/.claude/agents/"*.md .claude/agents/
```

`.claude/settings.json` 은 **덮어쓰지 말고 병합**한다. 대상 저장소에 이미 훅이 있을 수 있다.

- 대상에 `.claude/settings.json` 이 없으면: 그대로 복사한다.
- 있으면: `hooks.PreToolUse` 배열에 아래 항목을 **추가**한다 (교체하지 않는다).

```json
{
  "matcher": "Write|Edit|MultiEdit|NotebookEdit|Bash",
  "hooks": [
    {
      "type": "command",
      "command": "python3 \"$CLAUDE_PROJECT_DIR/.claude/skills/harness-architect/scripts/guard-readonly.py\"",
      "timeout": 10
    }
  ]
}
```

같은 `matcher` 를 쓰는 기존 훅이 있어도 안전하다 — `guard-readonly.py` 는 `agent_type` 이
`reviewer`/`orchestrator`/`dependency-mapper` 일 때만 판정하고, 그 외에는 아무 출력 없이
exit 0 이다. 다른 훅의 `deny` 판정과 충돌하지 않는다(하나라도 deny 면 거부된다).

### 2. 스택 감지 확인

대상 저장소의 실제 검증 명령을 하네스가 찾아내는지 첫 번째로 확인한다 — 이게 안 되면
모든 것이 사람이 검증 명령을 불러줘야 하는 수동 모드로 떨어진다.

```bash
cd /path/to/target-repo
bash .claude/skills/harness-architect/scripts/init-workspace.sh
```

- **exit 0** — `_workspace/harness/gates.tsv` 가 생겼다. 명령들을 눈으로 읽고 실제로 이 저장소의
  린트·타입체크·테스트·빌드 명령이 맞는지 확인한다.
- **exit 3** — 스택 미감지. `detect-stack.sh` 는 `package.json`(npm/pnpm/yarn/bun),
  `pyproject.toml`/`requirements.txt`, `go.mod`, `Cargo.toml`, `pom.xml`/`build.gradle` 만 안다.
  다른 스택이면 `_workspace/harness/gates.tsv` 를 `tier<TAB>command` 형식으로 손으로 채운다.
  **감지 실패는 실패가 아니라 정직한 신호다** — 이 스크립트는 검증 명령을 추측해서 지어내지 않는다.

### 3. 계약 검증기가 실제로 예제를 판정하는지 확인

```bash
python3 .claude/skills/harness-architect/scripts/validate-spec.py \
  .claude/skills/harness-architect/examples/h1-pipeline.yaml
```

`h1-pipeline.yaml: 통과 (경고 0건)` 이 나오면 PyYAML 이 있고 validator 가 정상이다.
`ModuleNotFoundError` 가 나오면 `pip install pyyaml` 하거나, 없이 쓰기로 하고
Phase 3 계약 검증을 사람이 대신 확인하기로 한다 (`CHECKLIST.md` A-2).

### 4. 읽기 전용 가드가 실제로 걸리는지 확인

```bash
echo '{"hook_event_name":"PreToolUse","agent_type":"reviewer","agent_id":"s1",
       "tool_name":"Write","tool_input":{"file_path":"src/x.ts","content":"y"}}' \
  | python3 .claude/skills/harness-architect/scripts/guard-readonly.py
```

`"permissionDecision": "deny"` 가 포함된 JSON 이 나와야 한다. 아무것도 안 나오면
`.claude/settings.json` 에 훅이 등록되지 않은 것이다 (2단계로 돌아간다).

### 5. superpowers 위임 스킬이 실제로 발견되는지 확인

`references/catalog.md` 의 매핑표에서 최소 이것만 확인한다 — 전 레벨 필수라 없으면
H0 도 끊긴다.

```
superpowers:verification-before-completion
```

H1 이상을 쓸 계획이면 추가로: `test-driven-development`, `requesting-code-review`,
`receiving-code-review`. H2/H3 을 쓸 계획이면: `using-git-worktrees`, `writing-plans`,
`subagent-driven-development`, `dispatching-parallel-agents`.

없으면 스킬이 동작하지 않는다는 뜻이 아니다 — `SKILL.md`/`routing.md` 의
`REQUIRED SUB-SKILL:` 지시를 그 저장소의 로컬 절차로 바꿔 써야 한다는 뜻이다.

### 6. (선택) Linear 추적 연결

`tracking.provider: linear` 를 쓰려면:

- [ ] Linear MCP 가 연결되어 있다
- [ ] 대상 팀 이름을 확인했다 (`references/linear-tracking.md` 의 엔티티 매핑 참고)
- [ ] **실채택 전에 리허설을 한 번 돌린다.** 이 예제 폴더의 `LINEAR-DRY-RUN.md` 절차를
      대상 워크스페이스에서 그대로 따라 하면 상태 전환·코멘트 형식이 기대대로 보이는지
      실제 이슈로 확인할 수 있다 (끝나면 `Canceled` 로 정리한다).

연결하지 않으면 `tracking.provider: none` 으로 spec 을 쓴다. 하네스는 추적 없이도
전부 동작한다 — 이것이 설계 원칙이다 (`SKILL.md` 불변 규칙: "Linear 쓰기는 컨트롤러만 한다.
추적 실패는 하네스를 멈추지 않는다").

## 검증 — 이전이 끝났다고 부를 수 있는 기준

```bash
# 1) 파일 수가 원본과 맞다 (고정값 없음 — 원본에서 같은 명령을 돌려 비교한다)
find .claude -type f -not -path '*/__pycache__/*' | wc -l

# 2) 스택을 감지했다 (또는 손으로 gates.tsv 를 채웠다)
bash .claude/skills/harness-architect/scripts/init-workspace.sh; echo "exit=$?"

# 3) HarnessSpec 예제 4종이 전부 통과한다 (PyYAML 있을 때)
for f in .claude/skills/harness-architect/examples/*.yaml; do
  python3 .claude/skills/harness-architect/scripts/validate-spec.py "$f"
done

# 4) 읽기 전용 가드가 걸린다
echo '{"hook_event_name":"PreToolUse","agent_type":"reviewer","agent_id":"s1",
       "tool_name":"Write","tool_input":{"file_path":"src/x.ts","content":"y"}}' \
  | python3 .claude/skills/harness-architect/scripts/guard-readonly.py | grep -q deny && echo OK

# 5) 에이전트 7종의 frontmatter 가 4필수키를 갖췄다
for f in .claude/agents/*.md; do
  echo "$(basename "$f"): $(awk '/^(name|description|model|tools):/{c++} /^---$/{if(++d==2)exit} END{print c}' "$f")/4"
done

# 6) 세션 재개 판정이 동작한다 (state 없는 새 저장소이므로 exit 0)
python3 .claude/skills/harness-architect/scripts/resume-check.py; echo "exit=$?"   # 0
```

1~6 이 전부 기대대로면 이전이 끝난 것이다. 그다음은 `USAGE.md` 를 따라 실제 작업을 맡긴다.

## 흔한 실패

| 증상 | 원인 | 조치 |
|---|---|---|
| 스킬이 트리거되지 않는다 | `.claude/skills/harness-architect/SKILL.md` 의 `name` 이 다른 스킬과 충돌 | 대상 저장소에 동명 스킬이 있는지 확인 |
| `init-workspace.sh` 가 항상 exit 3 | 지원하지 않는 스택이거나 매니페스트 파일 위치가 다름 | `detect-stack.sh` 를 읽고 이 저장소의 패턴을 추가하거나 `gates.tsv` 를 손으로 쓴다 |
| 가드 훅이 아무것도 막지 않는다 | `.claude/settings.json` 미등록 또는 병합 시 배열을 덮어씀 | 4단계 재확인. `hooks.PreToolUse` 가 배열이고 항목이 남아있는지 본다 |
| `validate-spec.py` 가 `ModuleNotFoundError: yaml` | PyYAML 미설치 | `pip install pyyaml` 또는 없이 진행(A-2 를 손으로) |
| H0 인데도 `verification-before-completion` 을 못 찾는다 | superpowers 미설치 | 5단계. 로컬 절차로 대체하거나 플러그인 설치 |
| Linear 코멘트가 안 올라간다 | MCP 미연결 또는 팀 이름 오타 | 하네스는 계속 진행된다(설계상 의도) — 연결을 고치고 다음 Phase 전환부터 재개 |
