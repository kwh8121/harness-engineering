#!/usr/bin/env bash
# apply-patches.sh
# _workspace/patches/*.diff (.rejected 제외)를 git apply --check로 검증 후
# 통과하는 것만 working tree에 반영한다. git add/commit은 절대 호출하지 않는다.
set -uo pipefail  # -e는 의도적으로 뺀다: 개별 patch 실패가 스크립트 전체를 죽이면 안 됨

PATCH_DIR="_workspace/patches"
applied=()
failed=()

shopt -s nullglob
for patch in "$PATCH_DIR"/*.diff; do
    if git apply --check "$patch" 2>/dev/null && git apply "$patch"; then
        applied+=("$(basename "$patch")")
    else
        failed+=("$(basename "$patch")")
    fi
done
shopt -u nullglob

echo "APPLIED:"
for f in "${applied[@]:-}"; do
    [[ -n "$f" ]] && echo "  - $f"
done
echo "FAILED:"
for f in "${failed[@]:-}"; do
    [[ -n "$f" ]] && echo "  - $f"
done

if [[ ${#failed[@]} -gt 0 ]]; then
    exit 1
fi
exit 0
