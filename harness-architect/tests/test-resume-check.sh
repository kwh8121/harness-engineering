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
# stdout+stderr 를 OUT 에 담고 exit code 를 RC 에 담는다. exit 11 을 내는 경로가
# 여럿이므로 "정상 판정 경로였는가"와 "traceback 없이 죽었는가"는 본문으로만 구분된다.
OUT=""; RC=""
capture() { OUT="$( (cd "$TMP/repo" && python3 "$CHECK" 2>&1) )"; RC=$?; }
no_traceback() { case "$OUT" in *Traceback*) echo yes;; *) echo no;; esac; }

# 1. state 없음
assert_eq "0" "$(run)" "state 가 없으면 exit 0 (새 작업)"

# 2. Phase 2, 불일치 없음 → 자동 재개 후보
(cd "$TMP/repo" && python3 "$CP" --phase 2 --level H1 --goal "테스트 작업" --next "라우팅 판정 중")
assert_eq "10" "$(run)" "Phase 2 + 불일치 없음이면 10"

# 3. Phase 3 은 승인 여부와 무관하게 사람 판단
(cd "$TMP/repo" && python3 "$CP" --phase 3 --approved --agents implementer,reviewer)
assert_eq "11" "$(run)" "Phase 3 + approved 는 자동 재개하지 않는다 (승인 부활 금지)"
# exit 11 만으로는 오류 경로와 구분되지 않는다 — 정상 판정 브리핑이 나왔는지 본문으로 확인한다.
capture
assert_contains "$OUT" "Phase 3" "Phase 3 재개는 정상 판정 경로를 탄다 (브리핑에 Phase 3)"
assert_contains "$OUT" "테스트 작업" "Phase 3 브리핑에 기록된 goal 이 나온다"
assert_eq "no" "$(no_traceback)" "Phase 3 판정에 traceback 이 없다"

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

# 8. 원소 타입 깨짐 — agents_done 에 int → render() 의 join() 이 죽을 자리
python3 -c "import json,sys;json.dump({'schema_version':1,'phase':'1','progress':{'agents_done':[1]}},open(sys.argv[1],'w'))" "$STATE"
capture
assert_exit_code 11 "$RC" "agents_done 원소가 int 면 11"
assert_eq "no" "$(no_traceback)" "agents_done 원소 오류에 traceback 이 없다"

# 9. artifacts 값 타입 깨짐 — spec 에 int + task.spec_digest 기록 → drift() 의 resolve() 가 죽을 자리
python3 -c "import json,sys;json.dump({'schema_version':1,'phase':'1','task':{'spec_digest':'sha256:x'},'artifacts':{'spec':123}},open(sys.argv[1],'w'))" "$STATE"
capture
assert_exit_code 11 "$RC" "artifacts.spec 가 int 면 11"
assert_eq "no" "$(no_traceback)" "artifacts 값 오류에 traceback 이 없다"

# 10. 음수 phase — 하한이 없으면 -1 <= 2 로 자동 재개 후보가 되는 위험한 방향
python3 -c "import json,sys;json.dump({'schema_version':1,'phase':'-1'},open(sys.argv[1],'w'))" "$STATE"
assert_eq "11" "$(run)" "음수 phase 는 자동 재개하지 않는다 (11)"

report_and_exit
