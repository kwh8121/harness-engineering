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

report_and_exit
