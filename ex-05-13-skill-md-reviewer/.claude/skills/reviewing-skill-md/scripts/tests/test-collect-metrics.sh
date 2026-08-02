#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COLLECT="$SCRIPT_DIR/../collect-metrics.sh"
FIXTURE="$SCRIPT_DIR/fixture-sample-SKILL.md"

output=$(bash "$COLLECT" "$FIXTURE")

assert_line() {
  local key="$1"
  local expected="$2"
  local actual
  actual=$(printf '%s\n' "$output" | grep "^${key}:" | sed "s/^${key}: *//")
  if [ "$actual" != "$expected" ]; then
    echo "FAIL: $key expected [$expected] got [$actual]"
    exit 1
  fi
  echo "PASS: $key = $actual"
}

assert_contains() {
  local needle="$1"
  if ! printf '%s\n' "$output" | grep -qF -- "$needle"; then
    echo "FAIL: expected output to contain [$needle]"
    exit 1
  fi
  echo "PASS: contains [$needle]"
}

assert_line "line_count" "16"
assert_line "name_value" "sample-skill"
assert_line "description_value" "Use when testing collect-metrics.sh output values"
assert_line "branch_keyword_count" "3"
assert_line "imperative_count" "5"
assert_line "reason_count" "2"
assert_line "dot_block_count" "0"
assert_line "has_references_dir" "no"

# frontmatter_chars는 픽스처의 실제 frontmatter 텍스트로부터 동일한 방식(printf %s | wc -m)으로
# 기대값을 계산해 하드코딩 오차를 없앤다.
expected_fm_chars=$(printf '%s' "$(cat <<'EOF'
name: sample-skill
description: Use when testing collect-metrics.sh output values
EOF
)" | wc -m | tr -d ' ')
assert_line "frontmatter_chars" "$expected_fm_chars"

assert_contains "  - Overview"
assert_contains "  - When to Use"
assert_contains "  - Rule"

echo "ALL TESTS PASSED"
