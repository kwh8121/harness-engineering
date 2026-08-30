# harness-architect 재개(Resume) 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 세션이 끊기거나 Phase 중간에 멈춰도 다음 세션이 "어디까지 했고 다음에 무엇을 할지"를 한 화면으로 알 수 있게 한다.

**Architecture:** `_workspace/harness/state.json` 하나에 Phase 위치·승인 여부·단위별 진행·저장소 지문을 원자적으로 기록한다. `checkpoint.py` 가 쓰고 `resume-check.py` 가 읽어 exit code로 판정한다(0 없음 / 10 자동재개 / 11 사람판단 / 12 완료됨). 가장 중요한 두 기록 지점은 `init-workspace.sh` 와 `run-gates.sh` 에 얹어 자동화한다.

**Tech Stack:** Bash + POSIX awk/grep, Python 3 표준 라이브러리(`json` 만). 프레임워크 없는 자체 assertion 헬퍼(`tests/lib/assert.sh`).

**Spec:** [docs/superpowers/specs/2026-08-30-harness-resume-design.md](../specs/2026-08-30-harness-resume-design.md)

## Global Constraints

- **절대 경로 하드코딩 금지.** 모든 경로는 상대 경로이거나 런타임에 계산한다. `CHECKLIST.md` B-4가 `grep -rn "/home/\|/Users/" .claude/` 로 검사한다.
- **PyYAML에 의존하지 않는다.** 재개는 PyYAML이 없는 환경에서도 동작해야 한다. `json` 만 쓴다.
- **한국어**로 주석·문서·커밋 메시지를 쓴다. 변수명·함수명·필드명은 영어.
- **`_workspace/` 는 메인 워크트리 루트에 고정**된다(`harness-paths.sh`). worktree가 제거돼도 state는 살아남아야 한다.
- **`_workspace/` 를 삭제하지 않는다.** 은퇴는 삭제가 아니라 `state.done-<updated_at>.json` 으로의 보존이다.
- 테스트는 `tests/` 에만 둔다 — 이식 경계 밖이다(`CHECKLIST.md` B-4).
- 작업 디렉터리는 `harness-architect/`.

## 설계 대비 보완 2건

계획을 쓰며 스펙의 구멍 두 개를 찾았다. 구현은 아래를 따르고, Task 8에서 스펙 문서도 함께 고친다.

1. **`checkpoint.sh` → `checkpoint.py`, `resume-check.sh` → `resume-check.py`.** JSON 조작이 본체인데 bash에 python 히어독을 박으면 테스트·린트가 어렵다. 이 저장소는 이미 `validate-spec.py` · `guard-readonly.py` 로 `.py` 진입점 선례가 있다.
2. **`--approved` 가 `spec.yaml` 을 직접 읽지 않는다.** 스펙은 "spec에서 읽어 채운다"고 했지만 그러려면 PyYAML이 필요해 Global Constraint와 충돌한다. 대신 스킬이 `--agents implementer,reviewer` 로 넘긴다. 스킬은 spec을 방금 자기가 썼으므로 이미 알고 있다.

---

### Task 1: 배포 저장소 변경 역이식

두 저장소의 스킬 트리가 13개 파일 분기해 있다. 테스트가 자기 저장소의 스크립트를 참조하므로 이걸 먼저 맞춰야 이후 태스크의 테스트가 의미를 가진다.

**Files:**
- Modify: `harness-architect/.claude/skills/harness-architect/` 전체 (배포본으로 교체)

**Interfaces:**
- Produces: `scripts/harness-paths.sh` (`harness_root()` · `harness_workspace()`), `scripts/check-superpowers.sh` — 이후 모든 태스크가 의존한다.

- [ ] **Step 1: 역이식 전 기준선 확인**

```bash
cd ~/projects/harness-engineering/harness-architect
bash tests/run-all.sh | tail -3
```
Expected: `run-all: 전체 통과 — PASS 132 / FAIL 0`

- [ ] **Step 2: 배포본 스킬 트리를 복사**

```bash
SRC=~/projects/agent-architect/harness-architect/.claude/skills/harness-architect
DST=~/projects/harness-engineering/harness-architect/.claude/skills/harness-architect
rsync -a --delete "$SRC/" "$DST/"
```

- [ ] **Step 3: 분기가 사라졌는지 확인**

```bash
diff -rq ~/projects/agent-architect/harness-architect/.claude/skills/harness-architect \
         ~/projects/harness-engineering/harness-architect/.claude/skills/harness-architect
```
Expected: 출력 없음 (exit 0)

- [ ] **Step 4: 회귀 없는지 확인**

```bash
cd ~/projects/harness-engineering/harness-architect
bash tests/run-all.sh | tail -3
```
Expected: `run-all: 전체 통과 — PASS 132 / FAIL 0`

- [ ] **Step 5: 절대 경로가 섞여 들어오지 않았는지 확인**

```bash
grep -rn "/home/\|/Users/" .claude/ && echo FAIL || echo OK
```
Expected: `OK`

- [ ] **Step 6: 커밋**

```bash
git add harness-architect/.claude
git commit -m "chore: 배포 저장소의 worktree 정리·preflight 변경을 역이식

agent-architect 에만 들어가 있던 13건을 가져와 두 저장소를 맞춘다.
재개 기능의 테스트가 이 저장소의 스크립트 트리를 참조하므로 선행되어야 한다."
```

---

### Task 2: harness-paths.sh 를 직접 실행 가능하게 만든다

`checkpoint.py` 와 `resume-check.py` 가 워크스페이스 경로를 알아야 하는데, `harness-paths.sh` 는 source 전용이라 파이썬이 쓸 수 없다. 경로 계산 로직을 파이썬에 복제하면 불변식이 둘로 갈라진다.

**Files:**
- Modify: `.claude/skills/harness-architect/scripts/harness-paths.sh`
- Test: `tests/test-harness-paths.sh` (신규)

**Interfaces:**
- Produces: `bash harness-paths.sh --print` → stdout에 `_workspace/harness` 절대 경로 한 줄, exit 0.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```bash
cat > tests/test-harness-paths.sh <<'EOF'
#!/usr/bin/env bash
# tests/test-harness-paths.sh — _workspace 위치를 메인 워크트리 루트에 고정한다.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/lib/assert.sh"
SCRIPT="$ROOT/.claude/skills/harness-architect/scripts/harness-paths.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# git 저장소를 만들고 worktree 를 하나 붙인다
git init -q "$TMP/repo"
git -C "$TMP/repo" config user.email t@t
git -C "$TMP/repo" config user.name t
echo hi > "$TMP/repo/a.txt"
git -C "$TMP/repo" add -A
git -C "$TMP/repo" commit -qm init
git -C "$TMP/repo" worktree add -q "$TMP/repo/.worktrees/feat" -b feat

main_ws="$(cd "$TMP/repo" && bash "$SCRIPT" --print)"
assert_eq "$TMP/repo/_workspace/harness" "$main_ws" "메인 트리에서 워크스페이스 경로를 낸다"

wt_ws="$(cd "$TMP/repo/.worktrees/feat" && bash "$SCRIPT" --print)"
assert_eq "$TMP/repo/_workspace/harness" "$wt_ws" "worktree 안에서도 메인 루트를 가리킨다"

out="$(cd "$TMP" && bash "$SCRIPT" --print)"
assert_eq "$TMP/_workspace/harness" "$out" "git 저장소가 아니면 현재 디렉터리로 물러난다"

override="$(HARNESS_WORKSPACE=/tmp/custom bash "$SCRIPT" --print)"
assert_eq "/tmp/custom" "$override" "HARNESS_WORKSPACE 가 우선한다"

report_and_exit
EOF
chmod +x tests/test-harness-paths.sh
```

- [ ] **Step 2: 실패를 확인한다**

Run: `bash tests/test-harness-paths.sh`
Expected: FAIL — `--print` 이 아무것도 출력하지 않으므로 첫 assert부터 깨진다.

- [ ] **Step 3: 직접 실행 모드를 추가한다**

`harness-paths.sh` 맨 끝에 붙인다. source 될 때는 `$0` 가 호출자이므로 실행되지 않는다.

```bash
# 직접 실행되면(`bash harness-paths.sh --print`) 워크스페이스 경로를 낸다.
# python3 진입점(checkpoint.py·resume-check.py)이 경로 계산을 복제하지 않도록
# 하는 유일한 목적이다 — 계산 로직의 진실의 원천은 이 파일 하나로 유지한다.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        --print) harness_workspace ;;
        *) echo "usage: harness-paths.sh --print  (그 외에는 source 해서 쓴다)" >&2; exit 2 ;;
    esac
fi
```

- [ ] **Step 4: 통과를 확인한다**

Run: `bash tests/test-harness-paths.sh`
Expected: PASS 4줄, `=== all tests passed ===`

- [ ] **Step 5: 기존 스위트에 회귀가 없는지 확인한다**

Run: `bash tests/run-all.sh | tail -3`
Expected: `run-all: 전체 통과 — PASS 136 / FAIL 0`

- [ ] **Step 6: 커밋**

```bash
git add .claude/skills/harness-architect/scripts/harness-paths.sh tests/test-harness-paths.sh
git commit -m "feat: harness-paths.sh 에 --print 직접 실행 모드 추가

python3 진입점이 워크스페이스 경로 계산을 복제하지 않게 한다."
```

---

### Task 3: checkpoint.py — 원자적 쓰기와 Phase 기록

**Files:**
- Create: `.claude/skills/harness-architect/scripts/checkpoint.py`
- Test: `tests/test-checkpoint.sh` (신규)

**Interfaces:**
- Consumes: `harness-paths.sh --print` (Task 2)
- Produces:
  - `python3 checkpoint.py --phase <0..5|done> [--level H0|H1|H2|H3] [--next "<한 줄>"]` → state.json 갱신, exit 0
  - state.json 스키마: `schema_version`(int, 현재 1) · `updated_at`(ISO8601 Z) · `phase`(str) · `level`(str|null) · `approved`(bool) · `repo{head,branch,worktree,dirty}` · `artifacts{spec,gates_tsv,sdd_ledger}` · `progress{agents_done[],agents_pending[],gates[],review_loops_used,human_gate_passed}` · `next_action`(str)
  - 없으면 기본값으로 새로 만들고, 있으면 읽어서 병합한다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```bash
cat > tests/test-checkpoint.sh <<'EOF'
#!/usr/bin/env bash
# tests/test-checkpoint.sh — 진행 상태를 원자적으로 기록한다.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/lib/assert.sh"
SCRIPT="$ROOT/.claude/skills/harness-architect/scripts/checkpoint.py"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HARNESS_WORKSPACE="$TMP/ws"
mkdir -p "$HARNESS_WORKSPACE"
STATE="$HARNESS_WORKSPACE/state.json"

# 1. 없으면 새로 만든다
python3 "$SCRIPT" --phase 1; rc=$?
assert_exit_code 0 "$rc" "state 가 없으면 새로 만든다"
assert_file_exists "$STATE" "state.json 생성됨"
assert_eq "1" "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["phase"])' "$STATE")" \
    "phase 를 기록한다"
assert_eq "1" "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["schema_version"])' "$STATE")" \
    "schema_version 은 1"

# 2. 기존 값을 보존하며 병합한다
python3 "$SCRIPT" --phase 2 --level H2 --next "게이트 감지 완료"
assert_eq "H2" "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["level"])' "$STATE")" \
    "level 을 기록한다"
assert_eq "게이트 감지 완료" \
    "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["next_action"])' "$STATE")" \
    "next_action 을 기록한다"

python3 "$SCRIPT" --phase 3
assert_eq "H2" "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["level"])' "$STATE")" \
    "phase 만 바꿔도 level 이 보존된다"

# 3. 원자적 쓰기 — 임시 파일이 남지 않는다
leftovers="$(find "$HARNESS_WORKSPACE" -name 'state.json.*' -o -name '*.tmp' | wc -l)"
assert_eq "0" "$leftovers" "임시 파일 잔여 없음"

# 4. 저장소 지문을 채운다
git init -q "$TMP/repo"
git -C "$TMP/repo" config user.email t@t
git -C "$TMP/repo" config user.name t
echo hi > "$TMP/repo/a.txt"; git -C "$TMP/repo" add -A; git -C "$TMP/repo" commit -qm init
head="$(git -C "$TMP/repo" rev-parse HEAD)"
(cd "$TMP/repo" && python3 "$SCRIPT" --phase 4)
assert_eq "$head" \
    "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["repo"]["head"])' "$STATE")" \
    "HEAD SHA 를 기록한다"

# 5. 잘못된 phase 는 거부한다
python3 "$SCRIPT" --phase 9 2>/dev/null; rc=$?
assert_exit_code 2 "$rc" "허용되지 않는 phase 를 거부한다"

report_and_exit
EOF
chmod +x tests/test-checkpoint.sh
```

- [ ] **Step 2: 실패를 확인한다**

Run: `bash tests/test-checkpoint.sh`
Expected: FAIL — `checkpoint.py` 가 없어 첫 assert부터 깨진다.

- [ ] **Step 3: checkpoint.py 를 구현한다**

```python
#!/usr/bin/env python3
"""checkpoint.py — 하네스 진행 상태를 state.json 에 원자적으로 기록한다.

사용법:
    checkpoint.py --phase <0..5|done> [--level H0..H3] [--next "<한 줄>"]

종료코드: 0 성공 / 2 사용법·입력 오류

왜 원자적으로 쓰는가:
    이 파일의 존재 이유가 "갑작스러운 중단에서 살아남는 것"이다. 쓰기 도중에
    중단되어 반쪽짜리 JSON 이 남으면 재개가 그 자리에서 막힌다. 같은 디렉터리에
    임시 파일을 쓰고 os.replace 로 교체한다(같은 파일시스템이라 원자적이다).

왜 PyYAML 을 쓰지 않는가:
    PyYAML 은 이 저장소에서 선택 의존이다. validate-spec.py 는 없으면 exit 2 로
    물러나도 되지만, 재개는 그때도 동작해야 한다. json 은 표준 라이브러리다.
"""
import argparse
import json
import os
import subprocess
import sys
import tempfile
from datetime import datetime, timezone

SCHEMA_VERSION = 1
PHASES = {"0", "1", "2", "3", "4", "5", "done"}
LEVELS = {"H0", "H1", "H2", "H3"}

HERE = os.path.dirname(os.path.abspath(__file__))


def workspace():
    """_workspace/harness 의 절대 경로. 계산의 진실의 원천은 harness-paths.sh 하나다."""
    out = subprocess.run(
        ["bash", os.path.join(HERE, "harness-paths.sh"), "--print"],
        capture_output=True, text=True,
    )
    if out.returncode != 0 or not out.stdout.strip():
        sys.exit("checkpoint: 워크스페이스 경로를 구하지 못했습니다")
    return out.stdout.strip()


def git(*args):
    """git 결과를 문자열로. 저장소가 아니거나 실패하면 None."""
    r = subprocess.run(["git", *args], capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else None


def repo_fingerprint():
    """재개 시 '세상이 움직였는가'를 판정할 지문."""
    worktree = None
    top = git("rev-parse", "--show-toplevel")
    common = git("rev-parse", "--git-common-dir")
    if top and common:
        # git-common-dir 의 부모가 메인 트리다. 다르면 지금은 linked worktree 안이다.
        main = os.path.dirname(os.path.abspath(common))
        if os.path.abspath(top) != main:
            worktree = os.path.abspath(top)
    status = git("status", "--porcelain")
    return {
        "head": git("rev-parse", "HEAD"),
        "branch": git("branch", "--show-current"),
        "worktree": worktree,
        "dirty": bool(status),
    }


def blank_state():
    return {
        "schema_version": SCHEMA_VERSION,
        "updated_at": None,
        "phase": "0",
        "level": None,
        "approved": False,
        "repo": {"head": None, "branch": None, "worktree": None, "dirty": False},
        "artifacts": {"spec": None, "gates_tsv": None, "sdd_ledger": None},
        "progress": {
            "agents_done": [],
            "agents_pending": [],
            "gates": [],
            "review_loops_used": 0,
            "human_gate_passed": False,
        },
        "next_action": "",
    }


def load(path):
    """깨진 state 는 여기서 고치지 않는다 — 판정은 resume-check.py 의 몫이다.
    checkpoint 는 쓰는 쪽이므로, 읽을 수 없으면 새 상태로 시작한다."""
    if not os.path.exists(path):
        return blank_state()
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (json.JSONDecodeError, OSError):
        return blank_state()
    if not isinstance(data, dict) or data.get("schema_version") != SCHEMA_VERSION:
        return blank_state()
    base = blank_state()
    base.update(data)
    return base


def save(path, state):
    state["updated_at"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    d = os.path.dirname(path)
    os.makedirs(d, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".state-", suffix=".json")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(state, f, ensure_ascii=False, indent=2)
            f.write("\n")
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)      # 원자적 교체
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def main():
    p = argparse.ArgumentParser(add_help=True)
    p.add_argument("--phase")
    p.add_argument("--level")
    p.add_argument("--next", dest="next_action")
    args = p.parse_args()

    if args.phase is not None and args.phase not in PHASES:
        sys.exit(f"checkpoint: 허용되지 않는 phase '{args.phase}' "
                 f"(가능: {sorted(PHASES)})")
    if args.level is not None and args.level not in LEVELS:
        sys.exit(f"checkpoint: 허용되지 않는 level '{args.level}' "
                 f"(가능: {sorted(LEVELS)})")

    path = os.path.join(workspace(), "state.json")
    state = load(path)

    if args.phase is not None:
        state["phase"] = args.phase
    if args.level is not None:
        state["level"] = args.level
    if args.next_action is not None:
        state["next_action"] = args.next_action

    state["repo"] = repo_fingerprint()
    save(path, state)
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

`sys.exit("문자열")` 은 exit 1을 내므로, 사용법 오류를 exit 2로 만들려면 `argparse` 의 기본 동작(exit 2)에 맞춰 `p.error(...)` 를 쓴다. 위 두 `sys.exit` 를 `p.error(...)` 로 바꾼다.

- [ ] **Step 4: 통과를 확인한다**

Run: `bash tests/test-checkpoint.sh`
Expected: PASS 8줄, `=== all tests passed ===`

- [ ] **Step 5: 커밋**

```bash
git add .claude/skills/harness-architect/scripts/checkpoint.py tests/test-checkpoint.sh
git commit -m "feat: checkpoint.py — 진행 상태 원자적 기록

Phase·level·next_action 과 저장소 지문(HEAD·브랜치·worktree·dirty)을
state.json 에 os.replace 로 원자적으로 쓴다. PyYAML 없이 동작한다."
```

---

### Task 4: checkpoint.py — 진행 갱신 옵션

**Files:**
- Modify: `.claude/skills/harness-architect/scripts/checkpoint.py`
- Modify: `tests/test-checkpoint.sh`

**Interfaces:**
- Consumes: Task 3의 `load()` · `save()` · `PHASES`
- Produces:
  - `--approved --agents implementer,reviewer` → `approved=true`, `progress.agents_pending` 초기화
  - `--agent-done <id>` → `agents_pending` 에서 빼고 `agents_done` 에 넣는다 (단일 연산)
  - `--gate <tier>:<exit>` → `progress.gates` 에 `{"tier":..,"exit":..}` 추가
  - `--review-loop` → `review_loops_used += 1`
  - `--human-gate-passed` → `human_gate_passed=true`
  - `--artifact spec=<path>` → `artifacts` 갱신
  - `--archive` → state.json 을 `state.done-<updated_at>.json` 으로 옮기고 원본을 지운다

- [ ] **Step 1: 실패하는 테스트를 덧붙인다**

`tests/test-checkpoint.sh` 의 `report_and_exit` 바로 위에 삽입한다.

```bash
# 6. 승인 시 agents_pending 초기화
python3 "$SCRIPT" --phase 3 --approved --agents implementer,reviewer
assert_eq "True" "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["approved"])' "$STATE")" \
    "approved 를 세운다"
assert_eq "implementer,reviewer" \
    "$(python3 -c 'import json,sys;print(",".join(json.load(open(sys.argv[1]))["progress"]["agents_pending"]))' "$STATE")" \
    "agents_pending 을 초기화한다"

# 7. --agent-done 은 두 목록을 옮기는 단일 연산이다
python3 "$SCRIPT" --agent-done implementer
assert_eq "implementer" \
    "$(python3 -c 'import json,sys;print(",".join(json.load(open(sys.argv[1]))["progress"]["agents_done"]))' "$STATE")" \
    "agents_done 으로 옮긴다"
assert_eq "reviewer" \
    "$(python3 -c 'import json,sys;print(",".join(json.load(open(sys.argv[1]))["progress"]["agents_pending"]))' "$STATE")" \
    "agents_pending 에서 제거한다"

# 8. 게이트·리뷰 루프·Human Gate
python3 "$SCRIPT" --gate fast:0
python3 "$SCRIPT" --gate feature:1
assert_eq "2" \
    "$(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1]))["progress"]["gates"]))' "$STATE")" \
    "게이트 결과를 누적한다"
python3 "$SCRIPT" --review-loop
python3 "$SCRIPT" --review-loop
assert_eq "2" \
    "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["progress"]["review_loops_used"])' "$STATE")" \
    "리뷰 루프를 센다"
python3 "$SCRIPT" --human-gate-passed
assert_eq "True" \
    "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["progress"]["human_gate_passed"])' "$STATE")" \
    "Human Gate 통과를 기록한다"

# 9. --archive 는 삭제가 아니라 보존이다
ts="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["updated_at"])' "$STATE")"
python3 "$SCRIPT" --phase done
python3 "$SCRIPT" --archive
archived="$(find "$HARNESS_WORKSPACE" -name 'state.done-*.json' | wc -l)"
assert_eq "1" "$archived" "완료된 state 를 보존한다"
if [[ -f "$STATE" ]]; then
    echo "FAIL: --archive 후에도 state.json 이 남아 있다"
    FAILURES=$((FAILURES + 1))
else
    echo "PASS: --archive 후 state.json 은 비워진다"
fi
```

- [ ] **Step 2: 실패를 확인한다**

Run: `bash tests/test-checkpoint.sh`
Expected: FAIL — `--approved` 등이 인식되지 않아 argparse가 exit 2로 죽는다.

- [ ] **Step 3: 옵션을 구현한다**

`main()` 의 argparse 블록에 추가한다.

```python
    p.add_argument("--approved", action="store_true")
    p.add_argument("--agents", help="쉼표로 구분한 에이전트 id 목록")
    p.add_argument("--agent-done", dest="agent_done")
    p.add_argument("--gate", help="<tier>:<exit>")
    p.add_argument("--review-loop", action="store_true", dest="review_loop")
    p.add_argument("--human-gate-passed", action="store_true", dest="human_gate")
    p.add_argument("--artifact", action="append", default=[], help="key=path")
    p.add_argument("--archive", action="store_true")
```

`state["repo"] = repo_fingerprint()` 바로 앞에 넣는다.

```python
    prog = state["progress"]

    if args.approved:
        state["approved"] = True
    if args.agents is not None:
        # 승인 시점에 스킬이 넘긴다. spec.yaml 을 직접 읽지 않는 이유는 PyYAML 이
        # 선택 의존이기 때문이다 — 재개는 PyYAML 없이도 동작해야 한다.
        prog["agents_pending"] = [a for a in args.agents.split(",") if a]
        prog["agents_done"] = []
    if args.agent_done:
        # 두 목록을 옮기는 단일 연산. 합집합은 항상 spec 의 에이전트 집합과 같다.
        if args.agent_done in prog["agents_pending"]:
            prog["agents_pending"].remove(args.agent_done)
        if args.agent_done not in prog["agents_done"]:
            prog["agents_done"].append(args.agent_done)
    if args.gate:
        tier, _, code = args.gate.partition(":")
        if tier not in {"fast", "feature", "final"} or not code.isdigit():
            p.error(f"--gate 형식은 <fast|feature|final>:<exit> 입니다 (받은 값: {args.gate})")
        prog["gates"].append({"tier": tier, "exit": int(code)})
    if args.review_loop:
        prog["review_loops_used"] += 1
    if args.human_gate:
        prog["human_gate_passed"] = True
    for item in args.artifact:
        key, _, val = item.partition("=")
        if key not in state["artifacts"]:
            p.error(f"알 수 없는 artifact 키 '{key}' "
                    f"(가능: {sorted(state['artifacts'])})")
        state["artifacts"][key] = val
```

`--archive` 는 지문 갱신·저장을 하지 않고 곧바로 끝낸다. `main()` 에서 `path` 를 구한 직후에 둔다.

```python
    if args.archive:
        if not os.path.exists(path):
            return 0                     # 지울 것이 없으면 성공으로 본다 (멱등)
        # 파일 이름은 아카이브 시각이 아니라 updated_at 을 쓴다 — "언제까지의
        # 작업인가"를 말해야 나중에 찾을 수 있다.
        stamp = (state.get("updated_at") or "unknown").replace(":", "").replace("-", "")
        os.replace(path, os.path.join(os.path.dirname(path), f"state.done-{stamp}.json"))
        return 0
```

- [ ] **Step 4: 통과를 확인한다**

Run: `bash tests/test-checkpoint.sh`
Expected: 전부 PASS, `=== all tests passed ===`

- [ ] **Step 5: 커밋**

```bash
git add .claude/skills/harness-architect/scripts/checkpoint.py tests/test-checkpoint.sh
git commit -m "feat: checkpoint.py 진행 갱신 옵션

--approved/--agents, --agent-done, --gate, --review-loop,
--human-gate-passed, --artifact, --archive 를 추가한다.
--archive 는 삭제가 아니라 state.done-<updated_at>.json 으로의 보존이다."
```

---

### Task 5: resume-check.py — 판정과 exit code

**Files:**
- Create: `.claude/skills/harness-architect/scripts/resume-check.py`
- Test: `tests/test-resume-check.sh` (신규)

**Interfaces:**
- Consumes: `harness-paths.sh --print`, Task 3~4가 쓴 state.json
- Produces: `python3 resume-check.py` → exit `0` state 없음 / `10` 자동 재개 / `11` 사람 판단 / `12` 완료됨. 브리핑은 stdout.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```bash
cat > tests/test-resume-check.sh <<'EOF'
#!/usr/bin/env bash
# tests/test-resume-check.sh — 중단된 작업을 감지하고 재개 방식을 판정한다.
# 계약: Phase 0~3 은 자동(10), Phase 4~5 와 불일치·손상은 사람 판단(11).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/lib/assert.sh"
CHECK="$ROOT/.claude/skills/harness-architect/scripts/resume-check.py"
CP="$ROOT/.claude/skills/harness-architect/scripts/checkpoint.py"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
git init -q "$TMP/repo"
git -C "$TMP/repo" config user.email t@t
git -C "$TMP/repo" config user.name t
echo hi > "$TMP/repo/a.txt"; git -C "$TMP/repo" add -A; git -C "$TMP/repo" commit -qm init

export HARNESS_WORKSPACE="$TMP/ws"
mkdir -p "$HARNESS_WORKSPACE"
STATE="$HARNESS_WORKSPACE/state.json"

# 1. state 없음 → 새 작업
(cd "$TMP/repo" && python3 "$CHECK" >/dev/null 2>&1); rc=$?
assert_exit_code 0 "$rc" "state 가 없으면 exit 0 (새 작업)"

# 2. Phase 2, 불일치 없음 → 자동 재개
(cd "$TMP/repo" && python3 "$CP" --phase 2 --level H1 --next "라우팅 판정 중")
(cd "$TMP/repo" && python3 "$CHECK" >/dev/null 2>&1); rc=$?
assert_exit_code 10 "$rc" "Phase 2 + 불일치 없음이면 자동 재개(10)"

# 3. Phase 4 → 항상 사람 판단
(cd "$TMP/repo" && python3 "$CP" --phase 4)
(cd "$TMP/repo" && python3 "$CHECK" >/dev/null 2>&1); rc=$?
assert_exit_code 11 "$rc" "Phase 4 는 불일치가 없어도 사람 판단(11)"

# 4. Phase done → 완료된 이전 작업
(cd "$TMP/repo" && python3 "$CP" --phase done)
(cd "$TMP/repo" && python3 "$CHECK" >/dev/null 2>&1); rc=$?
assert_exit_code 12 "$rc" "phase done 이면 exit 12"

# 5. 깨진 JSON → 죽지 않고 사람 판단
printf '{ this is not json' > "$STATE"
(cd "$TMP/repo" && python3 "$CHECK" >/dev/null 2>&1); rc=$?
assert_exit_code 11 "$rc" "깨진 state 는 예외로 죽지 않고 11"

# 6. 알 수 없는 schema_version → 사람 판단
python3 -c "
import json,sys
json.dump({'schema_version': 99, 'phase': '2'}, open(sys.argv[1],'w'))" "$STATE"
(cd "$TMP/repo" && python3 "$CHECK" >/dev/null 2>&1); rc=$?
assert_exit_code 11 "$rc" "모르는 schema_version 은 11"

report_and_exit
EOF
chmod +x tests/test-resume-check.sh
```

- [ ] **Step 2: 실패를 확인한다**

Run: `bash tests/test-resume-check.sh`
Expected: FAIL — `resume-check.py` 가 없어 전부 exit 2로 나온다.

- [ ] **Step 3: resume-check.py 를 구현한다**

```python
#!/usr/bin/env python3
"""resume-check.py — 중단된 하네스 작업을 감지하고 재개 방식을 판정한다.

사용법: resume-check.py

종료코드:
     0  재개할 것 없음 (새 작업)
    10  자동 재개 가능 — Phase 0~3 이고 저장소가 그대로다
    11  사람 판단 필요 — Phase 4~5 이거나, 불일치가 있거나, state 가 손상됐다
    12  완료된 이전 작업이 남아 있다

exit code 가 10번대인 이유:
    init-workspace.sh 의 3(스택 미감지)·4(superpowers 미설치)와 헷갈리지 않게 한다.

왜 손상된 state 를 복구하지 않는가:
    깨진 상태를 추측으로 되살리면 틀린 지점에서 재개한다. 사람에게 넘기는 것이
    항상 더 싸다.
"""
import json
import os
import subprocess
import sys

SCHEMA_VERSION = 1
EXIT_NONE, EXIT_AUTO, EXIT_HUMAN, EXIT_DONE = 0, 10, 11, 12
AUTO_MAX_PHASE = 3          # Phase 0~3 까지만 자동. 파일을 쓰기 시작하면 사람이 판단한다.

HERE = os.path.dirname(os.path.abspath(__file__))


def workspace():
    out = subprocess.run(
        ["bash", os.path.join(HERE, "harness-paths.sh"), "--print"],
        capture_output=True, text=True,
    )
    if out.returncode != 0 or not out.stdout.strip():
        print("resume-check: 워크스페이스 경로를 구하지 못했습니다", file=sys.stderr)
        sys.exit(EXIT_HUMAN)
    return out.stdout.strip()


def git(*args):
    r = subprocess.run(["git", *args], capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else None


def current_fingerprint():
    worktree = None
    top = git("rev-parse", "--show-toplevel")
    common = git("rev-parse", "--git-common-dir")
    if top and common:
        main = os.path.dirname(os.path.abspath(common))
        if os.path.abspath(top) != main:
            worktree = os.path.abspath(top)
    return {"head": git("rev-parse", "HEAD"),
            "branch": git("branch", "--show-current"),
            "worktree": worktree}


def drift(recorded, current):
    """자동 재개를 막을 불일치만 낸다.

    dirty 는 일부러 보지 않는다 — 작업 중이면 항상 바뀌므로 강등 조건에 넣으면
    자동 재개가 사실상 죽는다. 브리핑에는 표시한다.
    """
    out = []
    for key, label in (("head", "HEAD"), ("branch", "브랜치")):
        was, now = recorded.get(key), current.get(key)
        if was and was != now:
            out.append(f"{label} {str(was)[:7]} → {str(now)[:7] if now else '없음'}")
    was_wt = recorded.get("worktree")
    if was_wt and not os.path.isdir(was_wt):
        out.append(f"worktree 제거됨 ({was_wt})")
    return out


def main():
    path = os.path.join(workspace(), "state.json")
    if not os.path.exists(path):
        return EXIT_NONE

    try:
        with open(path, encoding="utf-8") as f:
            state = json.load(f)
    except (json.JSONDecodeError, OSError) as e:
        print(f"[재개] state 를 읽을 수 없습니다: {e}")
        print(f"  파일: {path}")
        print("  추측으로 복구하지 않습니다. 내용을 확인하고 이어갈지 결정하십시오.")
        return EXIT_HUMAN

    if not isinstance(state, dict) or state.get("schema_version") != SCHEMA_VERSION:
        print(f"[재개] 알 수 없는 state 형식입니다 "
              f"(schema_version={state.get('schema_version') if isinstance(state, dict) else '?'}, "
              f"이 스크립트는 {SCHEMA_VERSION})")
        print(f"  파일: {path}")
        return EXIT_HUMAN

    phase = str(state.get("phase", "0"))
    if phase == "done":
        render(state, [], path)
        return EXIT_DONE

    marks = drift(state.get("repo") or {}, current_fingerprint())
    try:
        numeric = int(phase)
    except ValueError:
        return EXIT_HUMAN

    verdict = EXIT_AUTO if (numeric <= AUTO_MAX_PHASE and not marks) else EXIT_HUMAN
    render(state, marks, path)
    return verdict


if __name__ == "__main__":
    sys.exit(main())
```

`render()` 는 Task 6에서 구현한다. 이 태스크에서는 자리만 잡되 테스트가 stdout을 보지 않으므로 최소 구현을 둔다.

```python
def render(state, marks, path):
    print(f"[재개] {state.get('level') or '?'} · Phase {state.get('phase')}")
```

- [ ] **Step 4: 통과를 확인한다**

Run: `bash tests/test-resume-check.sh`
Expected: PASS 6줄, `=== all tests passed ===`

- [ ] **Step 5: 커밋**

```bash
git add .claude/skills/harness-architect/scripts/resume-check.py tests/test-resume-check.sh
git commit -m "feat: resume-check.py — 재개 판정과 exit code

0 없음 / 10 자동재개 / 11 사람판단 / 12 완료됨.
Phase 4~5 와 손상된 state 는 항상 사람 판단으로 보낸다."
```

---

### Task 6: resume-check.py — 불일치 강등과 브리핑 렌더링

**Files:**
- Modify: `.claude/skills/harness-architect/scripts/resume-check.py`
- Modify: `tests/test-resume-check.sh`

**Interfaces:**
- Consumes: Task 5의 `drift()` · `render()` 자리
- Produces: 브리핑 stdout 규격 — `[재개]` 헤더 → `다음 할 일` → `끝난 것` → `남은 것` → `불일치`(있을 때만) → `경로`

- [ ] **Step 1: 실패하는 테스트를 덧붙인다**

`report_and_exit` 바로 위에 삽입한다.

```bash
# 7. HEAD 가 바뀌면 Phase 2 라도 강등
rm -f "$STATE"
(cd "$TMP/repo" && python3 "$CP" --phase 2 --level H1)
echo more >> "$TMP/repo/a.txt"
git -C "$TMP/repo" add -A; git -C "$TMP/repo" commit -qm second
(cd "$TMP/repo" && python3 "$CHECK" >/dev/null 2>&1); rc=$?
assert_exit_code 11 "$rc" "HEAD 가 바뀌면 Phase 2 라도 강등(11)"

# 8. 브랜치가 바뀌면 강등
rm -f "$STATE"
(cd "$TMP/repo" && python3 "$CP" --phase 2)
git -C "$TMP/repo" checkout -q -b other
(cd "$TMP/repo" && python3 "$CHECK" >/dev/null 2>&1); rc=$?
assert_exit_code 11 "$rc" "브랜치가 바뀌면 강등(11)"
git -C "$TMP/repo" checkout -q -

# 9. worktree 가 사라지면 강등
rm -f "$STATE"
git -C "$TMP/repo" worktree add -q "$TMP/repo/.worktrees/w" -b wbranch
(cd "$TMP/repo/.worktrees/w" && python3 "$CP" --phase 2)
git -C "$TMP/repo" worktree remove --force "$TMP/repo/.worktrees/w"
(cd "$TMP/repo" && python3 "$CHECK" >/dev/null 2>&1); rc=$?
assert_exit_code 11 "$rc" "worktree 가 제거되면 강등(11)"

# 10. dirty 는 강등 조건이 아니다 (작업 중이면 항상 바뀐다)
rm -f "$STATE"
(cd "$TMP/repo" && python3 "$CP" --phase 2)
echo scratch > "$TMP/repo/untracked.txt"
(cd "$TMP/repo" && python3 "$CHECK" >/dev/null 2>&1); rc=$?
assert_exit_code 10 "$rc" "dirty 만으로는 강등하지 않는다"
rm -f "$TMP/repo/untracked.txt"

# 11. 브리핑 규격 — '다음 할 일' 이 헤더 바로 다음이다
rm -f "$STATE"
(cd "$TMP/repo" && python3 "$CP" --phase 2 --level H2 --next "implementer dispatch — 단위 2/3" \
    --approved --agents implementer,reviewer)
(cd "$TMP/repo" && python3 "$CP" --agent-done implementer --gate fast:0)
brief="$(cd "$TMP/repo" && python3 "$CHECK")"
assert_contains "$brief" "[재개]"          "재개 헤더를 낸다"
assert_contains "$brief" "H2"              "레벨을 낸다"
assert_contains "$brief" "다음 할 일"       "다음 행동을 낸다"
assert_contains "$brief" "implementer dispatch — 단위 2/3" "next_action 을 그대로 낸다"
assert_contains "$brief" "끝난 것"          "완료 목록을 낸다"
assert_contains "$brief" "남은 것"          "잔여 목록을 낸다"
assert_contains "$brief" "reviewer"        "남은 에이전트를 낸다"
assert_contains "$brief" "fast"            "실행한 게이트를 낸다"

second_line="$(sed -n '2p' <<< "$brief")"
assert_contains "$second_line" "다음 할 일" "'다음 할 일' 이 헤더 바로 다음 줄이다"

if [[ "$brief" == *"불일치"* ]]; then
    echo "FAIL: 불일치가 없는데 불일치 행을 냈다"
    FAILURES=$((FAILURES + 1))
else
    echo "PASS: 불일치가 없으면 그 행을 내지 않는다"
fi
```

- [ ] **Step 2: 실패를 확인한다**

Run: `bash tests/test-resume-check.sh`
Expected: FAIL — 브리핑이 헤더 한 줄뿐이라 `다음 할 일` 부터 깨진다.

- [ ] **Step 3: render() 를 구현한다**

Task 5의 최소 `render()` 를 통째로 교체한다.

```python
def render(state, marks, path):
    """브리핑. '다음 할 일'이 헤더 바로 다음에 오는 것이 규격의 핵심이다 —
    재개하는 사람이 가장 먼저 읽어야 하는 것은 이력이 아니라 다음 행동이다."""
    prog = state.get("progress") or {}
    art = state.get("artifacts") or {}
    repo = state.get("repo") or {}

    approved = "승인됨" if state.get("approved") else "미승인"
    stamp = state.get("updated_at") or "?"
    print(f"[재개] {state.get('level') or '?'} · Phase {state.get('phase')} · "
          f"{approved} · {stamp}")

    print(f"  다음 할 일: {state.get('next_action') or '(기록되지 않음)'}")

    done = ", ".join(prog.get("agents_done") or []) or "없음"
    gates = " ".join(f"{g.get('tier')}({g.get('exit')})"
                     for g in (prog.get("gates") or [])) or "없음"
    print(f"  끝난 것:   {done} · 게이트 {gates}")

    pending = ", ".join(prog.get("agents_pending") or []) or "없음"
    loops = prog.get("review_loops_used", 0)
    hg = "통과" if prog.get("human_gate_passed") else "미통과"
    print(f"  남은 것:   {pending} · 리뷰 루프 {loops}회 소진 · Human Gate {hg}")

    if marks:
        print(f"  불일치:    {'; '.join(marks)}")
    if repo.get("dirty"):
        print("  작업 트리: 커밋되지 않은 변경이 있습니다")

    print(f"  경로:      state {path}")
    for key in ("spec", "gates_tsv", "sdd_ledger"):
        if art.get(key):
            print(f"             {key} {art[key]}")
```

- [ ] **Step 4: 통과를 확인한다**

Run: `bash tests/test-resume-check.sh`
Expected: 전부 PASS, `=== all tests passed ===`

- [ ] **Step 5: 전체 스위트에 회귀가 없는지 확인한다**

Run: `bash tests/run-all.sh | tail -3`
Expected: `run-all: 전체 통과 — PASS <n> / FAIL 0`

- [ ] **Step 6: 커밋**

```bash
git add .claude/skills/harness-architect/scripts/resume-check.py tests/test-resume-check.sh
git commit -m "feat: 불일치 강등과 브리핑 렌더링

HEAD·브랜치·worktree 중 하나라도 바뀌면 Phase 0~3 이라도 사람 판단으로
강등한다. dirty 는 강등 조건에서 제외한다 — 작업 중이면 항상 바뀐다.
브리핑은 '다음 할 일'을 헤더 바로 다음에 낸다."
```

---

### Task 7: 자동 기록 — init-workspace.sh 와 run-gates.sh

규율에 의존하는 기록 지점을 둘 줄인다. 이 둘은 이미 필요한 정보를 손에 쥐고 있다.

**Files:**
- Modify: `.claude/skills/harness-architect/scripts/init-workspace.sh`
- Modify: `.claude/skills/harness-architect/scripts/run-gates.sh`
- Modify: `tests/test-run-gates.sh`
- Test: `tests/test-checkpoint.sh` (init 연동 확인 추가)

**Interfaces:**
- Consumes: `checkpoint.py --phase 1`, `checkpoint.py --gate <tier>:<exit>`

- [ ] **Step 1: 실패하는 테스트를 덧붙인다**

`tests/test-run-gates.sh` 의 `report_and_exit` 위에 삽입한다.

```bash
# 게이트 실행이 state.json 에 자동으로 기록된다
WS_AUTO="$(mktemp -d)"
printf 'fast\ttrue\n' > "$WS_AUTO/gates.tsv"
HARNESS_WORKSPACE="$WS_AUTO" bash "$SCRIPT" fast "$WS_AUTO/gates.tsv" "$WS_AUTO/logs" >/dev/null 2>&1
if [[ -f "$WS_AUTO/state.json" ]]; then
    tiers="$(python3 -c 'import json,sys;print(",".join(g["tier"] for g in json.load(open(sys.argv[1]))["progress"]["gates"]))' "$WS_AUTO/state.json")"
    assert_contains "$tiers" "fast" "run-gates 가 게이트 결과를 state 에 자동 기록한다"
else
    echo "FAIL: run-gates 실행 후 state.json 이 없다"
    FAILURES=$((FAILURES + 1))
fi
rm -rf "$WS_AUTO"
```

- [ ] **Step 2: 실패를 확인한다**

Run: `bash tests/test-run-gates.sh`
Expected: FAIL — `state.json` 이 생기지 않는다.

- [ ] **Step 3: run-gates.sh 에 자동 기록을 얹는다**

최종 판정 직전(`if [[ "$failed" -gt 0 ]]` 바로 위)에 넣는다.

```bash
# 진행 상태에 게이트 결과를 남긴다. 실패해도 게이트 판정을 바꾸지 않는다 —
# 기록은 관측 수단이지 실행 경로가 아니다.
if [[ -f "$HERE/checkpoint.py" ]]; then
    rc_gate=0
    [[ "$failed" -gt 0 ]] && rc_gate=1
    python3 "$HERE/checkpoint.py" --gate "$TIER:$rc_gate" >/dev/null 2>&1 || true
fi
```

- [ ] **Step 4: init-workspace.sh 에 자동 기록을 얹는다**

`mkdir -p "$WS/gates" ...` 바로 다음에 넣는다.

```bash
# Phase 1 진입을 기록한다. 이후 세션이 "어디까지 했나"를 물을 때의 출발점이다.
python3 "$HERE/checkpoint.py" --phase 1 \
    --next "게이트 감지 결과 확인 후 Phase 2 프로파일링" \
    --artifact "gates_tsv=$WS/gates.tsv" >/dev/null 2>&1 || true
```

- [ ] **Step 5: 통과를 확인한다**

```bash
bash tests/test-run-gates.sh
bash tests/run-all.sh | tail -3
```
Expected: 각각 `all tests passed`, `run-all: 전체 통과 — FAIL 0`

- [ ] **Step 6: 커밋**

```bash
git add .claude/skills/harness-architect/scripts/init-workspace.sh \
        .claude/skills/harness-architect/scripts/run-gates.sh \
        tests/test-run-gates.sh
git commit -m "feat: init-workspace 와 run-gates 가 진행을 자동 기록

규율에 의존하는 기록 지점을 둘 줄인다. 기록 실패는 게이트 판정을
바꾸지 않는다 — 관측 수단이지 실행 경로가 아니다."
```

---

### Task 8: SKILL.md 와 문서 동기화

**Files:**
- Modify: `.claude/skills/harness-architect/SKILL.md`
- Modify: `harness-architect/README.md`
- Modify: `harness-architect/CLAUDE.md`
- Modify: `harness-architect/CHECKLIST.md`
- Modify: `docs/superpowers/specs/2026-08-30-harness-resume-design.md` (보완 2건 반영)

- [ ] **Step 1: SKILL.md 에 Phase 0 앞 재개 판정을 넣는다**

`## Phase 0 — 입력 정규화` 바로 위에 절을 추가한다.

```markdown
## Phase −1 — 재개 판정 (Phase 0보다 먼저)

`Bash: python3 .claude/skills/harness-architect/scripts/resume-check.py`

- exit 0 → 재개할 것 없음. Phase 0으로 간다.
- exit 10 → **자동 재개.** 브리핑을 한 번 보이고 기록된 Phase부터 이어서 진행한다.
- exit 11 → **사람 판단.** 브리핑을 제시하고 **멈춘다.** 재개·재판정·폐기를 사용자가 고른다.
  추측으로 이어가지 않는다.
- exit 12 → 완료된 이전 작업이 남아 있다. 새 작업을 시작할지 묻고, 승인되면
  `checkpoint.py --archive` 로 보존한 뒤 Phase 0으로 간다.
```

- [ ] **Step 2: SKILL.md 의 각 Phase에 기록 호출을 넣는다**

- Phase 2 끝: `Bash: python3 .../checkpoint.py --phase 2 --level <판정 결과> --next "<다음 행동>"`
- Phase 3 승인 직후: `--phase 3 --approved --agents <spec의 agents id 쉼표 목록> --artifact spec=_workspace/harness/spec.yaml`
- Phase 4 에이전트 완료마다: `--agent-done <id> --next "<다음 행동>"`
- Phase 4 리뷰 루프 소진마다: `--review-loop`
- Phase 5 Human Gate 통과: `--human-gate-passed`
- Phase 5 종료: `--phase done`

- [ ] **Step 3: 불변 규칙을 한 줄 추가한다**

```markdown
- **진행을 기록한다**: Phase 전환과 단위 완료마다 `checkpoint.py` 를 부른다. 기록하지 않으면
  다음 세션이 처음부터 다시 판정하게 되고, 같은 작업에 다른 레벨이 나올 수 있다.
  기록 실패는 하네스를 멈추지 않는다 — 관측 수단이지 실행 경로가 아니다.
```

- [ ] **Step 4: README·CLAUDE.md·CHECKLIST.md 를 갱신한다**

- README 구성 목록에 `checkpoint.py` · `resume-check.py` 추가
- README에 "중단하면 재개한다" 절 추가 — exit code 표와 자동/사람 경계
- CLAUDE.md 불변식 표에 2행 추가: `resume exit code 10·11·12`(`resume-check.py`·`SKILL.md`·README), `state 스키마 schema_version`(`checkpoint.py`·`resume-check.py`)
- CLAUDE.md 검증 절차에 `bash tests/test-resume-check.sh` 추가
- CHECKLIST.md B-1에 재개 항목 추가

- [ ] **Step 5: 스펙 문서에 보완 2건을 반영한다**

`.sh` → `.py` 이름 변경과 `--agents` 로 넘기는 이유(PyYAML 회피)를 스펙에 반영한다.

- [ ] **Step 6: 문서가 실제와 맞는지 확인한다**

```bash
grep -rn "checkpoint.sh\|resume-check.sh" . --include="*.md" && echo "FAIL: 옛 이름이 남았다" || echo OK
bash tests/run-all.sh | tail -3
```
Expected: `OK`, `run-all: 전체 통과 — FAIL 0`

- [ ] **Step 7: 커밋**

```bash
git add -A
git commit -m "docs: 재개 절차를 SKILL.md·README·CLAUDE.md·CHECKLIST 에 반영

Phase -1 재개 판정을 Phase 0 앞에 두고, 각 Phase 에 기록 호출을 넣는다.
스펙의 스크립트 이름을 .py 로 정정한다."
```

---

### Task 9: 배포 저장소로 이식

**Files:**
- Modify: `~/projects/agent-architect/harness-architect/` (스킬 트리 + 문서)

- [ ] **Step 1: 두 경로만 복사한다**

```bash
SRC=~/projects/harness-engineering/harness-architect/.claude
DST=~/projects/agent-architect/harness-architect/.claude
rsync -a --delete "$SRC/skills/" "$DST/skills/"
rsync -a --delete "$SRC/agents/" "$DST/agents/"
```

- [ ] **Step 2: 이식 경계를 확인한다** (`CHECKLIST.md` B-4)

```bash
cd ~/projects/agent-architect/harness-architect
for d in tests fixtures evals; do [ -e "$d" ] && echo "FAIL: $d 이식됨" || echo "OK $d"; done
grep -rn "/home/\|/Users/" .claude/ && echo FAIL || echo "OK 절대 경로 없음"
```
Expected: `OK` 4줄

- [ ] **Step 3: 배포본에서 동작을 확인한다**

```bash
S=.claude/skills/harness-architect
for f in $S/scripts/*.sh; do bash -n "$f" || echo "FAIL $f"; done
bash $S/scripts/check-superpowers.sh
python3 $S/scripts/resume-check.py; echo "resume-check exit=$? (0 이어야 함 — state 없음)"
for f in $S/examples/*.yaml; do python3 $S/scripts/validate-spec.py "$f" | tail -1; done
```
Expected: 셸 문법 통과, preflight 11종, `resume-check exit=0`, 예제 4종 `통과 (경고 0건)`

- [ ] **Step 4: 배포 저장소 문서를 갱신한다**

`agent-architect/CLAUDE.md` 의 불변식 표와 검증 절차에 재개 관련 2행을 추가한다(원본과 같은 내용).

- [ ] **Step 5: 두 저장소가 다시 일치하는지 확인한다**

```bash
diff -rq ~/projects/harness-engineering/harness-architect/.claude/skills/harness-architect \
         ~/projects/agent-architect/harness-architect/.claude/skills/harness-architect
```
Expected: 출력 없음

- [ ] **Step 6: 커밋**

```bash
cd ~/projects/agent-architect
git add -A
git commit -m "feat: 재개(resume) 기능 이식

harness-engineering 에서 개발한 checkpoint.py·resume-check.py 와
Phase -1 재개 판정을 배포 저장소로 가져온다."
```

---

## Self-Review

**스펙 커버리지** — 스펙의 각 절이 어느 태스크에 대응하는가.

| 스펙 절 | 태스크 |
|---|---|
| 상태 파일 (위치·JSON·스키마) | Task 3 |
| 크래시 안전성 (원자적 쓰기) | Task 3 Step 1의 assert, Step 3의 `os.replace` |
| 기록 시점 — 규율 6종 | Task 4 (옵션) + Task 8 (SKILL.md 호출) |
| 기록 시점 — 자동 2종 | Task 7 |
| `agents_pending` 초기값 | Task 4 (`--agents`) |
| 재개 판정 exit code | Task 5 |
| 브리핑 규격 | Task 6 |
| 불일치 판정 (`dirty` 제외) | Task 6 |
| 생명주기 (`--archive`) | Task 4 |
| SDD ledger 경계 | Task 4 (`--artifact sdd_ledger=`), Task 6 (브리핑 경로 출력) |
| Linear 경계 | 코드 없음 — 설계상 "읽지 않는다"이므로 구현할 것이 없다 |
| worktree 경계 | Task 3 (`repo_fingerprint`), Task 6 (테스트 9) |
| 구현 단계 1·2·3 | Task 1 / Task 2~8 / Task 9 |
| 검증 시나리오 12종 | 1~8 → Task 5·6, 9 → Task 3, 10·11 → Task 7, 12 → Global Constraint(`json` 만 사용) |
| 새 불변식 | Task 8 Step 4 |

빠진 것 없음.

**Placeholder 스캔** — "적절히 처리한다" 류 없음. 모든 코드 단계에 실제 코드가 있다. Task 8 Step 4·5는 문서 편집이라 구체 항목을 나열했다.

**타입 정합성**
- `harness_workspace()` (Task 2) ↔ `workspace()` 의 `--print` 호출 (Task 3·5) — 일치
- `load()`/`save()`/`blank_state()` (Task 3) ↔ Task 4의 `prog = state["progress"]` — 일치
- `drift()` 반환값 `list[str]` (Task 5) ↔ `render(state, marks, path)` 의 `marks` (Task 6) — 일치
- `checkpoint.py --gate <tier>:<exit>` (Task 4) ↔ `run-gates.sh` 호출 (Task 7) — 일치
- exit 상수 `EXIT_NONE/AUTO/HUMAN/DONE` = 0/10/11/12 ↔ SKILL.md 표 (Task 8) — 일치
