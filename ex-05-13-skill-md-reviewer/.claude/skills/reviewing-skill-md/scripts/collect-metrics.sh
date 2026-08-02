#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "사용법: $0 <SKILL.md 경로>" >&2
  exit 1
fi

FILE="$1"

if [ ! -f "$FILE" ]; then
  echo "파일을 찾을 수 없습니다: $FILE" >&2
  exit 1
fi

DIR="$(dirname "$FILE")"

line_count=$(wc -l < "$FILE" | tr -d ' ')
word_count=$(wc -w < "$FILE" | tr -d ' ')

# frontmatter 블록(첫 --- ~ 두 번째 --- 직전)만 추출한다.
frontmatter=$(awk '/^---$/{c++; if(c==2) exit; next} c==1' "$FILE")
frontmatter_chars=$(printf '%s' "$frontmatter" | wc -m | tr -d ' ')

name_value=$(printf '%s\n' "$frontmatter" | grep -m1 '^name:' | sed 's/^name: *//' || true)
description_value=$(printf '%s\n' "$frontmatter" | grep -m1 '^description:' | sed 's/^description: *//' || true)

# grep은 매치가 없으면 exit 1을 반환한다. set -o pipefail 아래서 파이프라인 전체가
# 실패로 취급되어 set -e에 걸리므로, 매치 0건이 정상 케이스인 아래 항목들은 || true로 보호한다.
branch_keyword_count=$(grep -oE '이면|일 때|인 경우' "$FILE" | wc -l | tr -d ' ' || true)
imperative_count=$(grep -oE 'ALWAYS|NEVER|반드시|절대' "$FILE" | wc -l | tr -d ' ' || true)
reason_count=$(grep -oE '왜냐하면|때문에' "$FILE" | wc -l | tr -d ' ' || true)
dot_block_count=$(grep -c '```dot' "$FILE" | tr -d ' ' || true)

if [ -d "$DIR/references" ]; then
  has_references_dir="yes"
else
  has_references_dir="no"
fi

headers=$(grep -E '^## ' "$FILE" | sed 's/^## //' || true)

echo "line_count: $line_count"
echo "word_count: $word_count"
echo "frontmatter_chars: $frontmatter_chars"
echo "name_value: $name_value"
echo "description_value: $description_value"
echo "branch_keyword_count: $branch_keyword_count"
echo "imperative_count: $imperative_count"
echo "reason_count: $reason_count"
echo "dot_block_count: $dot_block_count"
echo "has_references_dir: $has_references_dir"
echo "headers:"
if [ -n "$headers" ]; then
  echo "$headers" | sed 's/^/  - /'
else
  echo "  (none)"
fi
