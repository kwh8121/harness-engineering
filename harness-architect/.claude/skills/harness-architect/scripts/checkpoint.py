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


# _workspace/ 제외는 pathspec 으로 한다 — 문자열 필터는 src/my_workspace/ 같은
# 무관한 경로까지 지운다. `:(top,...)` 매직이 있어야 CWD 상대가 아니라 저장소
# 루트 기준으로 해석된다 — 매직 없는 pathspec 은 하위 디렉터리에서 실행하면
# 루트의 변경을 통째로 놓친다(문서화된 사용법이 하위 디렉터리 실행이다).
EXCLUDE_WS = ":(top,exclude)_workspace/"


def file_digest(path):
    h = hashlib.sha256()
    try:
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(65536), b""):
                h.update(chunk)
    except OSError as e:
        # 읽을 수 없는 파일마다 **경로별로 다른** 표식을 낸다. 예전에는 상수
        # "unreadable" 을 돌려줘서, 열리지 않는 파일의 내용이 어떻게 바뀌어도
        # digest 가 흔들리지 않았다(조용한 상수가 그 버그를 숨겼다). stderr 로도 알린다.
        print(f"checkpoint: 파일을 읽지 못해 경로 표식으로 대체합니다: {path} ({e})",
              file=sys.stderr)
        tag = hashlib.sha256(path.encode("utf-8", "surrogateescape")).hexdigest()[:16]
        return "unreadable:" + tag
    return h.hexdigest()


def tree_digest():
    """_workspace/ 를 뺀 작업 트리 **내용**의 지문.

    git status --porcelain 의 행만 해시하면 부족하다. status 는 경로와 변경 여부만
    낼 뿐 내용을 담지 않으므로, 이미 수정된 같은 파일을 다시 다르게 고쳐도 출력이
    'M a.txt' 로 같아 digest 가 바뀌지 않는다(임시 저장소에서 재현됨).

    그래서 tracked 변경은 diff 본문을, untracked 는 경로와 파일 내용을 해시한다.

    git 명령은 **현재 체크아웃된 트리의 루트**(`--show-toplevel`)에서 실행한다 —
    CWD 가 하위 디렉터리여도 pathspec·출력 경로가 루트 기준으로 안정된다.
    untracked 는 `-z` 로 받아 NUL 로 자른다 — 기본 `core.quotePath=true` 는
    비-ASCII 이름을 C-따옴표로 감싸 file_digest 가 파일을 못 열게 만든다
    (이 저장소는 문서를 한국어로 쓰므로 실제로 마주치는 경우다).
    """
    top = (git("rev-parse", "--show-toplevel") or "").strip()
    if not top:
        return None
    diff = git("-C", top, "diff", "--binary", "HEAD", "--", EXCLUDE_WS)
    if diff is None:
        return None
    untracked = git("-C", top, "ls-files", "-z", "--others",
                    "--exclude-standard", "--", EXCLUDE_WS) or ""

    h = hashlib.sha256()
    h.update(diff.encode("utf-8", "surrogateescape"))
    for rel in sorted(untracked.split("\0")):
        if not rel:
            continue
        h.update(b"\0U\0")
        h.update(rel.encode("utf-8", "surrogateescape"))
        h.update(file_digest(os.path.join(top, rel)).encode("ascii", "surrogateescape"))
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


def validate_state(state):
    """state 내부 구조를 검사해 오류 목록을 낸다 — "무엇이 손상인가"의 **단일 정의**다.

    checkpoint.load() 와 resume-check 둘 다 이 함수를 부른다. 최상위가 매핑이고
    schema_version 이 맞아도 내부 타입이 깨져 있으면 이후 코드가 처리되지 않은
    예외로 죽는다 — 예를 들어 {"repo": "broken"} 은 recorded.get() 에서
    AttributeError 를, progress.gates:[1] 은 g.get() 에서 AttributeError 를 낸다.
    설계가 약속한 '손상된 state 는 예외 없이 fail-closed' 를 지키려면 여기서 먼저 건다.

    컨테이너 타입뿐 아니라 그 안의 원소·값 타입까지 본다. render()·drift() 는 이
    값들을 join 하거나 경로로 넘기므로, str 이어야 할 자리에 int 가 들어오면 검증을
    통과하고도 처리되지 않은 TypeError 로 죽는다."""
    errs = []
    for key in ("task", "repo", "artifacts", "progress"):
        if not isinstance(state.get(key, {}), dict):
            errs.append(f"{key} 가 매핑이 아닙니다 ({type(state.get(key)).__name__})")
    if not isinstance(state.get("phase", ""), str):
        errs.append("phase 가 문자열이 아닙니다")
    if not isinstance(state.get("approved", False), bool):
        errs.append("approved 가 bool 이 아닙니다")

    task = state.get("task")
    if isinstance(task, dict):
        for key in ("id", "goal"):
            if task.get(key) is not None and not isinstance(task.get(key), str):
                errs.append(f"task.{key} 가 문자열이 아닙니다")

    art = state.get("artifacts")
    if isinstance(art, dict):
        for key, val in art.items():
            if val is not None and not isinstance(val, str):
                errs.append(f"artifacts.{key} 가 문자열이 아닙니다")

    prog = state.get("progress")
    if isinstance(prog, dict):
        for key in ("agents_done", "agents_pending", "gates"):
            if not isinstance(prog.get(key, []), list):
                errs.append(f"progress.{key} 가 리스트가 아닙니다")
        for key in ("agents_done", "agents_pending"):
            for i, a in enumerate(prog.get(key) or []):
                if not isinstance(a, str):
                    errs.append(f"progress.{key}[{i}] 가 문자열이 아닙니다")
        for i, g in enumerate(prog.get("gates") or []):
            if not isinstance(g, dict):
                errs.append(f"progress.gates[{i}] 가 매핑이 아닙니다")
        for key in ("review_loops_used",):
            if not isinstance(prog.get(key, 0), int):
                errs.append(f"progress.{key} 가 정수가 아닙니다")
        if not isinstance(prog.get("human_gate_passed", False), bool):
            errs.append("progress.human_gate_passed 가 bool 이 아닙니다")
    return errs


def load(path):
    """(state, error) 를 낸다. 파일이 없을 때만 새 상태를 만든다."""
    if not os.path.exists(path):
        return blank_state(), None
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (ValueError, OSError) as e:
        # JSONDecodeError 가 아니라 ValueError 로 잡는다: 비-UTF-8 바이트가 든 state 는
        # json.load() 안에서 UnicodeDecodeError 를 던지는데, 이건 JSONDecodeError 가
        # 아니라 ValueError 의 하위 클래스다. 좁히면 fail-closed 계약이 비-UTF-8
        # 손상에서 깨져 traceback + exit 1 로 죽는다(자동 호출부가 exit 3 만 본다).
        return None, f"state 를 읽을 수 없습니다: {e}"
    if not isinstance(data, dict):
        return None, "state 가 매핑이 아닙니다"
    if data.get("schema_version") != SCHEMA_VERSION:
        return None, (f"지원하지 않는 schema_version={data.get('schema_version')} "
                      f"(이 스크립트는 {SCHEMA_VERSION})")

    # 손으로 고친 부분 state 도 traceback 을 내지 않게 한다. 파싱은 됐지만 중첩
    # 구획이 빠졌거나 타입이 틀린 state 는 fail-closed(exit 3)로 다뤄야지, 나중에
    # state["task"]["id"] 나 prog = state["progress"] 에서 KeyError·TypeError 로
    # 죽으면 안 된다(자동 호출부는 exit 3 만 본다). "무엇이 손상인가"의 정의는
    # validate_state() 하나이며 resume-check 와 공유한다 — 쓰기 측이 읽기 측보다
    # 약하면 안 된다(쓰기 측이 증거 보존의 책임을 진다).
    errs = validate_state(data)
    if errs:
        return None, "state 내부 구조가 손상됐습니다: " + "; ".join(errs)

    base = blank_state()
    base.update(data)
    # base.update 는 최상위 키를 통째로 갈아치운다. 중첩 구획을 한 단계 더 병합해
    # 빠진 하위 키(task.id 등)가 사라지지 않고 blank_state() 기본값으로 채워지게 한다.
    for key in ("task", "repo", "artifacts", "progress"):
        section = blank_state()[key]
        section.update(data.get(key) or {})
        base[key] = section
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
    p.add_argument("--approved", action="store_true")
    p.add_argument("--agents", help="쉼표로 구분한 에이전트 id 목록")
    p.add_argument("--agent-done", dest="agent_done")
    p.add_argument("--gate", help="<fast|feature|final>:<exit>")
    p.add_argument("--log-path", dest="log_path")
    p.add_argument("--review-loop", action="store_true", dest="review_loop")
    p.add_argument("--human-gate-passed", action="store_true", dest="human_gate")
    p.add_argument("--artifact", action="append", default=[], help="key=path")
    p.add_argument("--archive", action="store_true")
    p.add_argument("--discard", action="store_true",
                   help="현재 state 를 폐기한다 — state.discarded-<id>.json 으로 "
                        "보존하고 state.json 을 제거한다 (어느 phase 에서든 가능)")
    p.add_argument("--replan", action="store_true",
                   help="계약을 다시 만든다 — 승인·진행을 초기화하고 phase 3 으로 되돌린다 "
                        "(--level 필수)")
    return p


def main():
    """무조건 백스톱 — resume-check.py 의 방어를 그대로 반영한다. validate_state() 가
    놓친 형태든 예기치 못한 버그든, checkpoint 는 손상 판정(exit 3)으로 실패하지
    traceback + exit 1 로 죽지 않는다 — 자동 호출부(run-gates·init-workspace)는
    exit 3 만 보고 판정하기 때문이다. argparse 의 SystemExit(exit 2)은
    BaseException 하위라 여기에 걸리지 않는다."""
    try:
        return _main()
    except Exception as e:                     # noqa: BLE001 — 계약이 무조건이므로 방어도 무조건이다
        print(f"checkpoint: 예기치 못한 오류 — state 를 손상으로 간주합니다: {e}",
              file=sys.stderr)
        return EXIT_CORRUPT


def _main():
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

    if args.discard:
        # 재판정·폐기의 '폐기' 경로. --archive 와 달리 phase 제한이 없다 —
        # exit 11 브리핑을 본 사용자가 어느 단계에서든 그만두기로 하면 증거를
        # 남기고 지운다. 파일명 충돌 처리는 --archive 와 같다(기존 기록 불가침).
        if not os.path.exists(path):
            p.error("폐기할 state 가 없습니다")
        tid = state["task"]["id"] or "unknown"
        base = os.path.join(os.path.dirname(path), f"state.discarded-{tid}")
        target, n = f"{base}.json", 1
        while os.path.exists(target):
            target, n = f"{base}-{n}.json", n + 1
        os.replace(path, target)
        return EXIT_OK

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

    prog = state["progress"]

    # --replan: 계약을 다시 만든다. 맨 --phase 로 역행하면 이전 계약의 승인·진행이
    # 그대로 남아 새 계획으로 흘러든다(이전 승인이 살아 있고 리뷰 루프가 이월된다).
    # 게이트를 비워도 증거를 잃지 않는다 — 로그 전문은 gates/*.log 에 그대로 있다.
    if args.replan:
        if args.phase is not None:
            p.error("--replan 은 --phase 와 함께 쓰지 않습니다 (항상 phase 3 으로 갑니다)")
        if args.level is None:
            p.error("--replan 에는 --level <새 레벨> 이 필요합니다 — 재판정의 목적이 "
                    "레벨 변경(예: H2→H1 강등)이다. 안 주면 이전 레벨이 그대로 남아 "
                    "브리핑이 거짓을 말한다")
        state["approved"] = False
        state["phase"] = "3"
        state["task"]["spec_digest"] = None
        prog["agents_done"] = []
        prog["agents_pending"] = []
        prog["gates"] = []
        prog["review_loops_used"] = 0
        prog["human_gate_passed"] = False

    # artifact 등록은 --approved 보다 먼저 처리한다. --approved 는 지금 artifacts.spec 이
    # 가리키는 파일을 그 자리에서 해시하므로, 같은 호출에 --artifact spec=... 이 함께 오면
    # 등록이 먼저 반영돼야 spec_digest 가 채워진다. 순서가 바뀌면 결합 호출
    # (--phase 3 --approved --agents ... --artifact spec=...)에서 지문이 조용히 비어
    # 재개 시 spec 변조 감지가 무력화된다.
    for item in args.artifact:
        key, _, val = item.partition("=")
        if key not in state["artifacts"]:
            p.error(f"알 수 없는 artifact 키 '{key}' (가능: {sorted(state['artifacts'])})")
        state["artifacts"][key] = val

    if args.approved:
        # 승인은 Phase 3 의 산물이다. 다른 Phase 에서 세우면 재개 시 이전 승인이
        # 실행 권한으로 되살아나는 경로가 열린다.
        if args.phase != "3":
            p.error("--approved 는 --phase 3 과 함께 써야 합니다")
        if not state["artifacts"].get("spec"):
            # spec 지문이 없으면 spec_digest(None) → None → 재개 시 drift() 가 spec
            # 검사를 통째로 건너뛴다. _workspace/ 는 tree_digest 에서 제외되므로
            # 이 지문이 승인된 계약의 변조를 잡는 **유일한** 경로다. 조용히 비우지 않는다.
            p.error("--approved 에는 artifacts.spec 이 있어야 합니다 — "
                    "--artifact spec=<경로> 를 함께 주십시오 "
                    "(없으면 재개 시 spec 변조 감지가 꺼진다)")
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

    state["repo"] = repo_fingerprint()
    save(path, state)
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
