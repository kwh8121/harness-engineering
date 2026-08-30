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

report_and_exit
