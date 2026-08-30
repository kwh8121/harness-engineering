#!/usr/bin/env bash
# tests/lib/assert.sh — 프레임워크 없는 최소 assertion 헬퍼

FAILURES=0

assert_eq() {
    local expected="$1" actual="$2" msg="${3:-assert_eq}"
    if [[ "$expected" != "$actual" ]]; then
        echo "FAIL: $msg"
        echo "  expected: $expected"
        echo "  actual:   $actual"
        FAILURES=$((FAILURES + 1))
    else
        echo "PASS: $msg"
    fi
}

assert_file_exists() {
    local path="$1" msg="${2:-assert_file_exists $path}"
    if [[ ! -f "$path" ]]; then
        echo "FAIL: $msg (file not found: $path)"
        FAILURES=$((FAILURES + 1))
    else
        echo "PASS: $msg"
    fi
}

assert_contains() {
    local haystack="$1" needle="$2" msg="${3:-assert_contains}"
    if [[ "$haystack" != *"$needle"* ]]; then
        echo "FAIL: $msg"
        echo "  expected to contain: $needle"
        FAILURES=$((FAILURES + 1))
    else
        echo "PASS: $msg"
    fi
}

assert_exit_code() {
    local expected="$1" actual="$2" msg="${3:-assert_exit_code}"
    if [[ "$expected" -ne "$actual" ]]; then
        echo "FAIL: $msg (expected exit $expected, got $actual)"
        FAILURES=$((FAILURES + 1))
    else
        echo "PASS: $msg"
    fi
}

report_and_exit() {
    if [[ "$FAILURES" -gt 0 ]]; then
        echo "=== $FAILURES failure(s) ==="
        exit 1
    fi
    echo "=== all tests passed ==="
    exit 0
}
