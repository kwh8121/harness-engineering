#!/usr/bin/env python3
"""guard-readonly.py — 읽기 전용 역할이 소스를 쓰는 것을 PreToolUse 단계에서 막는다.

왜 필요한가:
    에이전트 정의에서 `Edit` 을 빼면 *정식 편집 경로*만 사라진다. `Write` 는 새 파일을,
    `Bash` 는 `sed -i`·리다이렉션으로 무엇이든 바꿀 수 있다. 그래서 "reviewer 는 코드를
    고치지 않는다", "orchestrator 는 코드를 쓰지 않는다" 는 프롬프트 준수에만 의존했다.
    이 훅이 그 간극을 메운다.

무엇을 막는가 (역할별 쓰기 허용 범위):
    reviewer          _workspace/ 아래만        — 보고서는 써야 하므로
    orchestrator      _workspace/ 아래만        — dag.md·상태 파일
    dependency-mapper 아무 데도 못 쓴다          — 조사 전용
    그 밖의 역할과 메인 스레드는 건드리지 않는다.
    implementer·integrator 는 소스를 고치는 것이 일이고, baseline-tester 는 특성화
    테스트를 레포의 테스트 디렉터리에 써야 해서 가드 대상이 아니다.

한계 — 이것은 샌드박스가 아니다:
    Bash 검사는 셸을 파싱하지 않고 쓰기 구문을 패턴으로 찾는다. 변수 확장, base64,
    파이프로 넘긴 인터프리터 같은 우회는 잡지 못한다. 규율 장치이지 보안 경계가 아니다.
    막지 못한 경로는 여전히 프롬프트 준수에 의존한다.

설치:
    .claude/settings.json 의 hooks.PreToolUse 에 등록한다. README 의 "훅 설치" 참고.

계약:
    입력  stdin JSON — agent_type / tool_name / tool_input
          (agent_type 은 서브에이전트에서 호출됐을 때만 있다)
    출력  거부할 때만 JSON 한 덩어리. 허용은 출력 없이 exit 0.
"""
import json
import re
import sys

# 역할 → 쓰기가 허용되는 경로 접두사. 빈 튜플이면 아무 데도 못 쓴다.
READONLY_ROLES = {
    "reviewer": ("_workspace/",),
    "orchestrator": ("_workspace/",),
    "dependency-mapper": (),
}

WRITE_TOOLS = {"Write", "Edit", "NotebookEdit", "MultiEdit"}

# Bash 안에서 파일을 바꾸는 구문들. 리다이렉션은 대상 경로를 따로 검사한다.
MUTATING_COMMANDS = [
    (re.compile(r"\bsed\b[^|;&]*\s-i\b"), "sed -i (제자리 편집)"),
    (re.compile(r"\bperl\b[^|;&]*\s-i\b"), "perl -i (제자리 편집)"),
    (re.compile(r"\b(rm|rmdir)\s"), "rm/rmdir (삭제)"),
    (re.compile(r"\b(mv|cp|install)\s"), "mv/cp/install (파일 생성·이동)"),
    (re.compile(r"\b(truncate|dd|shred)\s"), "truncate/dd/shred"),
    (re.compile(r"\b(chmod|chown|ln)\s"), "chmod/chown/ln"),
    (re.compile(r"\b(mkdir|touch)\s"), "mkdir/touch (파일·디렉터리 생성)"),
    (re.compile(r"\bgit\s+(commit|apply|checkout|reset|restore|stash|clean|rm|add)\b"),
     "git 쓰기 명령"),
    (re.compile(r"\bnpm\s+(i|install|ci)\b|\bpip\s+install\b"), "패키지 설치"),
    (re.compile(r"\btee\b"), "tee (파일 쓰기)"),
]

# `> path` / `>> path` — `2>&1`, `>&2` 같은 fd 복제는 제외한다.
REDIRECT = re.compile(r"(?<![0-9&])>>?\s*([^\s;|&()<>]+)")

ALWAYS_OK_TARGETS = {"/dev/null", "/dev/stdout", "/dev/stderr"}


def deny(reason):
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }, ensure_ascii=False))
    sys.exit(0)


def allowed(path, prefixes):
    """path 가 허용 접두사 안에 있는가. 상위로 빠져나가는 경로는 거부한다."""
    p = path.strip().strip("\"'")
    if p in ALWAYS_OK_TARGETS:
        return True
    if p.startswith("/") or p.startswith("~"):
        return False          # 절대 경로는 작업 트리 밖 — 허용하지 않는다
    if ".." in p.split("/"):
        return False
    p = p[2:] if p.startswith("./") else p
    return any(p.startswith(pre) for pre in prefixes)


def scope_text(prefixes):
    return " 또는 ".join(prefixes) + " 아래" if prefixes else "어디에도 (조사 전용 역할)"


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        # 입력을 못 읽으면 판단할 근거가 없다. 조용히 통과시킨다 —
        # 깨진 가드가 모든 도구를 막는 쪽이 더 나쁘다.
        return 0
    if not isinstance(data, dict):
        return 0

    role = data.get("agent_type")
    if role not in READONLY_ROLES:
        return 0                      # 메인 스레드이거나 가드 대상이 아닌 역할

    prefixes = READONLY_ROLES[role]
    tool = data.get("tool_name") or ""
    ti = data.get("tool_input") or {}
    if not isinstance(ti, dict):
        return 0

    if tool in WRITE_TOOLS:
        path = ti.get("file_path") or ti.get("notebook_path") or ""
        if not allowed(path, prefixes):
            deny(f"[harness-architect] {role} 는 읽기 전용 역할입니다. "
                 f"'{path}' 에 쓸 수 없습니다 — 쓰기 허용 범위: {scope_text(prefixes)}. "
                 f"발견 사항은 고치지 말고 보고서에 적으십시오. "
                 f"(references/catalog.md 의 도구 경계)")
        return 0

    if tool == "Bash":
        cmd = ti.get("command") or ""

        for pattern, label in MUTATING_COMMANDS:
            if pattern.search(cmd):
                deny(f"[harness-architect] {role} 는 읽기 전용 역할입니다. "
                     f"{label} 을(를) 쓸 수 없습니다 — 쓰기 허용 범위: {scope_text(prefixes)}. "
                     f"명령: {cmd[:160]}")

        for target in REDIRECT.findall(cmd):
            if target.startswith("&"):
                continue              # >&2 같은 fd 복제
            if not allowed(target, prefixes):
                deny(f"[harness-architect] {role} 는 읽기 전용 역할입니다. "
                     f"'{target}' 로 리다이렉션할 수 없습니다 — "
                     f"쓰기 허용 범위: {scope_text(prefixes)}. 명령: {cmd[:160]}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
