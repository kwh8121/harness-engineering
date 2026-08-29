#!/usr/bin/env bash
# tests/test-validate-spec.sh — validate-spec.py 가 잘못된 HarnessSpec 을 실제로 거부하는지 검증한다.
#
# 나쁜 spec 픽스처는 canonical 예제(examples/*.yaml)를 런타임에 변형해 만든다.
# 파일로 고정해 두면 예제가 바뀔 때 조용히 낡아버리기 때문이다.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/lib/assert.sh"

SKILL="$ROOT/.claude/skills/harness-architect"
VALIDATOR="$SKILL/scripts/validate-spec.py"

if ! python3 -c "import yaml" 2>/dev/null; then
    echo "SKIP: PyYAML 이 없어 validator 테스트를 건너뜁니다 (pip install pyyaml)"
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 정상 spec 4종 — 전부 통과해야 한다
for f in "$SKILL"/examples/*.yaml; do
    out="$(python3 "$VALIDATOR" "$f" 2>&1)"; rc=$?
    assert_exit_code 0 "$rc" "정상: $(basename "$f") 통과"
    [[ "$rc" -ne 0 ]] && echo "  출력: $out"
done

# mutate <원본예제> <파이썬 변형코드> → $TMP/spec.yaml 생성
mutate() {
    python3 - "$SKILL/examples/$1" "$TMP/spec.yaml" <<PY
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
$2
yaml.safe_dump(d, open(sys.argv[2], "w"), allow_unicode=True, sort_keys=False)
PY
}

# expect_error <에러코드> <설명>
expect_error() {
    local code="$1" msg="$2"
    local out; out="$(python3 "$VALIDATOR" "$TMP/spec.yaml" 2>&1)"; local rc=$?
    if [[ "$rc" -eq 0 ]]; then
        echo "FAIL: $msg (통과해버림 — exit 0)"
        FAILURES=$((FAILURES + 1))
    elif [[ "$out" != *"$code"* ]]; then
        echo "FAIL: $msg (exit $rc 이지만 $code 가 없음)"
        echo "  출력: $out"
        FAILURES=$((FAILURES + 1))
    else
        echo "PASS: $msg"
    fi
}

# --- 카탈로그 밖 에이전트 ---
mutate h1-pipeline.yaml 'd["agents"].append({"id":"security-reviewer","model":"opus","responsibility":"보안"})'
expect_error "E-AGENT-UNKNOWN" "카탈로그 7종 밖의 에이전트를 거부한다"

# --- model 누락 (생략하면 세션의 가장 비싼 모델을 상속한다) ---
mutate h1-pipeline.yaml 'del d["agents"][0]["model"]'
expect_error "E-AGENT-MODEL" "에이전트의 model 누락을 거부한다"

# --- enum 위반 ---
mutate h1-pipeline.yaml 'd["profile"]["risk"] = "critical"'
expect_error "E-ENUM" "profile 축의 잘못된 enum 값을 거부한다"

# --- 축 모순: coupling high + parallelism != none ---
mutate h2-fanout.yaml 'd["profile"]["coupling"] = "high"'
expect_error "E-AXIS" "coupling high + parallelism none 아님을 거부한다"

# --- H0 인데 에이전트가 있다 ---
mutate h0-single.yaml 'd["agents"] = [{"id":"implementer","model":"sonnet","responsibility":"구현"}]'
expect_error "E-LEVEL-AGENTS" "H0 에 에이전트가 배치된 것을 거부한다"

# --- H3 인데 orchestrator 가 없다 ---
mutate h3-orchestrator.yaml 'd["agents"] = [a for a in d["agents"] if a["id"] != "orchestrator"]'
expect_error "E-LEVEL-AGENTS" "H3 에 orchestrator 가 없는 것을 거부한다"

# --- controller 전용 스킬이 워커에 주입됐다 (리뷰 H-3) ---
mutate h2-fanout.yaml 'd["agent_skills"]["implementer"].append("superpowers:subagent-driven-development")'
expect_error "E-SKILL-OWNER" "Agent 도구가 없는 워커에 controller 스킬 주입을 거부한다"

# --- 구 스키마 키 잔존 ---
mutate h1-pipeline.yaml 'd["skills"] = {"implementer": ["superpowers:test-driven-development"]}'
expect_error "E-SCHEMA-LEGACY" "폐기된 skills 키를 거부한다"

# --- 수용 기준을 확인할 게이트가 없다 (리뷰 H-1 재발 방지) ---
mutate h1-pipeline.yaml 'd["verification"]["local"] = ["fast"]; d["verification"]["final"] = ["final"]'
expect_error "E-GATE-COVERAGE" "테스트를 요구하는 수용 기준에 feature tier 미배정을 거부한다"

# --- 되돌릴 수 없는데 human_gate 가 false ---
mutate h3-orchestrator.yaml 'd["human_gate"] = {"required": False}'
expect_error "E-HUMAN-GATE" "irreversible/production 인데 human_gate false 를 거부한다"

# --- human_gate true 인데 사유가 없다 ---
mutate h3-orchestrator.yaml 'd["human_gate"] = {"required": True}'
expect_error "E-HUMAN-GATE" "human_gate true 인데 reason 누락을 거부한다"

# --- 컨텍스트 예산에 full_repository_dump 금지가 빠졌다 ---
mutate h1-pipeline.yaml 'd["context"]["reviewer"]["forbidden"] = ["session_history"]'
expect_error "E-CONTEXT" "forbidden 에서 full_repository_dump 누락을 거부한다"

# --- max_workers 상한 초과 ---
mutate h2-fanout.yaml 'd["parallelism"]["max_workers"] = 5'
expect_error "E-PARALLEL" "max_workers 3 초과를 거부한다"

# --- max_loops 가 risk 에 비해 과도 ---
mutate h1-pipeline.yaml 'd["review_policy"]["max_loops"] = 3'
expect_error "E-REVIEW-LOOPS" "risk 가 high 가 아닌데 max_loops 3 을 거부한다"

# --- rationale 누락 ---
mutate h1-pipeline.yaml 'd["harness"]["rationale"] = ""'
expect_error "E-RATIONALE" "빈 rationale 을 거부한다"

# --- 필수 최상위 키 누락 ---
mutate h1-pipeline.yaml 'del d["review_policy"]'
expect_error "E-REQUIRED" "필수 최상위 키 누락을 거부한다"

# --- 파일이 없을 때 ---
out="$(python3 "$VALIDATOR" "$TMP/does-not-exist.yaml" 2>&1)"; rc=$?
if [[ "$rc" -eq 0 ]]; then
    echo "FAIL: 없는 파일에 exit 0"; FAILURES=$((FAILURES + 1))
else
    echo "PASS: 없는 파일을 거부한다"
fi

report_and_exit
