#!/usr/bin/env bash
# resolve-diff.sh [PR_NUMBER]
# PR 번호가 있으면 gh pr diff, 없으면 로컬 diff(staged → unstaged → 브랜치 base)를
# 순서대로 시도해 _workspace/input/diff.patch, _workspace/input/files.txt를 만든다.
# 아무 diff도 찾지 못하면 exit 1.
set -euo pipefail

OUT_DIR="_workspace/input"
mkdir -p "$OUT_DIR"
DIFF_FILE="$OUT_DIR/diff.patch"
FILES_FILE="$OUT_DIR/files.txt"
PR_NUMBER="${1:-}"

try_pr_diff() {
    local pr="$1"
    if ! command -v gh >/dev/null 2>&1; then
        echo "resolve-diff: gh CLI가 설치되어 있지 않습니다. 로컬 diff로 폴백합니다." >&2
        return 1
    fi
    if ! gh pr diff "$pr" > "$DIFF_FILE" 2>/dev/null; then
        echo "resolve-diff: gh pr diff $pr 실패(인증/네트워크/PR 없음). 로컬 diff로 폴백합니다." >&2
        return 1
    fi
    gh pr diff "$pr" --name-only > "$FILES_FILE" 2>/dev/null || : > "$FILES_FILE"
    return 0
}

find_branch_base() {
    local ref
    ref=$(git symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null | sed 's#^refs/remotes/##') || true
    if [[ -z "$ref" ]]; then
        if git show-ref --verify -q refs/heads/main; then
            ref="main"
        elif git show-ref --verify -q refs/heads/master; then
            ref="master"
        fi
    fi
    echo "$ref"
}

try_local_diff() {
    if git diff --cached --quiet; then
        : # staged 없음
    else
        git diff --cached > "$DIFF_FILE"
        git diff --cached --name-only > "$FILES_FILE"
        return 0
    fi

    if git diff --quiet; then
        : # unstaged 없음
    else
        git diff > "$DIFF_FILE"
        git diff --name-only > "$FILES_FILE"
        return 0
    fi

    local base
    base=$(find_branch_base)
    if [[ -n "$base" ]]; then
        local merge_base
        if merge_base=$(git merge-base HEAD "$base" 2>/dev/null); then
            if ! git diff --quiet "$merge_base" HEAD; then
                git diff "$merge_base" HEAD > "$DIFF_FILE"
                git diff --name-only "$merge_base" HEAD > "$FILES_FILE"
                return 0
            fi
        fi
    fi

    return 1
}

if [[ -n "$PR_NUMBER" ]] && try_pr_diff "$PR_NUMBER"; then
    exit 0
fi

if try_local_diff; then
    exit 0
fi

echo "resolve-diff: 리뷰할 변경사항을 찾지 못했습니다 (staged/unstaged/브랜치 base 모두 비어있음)." >&2
exit 1
