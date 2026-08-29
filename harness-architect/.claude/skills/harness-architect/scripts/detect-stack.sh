#!/usr/bin/env bash
# detect-stack.sh — 프로젝트 스택을 감지해 결정론적 게이트 목록을 TSV 로 출력한다.
#
# 사용법:  detect-stack.sh [프로젝트_디렉터리]      (기본값: 현재 디렉터리)
# 출력:    stdout 에 "tier<TAB>command" 한 줄씩. tier ∈ {fast, feature, final}
# 종료코드: 0 = 게이트를 1개 이상 찾음 / 1 = 스택 미감지 (stdout 비어 있음)
#
# 설계 원칙: 실제로 존재하는 것만 출력한다. package.json 에 없는 스크립트나
# 선언되지 않은 도구를 추측해서 만들어내지 않는다 — 지어낸 게이트는 항상 실패하고,
# 에이전트는 그 실패를 코드 문제로 오인한다.
set -uo pipefail

PROJECT_DIR="${1:-.}"

if [[ ! -d "$PROJECT_DIR" ]]; then
    echo "detect-stack: 디렉터리를 찾을 수 없습니다: $PROJECT_DIR" >&2
    exit 1
fi

emit() { printf '%s\t%s\n' "$1" "$2"; }

# package.json 의 "scripts" 블록에서 스크립트 이름만 뽑아낸다 (jq 의존 없음).
list_npm_scripts() {
    awk '
        /"scripts"[[:space:]]*:[[:space:]]*\{/ { depth=1; next }
        depth > 0 {
            if ($0 ~ /\}/) { print_rest=1 }
            if (match($0, /"[^"]+"[[:space:]]*:/)) {
                key = substr($0, RSTART + 1, RLENGTH - 1)
                sub(/"[[:space:]]*:$/, "", key)
                print key
            }
            if (print_rest) { exit }
        }
    ' "$1"
}

found=0

# ---------- Node / TypeScript ----------
if [[ -f "$PROJECT_DIR/package.json" ]]; then
    if   [[ -f "$PROJECT_DIR/pnpm-lock.yaml" ]]; then pm="pnpm"
    elif [[ -f "$PROJECT_DIR/yarn.lock"      ]]; then pm="yarn"
    elif [[ -f "$PROJECT_DIR/bun.lockb"      ]]; then pm="bun"
    else                                              pm="npm"
    fi

    scripts="$(list_npm_scripts "$PROJECT_DIR/package.json")"

    # 스크립트 이름 → tier 매핑. 이 순서대로 출력된다 (싼 것부터).
    while IFS='|' read -r tier name; do
        [[ -n "$name" ]] || continue
        if printf '%s\n' "$scripts" | grep -Fxq "$name"; then
            emit "$tier" "$pm run $name"
            found=1
        fi
    done <<'MAP'
fast|format:check
fast|format-check
fast|lint
fast|typecheck
fast|type-check
fast|check-all
feature|test
feature|test:unit
final|build
final|test:e2e
MAP
fi

# ---------- Python ----------
py_manifest=""
[[ -f "$PROJECT_DIR/pyproject.toml"    ]] && py_manifest="$PROJECT_DIR/pyproject.toml"
[[ -z "$py_manifest" && -f "$PROJECT_DIR/requirements.txt" ]] && py_manifest="$PROJECT_DIR/requirements.txt"

if [[ -n "$py_manifest" ]]; then
    grep -qi 'ruff'   "$py_manifest" && { emit fast    "ruff check ."     ; found=1; }
    grep -qi 'black'  "$py_manifest" && { emit fast    "black --check ."  ; found=1; }
    grep -qi 'mypy'   "$py_manifest" && { emit fast    "mypy ."           ; found=1; }
    grep -qi 'pytest' "$py_manifest" && { emit feature "pytest"           ; found=1; }
fi

# ---------- Go ----------
if [[ -f "$PROJECT_DIR/go.mod" ]]; then
    emit fast    "go vet ./..."
    emit feature "go test ./..."
    emit final   "go build ./..."
    found=1
fi

# ---------- Rust ----------
if [[ -f "$PROJECT_DIR/Cargo.toml" ]]; then
    emit fast    "cargo fmt --check"
    emit fast    "cargo clippy --all-targets -- -D warnings"
    emit feature "cargo test"
    emit final   "cargo build --release"
    found=1
fi

# ---------- JVM ----------
if [[ -f "$PROJECT_DIR/pom.xml" ]]; then
    emit feature "mvn -q -B test"
    emit final   "mvn -q -B package -DskipTests"
    found=1
elif [[ -f "$PROJECT_DIR/build.gradle" || -f "$PROJECT_DIR/build.gradle.kts" ]]; then
    emit feature "./gradlew test"
    emit final   "./gradlew build -x test"
    found=1
fi

if [[ "$found" -eq 0 ]]; then
    echo "detect-stack: '$PROJECT_DIR' 에서 알려진 스택을 찾지 못했습니다." >&2
    echo "  게이트 명령을 추측하지 마십시오. 사용자에게 검증 명령을 직접 물어보고" >&2
    echo "  _workspace/harness/gates.tsv 에 'tier<TAB>command' 형식으로 기록하십시오." >&2
    exit 1
fi

exit 0
