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
