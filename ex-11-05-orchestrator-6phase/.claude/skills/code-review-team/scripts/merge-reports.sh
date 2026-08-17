#!/usr/bin/env bash
# merge-reports.sh
# _workspace/review/01_static.md ~ 04_refactor.md 를 P0 → P1 → P2 순으로 재배열해
# _workspace/review_report.md 를 만든다. 존재하지 않는 리포트는 건너뛰고 상단에 명시한다.
set -euo pipefail

REVIEW_DIR="_workspace/review"
OUT_FILE="_workspace/review_report.md"

ORDER=(01_static.md 02_design.md 03_security.md 04_refactor.md)
declare -A LABELS=(
    [01_static.md]="정적 분석 (static-analyzer)"
    [02_design.md]="설계 검토 (design-reviewer)"
    [03_security.md]="보안 감사 (security-auditor)"
    [04_refactor.md]="리팩토링 (refactorer)"
)

present=()
missing=()
for f in "${ORDER[@]}"; do
    if [[ -f "$REVIEW_DIR/$f" ]]; then
        present+=("$f")
    else
        missing+=("$f")
    fi
done

extract_section() {
    local file="$1" priority="$2"
    awk -v target="### [$priority]" '
        substr($0, 1, length(target)) == target { printing = 1; print; next }
        /^### \[/ { printing = 0; next }
        printing { print }
    ' "$file"
}

{
    echo "# 코드 리뷰 통합 보고서"
    echo

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "## 누락된 리뷰"
        for f in "${missing[@]}"; do
            echo "- ${LABELS[$f]} 보고서 없음 ($f)"
        done
        echo
    fi

    for priority in P0 P1 P2; do
        echo "## [$priority]"
        echo
        any=0
        for f in "${present[@]}"; do
            section=$(extract_section "$REVIEW_DIR/$f" "$priority")
            if [[ -n "$section" ]]; then
                echo "$section"
                echo
                any=1
            fi
        done
        if [[ "$any" -eq 0 ]]; then
            echo "_해당 없음_"
            echo
        fi
    done
} > "$OUT_FILE"

exit 0
