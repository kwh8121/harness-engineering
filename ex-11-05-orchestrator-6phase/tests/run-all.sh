#!/usr/bin/env bash
# tests/run-all.sh — tests/test-*.sh 를 전부 실행하고 결과를 집계한다
set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
overall=0

for t in "$PROJECT_ROOT"/test-*.sh; do
    [[ -f "$t" ]] || continue
    echo "=== $(basename "$t") ==="
    bash "$t"
    rc=$?
    if [[ $rc -ne 0 ]]; then
        overall=1
    fi
    echo
done

exit $overall
