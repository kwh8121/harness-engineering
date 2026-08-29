#!/usr/bin/env bash
# tests/test-detect-stack.sh — detect-stack.sh 가 스택별로 올바른 게이트 TSV를 내는지 검증한다
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/lib/assert.sh"

SCRIPT="$ROOT/.claude/skills/harness-architect/scripts/detect-stack.sh"
FIXTURES="$ROOT/fixtures"

# --- node + npm: package.json scripts 를 tier 에 매핑한다 ---
out="$(bash "$SCRIPT" "$FIXTURES/node-npm" 2>/dev/null)"
rc=$?
assert_exit_code 0 "$rc" "node-npm: exit 0"
assert_contains "$out" "$(printf 'fast\tnpm run format:check')" "node-npm: format:check → fast"
assert_contains "$out" "$(printf 'fast\tnpm run lint')"          "node-npm: lint → fast"
assert_contains "$out" "$(printf 'fast\tnpm run typecheck')"     "node-npm: typecheck → fast"
assert_contains "$out" "$(printf 'feature\tnpm run test')"       "node-npm: test → feature"
assert_contains "$out" "$(printf 'final\tnpm run build')"        "node-npm: build → final"
assert_contains "$out" "$(printf 'final\tnpm run test:e2e')"     "node-npm: test:e2e → final"

# package.json 에 없는 스크립트는 지어내지 않는다
if [[ "$out" == *"npm run dev"* ]]; then
    echo "FAIL: node-npm: dev 스크립트는 게이트가 아니다"
    FAILURES=$((FAILURES + 1))
else
    echo "PASS: node-npm: dev 스크립트는 게이트가 아니다"
fi

# --- node + pnpm: 락파일로 패키지 매니저를 판별한다 ---
out="$(bash "$SCRIPT" "$FIXTURES/node-pnpm" 2>/dev/null)"
assert_contains "$out" "$(printf 'fast\tpnpm run lint')"    "node-pnpm: pnpm 감지"
assert_contains "$out" "$(printf 'feature\tpnpm run test')" "node-pnpm: test → feature"
if [[ "$out" == *"build"* ]]; then
    echo "FAIL: node-pnpm: 없는 build 스크립트를 만들어내면 안 된다"
    FAILURES=$((FAILURES + 1))
else
    echo "PASS: node-pnpm: 없는 build 스크립트를 만들어내지 않는다"
fi

# --- python: pyproject 의 도구 선언에서 게이트를 유도한다 ---
out="$(bash "$SCRIPT" "$FIXTURES/python-uv" 2>/dev/null)"
rc=$?
assert_exit_code 0 "$rc" "python-uv: exit 0"
assert_contains "$out" "$(printf 'fast\truff check .')" "python-uv: ruff → fast"
assert_contains "$out" "$(printf 'fast\tmypy .')"       "python-uv: mypy → fast"
assert_contains "$out" "$(printf 'feature\tpytest')"    "python-uv: pytest → feature"

# --- go ---
out="$(bash "$SCRIPT" "$FIXTURES/go-mod" 2>/dev/null)"
rc=$?
assert_exit_code 0 "$rc" "go-mod: exit 0"
assert_contains "$out" "$(printf 'fast\tgo vet ./...')"     "go-mod: go vet → fast"
assert_contains "$out" "$(printf 'feature\tgo test ./...')" "go-mod: go test → feature"
assert_contains "$out" "$(printf 'final\tgo build ./...')"  "go-mod: go build → final"

# --- 한 줄로 압축된 package.json (prettier 미적용·번들러 산출물에서 흔하다) ---
out="$(bash "$SCRIPT" "$FIXTURES/node-oneline" 2>/dev/null)"
rc=$?
assert_exit_code 0 "$rc" "node-oneline: exit 0"
assert_contains "$out" "$(printf 'fast\tnpm run lint')"    "node-oneline: 한 줄 JSON 에서 lint 추출"
assert_contains "$out" "$(printf 'feature\tnpm run test')" "node-oneline: 한 줄 JSON 에서 test 추출"
assert_contains "$out" "$(printf 'final\tnpm run build')"  "node-oneline: 한 줄 JSON 에서 build 추출"

# --- scripts 뒤의 다른 객체 키를 스크립트로 오인하지 않는다 ---
out="$(bash "$SCRIPT" "$FIXTURES/node-nested" 2>/dev/null)"
rc=$?
assert_exit_code 0 "$rc" "node-nested: exit 0"
assert_contains "$out" "$(printf 'fast\tnpm run lint')"    "node-nested: 값에 중괄호가 있어도 lint 추출"
assert_contains "$out" "$(printf 'feature\tnpm run test')" "node-nested: test 추출"
if [[ "$out" == *"run build"* || "$out" == *"run typecheck"* ]]; then
    echo "FAIL: node-nested: dependencies 의 키를 스크립트로 오인했다"
    FAILURES=$((FAILURES + 1))
else
    echo "PASS: node-nested: scripts 블록 밖의 키를 스크립트로 오인하지 않는다"
fi

# --- unknown: 명령을 지어내지 않고 실패한다 ---
out="$(bash "$SCRIPT" "$FIXTURES/unknown" 2>/dev/null)"
rc=$?
assert_exit_code 1 "$rc" "unknown: 스택 미감지 시 exit 1"
assert_eq "" "$out" "unknown: stdout 은 비어 있다 (명령을 지어내지 않는다)"

# --- 출력 형식: 모든 줄이 정확히 2열 TSV 이고 tier 는 3종 중 하나 ---
out="$(bash "$SCRIPT" "$FIXTURES/node-npm" 2>/dev/null)"
bad="$(printf '%s\n' "$out" | awk -F'\t' 'NF!=2 || ($1!="fast" && $1!="feature" && $1!="final")' | head -3)"
assert_eq "" "$bad" "출력은 tier<TAB>command 2열이며 tier 는 fast/feature/final 뿐이다"

report_and_exit
