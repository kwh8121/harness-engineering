#!/usr/bin/env bash
# tests/run-all.sh — tests/test-*.sh 를 전부 실행하고 결과를 집계한다
#
# 왜 자체 요약을 내는가:
#   하위 테스트 파일마다 tests/lib/assert.sh 가 자기 파일의 결과를 찍는다
#   ("=== all tests passed ===" 또는 "=== N failure(s) ==="). 그래서 예전에는
#   앞쪽 파일이 실패해도 마지막 파일만 통과하면 출력의 꼬리에 "all tests passed"
#   가 찍혀, 꼬리만 본 사람이 통과로 오독했다. exit code 는 맞았지만 눈에 보이는
#   마지막 줄이 거짓말을 했다. 전체 판정을 반드시 여기서 한 번 더 낸다.
set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

overall=0
total_pass=0
total_fail=0
failed_files=()

for t in "$PROJECT_ROOT"/test-*.sh; do
    [[ -f "$t" ]] || continue
    name="$(basename "$t")"
    echo "=== $name ==="

    # tee 로 실시간 출력을 유지하면서 집계용 사본을 남긴다.
    bash "$t" 2>&1 | tee "$TMP"
    rc="${PIPESTATUS[0]}"

    total_pass=$(( total_pass + $(grep -c '^PASS' "$TMP") ))
    total_fail=$(( total_fail + $(grep -c '^FAIL' "$TMP") ))

    if [[ "$rc" -ne 0 ]]; then
        overall=1
        failed_files+=("$name")
    fi
    echo
done

echo "======================================"
if [[ "$overall" -eq 0 ]]; then
    echo "run-all: 전체 통과 — PASS $total_pass / FAIL $total_fail"
else
    echo "run-all: 실패 — PASS $total_pass / FAIL $total_fail"
    echo "실패한 테스트 파일 ${#failed_files[@]}건:"
    for f in "${failed_files[@]}"; do echo "  - $f"; done
fi
echo "======================================"

exit "$overall"
