#!/usr/bin/env bash
# tests/test-dry-run-doc.sh — LINEAR-DRY-RUN.md 에 박아 넣은 코멘트 예시가
# gate-summary.sh 의 실제 출력과 일치하는지 검증한다.
#
# 왜 필요한가: 런북의 "이렇게 보여야 합니다" 가 실제와 어긋나면 사용자는 정상 동작을
# 실패로 오인하거나 그 반대를 한다. 스크립트를 고칠 때 문서가 같이 낡는 것을 막는다.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/lib/assert.sh"

DOC="$ROOT/LINEAR-DRY-RUN.md"
SCRIPT="$ROOT/.claude/skills/harness-architect/scripts/gate-summary.sh"
FIXTURES="$ROOT/fixtures/dry-run/gates"

assert_file_exists "$DOC" "런북이 존재한다"

for tier in fast feature final; do
    assert_file_exists "$FIXTURES/$tier.log" "리허설 픽스처 $tier.log 가 존재한다"
    out="$(cd "$ROOT" && bash "$SCRIPT" "$tier" fixtures/dry-run/gates)"
    missing=0
    while IFS= read -r line; do
        [[ -z "${line// }" ]] && continue
        [[ "$line" == "|---"* ]] && continue
        grep -Fq "$line" "$DOC" || { echo "  문서에 없음: $line"; missing=1; }
    done <<< "$out"
    if [[ "$missing" -eq 0 ]]; then
        echo "PASS: $tier 실제 출력이 런북과 일치한다"
    else
        echo "FAIL: $tier 실제 출력이 런북과 어긋난다 (스크립트를 고쳤다면 문서도 고쳐라)"
        FAILURES=$((FAILURES + 1))
    fi
done

# 런북이 전체 상태 경로를 빠짐없이 다루는가
for state in Triage Todo "In Progress" "In Review" Done Canceled; do
    grep -Fq "$state" "$DOC" \
        && echo "PASS: 런북이 '$state' 상태를 다룬다" \
        || { echo "FAIL: 런북에 '$state' 가 없다"; FAILURES=$((FAILURES + 1)); }
done

# 정리 단계가 있는가 — 실제 워크스페이스에 데이터를 만드는 리허설이다
grep -Fq "[DRY-RUN]" "$DOC" \
    && echo "PASS: 리허설 산출물에 식별 접두사를 쓴다" \
    || { echo "FAIL: [DRY-RUN] 접두사 규칙이 없다"; FAILURES=$((FAILURES + 1)); }

report_and_exit
