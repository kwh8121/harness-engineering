#!/usr/bin/env bash
# judge-verdict.sh <patch_filename> <attempt_number>
# stdin으로 검증 Agent의 응답 전체를 받는다. 마지막 비어있지 않은 줄이 "VERDICT: PASS"로
# 시작하면 PASS. 아니면(FAIL 또는 형식 위반) attempt_number < 3이면 RETRY, 3 이상이면
# _workspace/patches/{patch}를 {patch}.rejected로 리네임하고 REJECTED를 출력한다.
set -euo pipefail

PATCH="$1"
ATTEMPT="$2"
PATCH_DIR="_workspace/patches"

response=$(cat)
last_line=$(printf '%s\n' "$response" | grep -v '^[[:space:]]*$' | tail -n 1)

if [[ "$last_line" == "VERDICT: PASS"* ]]; then
    echo "PASS"
    exit 0
fi

if [[ "$ATTEMPT" -lt 3 ]]; then
    echo "RETRY"
    exit 0
fi

if [[ -f "$PATCH_DIR/$PATCH" ]]; then
    mv "$PATCH_DIR/$PATCH" "$PATCH_DIR/$PATCH.rejected"
fi
echo "REJECTED"
exit 0
