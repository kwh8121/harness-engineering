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

# checkpoint 를 import 하면 scripts/__pycache__/ 가 생기는데, 이 디렉터리는 배포
# 저장소로 복사되는 세 경로 안에 있다 — 이식 시 남의 인터프리터 바이트코드가 딸려
# 간다. 무시(.gitignore)보다 애초에 안 만드는 게 낫다.
sys.dont_write_bytecode = True

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from checkpoint import (                                     # noqa: E402
    repo_fingerprint, resolve, spec_digest, validate_state, SCHEMA_VERSION,
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
    # ValueError 로 잡는다 — JSONDecodeError 와 UnicodeDecodeError 가 모두 그 하위다.
    # JSONDecodeError 만 잡으면 비-UTF-8 바이트로 손상된 state 에서 traceback 과 함께
    # exit 1 이 나가고, exit code 로 판정하는 호출부가 '손상'을 알아채지 못한다.
    except (ValueError, OSError) as e:
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

    # validate_state() 가 예상하지 못한 형태를 위한 무조건 백스톱이다. 정밀 검증은
    # 항상 어떤 모양을 놓칠 수 있는데 '손상된 state 는 예외 없이 exit 11'이라는
    # 계약은 무조건이므로 방어도 무조건이어야 한다. 여기서 traceback 을 전파하면
    # exit 1 이 나가고, exit code 로 판정하는 호출부가 계약을 신뢰할 수 없게 된다 —
    # 반드시 11 을 반환한다.
    try:
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

        # 하한이 없으면 {"phase":"-1"} 이 -1 <= 2 로 자동 재개 후보가 된다 —
        # 말이 안 되는 state 를 자동 재개하는 위험한 방향이다. 0 으로 하한을 건다.
        verdict = (EXIT_AUTO
                   if (0 <= numeric <= AUTO_MAX_PHASE and not marks)
                   else EXIT_HUMAN)
        render(state, marks, path)
        return verdict
    except Exception as e:                    # noqa: BLE001 — 계약이 무조건이므로 방어도 무조건이다
        print(f"[재개] state 를 해석하는 중 예기치 못한 오류: {e}")
        print(f"  파일: {path}")
        print("  손상된 state 로 판단합니다. 내용을 확인하고 이어갈지 결정하십시오.")
        return EXIT_HUMAN


if __name__ == "__main__":
    sys.exit(main())
