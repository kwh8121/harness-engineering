# harness-architect 재개(Resume) 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 세션이 끊기거나 Phase 중간에 멈춰도 다음 세션이 "이게 그 작업이 맞는지"와 "다음에 무엇을 할지"를 한 화면으로 알 수 있게 한다.

**Architecture:** `_workspace/harness/state.json` 하나에 작업 식별자·Phase 위치·역할 마일스톤·저장소 지문을 원자적으로 기록한다. `checkpoint.py` 가 쓰고 `resume-check.py` 가 읽어 exit code로 판정한다(0 없음 / 10 자동재개 후보 / 11 사람판단 / 12 완료됨). 자동 재개는 Phase 0~2로 제한하고, 손상된 state는 절대 덮어쓰지 않는다.

**Tech Stack:** Bash + POSIX awk/grep, Python 3 표준 라이브러리(`json` · `hashlib` 만). 프레임워크 없는 자체 assertion 헬퍼(`tests/lib/assert.sh`).

**Spec:** [docs/superpowers/specs/2026-08-30-harness-resume-design.md](../specs/2026-08-30-harness-resume-design.md) (2026-08-30 리뷰 반영본)
**Review:** [docs/superpowers/specs/2026-08-30-harness-resume-review.md](../specs/2026-08-30-harness-resume-review.md)

## Global Constraints

- **절대 경로 하드코딩 금지.** `CHECKLIST.md` B-4가 `grep -rn "/home/\|/Users/" .claude/` 로 검사한다.
- **PyYAML에 의존하지 않는다.** 재개는 PyYAML이 없는 환경에서도 동작해야 한다. `json` · `hashlib` 만 쓴다.
- **한국어**로 주석·문서·커밋 메시지를 쓴다. 변수명·함수명·필드명은 영어.
- **자동 재개 상한은 Phase 2다.** `approved` 는 재개 시 실행 권한으로 쓰이지 않는다.
- **손상된 state를 절대 덮어쓰지 않는다.** `blank_state()` 는 파일이 없을 때만 반환한다.
- **파괴적 동기화 금지.** `rsync --delete` 는 `-ain` 선행 확인 후에만. **`git add -A` 를 쓰지 않는다** — 태스크가 소유한 경로만 stage한다. 배포 저장소에는 이 작업과 무관한 `.gitignore` 변경(`.omx/`)이 실재한다.
- **동시 writer는 지원하지 않는다.** 하네스가 구현 워커 동시 dispatch를 금지하므로 writer는 항상 하나다.
- 테스트는 `tests/` 에만 둔다 — 이식 경계 밖이다.
- 작업 디렉터리는 `harness-architect/`.

---

### Task 1: 배포 저장소 변경 역이식 (비파괴)

**Files:**
- Modify: `harness-architect/.claude/skills/harness-architect/` (배포본 기준으로 맞춤)

**Interfaces:**
- Produces: `scripts/harness-paths.sh`(`harness_root()`·`harness_workspace()`), `scripts/check-superpowers.sh` — 이후 모든 태스크가 의존한다.

- [ ] **Step 1: 양쪽 저장소의 사전 상태를 기록한다**

```bash
cd ~/projects/harness-engineering && git status --short > /tmp/pre-dev.txt
cd ~/projects/agent-architect  && git status --short > /tmp/pre-dist.txt
cat /tmp/pre-dev.txt /tmp/pre-dist.txt
```
예상하지 않은 변경이 있으면 여기서 멈추고 사용자에게 확인한다. 배포 저장소의 `.gitignore` 변경은 이 작업과 무관하므로 **건드리지 않는다.**

- [ ] **Step 2: 기준선을 확인한다**

```bash
cd ~/projects/harness-engineering/harness-architect
bash tests/run-all.sh | tail -3
```
Expected: `run-all: 전체 통과 — PASS 132 / FAIL 0`

- [ ] **Step 3: 무엇이 바뀔지 먼저 본다 (dry-run)**

```bash
SRC=~/projects/agent-architect/harness-architect/.claude/skills/harness-architect
DST=~/projects/harness-engineering/harness-architect/.claude/skills/harness-architect
rsync -ain --delete "$SRC/" "$DST/" | tee /tmp/sync-plan.txt
```
`deleting` 으로 시작하는 줄이 있으면 각각이 의도된 삭제인지 확인한다. 개발 저장소에만 있어야 할 파일이 목록에 있으면 중단한다.

- [ ] **Step 4: 확인한 뒤 실제로 복사한다**

```bash
rsync -a --delete "$SRC/" "$DST/"
diff -rq "$SRC" "$DST"
```
Expected: `diff` 출력 없음

- [ ] **Step 5: 회귀와 절대 경로를 확인한다**

```bash
cd ~/projects/harness-engineering/harness-architect
bash tests/run-all.sh | tail -3
grep -rn "/home/\|/Users/" .claude/ && echo FAIL || echo "OK 절대 경로 없음"
```
Expected: `PASS 132 / FAIL 0`, `OK 절대 경로 없음`

- [ ] **Step 6: 소유한 경로만 stage하고 커밋한다**

```bash
cd ~/projects/harness-engineering
git add harness-architect/.claude/skills/harness-architect
git status --short          # 의도한 것만 stage 됐는지 눈으로 확인
git commit -m "chore: 배포 저장소의 worktree 정리·preflight 변경을 역이식

agent-architect 에만 들어가 있던 변경을 가져와 두 저장소를 맞춘다.
재개 기능의 테스트가 이 저장소의 스크립트 트리를 참조하므로 선행되어야 한다."
```

---

### Task 2: harness-paths.sh 를 직접 실행 가능하게 만든다

`checkpoint.py` 와 `resume-check.py` 가 워크스페이스 경로를 알아야 한다. 파이썬에 계산 로직을 복제하면 불변식이 둘로 갈라진다.

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

bash "$SCRIPT" >/dev/null 2>&1; rc=$?
assert_exit_code 2 "$rc" "인자 없이 실행하면 사용법 오류"

report_and_exit
EOF
chmod +x tests/test-harness-paths.sh
```

- [ ] **Step 2: 실패를 확인한다**

Run: `bash tests/test-harness-paths.sh`
Expected: FAIL — `--print` 이 아무것도 출력하지 않는다.

- [ ] **Step 3: 직접 실행 모드를 추가한다**

`harness-paths.sh` 맨 끝에 붙인다. source 될 때는 `$0` 가 호출자이므로 실행되지 않는다.

```bash
# 직접 실행되면(`bash harness-paths.sh --print`) 워크스페이스 경로를 낸다.
# python3 진입점(checkpoint.py·resume-check.py)이 경로 계산을 복제하지 않도록
# 하는 유일한 목적이다 — 계산 로직의 진실의 원천은 이 파일 하나로 유지한다.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        --print)      harness_workspace ;;
        # artifacts 에 상대 경로로 적힌 산출물(spec.yaml 등)을 두 스크립트가 같은
        # 기준으로 해석하도록 루트도 낸다. HARNESS_WORKSPACE 로 워크스페이스만
        # 옮긴 경우에도 루트는 여전히 메인 워크트리다.
        --print-root) harness_root ;;
        *) echo "usage: harness-paths.sh --print|--print-root  (그 외에는 source 해서 쓴다)" >&2
           exit 2 ;;
    esac
fi
```

- [ ] **Step 4: 통과와 회귀를 확인한다**

```bash
bash tests/test-harness-paths.sh
bash tests/run-all.sh | tail -3
```
Expected: `all tests passed`, `run-all: 전체 통과 — FAIL 0`

- [ ] **Step 5: 커밋**

```bash
git add .claude/skills/harness-architect/scripts/harness-paths.sh tests/test-harness-paths.sh
git commit -m "feat: harness-paths.sh 에 --print 직접 실행 모드 추가

python3 진입점이 워크스페이스 경로 계산을 복제하지 않게 한다."
```

---

### Task 3: checkpoint.py — 원자적 쓰기와 fail-closed 로드

**Files:**
- Create: `.claude/skills/harness-architect/scripts/checkpoint.py`
- Test: `tests/test-checkpoint.sh` (신규)

**Interfaces:**
- Consumes: `harness-paths.sh --print` (Task 2)
- Produces:
  - `checkpoint.py --phase <0..5|done> [--level H0..H3] [--next "<한 줄>"] [--goal "<문장>"]`
  - `load(path) -> (state|None, error|None)` — 파일이 없을 때만 `blank_state()`. 파싱 실패·미지원 schema는 `(None, 사유)`.
  - `save(path, state)` — 같은 디렉터리 임시 파일 + `os.replace`.
  - exit 0 성공 / 2 사용법·입력 오류 / 3 **state 손상 — 아무것도 쓰지 않았다**

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```bash
cat > tests/test-checkpoint.sh <<'EOF'
#!/usr/bin/env bash
# tests/test-checkpoint.sh — 진행 상태를 원자적으로 기록하고, 손상된 state 를 덮지 않는다.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/lib/assert.sh"
CP="$ROOT/.claude/skills/harness-architect/scripts/checkpoint.py"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HARNESS_WORKSPACE="$TMP/ws"
mkdir -p "$HARNESS_WORKSPACE"
STATE="$HARNESS_WORKSPACE/state.json"

jq_() { python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print(eval(sys.argv[2],{},{'d':d}))" "$STATE" "$1"; }

# 1. 없으면 새로 만든다
python3 "$CP" --phase 1 --goal "업로드 API 이관"; rc=$?
assert_exit_code 0 "$rc" "state 가 없으면 새로 만든다"
assert_file_exists "$STATE" "state.json 생성됨"
assert_eq "1" "$(jq_ 'd["phase"]')"          "phase 를 기록한다"
assert_eq "1" "$(jq_ 'd["schema_version"]')" "schema_version 은 1"
assert_eq "업로드 API 이관" "$(jq_ 'd["task"]["goal"]')" "goal 을 기록한다"

tid="$(jq_ 'd["task"]["id"]')"
if [[ -n "$tid" && "$tid" != "None" ]]; then echo "PASS: task.id 를 발급한다"
else echo "FAIL: task.id 가 비었다"; FAILURES=$((FAILURES+1)); fi

# 2. 병합 — 기존 값을 보존한다
python3 "$CP" --phase 2 --level H2 --next "게이트 감지 완료"
assert_eq "H2" "$(jq_ 'd["level"]')" "level 을 기록한다"
assert_eq "게이트 감지 완료" "$(jq_ 'd["next_action"]')" "next_action 을 기록한다"
python3 "$CP" --phase 3
assert_eq "H2" "$(jq_ 'd["level"]')" "phase 만 바꿔도 level 이 보존된다"
assert_eq "$tid" "$(jq_ 'd["task"]["id"]')" "task.id 는 유지된다"

# 3. 원자적 쓰기 — 임시 파일 잔여 없음
assert_eq "0" "$(find "$HARNESS_WORKSPACE" -name '.state-*' | wc -l)" "임시 파일 잔여 없음"

# 4. 저장소 지문
git init -q "$TMP/repo"; git -C "$TMP/repo" config user.email t@t; git -C "$TMP/repo" config user.name t
echo hi > "$TMP/repo/a.txt"; git -C "$TMP/repo" add -A; git -C "$TMP/repo" commit -qm init
head="$(git -C "$TMP/repo" rev-parse HEAD)"
(cd "$TMP/repo" && python3 "$CP" --phase 2)
assert_eq "$head" "$(jq_ 'd["repo"]["head"]')" "HEAD SHA 를 기록한다"
dg="$(jq_ 'd["repo"]["tree_digest"]')"
if [[ "$dg" == sha256:* ]]; then echo "PASS: tree_digest 를 기록한다"
else echo "FAIL: tree_digest 형식이 아니다 ($dg)"; FAILURES=$((FAILURES+1)); fi

# 5. 잘못된 입력을 거부한다
python3 "$CP" --phase 9 2>/dev/null; assert_exit_code 2 "$?" "허용되지 않는 phase 를 거부한다"
python3 "$CP" --level H9 2>/dev/null; assert_exit_code 2 "$?" "허용되지 않는 level 을 거부한다"

# 6. fail-closed — 손상된 state 를 절대 덮지 않는다
cp "$STATE" "$TMP/good.json"
printf '{ this is not json' > "$STATE"
before="$(cat "$STATE")"
python3 "$CP" --phase 4 2>/dev/null; rc=$?
assert_exit_code 3 "$rc" "손상된 state 에서는 exit 3"
assert_eq "$before" "$(cat "$STATE")" "손상된 원본 바이트가 보존된다"

# 7. 미지원 schema_version 도 덮지 않는다
python3 -c "import json,sys;json.dump({'schema_version':99},open(sys.argv[1],'w'))" "$STATE"
before="$(cat "$STATE")"
python3 "$CP" --phase 4 2>/dev/null; rc=$?
assert_exit_code 3 "$rc" "미지원 schema_version 에서는 exit 3"
assert_eq "$before" "$(cat "$STATE")" "미지원 schema 원본도 보존된다"

# 8. 반복 쓰기 중 reader 가 불완전 JSON 을 보지 않는다 (원자성)
cp "$TMP/good.json" "$STATE"
( for i in $(seq 1 40); do python3 "$CP" --next "n$i" >/dev/null 2>&1; done ) &
writer=$!
bad=0
while kill -0 "$writer" 2>/dev/null; do
    python3 -c "import json,sys;json.load(open(sys.argv[1]))" "$STATE" 2>/dev/null || bad=$((bad+1))
done
wait "$writer"
assert_eq "0" "$bad" "쓰기 중에도 항상 완전한 JSON 만 읽힌다"

report_and_exit
EOF
chmod +x tests/test-checkpoint.sh
```

- [ ] **Step 2: 실패를 확인한다**

Run: `bash tests/test-checkpoint.sh`
Expected: FAIL — `checkpoint.py` 가 없다.

- [ ] **Step 3: checkpoint.py 를 구현한다**

```python
#!/usr/bin/env python3
"""checkpoint.py — 하네스 진행 상태를 state.json 에 원자적으로 기록한다.

사용법:
    checkpoint.py --phase <0..5|done> [--level H0..H3] [--next "<한 줄>"] [--goal "<문장>"]

종료코드:
    0  성공
    2  사용법·입력 오류 (argparse 기본값)
    3  state 가 손상됐다 — **아무것도 쓰지 않았다**

왜 원자적으로 쓰는가:
    이 파일의 존재 이유가 "갑작스러운 중단에서 살아남는 것"이다. 쓰기 도중에
    중단되어 반쪽짜리 JSON 이 남으면 재개가 그 자리에서 막힌다. 같은 디렉터리에
    임시 파일을 쓰고 os.replace 로 교체한다(같은 파일시스템이라 원자적이다).

왜 손상된 state 를 빈 상태로 갈아치우지 않는가 (fail-closed):
    초기 설계는 파싱 실패를 blank_state() 로 바꿨다. 그러면 뒤이은 save() 가
    원본 손상 파일을 덮어써 복구 근거를 잃는다. 게다가 자동 기록(init-workspace·
    run-gates)이 오류를 숨기므로 사용자는 알아채지도 못한다. 파일이 없을 때만
    새로 만들고, 읽을 수 없으면 손대지 않고 exit 3 으로 알린다.

왜 PyYAML 을 쓰지 않는가:
    PyYAML 은 이 저장소에서 선택 의존이다. validate-spec.py 는 없으면 exit 2 로
    물러나도 되지만, 재개는 그때도 동작해야 한다. json 은 표준 라이브러리다.

동시 writer 는 지원하지 않는다. 하네스가 구현 워커의 동시 dispatch 를 금지하므로
state 를 쓰는 주체는 항상 하나다.
"""
import argparse
import hashlib
import json
import os
import subprocess
import sys
import tempfile
from datetime import datetime, timezone

SCHEMA_VERSION = 1
PHASES = {"0", "1", "2", "3", "4", "5", "done"}
LEVELS = {"H0", "H1", "H2", "H3"}
TIERS = {"fast", "feature", "final"}

# references/catalog.md · validate-spec.py 의 CATALOG 와 같은 집합이어야 한다.
CATALOG = {
    "implementer", "reviewer", "dependency-mapper", "baseline-tester",
    "integrator", "orchestrator", "deployment-agent",
}

EXIT_OK, EXIT_USAGE, EXIT_CORRUPT = 0, 2, 3
HERE = os.path.dirname(os.path.abspath(__file__))


def now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _paths(flag):
    """경로 계산의 진실의 원천은 harness-paths.sh 하나다 — 여기서 복제하지 않는다."""
    out = subprocess.run(
        ["bash", os.path.join(HERE, "harness-paths.sh"), flag],
        capture_output=True, text=True,
    )
    if out.returncode != 0 or not out.stdout.strip():
        print(f"checkpoint: 경로를 구하지 못했습니다 ({flag})", file=sys.stderr)
        sys.exit(EXIT_USAGE)
    return out.stdout.strip()


def workspace():
    return _paths("--print")


def resolve(rel):
    """artifacts 에 상대 경로로 적힌 산출물을 메인 워크트리 기준으로 푼다.
    linked worktree 안에서 재개해도 같은 파일을 가리켜야 한다."""
    if not rel:
        return None
    return rel if os.path.isabs(rel) else os.path.join(_paths("--print-root"), rel)


def git(*args):
    r = subprocess.run(["git", *args], capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else None


EXCLUDE_WS = ":(exclude)_workspace/"


def file_digest(path):
    h = hashlib.sha256()
    try:
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(65536), b""):
                h.update(chunk)
    except OSError:
        return "unreadable"
    return h.hexdigest()


def tree_digest():
    """_workspace/ 를 뺀 작업 트리 **내용**의 지문.

    git status --porcelain 의 행만 해시하면 부족하다. status 는 경로와 변경 여부만
    낼 뿐 내용을 담지 않으므로, 이미 수정된 같은 파일을 다시 다르게 고쳐도 출력이
    'M a.txt' 로 같아 digest 가 바뀌지 않는다(임시 저장소에서 재현됨).

    그래서 tracked 변경은 diff 본문을, untracked 는 경로와 파일 내용을 해시한다.
    _workspace/ 제외는 pathspec 으로 한다 — 문자열 필터는 src/my_workspace/ 같은
    무관한 경로까지 지운다.
    """
    diff = git("diff", "--binary", "HEAD", "--", ".", EXCLUDE_WS)
    if diff is None:
        return None
    untracked = git("ls-files", "--others", "--exclude-standard", "--", ".", EXCLUDE_WS) or ""

    h = hashlib.sha256()
    h.update(diff.encode("utf-8", "surrogateescape"))
    for rel in sorted(untracked.split("\n")):
        if not rel:
            continue
        h.update(b"\0U\0")
        h.update(rel.encode("utf-8", "surrogateescape"))
        h.update(file_digest(rel).encode("ascii"))
    return "sha256:" + h.hexdigest()


def spec_digest(spec_path):
    """승인된 spec.yaml 의 지문. 파일이 없으면 None 이 아니라 표식을 낸다 —
    '기록된 적 없음'과 '있었는데 사라졌음'은 다르게 다뤄야 한다."""
    if not spec_path:
        return None
    if not os.path.isfile(spec_path):
        return "missing"
    return "sha256:" + file_digest(spec_path)


def repo_fingerprint():
    """재개 시 '세상이 움직였는가'를 판정할 지문."""
    worktree = None
    top = (git("rev-parse", "--show-toplevel") or "").strip()
    common = (git("rev-parse", "--git-common-dir") or "").strip()
    if top and common:
        # git-common-dir 의 부모가 메인 트리다. 다르면 지금은 linked worktree 안이다.
        main = os.path.dirname(os.path.abspath(common))
        if os.path.abspath(top) != main:
            worktree = os.path.abspath(top)
    head = git("rev-parse", "HEAD")
    branch = git("branch", "--show-current")
    return {
        "head": head.strip() if head else None,
        "branch": branch.strip() if branch else None,
        "worktree": worktree,
        "tree_digest": tree_digest(),
    }


def blank_state():
    return {
        "schema_version": SCHEMA_VERSION,
        "updated_at": None,
        "task": {"id": datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
                       + "-" + hashlib.sha256(os.urandom(8)).hexdigest()[:4],
                 "goal": "", "spec_digest": None},
        "phase": "0",
        "level": None,
        "approved": False,
        "repo": {"head": None, "branch": None, "worktree": None, "tree_digest": None},
        "artifacts": {"spec": None, "gates_tsv": None, "sdd_ledger": None},
        "progress": {"agents_done": [], "agents_pending": [], "gates": [],
                     "review_loops_used": 0, "human_gate_passed": False},
        "next_action": "",
    }


def load(path):
    """(state, error) 를 낸다. 파일이 없을 때만 새 상태를 만든다."""
    if not os.path.exists(path):
        return blank_state(), None
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (json.JSONDecodeError, OSError) as e:
        return None, f"state 를 읽을 수 없습니다: {e}"
    if not isinstance(data, dict):
        return None, "state 가 매핑이 아닙니다"
    if data.get("schema_version") != SCHEMA_VERSION:
        return None, (f"지원하지 않는 schema_version={data.get('schema_version')} "
                      f"(이 스크립트는 {SCHEMA_VERSION})")
    base = blank_state()
    base.update(data)
    return base, None


def save(path, state):
    state["updated_at"] = now()
    d = os.path.dirname(path)
    os.makedirs(d, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".state-", suffix=".json")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(state, f, ensure_ascii=False, indent=2)
            f.write("\n")
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)          # 원자적 교체
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def build_parser():
    p = argparse.ArgumentParser(add_help=True)
    p.add_argument("--phase")
    p.add_argument("--level")
    p.add_argument("--next", dest="next_action")
    p.add_argument("--goal")
    return p


def main():
    p = build_parser()
    args = p.parse_args()

    if args.phase is not None and args.phase not in PHASES:
        p.error(f"허용되지 않는 phase '{args.phase}' (가능: {sorted(PHASES)})")
    if args.level is not None and args.level not in LEVELS:
        p.error(f"허용되지 않는 level '{args.level}' (가능: {sorted(LEVELS)})")

    path = os.path.join(workspace(), "state.json")
    state, err = load(path)
    if err:
        print(f"checkpoint: {err}", file=sys.stderr)
        print(f"  파일: {path}", file=sys.stderr)
        print("  아무것도 쓰지 않았습니다. 내용을 확인하고 직접 처리하십시오.", file=sys.stderr)
        return EXIT_CORRUPT

    if args.phase is not None:
        # 역행은 --replan 으로만 한다. 맨 --phase 로 되돌리면 이전 계약의 승인과
        # 진행이 그대로 남는다 — 무엇을 초기화할지 아무도 정하지 않은 상태가 된다.
        old, new = state.get("phase"), args.phase
        if old not in (None, "done") and new != "done" \
                and str(new).isdigit() and str(old).isdigit() and int(new) < int(old):
            p.error(f"phase 역행({old}→{new})은 --replan 으로 하십시오 "
                    "(승인·진행 초기화 계약이 붙어 있습니다)")
        state["phase"] = args.phase
    if args.level is not None:
        state["level"] = args.level
    if args.next_action is not None:
        state["next_action"] = args.next_action
    if args.goal is not None:
        state["task"]["goal"] = args.goal

    state["repo"] = repo_fingerprint()
    save(path, state)
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: 통과를 확인한다**

Run: `bash tests/test-checkpoint.sh`
Expected: 전부 PASS, `=== all tests passed ===`

- [ ] **Step 5: 커밋**

```bash
git add .claude/skills/harness-architect/scripts/checkpoint.py tests/test-checkpoint.sh
git commit -m "feat: checkpoint.py — 원자적 기록과 fail-closed 로드

os.replace 로 원자적으로 쓰고, 손상된 state 는 손대지 않고 exit 3 으로
알린다. 파일이 없을 때만 새로 만든다 — 파싱 실패를 빈 상태로 갈아치우면
복구 근거를 잃는다. tree_digest 로 같은 HEAD 의 unstaged 변경도 잡는다."
```

---

### Task 4: checkpoint.py — 진행 갱신과 상태 전이 불변식

**Files:**
- Modify: `.claude/skills/harness-architect/scripts/checkpoint.py`
- Modify: `tests/test-checkpoint.sh`

**Interfaces:**
- Consumes: Task 3의 `load()` · `save()` · `CATALOG` · `TIERS`
- Produces:
  - `--approved --agents a,b` — **`--phase 3` 과 함께여야 한다**
  - `--agent-done <id>` — `agents_pending` 에 있고 카탈로그 안인 id만
  - `--gate <tier>:<exit> [--log-path <path>]` — `attempt` 는 tier별로 자동 증가
  - `--review-loop` · `--human-gate-passed` · `--artifact <key>=<path>`
  - `--approved` 시 `artifacts.spec` 파일을 직접 읽어 `task.spec_digest` 를 채운다
  - `--replan --level <새 레벨>` — 승인·에이전트·게이트·루프·Human Gate·spec_digest 초기화, `phase` → `"3"`
  - 맨 `--phase` 로 번호를 낮추면 거부하고 `--replan` 으로 유도한다
  - `--archive` — **`phase == done` 일 때만.** 파일명 충돌 시 접미사를 붙인다

- [ ] **Step 1: 실패하는 테스트를 덧붙인다**

`report_and_exit` 바로 위에 삽입한다.

```bash
# 9. 승인은 Phase 3 의 산물이다
cp "$TMP/good.json" "$STATE"
python3 "$CP" --approved --agents implementer,reviewer 2>/dev/null
assert_exit_code 2 "$?" "--approved 가 --phase 3 없이 오면 거부한다"

python3 "$CP" --phase 3 --approved --agents implementer,reviewer
assert_eq "True" "$(jq_ 'd["approved"]')" "phase 3 과 함께면 승인을 세운다"
assert_eq "implementer,reviewer" "$(jq_ '",".join(d["progress"]["agents_pending"])')" \
    "agents_pending 을 초기화한다"

# 10. 카탈로그 밖 에이전트를 거부한다
python3 "$CP" --phase 3 --approved --agents implementer,ghost-agent 2>/dev/null
assert_exit_code 2 "$?" "카탈로그 밖 에이전트를 거부한다"

# 11. --agent-done 은 pending 에 있는 것만
python3 "$CP" --agent-done implementer
assert_eq "implementer" "$(jq_ '",".join(d["progress"]["agents_done"])')" "agents_done 으로 옮긴다"
assert_eq "reviewer"    "$(jq_ '",".join(d["progress"]["agents_pending"])')" "pending 에서 제거한다"
python3 "$CP" --agent-done implementer 2>/dev/null
assert_exit_code 2 "$?" "pending 에 없는 --agent-done 을 거부한다"

# 12. 게이트는 tier 별 attempt 를 센다
python3 "$CP" --gate fast:1 --log-path _workspace/harness/gates/fast.log
python3 "$CP" --gate fast:0 --log-path _workspace/harness/gates/fast.log
python3 "$CP" --gate feature:0
assert_eq "3" "$(jq_ 'len(d["progress"]["gates"])')" "게이트 결과를 누적한다"
assert_eq "2" "$(jq_ '[g for g in d["progress"]["gates"] if g["tier"]==\"fast\"][-1][\"attempt\"]')" \
    "같은 tier 의 attempt 를 증가시킨다"
assert_eq "1" "$(jq_ '[g for g in d["progress"]["gates"] if g["tier"]==\"feature\"][0][\"attempt\"]')" \
    "다른 tier 의 attempt 는 1 부터"
rec="$(jq_ 'd["progress"]["gates"][0]["recorded_at"]')"
if [[ "$rec" == 20*Z ]]; then echo "PASS: 게이트에 recorded_at 을 남긴다"
else echo "FAIL: recorded_at 형식이 아니다 ($rec)"; FAILURES=$((FAILURES+1)); fi
python3 "$CP" --gate bogus:0 2>/dev/null; assert_exit_code 2 "$?" "알 수 없는 tier 를 거부한다"

# 13. 리뷰 루프 · Human Gate
python3 "$CP" --review-loop; python3 "$CP" --review-loop
assert_eq "2" "$(jq_ 'd["progress"]["review_loops_used"]')" "리뷰 루프를 센다"
python3 "$CP" --human-gate-passed
assert_eq "True" "$(jq_ 'd["progress"]["human_gate_passed"]')" "Human Gate 통과를 기록한다"

# 14. 맨 phase 역행은 거부하고 --replan 으로 유도한다
python3 "$CP" --phase 4
python3 "$CP" --phase 3 2>/dev/null
assert_exit_code 2 "$?" "맨 --phase 역행을 거부한다"

# 14b. --replan 은 승인·진행을 초기화하고 phase 3 으로 되돌린다 (H2→H1 강등 경로)
python3 "$CP" --replan --level H1; assert_exit_code 0 "$?" "--replan 은 성공한다"
assert_eq "3"     "$(jq_ 'd["phase"]')"   "phase 를 3 으로 되돌린다"
assert_eq "H1"    "$(jq_ 'd["level"]')"   "새 레벨을 기록한다"
assert_eq "False" "$(jq_ 'd["approved"]')" "이전 승인을 초기화한다"
assert_eq "0" "$(jq_ 'len(d["progress"]["gates"])')"        "게이트를 비운다"
assert_eq "0" "$(jq_ 'd["progress"]["review_loops_used"]')" "리뷰 루프를 초기화한다"
assert_eq "0" "$(jq_ 'len(d["progress"]["agents_pending"])')" "에이전트 목록을 비운다"
assert_eq "False" "$(jq_ 'd["progress"]["human_gate_passed"]')" "Human Gate 를 초기화한다"
assert_eq "None"  "$(jq_ 'd["task"]["spec_digest"]')" "spec 지문을 초기화한다"
assert_eq "$tid"  "$(jq_ 'd["task"]["id"]')" "task.id 는 유지한다 (같은 작업이다)"

# 14c. --agents 는 --phase 3 --approved 와 함께여야 하고 중복을 거부한다
python3 "$CP" --agents implementer,reviewer 2>/dev/null
assert_exit_code 2 "$?" "--agents 단독 사용을 거부한다"
python3 "$CP" --phase 3 --approved --agents implementer,implementer 2>/dev/null
assert_exit_code 2 "$?" "--agents 중복 id 를 거부한다"
python3 "$CP" --phase 3 --approved --agents "" 2>/dev/null
assert_exit_code 2 "$?" "빈 --agents 를 거부한다"

# 15. archive 는 done 일 때만
python3 "$CP" --archive 2>/dev/null
assert_exit_code 2 "$?" "phase 가 done 이 아니면 archive 를 거부한다"
tid2="$(jq_ 'd["task"]["id"]')"
python3 "$CP" --phase done
python3 "$CP" --archive; assert_exit_code 0 "$?" "done 이면 archive 한다"
assert_file_exists "$HARNESS_WORKSPACE/state.done-$tid2.json" "task.id 로 보존한다"
if [[ -f "$STATE" ]]; then echo "FAIL: archive 후에도 state.json 이 남아 있다"; FAILURES=$((FAILURES+1))
else echo "PASS: archive 후 state.json 은 비워진다"; fi

# 16. 파일명 충돌 시 기존 기록을 덮지 않는다
cp "$TMP/good.json" "$STATE"
python3 -c "
import json,sys
d=json.load(open(sys.argv[1])); d['task']['id']=sys.argv[2]; d['phase']='done'
json.dump(d,open(sys.argv[1],'w'))" "$STATE" "$tid2"
python3 "$CP" --archive
assert_eq "2" "$(find "$HARNESS_WORKSPACE" -name "state.done-$tid2*.json" | wc -l)" \
    "파일명이 충돌하면 기존 기록을 덮지 않는다"
```

- [ ] **Step 2: 실패를 확인한다**

Run: `bash tests/test-checkpoint.sh`
Expected: FAIL — `--approved` 등이 인식되지 않아 argparse가 exit 2로 죽는다.

- [ ] **Step 3: 옵션과 불변식을 구현한다**

`build_parser()` 에 추가한다.

```python
    p.add_argument("--approved", action="store_true")
    p.add_argument("--agents", help="쉼표로 구분한 에이전트 id 목록")
    p.add_argument("--agent-done", dest="agent_done")
    p.add_argument("--gate", help="<fast|feature|final>:<exit>")
    p.add_argument("--log-path", dest="log_path")
    p.add_argument("--review-loop", action="store_true", dest="review_loop")
    p.add_argument("--human-gate-passed", action="store_true", dest="human_gate")
    p.add_argument("--artifact", action="append", default=[], help="key=path")
    p.add_argument("--archive", action="store_true")
    p.add_argument("--replan", action="store_true",
                   help="계약을 다시 만든다 — 승인·진행을 초기화하고 phase 3 으로 되돌린다")
```

`--spec-digest` 는 두지 않는다. 스킬이 해시를 계산해 넘기게 하면 잊거나 틀릴 수 있으므로
`--approved` 시 `checkpoint.py` 가 `artifacts.spec` 파일을 **직접 읽어 해시한다.**

`main()` 에서 `state, err = load(path)` 직후, `--archive` 를 먼저 처리한다.

```python
    if args.archive:
        # 진행 중인 작업을 은퇴시키지 않는다.
        if state["phase"] != "done":
            p.error(f"--archive 는 phase 가 done 일 때만 가능합니다 (현재 '{state['phase']}')")
        tid = state["task"]["id"] or "unknown"
        base = os.path.join(os.path.dirname(path), f"state.done-{tid}")
        target, n = f"{base}.json", 1
        while os.path.exists(target):     # 기존 기록을 절대 덮지 않는다
            target, n = f"{base}-{n}.json", n + 1
        os.replace(path, target)
        return EXIT_OK
```

`state["repo"] = repo_fingerprint()` 바로 앞에 넣는다.

```python
    prog = state["progress"]

    # --replan: 계약을 다시 만든다. 맨 --phase 로 역행하면 이전 계약의 승인·진행이
    # 그대로 남아 새 계획으로 흘러든다(이전 승인이 살아 있고 리뷰 루프가 이월된다).
    # 게이트를 비워도 증거를 잃지 않는다 — 로그 전문은 gates/*.log 에 그대로 있다.
    if args.replan:
        if args.phase is not None:
            p.error("--replan 은 --phase 와 함께 쓰지 않습니다 (항상 phase 3 으로 갑니다)")
        state["approved"] = False
        state["phase"] = "3"
        state["task"]["spec_digest"] = None
        prog["agents_done"] = []
        prog["agents_pending"] = []
        prog["gates"] = []
        prog["review_loops_used"] = 0
        prog["human_gate_passed"] = False

    if args.approved:
        # 승인은 Phase 3 의 산물이다. 다른 Phase 에서 세우면 재개 시 이전 승인이
        # 실행 권한으로 되살아나는 경로가 열린다.
        if args.phase != "3":
            p.error("--approved 는 --phase 3 과 함께 써야 합니다")
        state["approved"] = True
        # spec 지문은 스킬이 아니라 여기서 계산한다 — 넘기게 하면 잊거나 틀린다.
        # _workspace/ 는 tree_digest 에서 제외되므로 이 지문이 없으면 승인된 계약이
        # 손으로 바뀌어도 재개가 알아채지 못한다.
        state["task"]["spec_digest"] = spec_digest(resolve(state["artifacts"].get("spec")))
    if args.agents is not None:
        # 에이전트 구성은 승인의 산물이다.
        if not (args.approved and args.phase == "3"):
            p.error("--agents 는 --phase 3 --approved 와 함께 써야 합니다")
        ids = [a for a in args.agents.split(",") if a]
        if not ids:
            p.error("--agents 가 비었습니다")
        dup = sorted({x for x in ids if ids.count(x) > 1})
        if dup:
            p.error(f"--agents 에 중복된 id: {dup}")
        unknown = sorted(set(ids) - CATALOG)
        if unknown:
            p.error(f"카탈로그 7종에 없는 에이전트: {unknown} (가능: {sorted(CATALOG)})")
        prog["agents_pending"] = ids
        prog["agents_done"] = []
    if args.agent_done:
        if args.agent_done not in prog["agents_pending"]:
            p.error(f"'{args.agent_done}' 는 agents_pending 에 없습니다 "
                    f"(현재: {prog['agents_pending']})")
        prog["agents_pending"].remove(args.agent_done)
        prog["agents_done"].append(args.agent_done)
    if args.gate:
        tier, _, code = args.gate.partition(":")
        if tier not in TIERS or not code.isdigit():
            p.error(f"--gate 형식은 <fast|feature|final>:<exit> 입니다 (받은 값: {args.gate})")
        attempt = sum(1 for g in prog["gates"] if g.get("tier") == tier) + 1
        prog["gates"].append({"tier": tier, "exit": int(code), "attempt": attempt,
                              "recorded_at": now(), "log_path": args.log_path})
    if args.review_loop:
        prog["review_loops_used"] += 1
    if args.human_gate:
        prog["human_gate_passed"] = True
    if args.spec_digest:
        state["task"]["spec_digest"] = args.spec_digest
    for item in args.artifact:
        key, _, val = item.partition("=")
        if key not in state["artifacts"]:
            p.error(f"알 수 없는 artifact 키 '{key}' (가능: {sorted(state['artifacts'])})")
        state["artifacts"][key] = val
```

- [ ] **Step 4: 통과를 확인한다**

Run: `bash tests/test-checkpoint.sh`
Expected: 전부 PASS

- [ ] **Step 5: 커밋**

```bash
git add .claude/skills/harness-architect/scripts/checkpoint.py tests/test-checkpoint.sh
git commit -m "feat: checkpoint.py 진행 갱신과 상태 전이 불변식

--approved 는 --phase 3 과만, --agent-done 은 pending 에 있는 카탈로그
에이전트만, --archive 는 phase done 일 때만 허용한다. 아카이브 파일명이
충돌하면 접미사를 붙여 기존 기록을 보존한다. phase 역행은 허용한다 —
routing.md 의 H2→H1 강등이 4→3 을 정상 경로로 쓴다.
게이트에 attempt·recorded_at·log_path 를 남긴다."
```

---

### Task 5: resume-check.py — 판정과 exit code

**Files:**
- Create: `.claude/skills/harness-architect/scripts/resume-check.py`
- Test: `tests/test-resume-check.sh` (신규)

**Interfaces:**
- Consumes: `harness-paths.sh --print`, Task 3~4가 쓴 state.json
- Produces: exit `0` 없음 / `10` 자동 재개 후보 / `11` 사람 판단 / `12` 완료됨. 브리핑은 stdout.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```bash
cat > tests/test-resume-check.sh <<'EOF'
#!/usr/bin/env bash
# tests/test-resume-check.sh — 중단된 작업을 감지하고 재개 방식을 판정한다.
# 계약: Phase 0~2 만 자동(10). Phase 3 이상·불일치·손상은 사람 판단(11).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/lib/assert.sh"
CHECK="$ROOT/.claude/skills/harness-architect/scripts/resume-check.py"
CP="$ROOT/.claude/skills/harness-architect/scripts/checkpoint.py"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
git init -q "$TMP/repo"; git -C "$TMP/repo" config user.email t@t; git -C "$TMP/repo" config user.name t
echo hi > "$TMP/repo/a.txt"; git -C "$TMP/repo" add -A; git -C "$TMP/repo" commit -qm init

export HARNESS_WORKSPACE="$TMP/ws"
mkdir -p "$HARNESS_WORKSPACE"
STATE="$HARNESS_WORKSPACE/state.json"
run() { (cd "$TMP/repo" && python3 "$CHECK" >/dev/null 2>&1); echo $?; }

# 1. state 없음
assert_eq "0" "$(run)" "state 가 없으면 exit 0 (새 작업)"

# 2. Phase 2, 불일치 없음 → 자동 재개 후보
(cd "$TMP/repo" && python3 "$CP" --phase 2 --level H1 --goal "테스트 작업" --next "라우팅 판정 중")
assert_eq "10" "$(run)" "Phase 2 + 불일치 없음이면 10"

# 3. Phase 3 은 승인 여부와 무관하게 사람 판단
(cd "$TMP/repo" && python3 "$CP" --phase 3 --approved --agents implementer,reviewer)
assert_eq "11" "$(run)" "Phase 3 + approved 는 자동 재개하지 않는다 (승인 부활 금지)"

# 4. Phase 4
(cd "$TMP/repo" && python3 "$CP" --phase 4)
assert_eq "11" "$(run)" "Phase 4 는 사람 판단(11)"

# 5. Phase done
(cd "$TMP/repo" && python3 "$CP" --phase done)
assert_eq "12" "$(run)" "phase done 이면 exit 12"

# 6. 손상된 JSON
printf '{ this is not json' > "$STATE"
assert_eq "11" "$(run)" "손상된 state 는 예외로 죽지 않고 11"

# 7. 미지원 schema_version
python3 -c "import json,sys;json.dump({'schema_version':99,'phase':'2'},open(sys.argv[1],'w'))" "$STATE"
assert_eq "11" "$(run)" "모르는 schema_version 은 11"

report_and_exit
EOF
chmod +x tests/test-resume-check.sh
```

- [ ] **Step 2: 실패를 확인한다**

Run: `bash tests/test-resume-check.sh`
Expected: FAIL — `resume-check.py` 가 없다.

- [ ] **Step 3: resume-check.py 를 구현한다**

```python
#!/usr/bin/env python3
"""resume-check.py — 중단된 하네스 작업을 감지하고 재개 방식을 판정한다.

사용법: resume-check.py

종료코드:
     0  재개할 것 없음 (새 작업)
    10  자동 재개 후보 — Phase 0~2 이고 저장소가 그대로다
    11  사람 판단 필요 — Phase 3 이상이거나, 불일치가 있거나, state 가 손상됐다
    12  완료된 이전 작업이 남아 있다

exit code 가 10번대인 이유:
    init-workspace.sh 의 3(스택 미감지)·4(superpowers 미설치)와 헷갈리지 않게 한다.

왜 상한이 Phase 2 인가:
    Phase 3 state 에는 approved: true 가 남아 있을 수 있다. Phase 3 을 자동
    재개하면 그 승인이 새 세션의 Phase 4 실행 권한으로 읽힌다. 승인은 부활하지
    않는다 — Phase 3 이상은 항상 사람이 판단한다.

exit 10 도 "자동 재개 후보"일 뿐이다:
    이 스크립트는 state 의 task.goal 이 지금 사용자가 요청한 작업과 같은지
    판단할 수 없다(의미 판단이다). 그래서 goal 을 브리핑 맨 위에 내고, 동일성
    확인은 SKILL.md 가 한다. 같지 않으면 스킬이 자동 재개하지 않는다.
"""
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from checkpoint import (                                     # noqa: E402
    repo_fingerprint, resolve, spec_digest, SCHEMA_VERSION,
)

EXIT_NONE, EXIT_AUTO, EXIT_HUMAN, EXIT_DONE = 0, 10, 11, 12
AUTO_MAX_PHASE = 2

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


def validate_state(state):
    """state 내부 구조를 검사한다. 최상위가 매핑이고 schema_version 이 맞아도 내부
    타입이 깨져 있으면 drift()·render() 가 처리되지 않은 예외로 죽는다 — 예를 들어
    {"repo": "broken"} 은 recorded.get() 에서 AttributeError 를 낸다. 설계가 약속한
    '손상된 state 는 예외 없이 exit 11'을 지키려면 여기서 먼저 걸러야 한다."""
    errs = []
    for key in ("task", "repo", "artifacts", "progress"):
        if not isinstance(state.get(key, {}), dict):
            errs.append(f"{key} 가 매핑이 아닙니다 ({type(state.get(key)).__name__})")
    if not isinstance(state.get("phase", ""), str):
        errs.append("phase 가 문자열이 아닙니다")
    prog = state.get("progress")
    if isinstance(prog, dict):
        for key in ("agents_done", "agents_pending", "gates"):
            if not isinstance(prog.get(key, []), list):
                errs.append(f"progress.{key} 가 리스트가 아닙니다")
        for i, g in enumerate(prog.get("gates") or []):
            if not isinstance(g, dict):
                errs.append(f"progress.gates[{i}] 가 매핑이 아닙니다")
        for key in ("review_loops_used",):
            if not isinstance(prog.get(key, 0), int):
                errs.append(f"progress.{key} 가 정수가 아닙니다")
    return errs


def drift(recorded, current, state):
    """자동 재개를 막을 불일치만 낸다."""
    out = []
    for key, label in (("head", "HEAD"), ("branch", "브랜치")):
        was, now_ = recorded.get(key), current.get(key)
        if was and was != now_:
            out.append(f"{label} {str(was)[:7]} → {str(now_)[:7] if now_ else '없음'}")
    was_wt = recorded.get("worktree")
    if was_wt and not os.path.isdir(was_wt):
        out.append(f"worktree 제거됨 ({was_wt})")
    was_dg, now_dg = recorded.get("tree_digest"), current.get("tree_digest")
    if was_dg and now_dg and was_dg != now_dg:
        out.append("작업 트리 변경됨 (_workspace 제외)")

    # 승인된 계약 자체가 바뀌었는가. _workspace/ 는 tree_digest 에서 제외되므로
    # 이 검사가 없으면 spec.yaml 변조가 어떤 지문에도 잡히지 않는다.
    was_spec = (state.get("task") or {}).get("spec_digest")
    if was_spec:
        now_spec = spec_digest(resolve((state.get("artifacts") or {}).get("spec")))
        if now_spec == "missing":
            out.append("승인된 spec.yaml 이 없습니다")
        elif now_spec != was_spec:
            out.append("승인된 spec.yaml 이 변경되었습니다")
    return out


def render(state, marks, path):
    """브리핑. '작업'과 '다음 할 일'이 헤더 바로 다음에 오는 것이 규격의 핵심이다 —
    재개하는 사람이 먼저 확인해야 하는 것은 '이게 그 작업인가'이고, 그 다음이
    '무엇부터 하는가'다. 이력은 그 뒤다."""
    prog = state.get("progress") or {}
    art = state.get("artifacts") or {}
    task = state.get("task") or {}

    approved = "이전 세션에서 승인됨" if state.get("approved") else "미승인"
    print(f"[재개] {state.get('level') or '?'} · Phase {state.get('phase')} · "
          f"{approved} · {state.get('updated_at') or '?'}")
    print(f"  작업:      {task.get('goal') or '(기록되지 않음)'}  ({task.get('id') or '?'})")
    print(f"  다음 할 일: {state.get('next_action') or '(기록되지 않음)'}")

    done = ", ".join(prog.get("agents_done") or []) or "없음"
    gates = " ".join(f"{g.get('tier')}({g.get('exit')})×{g.get('attempt')}"
                     for g in (prog.get("gates") or [])) or "없음"
    print(f"  끝난 것:   {done} · 게이트 {gates}")

    pending = ", ".join(prog.get("agents_pending") or []) or "없음"
    hg = "통과" if prog.get("human_gate_passed") else "미통과"
    print(f"  남은 것:   {pending} · 리뷰 루프 {prog.get('review_loops_used', 0)}회 소진 "
          f"· Human Gate {hg}")

    if marks:
        print(f"  불일치:    {'; '.join(marks)}")

    print(f"  경로:      state {path}")
    for key in ("spec", "gates_tsv", "sdd_ledger"):
        if art.get(key):
            print(f"             {key} {art[key]}")


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
        got = state.get("schema_version") if isinstance(state, dict) else "?"
        print(f"[재개] 알 수 없는 state 형식입니다 (schema_version={got}, "
              f"이 스크립트는 {SCHEMA_VERSION})")
        print(f"  파일: {path}")
        return EXIT_HUMAN

    errs = validate_state(state)
    if errs:
        print("[재개] state 내부 구조가 손상됐습니다")
        print(f"  파일: {path}")
        for e in errs:
            print(f"  - {e}")
        print("  추측으로 복구하지 않습니다. 내용을 확인하고 이어갈지 결정하십시오.")
        return EXIT_HUMAN

    phase = str(state.get("phase", "0"))
    if phase == "done":
        render(state, [], path)
        return EXIT_DONE

    marks = drift(state.get("repo") or {}, repo_fingerprint(), state)
    try:
        numeric = int(phase)
    except ValueError:
        render(state, marks, path)
        return EXIT_HUMAN

    verdict = EXIT_AUTO if (numeric <= AUTO_MAX_PHASE and not marks) else EXIT_HUMAN
    render(state, marks, path)
    return verdict


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: 통과를 확인한다**

Run: `bash tests/test-resume-check.sh`
Expected: PASS 7줄, `=== all tests passed ===`

- [ ] **Step 5: 커밋**

```bash
git add .claude/skills/harness-architect/scripts/resume-check.py tests/test-resume-check.sh
git commit -m "feat: resume-check.py — 재개 판정과 exit code

0 없음 / 10 자동재개 후보 / 11 사람판단 / 12 완료됨.
자동 재개 상한은 Phase 2 다 — Phase 3 state 의 approved 가 새 세션의
실행 권한으로 되살아나는 경로를 막는다."
```

---

### Task 6: 불일치 강등과 브리핑 규격 검증

**Files:**
- Modify: `tests/test-resume-check.sh`

**Interfaces:**
- Consumes: Task 5의 `drift()` · `render()`

- [ ] **Step 1: 실패하는 테스트를 덧붙인다**

`report_and_exit` 바로 위에 삽입한다.

```bash
# 8. HEAD 변경 → 강등
rm -f "$STATE"; (cd "$TMP/repo" && python3 "$CP" --phase 2 --level H1 --goal "g")
echo more >> "$TMP/repo/a.txt"; git -C "$TMP/repo" add -A; git -C "$TMP/repo" commit -qm second
assert_eq "11" "$(run)" "HEAD 가 바뀌면 Phase 2 라도 강등"

# 9. 브랜치 변경 → 강등
rm -f "$STATE"; (cd "$TMP/repo" && python3 "$CP" --phase 2 --goal "g")
git -C "$TMP/repo" checkout -q -b other
assert_eq "11" "$(run)" "브랜치가 바뀌면 강등"
git -C "$TMP/repo" checkout -q -

# 10. worktree 제거 → 강등
rm -f "$STATE"
git -C "$TMP/repo" worktree add -q "$TMP/repo/.worktrees/w" -b wbranch
(cd "$TMP/repo/.worktrees/w" && python3 "$CP" --phase 2 --goal "g")
git -C "$TMP/repo" worktree remove --force "$TMP/repo/.worktrees/w"
assert_eq "11" "$(run)" "worktree 가 제거되면 강등"

# 11. 같은 HEAD 에서 작업 트리 변경 → 강등 (tree_digest)
rm -f "$STATE"; (cd "$TMP/repo" && python3 "$CP" --phase 2 --goal "g")
echo scratch > "$TMP/repo/untracked.txt"
assert_eq "11" "$(run)" "같은 HEAD 라도 작업 트리가 바뀌면 강등"
rm -f "$TMP/repo/untracked.txt"
assert_eq "10" "$(run)" "되돌리면 다시 자동 재개 후보"

# 12. _workspace 변경은 지문을 흔들지 않는다
mkdir -p "$TMP/repo/_workspace/harness"; echo x > "$TMP/repo/_workspace/harness/noise.txt"
assert_eq "10" "$(run)" "_workspace 변경은 강등하지 않는다"
rm -rf "$TMP/repo/_workspace"

# 13. 브리핑 규격
rm -f "$STATE"
(cd "$TMP/repo" && python3 "$CP" --phase 2 --level H2 --goal "업로드 API 를 S3 로 이관" \
    --next "implementer dispatch — 단위 2/3")
(cd "$TMP/repo" && python3 "$CP" --phase 3 --approved --agents implementer,reviewer)
(cd "$TMP/repo" && python3 "$CP" --agent-done implementer --gate fast:0)
brief="$(cd "$TMP/repo" && python3 "$CHECK")"
assert_contains "$brief" "[재개]"   "재개 헤더를 낸다"
assert_contains "$brief" "H2"       "레벨을 낸다"
assert_contains "$brief" "업로드 API 를 S3 로 이관" "task.goal 을 낸다"
assert_contains "$brief" "implementer dispatch — 단위 2/3" "next_action 을 낸다"
assert_contains "$brief" "reviewer" "남은 에이전트를 낸다"
assert_contains "$brief" "fast"     "실행한 게이트를 낸다"
assert_contains "$brief" "이전 세션에서 승인됨" "승인은 사실로만 표시한다"

assert_contains "$(sed -n '2p' <<< "$brief")" "작업:"      "둘째 줄은 작업이다"
assert_contains "$(sed -n '3p' <<< "$brief")" "다음 할 일" "셋째 줄은 다음 할 일이다"

if [[ "$brief" == *"불일치"* ]]; then
    echo "FAIL: 불일치가 없는데 불일치 행을 냈다"; FAILURES=$((FAILURES+1))
else echo "PASS: 불일치가 없으면 그 행을 내지 않는다"; fi

# 14. tree_digest 는 내용 기반이다 — 이미 수정된 파일을 다시 다르게 고쳐도 잡는다
#     (git status --porcelain 만 해시하면 둘 다 'M a.txt' 라 놓친다)
rm -f "$STATE"
echo "first change" > "$TMP/repo/a.txt"
(cd "$TMP/repo" && python3 "$CP" --phase 2 --goal "g")
assert_eq "10" "$(run)" "같은 내용이면 자동 재개 후보"
echo "second different change" > "$TMP/repo/a.txt"
assert_eq "11" "$(run)" "이미 수정된 파일을 다시 고치면 강등한다"
git -C "$TMP/repo" checkout -- a.txt

# 15. _workspace 제외는 pathspec 이다 — 유사 경로까지 지우지 않는다
rm -f "$STATE"; (cd "$TMP/repo" && python3 "$CP" --phase 2 --goal "g")
mkdir -p "$TMP/repo/src/my_workspace"; echo x > "$TMP/repo/src/my_workspace/f.txt"
assert_eq "11" "$(run)" "src/my_workspace 변경은 강등한다 (_workspace 와 다르다)"
rm -rf "$TMP/repo/src"

# 16. spec_digest — 승인된 계약이 바뀌면 강등한다
rm -f "$STATE"
mkdir -p "$TMP/repo/_workspace/harness"
printf 'harness_version: 1\n' > "$TMP/repo/_workspace/harness/spec.yaml"
(cd "$TMP/repo" && python3 "$CP" --phase 2 --goal "g" \
    --artifact spec=_workspace/harness/spec.yaml)
(cd "$TMP/repo" && python3 "$CP" --phase 3 --approved --agents implementer,reviewer)
assert_eq "11" "$(run)" "Phase 3 은 그 자체로 사람 판단"
brief="$(cd "$TMP/repo" && python3 "$CHECK")"
if [[ "$brief" == *"spec.yaml 이 변경"* ]]; then
    echo "FAIL: 바뀌지 않았는데 변경으로 봤다"; FAILURES=$((FAILURES+1))
else echo "PASS: spec 이 그대로면 불일치로 보지 않는다"; fi

printf 'harness_version: 1\nlevel: tampered\n' > "$TMP/repo/_workspace/harness/spec.yaml"
brief="$(cd "$TMP/repo" && python3 "$CHECK")"
assert_contains "$brief" "spec.yaml 이 변경되었습니다" "spec 내용 변경을 불일치로 낸다"

rm -f "$TMP/repo/_workspace/harness/spec.yaml"
brief="$(cd "$TMP/repo" && python3 "$CHECK")"
assert_contains "$brief" "spec.yaml 이 없습니다" "spec 삭제를 불일치로 낸다"
rm -rf "$TMP/repo/_workspace"

# 17. 내부 구조 손상 — 처리되지 않은 예외로 죽지 않는다
for broken in '{"schema_version":1,"phase":"2","repo":"broken"}' \
              '{"schema_version":1,"phase":"2","progress":[]}' \
              '{"schema_version":1,"phase":"2","progress":{"gates":[null]}}'; do
    printf '%s' "$broken" > "$STATE"
    out="$(cd "$TMP/repo" && python3 "$CHECK" 2>&1)"; rc=$?
    assert_exit_code 11 "$rc" "내부 손상 state 는 exit 11: ${broken:0:44}"
    if [[ "$out" == *"Traceback"* ]]; then
        echo "FAIL: 처리되지 않은 예외가 났다"; FAILURES=$((FAILURES+1))
    else echo "PASS: 예외 없이 브리핑한다"; fi
done
```

- [ ] **Step 2: 실패를 확인한다**

Run: `bash tests/test-resume-check.sh`
Expected: FAIL — `tree_digest` 비교가 없으면 11번이 `10` 으로 나온다.

- [ ] **Step 3: 필요한 보완만 한다**

Task 5의 `drift()` 에 이미 `tree_digest` 비교가 있다. 실패하는 항목이 있으면 그 항목만 고친다. 브리핑 줄 순서가 어긋나면 `render()` 의 `print` 순서를 규격에 맞춘다.

- [ ] **Step 4: 통과와 회귀를 확인한다**

```bash
bash tests/test-resume-check.sh
bash tests/run-all.sh | tail -3
```
Expected: `all tests passed`, `run-all: 전체 통과 — FAIL 0`

- [ ] **Step 5: 커밋**

```bash
git add tests/test-resume-check.sh .claude/skills/harness-architect/scripts/resume-check.py
git commit -m "test: 불일치 강등과 브리핑 규격 회귀

HEAD·브랜치·worktree·tree_digest 각각이 강등을 유발하는지, _workspace
변경은 유발하지 않는지 확인한다. 브리핑의 둘째·셋째 줄이 '작업'과
'다음 할 일'인지 고정한다."
```

---

### Task 7: 자동 기록 — 실패를 숨기지 않는다

**Files:**
- Modify: `.claude/skills/harness-architect/scripts/init-workspace.sh`
- Modify: `.claude/skills/harness-architect/scripts/run-gates.sh`
- Modify: `tests/test-run-gates.sh`

**Interfaces:**
- Consumes: `checkpoint.py --phase 1`, `checkpoint.py --gate <tier>:<exit> --log-path <p>`

- [ ] **Step 1: 실패하는 테스트를 덧붙인다**

`tests/test-run-gates.sh` 의 `report_and_exit` 위에 삽입한다.

```bash
# 게이트 실행이 state.json 에 자동 기록된다
WS_AUTO="$(mktemp -d)"
printf 'fast\ttrue\n' > "$WS_AUTO/gates.tsv"
HARNESS_WORKSPACE="$WS_AUTO" bash "$SCRIPT" fast "$WS_AUTO/gates.tsv" "$WS_AUTO/logs" >/dev/null 2>&1
assert_file_exists "$WS_AUTO/state.json" "run-gates 실행 후 state 가 생긴다"
tiers="$(python3 -c 'import json,sys;print(",".join(g["tier"] for g in json.load(open(sys.argv[1]))["progress"]["gates"]))' "$WS_AUTO/state.json")"
assert_contains "$tiers" "fast" "게이트 결과를 자동 기록한다"

# 손상된 state 에서도 게이트 판정은 유지되고, 원본은 보존되며, 경고가 뜬다
printf '{ broken' > "$WS_AUTO/state.json"
before="$(cat "$WS_AUTO/state.json")"
err="$(HARNESS_WORKSPACE="$WS_AUTO" bash "$SCRIPT" fast "$WS_AUTO/gates.tsv" "$WS_AUTO/logs" 2>&1 >/dev/null)"; rc=$?
assert_exit_code 0 "$rc" "checkpoint 실패가 게이트 exit code 를 바꾸지 않는다"
assert_eq "$before" "$(cat "$WS_AUTO/state.json")" "손상된 state 원본이 보존된다"
assert_contains "$err" "checkpoint" "기록 실패를 stderr 로 알린다"
rm -rf "$WS_AUTO"
```

- [ ] **Step 2: 실패를 확인한다**

Run: `bash tests/test-run-gates.sh`
Expected: FAIL — `state.json` 이 생기지 않는다.

- [ ] **Step 3: run-gates.sh 에 자동 기록을 얹는다**

최종 판정 직전(`if [[ "$failed" -gt 0 ]]` 바로 위)에 넣는다.

```bash
# 진행 상태에 게이트 결과를 남긴다. 기록 실패는 게이트 판정을 바꾸지 않지만
# **조용히 넘어가지도 않는다** — 조용한 실패는 재개 기능의 목적을 무너뜨린다.
if [[ -f "$HERE/checkpoint.py" ]]; then
    rc_gate=0
    [[ "$failed" -gt 0 ]] && rc_gate=1
    if ! python3 "$HERE/checkpoint.py" --gate "$TIER:$rc_gate" --log-path "$LOG" >/dev/null; then
        echo "run-gates: checkpoint 기록에 실패했습니다 (게이트 판정에는 영향 없음)." >&2
        echo "  재개 상태가 최신이 아닐 수 있습니다: $(bash "$HERE/harness-paths.sh" --print)/state.json" >&2
    fi
fi
```

- [ ] **Step 4: init-workspace.sh 에 자동 기록을 얹는다**

`mkdir -p "$WS/gates" ...` 바로 다음에 넣는다.

```bash
# Phase 1 진입을 기록한다. 이후 세션이 "어디까지 했나"를 물을 때의 출발점이다.
if ! python3 "$HERE/checkpoint.py" --phase 1 \
        --next "게이트 감지 결과 확인 후 Phase 2 프로파일링" \
        --artifact "gates_tsv=$WS/gates.tsv" >/dev/null; then
    echo "init-workspace: checkpoint 기록에 실패했습니다 (워크스페이스 준비는 계속합니다)." >&2
fi
```

- [ ] **Step 5: 통과와 회귀를 확인한다**

```bash
bash tests/test-run-gates.sh
bash tests/run-all.sh | tail -3
```
Expected: `all tests passed`, `run-all: 전체 통과 — FAIL 0`

- [ ] **Step 6: 커밋**

```bash
git add .claude/skills/harness-architect/scripts/init-workspace.sh \
        .claude/skills/harness-architect/scripts/run-gates.sh tests/test-run-gates.sh
git commit -m "feat: init-workspace 와 run-gates 가 진행을 자동 기록

규율에 의존하는 기록 지점을 둘 줄인다. 기록 실패는 게이트 판정을 바꾸지
않지만 stderr 로 알린다 — 조용한 실패는 재개의 목적을 무너뜨린다."
```

---

### Task 8: SKILL.md 와 문서 동기화

**Files:**
- Modify: `.claude/skills/harness-architect/SKILL.md`
- Modify: `harness-architect/README.md` · `CLAUDE.md` · `CHECKLIST.md` · `MIGRATION.md`

- [ ] **Step 1: SKILL.md 에 Phase −1 을 넣는다**

`## Phase 0 — 입력 정규화` 바로 위에 추가한다.

```markdown
## Phase −1 — 재개 판정 (Phase 0보다 먼저)

`Bash: python3 .claude/skills/harness-architect/scripts/resume-check.py`

- exit 0 → 재개할 것 없음. Phase 0으로 간다.
- exit 10 → **자동 재개 후보.** 브리핑의 `작업:` 줄이 **지금 사용자가 요청한 작업과 같은지
  판단한다.** 같으면 기록된 Phase부터 이어서 진행한다. 같지 않거나 확신할 수 없으면
  exit 11과 똑같이 다룬다 — 남의 작업을 이어받지 않는다.
- exit 11 → **사람 판단.** 브리핑을 제시하고 **멈춘다.** 재개·재판정·폐기를 사용자가 고른다.
  **Phase 3 이상이면 승인이 남아 있어도 새로 승인받는다.** 이전 세션의 승인은 이번 세션의
  실행 권한이 아니다.
- exit 12 → 완료된 이전 작업이 남아 있다. 새 작업을 시작할지 묻고, 승인되면
  `checkpoint.py --archive` 로 보존한 뒤 Phase 0으로 간다.

state가 손상됐다는 브리핑이 나오면 **추측으로 복구하지 않는다.** 파일을 사용자에게 보이고
이어갈지 새로 시작할지 묻는다.
```

- [ ] **Step 2: 각 Phase에 기록 호출을 넣는다**

- Phase 0 끝: `--phase 0 --goal "<정규화한 goal>"`
- Phase 2 끝: `--phase 2 --level <판정> --next "<다음 행동>"`
- Phase 3 승인 직후: `--phase 3 --approved --agents <spec의 agents id 쉼표 목록> --artifact spec=_workspace/harness/spec.yaml`
- Phase 4 역할 완료마다: `--agent-done <id> --next "<다음 행동>"` — **H2/H3의 `implementer` 는 SDD 루프 전체가 끝났을 때만** 호출한다(역할 마일스톤이지 작업 단위가 아니다)
- 리뷰 루프 소진마다: `--review-loop`
- Human Gate 통과: `--human-gate-passed`
- Phase 5 종료: `--phase done`

- [ ] **Step 3: 불변 규칙을 추가한다**

```markdown
- **진행을 기록한다**: Phase 전환과 역할 완료마다 `checkpoint.py` 를 부른다. 기록하지 않으면
  다음 세션이 처음부터 다시 판정하게 되고, 같은 작업에 다른 레벨이 나올 수 있다.
  기록 실패는 하네스를 멈추지 않지만 조용히 넘어가지도 않는다.
- **승인은 세션을 넘어 상속되지 않는다**: 재개 시 `approved: true` 는 사실 기록일 뿐
  실행 권한이 아니다. Phase 3 이상에서 재개하면 반드시 새로 승인받는다.
```

- [ ] **Step 4: README·CLAUDE.md·CHECKLIST.md 를 갱신한다**

- README 구성 목록에 `checkpoint.py` · `resume-check.py` 추가, "중단하면 재개한다" 절 추가(exit code 표 + Phase 2 상한 근거)
- CLAUDE.md 불변식 표에 4행 추가: resume exit code / state 스키마 / `AUTO_MAX_PHASE` / 카탈로그 7종에 `checkpoint.py` 포함
- CLAUDE.md 검증 절차에 `bash tests/test-checkpoint.sh` · `test-resume-check.sh` 추가
- CHECKLIST.md B-1에 재개 항목 추가, **B-4의 "두 경로만 복사"를 `MIGRATION.md` 와 맞춘다** (`settings.json` 포함)

- [ ] **Step 5: MIGRATION.md 의 낡은 파일 수를 고친다**

"정확히 25개 파일"과 `find .claude -type f | wc -l   # 25` 가 이미 틀렸다. `harness-paths.sh` ·
`check-superpowers.sh` 로 27개가 됐고, 이 작업이 `checkpoint.py` · `resume-check.py` 를 더해 29개가 된다.

```bash
find .claude -type f | wc -l   # 실측값으로 갱신
```
숫자를 고정값으로 박는 대신 **구성 내역(SKILL.md 1 + references 5 + examples 4 + schemas 1 + scripts N + agents 7 + settings.json 1)** 을 적고, 검증은 실측 명령으로 대체한다.

- [ ] **Step 6: 문서가 실제와 맞는지 확인한다**

```bash
grep -rn "checkpoint\.sh\|resume-check\.sh" . --include="*.md" && echo "FAIL: 옛 이름" || echo OK
grep -rn "두 경로만" CHECKLIST.md && echo "FAIL: settings.json 누락" || echo OK
bash tests/run-all.sh | tail -3
```
Expected: `OK` 2줄, `FAIL 0`

- [ ] **Step 7: 소유한 파일만 stage하고 커밋한다**

```bash
git add .claude/skills/harness-architect/SKILL.md README.md CLAUDE.md CHECKLIST.md MIGRATION.md
git status --short
git commit -m "docs: 재개 절차를 SKILL.md 와 저장소 문서에 반영

Phase -1 재개 판정을 Phase 0 앞에 둔다. 승인이 세션을 넘어 상속되지
않는다는 불변 규칙을 추가한다. CHECKLIST B-4 의 이식 경계를 MIGRATION.md
와 맞추고(settings.json 포함), 낡은 '25개 파일' 수치를 실측 기준으로 바꾼다."
```

---

### Task 9: 배포 저장소로 이식 (비파괴)

**Files:**
- Modify: `~/projects/agent-architect/harness-architect/`

- [ ] **Step 1: 배포 저장소의 사전 상태를 확인한다**

```bash
cd ~/projects/agent-architect && git status --short
```
`.gitignore` 의 `.omx/` 변경은 **이 작업과 무관하다.** 건드리지 않고 stage하지도 않는다. 다른 예상치 못한 변경이 있으면 멈추고 사용자에게 확인한다.

- [ ] **Step 2: 무엇이 바뀔지 먼저 본다**

```bash
SRC=~/projects/harness-engineering/harness-architect/.claude
DST=~/projects/agent-architect/harness-architect/.claude
rsync -ain --delete "$SRC/skills/" "$DST/skills/"
rsync -ain --delete "$SRC/agents/" "$DST/agents/"
diff "$SRC/settings.json" "$DST/settings.json" && echo "settings.json 동일" || echo "settings.json 차이 — 병합 필요"
```
삭제 목록을 확인한 뒤 진행한다.

- [ ] **Step 3: 실제로 복사한다**

```bash
rsync -a --delete "$SRC/skills/" "$DST/skills/"
rsync -a --delete "$SRC/agents/" "$DST/agents/"
```
`settings.json` 은 Step 2에서 차이가 있을 때만, 훅 항목을 **병합**한다(교체하지 않는다).

- [ ] **Step 4: 이식 경계를 확인한다**

```bash
cd ~/projects/agent-architect/harness-architect
for d in tests fixtures evals; do [ -e "$d" ] && echo "FAIL: $d 이식됨" || echo "OK $d"; done
grep -rn "/home/\|/Users/" .claude/ && echo FAIL || echo "OK 절대 경로 없음"
find .claude -type f | wc -l    # MIGRATION.md 의 구성 내역과 일치하는지
```

- [ ] **Step 5: 배포본에서 동작을 확인한다**

```bash
S=.claude/skills/harness-architect
for f in $S/scripts/*.sh; do bash -n "$f" || echo "FAIL $f"; done
bash $S/scripts/check-superpowers.sh
python3 $S/scripts/resume-check.py; echo "resume-check exit=$? (0 이어야 함 — state 없음)"
for f in $S/examples/*.yaml; do python3 $S/scripts/validate-spec.py "$f" | tail -1; done
```
Expected: 셸 문법 통과, preflight 11종, `resume-check exit=0`, 예제 4종 `통과 (경고 0건)`

- [ ] **Step 6: 배포 저장소 문서를 갱신하고, 소유한 파일만 커밋한다**

`agent-architect/CLAUDE.md` 의 불변식 표와 검증 절차에 재개 관련 행을 추가한다(원본과 같은 내용).

```bash
cd ~/projects/agent-architect
git add harness-architect/.claude CLAUDE.md
git status --short          # .gitignore 가 stage 되지 않았는지 반드시 확인
git commit -m "feat: 재개(resume) 기능 이식

harness-engineering 에서 개발한 checkpoint.py·resume-check.py 와
Phase -1 재개 판정을 배포 저장소로 가져온다."
```

- [ ] **Step 7: 두 저장소가 일치하는지 확인한다**

```bash
diff -rq ~/projects/harness-engineering/harness-architect/.claude/skills/harness-architect \
         ~/projects/agent-architect/harness-architect/.claude/skills/harness-architect
```
Expected: 출력 없음

---

## Self-Review

**스펙 커버리지**

| 스펙 절 | 태스크 |
|---|---|
| 자동 재개 상한 Phase 2 · 승인 부활 금지 | Task 5(`AUTO_MAX_PHASE`), Task 5 테스트 3, Task 8 Step 1·3 |
| 상태 파일 위치·JSON·스키마 | Task 3 |
| `task.id`/`goal` | Task 3(발급·goal), Task 8 Step 1(의미 동일성 판단) |
| `spec_digest` 계산·저장·재검증 | Task 3(`spec_digest()`), Task 4(`--approved` 시 자동 계산), Task 5(`drift` 비교), Task 6 테스트 16 |
| 내용 기반 `tree_digest` · pathspec 제외 | Task 3(`tree_digest()`), Task 6 테스트 14·15 |
| `validate_state` 내부 구조 검증 | Task 5, Task 6 테스트 17 |
| `--replan` reset 계약 | Task 4(구현·테스트 14b), 설계 전이표 |
| `--agents` 조건·중복 거부 | Task 4 테스트 14c |
| 손상 state fail-closed | Task 3 테스트 6·7, Task 7 테스트(원본 보존) |
| 상태 전이 불변식 | Task 4 테스트 9~16 |
| phase 역행 허용 | Task 4 테스트 14 |
| 재개 판정 exit code | Task 5 |
| 브리핑 규격 | Task 6 테스트 13 |
| 불일치 판정(`tree_digest` 포함) | Task 3(기록), Task 5(`drift`), Task 6 테스트 8~12 |
| gate 메타(attempt·recorded_at·log_path) | Task 4 테스트 12 |
| 생명주기·아카이브 충돌 | Task 4 테스트 15·16 |
| 역할 마일스톤 | Task 8 Step 2 |
| 자동 기록 + 실패 가시화 | Task 7 |
| 비파괴 동기화 | Task 1 Step 1·3·6, Task 9 Step 1·2·6 |
| 이식 경계에 settings.json | Task 9 Step 2·3, Task 8 Step 4 |
| MIGRATION.md 파일 수 | Task 8 Step 5 |
| 원자성 증명 | Task 3 테스트 8 |
| PyYAML 없이 동작 | Global Constraint — `json`·`hashlib` 만 import |

빠진 것 없음. 검증 시나리오 23종이 모두 어느 태스크엔가 대응한다.

**Placeholder 스캔** — 모든 코드 단계에 실행 가능한 코드가 있다. Task 6 Step 3만 "실패하는 항목만 고친다"인데, 이는 Task 5에서 이미 구현된 `drift()`·`render()` 의 회귀 확인이 목적이라 새 코드가 없는 것이 정상이다.

**타입 정합성**
- `harness_workspace()` (Task 2) ↔ `workspace()` 의 `--print` (Task 3·5) — 일치
- `load()` 가 `(state, error)` 튜플 (Task 3) ↔ Task 4·5의 언패킹 — 일치
- `repo_fingerprint()` · `SCHEMA_VERSION` 을 Task 5가 `checkpoint` 에서 import — Task 3에 정의됨
- `drift()` → `list[str]` ↔ `render(state, marks, path)` — 일치
- `--gate <tier>:<exit> --log-path` (Task 4) ↔ `run-gates.sh` 호출 (Task 7) — 일치
- exit 0/10/11/12 ↔ SKILL.md 표 (Task 8) — 일치
- `CATALOG` (Task 3) = `validate-spec.py` 의 `CATALOG` — 불변식 표에 등재(Task 8 Step 4)
