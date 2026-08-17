#!/usr/bin/env bash
# route-verification.sh
# _workspace/review/04_refactor.md의 "### {patch}.diff" + "- 발견 출처: {report}.md ..." 쌍을 파싱해
# _workspace/verification/queue.tsv (patch파일\t담당에이전트\t발견원문)를 만든다.
set -euo pipefail

REFACTOR_REPORT="_workspace/review/04_refactor.md"
OUT_DIR="_workspace/verification"
OUT_FILE="$OUT_DIR/queue.tsv"

if [[ ! -f "$REFACTOR_REPORT" ]]; then
    echo "route-verification: $REFACTOR_REPORT 가 없습니다." >&2
    exit 1
fi

mkdir -p "$OUT_DIR"

awk '
    /^### .+\.diff[[:space:]]*$/ {
        line = $0;
        sub(/^### /, "", line);
        sub(/[[:space:]]*$/, "", line);
        current_patch = line;
        next;
    }
    /^- 발견 출처: / && current_patch != "" {
        line = $0;
        sub(/^- 발견 출처: /, "", line);
        report_file = line;
        sub(/[[:space:]].*$/, "", report_file);

        agent = "";
        if (report_file == "01_static.md") agent = "static-analyzer";
        else if (report_file == "02_design.md") agent = "design-reviewer";
        else if (report_file == "03_security.md") agent = "security-auditor";

        if (agent != "") {
            print current_patch "\t" agent "\t" line;
        } else {
            print "route-verification: 알 수 없는 보고서 " report_file " (patch: " current_patch ") — 검증 대상에서 제외됨" > "/dev/stderr";
        }
        current_patch = "";
    }
' "$REFACTOR_REPORT" > "$OUT_FILE"

exit 0
