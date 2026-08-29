#!/usr/bin/env bash
# tests/test-guard-readonly.sh — 읽기 전용 역할의 쓰기 시도를 훅이 실제로 거부하는지 검증한다.
#
# 훅 계약(Claude Code PreToolUse):
#   입력  stdin JSON — agent_type(서브에이전트 역할명), tool_name, tool_input
#   출력  {"hookSpecificOutput":{"hookEventName":"PreToolUse",
#                                "permissionDecision":"deny","permissionDecisionReason":"..."}}
#   허용은 출력 없이 exit 0.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/lib/assert.sh"
GUARD="$ROOT/.claude/skills/harness-architect/scripts/guard-readonly.py"

# run <agent_type> <tool_name> <tool_input JSON> → stdout
run() {
    local at="$1" tn="$2" ti="$3"
    python3 - "$at" "$tn" "$ti" <<'PY' | python3 "$GUARD"
import json, sys
at, tn, ti = sys.argv[1], sys.argv[2], sys.argv[3]
d = {"hook_event_name": "PreToolUse", "tool_name": tn, "tool_input": json.loads(ti)}
if at:
    d["agent_type"] = at
    d["agent_id"] = "sub_test"
print(json.dumps(d))
PY
}

assert_deny() {
    local out="$1" msg="$2"
    if [[ "$out" == *'"permissionDecision"'*'"deny"'* ]]; then
        echo "PASS: $msg"
    else
        echo "FAIL: $msg (거부하지 않았다)"; echo "  출력: ${out:-<없음>}"
        FAILURES=$((FAILURES + 1))
    fi
}
assert_allow() {
    local out="$1" msg="$2"
    if [[ "$out" == *'"deny"'* ]]; then
        echo "FAIL: $msg (거부해버렸다)"; echo "  출력: $out"
        FAILURES=$((FAILURES + 1))
    else
        echo "PASS: $msg"
    fi
}

# ---------- reviewer: 소스 쓰기 차단, _workspace 보고서는 허용 ----------
assert_deny  "$(run reviewer Write '{"file_path":"src/api/upload.ts","content":"x"}')" \
             "reviewer 의 소스 Write 를 거부한다"
assert_deny  "$(run reviewer Edit '{"file_path":"src/api/upload.ts","old_string":"a","new_string":"b"}')" \
             "reviewer 의 소스 Edit 을 거부한다"
assert_allow "$(run reviewer Write '{"file_path":"_workspace/harness/review/report.md","content":"x"}')" \
             "reviewer 의 보고서 Write 는 허용한다"
assert_deny  "$(run reviewer Bash '{"command":"sed -i s/a/b/ src/api/upload.ts"}')" \
             "reviewer 의 sed -i 를 거부한다"
assert_deny  "$(run reviewer Bash '{"command":"echo hacked > src/api/upload.ts"}')" \
             "reviewer 의 소스 리다이렉션을 거부한다"
assert_deny  "$(run reviewer Bash '{"command":"cat x | tee src/api/upload.ts"}')" \
             "reviewer 의 tee 소스 쓰기를 거부한다"
assert_deny  "$(run reviewer Bash '{"command":"rm -rf src/api"}')" \
             "reviewer 의 rm 을 거부한다"
assert_deny  "$(run reviewer Bash '{"command":"git commit -m x"}')" \
             "reviewer 의 git commit 을 거부한다"
assert_allow "$(run reviewer Bash '{"command":"git diff HEAD~1 HEAD"}')" \
             "reviewer 의 git diff 는 허용한다"
assert_allow "$(run reviewer Bash '{"command":"grep -rn TODO src/ 2>/dev/null"}')" \
             "reviewer 의 grep + 2>/dev/null 은 허용한다"
assert_allow "$(run reviewer Bash '{"command":"npm run lint > _workspace/harness/gates/fast.log 2>&1"}')" \
             "reviewer 의 _workspace 로그 리다이렉션은 허용한다"

# ---------- orchestrator: 코드를 쓰지 않는다 ----------
assert_deny  "$(run orchestrator Write '{"file_path":"lib/auth/session.ts","content":"x"}')" \
             "orchestrator 의 소스 Write 를 거부한다"
assert_allow "$(run orchestrator Write '{"file_path":"_workspace/harness/dag.md","content":"x"}')" \
             "orchestrator 의 dag.md Write 는 허용한다"

# ---------- dependency-mapper: 아무것도 쓰지 않는다 ----------
assert_deny  "$(run dependency-mapper Bash '{"command":"echo x > _workspace/harness/research/deps.md"}')" \
             "dependency-mapper 는 _workspace 에도 쓰지 못한다 (조사 전용)"
assert_allow "$(run dependency-mapper Bash '{"command":"rg -n \"import\" src/"}')" \
             "dependency-mapper 의 검색은 허용한다"

# ---------- 가드 대상이 아닌 역할·메인 스레드는 건드리지 않는다 ----------
assert_allow "$(run implementer Write '{"file_path":"src/api/upload.ts","content":"x"}')" \
             "implementer 의 소스 Write 는 허용한다 (유일한 편집 권한)"
assert_allow "$(run integrator Edit '{"file_path":"src/x.ts","old_string":"a","new_string":"b"}')" \
             "integrator 의 접합부 Edit 은 허용한다"
assert_allow "$(run baseline-tester Write '{"file_path":"tests/auth.spec.ts","content":"x"}')" \
             "baseline-tester 의 테스트 작성은 허용한다"
assert_allow "$(run "" Write '{"file_path":"src/api/upload.ts","content":"x"}')" \
             "메인 스레드(agent_type 없음)는 건드리지 않는다"

# ---------- 입력이 깨졌을 때 허용으로 새지 않는다 ----------
out="$(printf 'not json' | python3 "$GUARD" 2>/dev/null)"
assert_allow "$out" "파싱 불가 입력에서 조용히 통과시킨다 (가드는 보안 경계가 아니라 규율 장치)"

report_and_exit
