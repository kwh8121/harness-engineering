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
