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
(cd "$TMP/repo" && python3 "$CP" --phase 3)
assert_eq "$head" "$(jq_ 'd["repo"]["head"]')" "HEAD SHA 를 기록한다"
dg="$(jq_ 'd["repo"]["tree_digest"]')"
if [[ "$dg" == sha256:* ]]; then echo "PASS: tree_digest 를 기록한다"
else echo "FAIL: tree_digest 형식이 아니다 ($dg)"; FAILURES=$((FAILURES+1)); fi

# 5. 잘못된 입력을 거부한다
python3 "$CP" --phase 9 2>/dev/null; assert_exit_code 2 "$?" "허용되지 않는 phase 를 거부한다"
python3 "$CP" --level H9 2>/dev/null; assert_exit_code 2 "$?" "허용되지 않는 level 을 거부한다"
python3 "$CP" --phase 2 2>/dev/null; assert_exit_code 2 "$?" "phase 역행을 거부한다 (--replan 으로 유도)"

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

# 7b. 비-UTF-8 손상도 fail-closed — UnicodeDecodeError 가 exit 3 으로 잡혀야 한다
printf 'invalid \xff\xfe utf8' > "$STATE"
before="$(cat "$STATE" 2>/dev/null | od -An -tx1)"
python3 "$CP" --phase 4 2>/dev/null; rc=$?
assert_exit_code 3 "$rc" "비-UTF-8 손상에서도 exit 3"
assert_eq "$before" "$(cat "$STATE" 2>/dev/null | od -An -tx1)" "비-UTF-8 원본 바이트가 보존된다"

# 7c. 구조가 깨진 state(파싱은 됨)도 fail-closed — KeyError traceback + exit 1 이 아니라 exit 3
python3 -c "import json,sys;json.dump({'schema_version':1,'phase':'2','repo':'broken'},open(sys.argv[1],'w'))" "$STATE"
before="$(cat "$STATE")"
python3 "$CP" --phase 4 2>/dev/null; rc=$?
assert_exit_code 3 "$rc" "repo 가 매핑이 아니면 exit 3"
assert_eq "$before" "$(cat "$STATE")" "구조 손상 원본이 보존된다 (repo)"

python3 -c "import json,sys;json.dump({'schema_version':1,'phase':'2','progress':[]},open(sys.argv[1],'w'))" "$STATE"
before="$(cat "$STATE")"
python3 "$CP" --phase 4 2>/dev/null; rc=$?
assert_exit_code 3 "$rc" "progress 가 리스트면 exit 3"
assert_eq "$before" "$(cat "$STATE")" "구조 손상 원본이 보존된다 (progress)"

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
assert_eq "n40" "$(jq_ 'd["next_action"]')" "쓰기가 실제로 반영됐다 (원자성 테스트가 공허하지 않다)"

# 9. 승인은 Phase 3 의 산물이다
cp "$TMP/good.json" "$STATE"
python3 "$CP" --approved --agents implementer,reviewer 2>/dev/null
assert_exit_code 2 "$?" "--approved 가 --phase 3 없이 오면 거부한다"

python3 "$CP" --phase 3 --approved --agents implementer,reviewer
assert_eq "True" "$(jq_ 'd["approved"]')" "phase 3 과 함께면 승인을 세운다"
assert_eq "implementer,reviewer" "$(jq_ '",".join(d["progress"]["agents_pending"])')" \
    "agents_pending 을 초기화한다"

# 9b. --approved 는 artifacts.spec 파일을 직접 읽어 해시한다 (호출자가 해시를 넘기지 않는다)
mkdir -p "$TMP/repo/_workspace/harness"
printf 'harness_version: 1\n' > "$TMP/repo/_workspace/harness/spec.yaml"
(cd "$TMP/repo" && python3 "$CP" --artifact spec=_workspace/harness/spec.yaml)
(cd "$TMP/repo" && python3 "$CP" --phase 3 --approved --agents implementer,reviewer)
dg="$(jq_ 'd["task"]["spec_digest"]')"
case "$dg" in
    sha256:*) echo "PASS: --approved 가 spec 파일을 직접 sha256 해시한다" ;;
    *) echo "FAIL: spec_digest 가 sha256 형식이 아니다 ($dg)"; FAILURES=$((FAILURES+1)) ;;
esac

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
assert_eq "2" "$(jq_ '[g for g in d["progress"]["gates"] if g["tier"]=="fast"][-1]["attempt"]')" \
    "같은 tier 의 attempt 를 증가시킨다"
assert_eq "1" "$(jq_ '[g for g in d["progress"]["gates"] if g["tier"]=="feature"][0]["attempt"]')" \
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

report_and_exit
