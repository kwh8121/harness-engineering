#!/usr/bin/env python3
"""validate-spec.py — HarnessSpec 이 실행 계약으로서 온전한지 기계적으로 검증한다.

사용법:
    python3 validate-spec.py <spec.yaml> [--gates <gates.tsv>]

종료코드:
    0  통과 (경고는 있을 수 있다)
    1  계약 위반 — 이 spec 으로 실행하면 안 된다
    2  검증기를 돌릴 수 없다 (파일 없음·파싱 실패·PyYAML 없음)

왜 필요한가:
    `yaml.safe_load` 성공은 "문법이 YAML 이다"만 말해 준다. 카탈로그 밖 에이전트,
    model 누락, 축 모순, 수용 기준에 대응하는 게이트 부재는 전부 통과해 버린다.
    실제로 H0 가 feature tier 를 배정하지 않아 테스트 없이 완료를 선언하던 결함이
    이 검증기가 없어서 리뷰까지 살아남았다.
"""
import sys

EXIT_OK, EXIT_INVALID, EXIT_CANNOT_RUN = 0, 1, 2

# 카탈로그 7종 — references/catalog.md 와 .claude/agents/*.md 가 진실의 원천이다.
CATALOG = {
    "implementer", "reviewer", "dependency-mapper", "baseline-tester",
    "integrator", "orchestrator", "deployment-agent",
}

# Agent 도구가 필요한 스킬. 워커에 주입하면 실행되지 않는다.
CONTROLLER_ONLY_SKILLS = {
    "superpowers:brainstorming",
    "superpowers:writing-plans",
    "superpowers:subagent-driven-development",
    "superpowers:dispatching-parallel-agents",
    "superpowers:using-git-worktrees",
    "superpowers:requesting-code-review",
    "superpowers:verification-before-completion",
    "superpowers:finishing-a-development-branch",
}

ENUMS = {
    ("profile", "scope"): {"single", "few", "many"},
    ("profile", "coupling"): {"low", "medium", "high"},
    ("profile", "parallelism"): {"none", "some", "high"},
    ("profile", "uncertainty"): {"low", "medium", "high"},
    ("profile", "risk"): {"low", "medium", "high"},
    ("profile", "side_effect"): {"none", "reversible", "irreversible"},
    ("harness", "level"): {"H0", "H1", "H2", "H3"},
    ("harness", "pattern"): {"single", "pipeline", "fanout", "dag"},
    ("task", "target_environment"): {"local", "staging", "production"},
}

# nested 섹션은 전부 매핑(딕셔너리)이어야 한다. yaml 은 `key: []`·`key: null`·`key: "text"`
# 를 전부 문법적으로 허용하므로 각 섹션을 쓰기 전에 타입부터 확인해야 한다 — 아니면
# `verification: []` 같은 입력이 처리되지 않은 예외로 죽거나, `tracking: null` 같은 입력이
# 검사를 전부 건너뛰고 조용히 통과해 버린다.
MAPPING_SECTIONS = [
    "task", "profile", "harness", "verification", "review_policy",
    "parallelism", "human_gate", "tracking", "context", "agent_skills", "escalation",
]

# H3 의 Feedback Router 계약: 실패 원인마다 정확히 이 대상으로 되돌아가야 한다.
# routing.md 의 재라우팅 표, schemas/harness-spec.yaml 의 escalation 주석과 같은 값이다.
ESCALATION_TARGETS = {
    "if_hidden_dependency": "dependency-mapper",
    "if_baseline_unknown": "baseline-tester",
    "if_implementation_error": "implementer",
}
# if_gate_fails_repeatedly 는 카탈로그 에이전트가 아니라 superpowers 스킬을 가리킨다.
# 게이트 반복 실패의 복구 경로는 superpowers:systematic-debugging 하나로 고정되어
# 있으므로(routing.md·SKILL.md·catalog.md 가 전부 이 값으로 참조한다), check_escalation()
# 에서 접두사가 아니라 정확한 값 일치로 검사한다.
ESCALATION_KEYS = set(ESCALATION_TARGETS) | {"if_gate_fails_repeatedly"}

LEVEL_PATTERN = {"H0": "single", "H1": "pipeline", "H2": "fanout", "H3": "dag"}
TIERS = {"fast", "feature", "final"}

REQUIRED_TOP = [
    "harness_version", "task", "profile", "harness", "agents",
    "controller_skills", "agent_skills", "context",
    "verification", "review_policy", "parallelism", "human_gate", "tracking",
    "escalation",
]

TRACKING_PROVIDERS = {"linear", "none"}
TRACKING_MODES = {"issue", "project"}
APPROVAL_PATHS = {"terminal", "linear", "both"}

# 워커에 주입 가능한 스킬(agent_skills) + 컨트롤러가 호출하는 스킬(controller_skills) 의
# 전체 허용 목록. references/catalog.md 의 매핑표와 정확히 같아야 한다 — 여기 없는
# 이름은 존재하지 않는 스킬이거나 오타다.
ALLOWED_SKILLS = CONTROLLER_ONLY_SKILLS | {
    "superpowers:test-driven-development",
    "superpowers:receiving-code-review",
    "superpowers:systematic-debugging",
    "security-review",
}
# 레벨별로 허용되는 추적 모드. H0 은 추적하지 않는다.
LEVEL_TRACKING_MODE = {"H1": "issue", "H2": "project", "H3": "project"}

# 레벨별로 controller_skills 에 반드시 있어야 하는 스킬.
# H2/H3 은 격리된 worktree 에서 작업하므로(references/routing.md H2 1단계) 격리를 **만드는**
# 스킬과 **해제하는** 스킬을 쌍으로 선언해야 한다. 해제를 빼면 고아 worktree 가 남고,
# 그 안에서 만들어진 브랜치의 통합 방식도 정해지지 않은 채 하네스가 끝난다.
LEVEL_REQUIRED_CONTROLLER_SKILLS = {
    "H2": ("superpowers:using-git-worktrees",
           "superpowers:finishing-a-development-branch"),
    "H3": ("superpowers:using-git-worktrees",
           "superpowers:finishing-a-development-branch"),
}

# 수용 기준이 테스트 통과를 요구하는지 판별할 때 쓰는 표지
TEST_WORDS = ("테스트", "test", "spec 통과", "회귀")


class Report:
    def __init__(self):
        self.errors = []
        self.warnings = []

    def error(self, code, where, msg):
        self.errors.append(f"ERROR {code}  {where}: {msg}")

    def warn(self, code, where, msg):
        self.warnings.append(f"WARN  {code}  {where}: {msg}")


def get(d, *path, default=None):
    cur = d
    for k in path:
        if not isinstance(cur, dict) or k not in cur:
            return default
        cur = cur[k]
    return cur


def check_types(spec, r):
    """MAPPING_SECTIONS 각각이 매핑인지 먼저 확인한다.

    아니면 두 가지 실패 모드가 생긴다: `verification: []` 처럼 리스트를 주면 이후
    `.get()` 호출이 AttributeError 로 죽어 처리되지 않은 예외가 사용자에게 그대로
    노출되고, `tracking: null` 처럼 None 을 주면 `if t is None: return` 류의 조기
    반환에 걸려 나머지 검사를 전부 건너뛰고 조용히 통과해 버린다.

    타입이 틀린 섹션은 여기서 E-TYPE 으로 보고하고, 이후 검사가 죽지 않도록 spec
    안에서 빈 매핑으로 바꿔치기한다 — 그래도 이미 E-TYPE 이 있으므로 최종 판정은
    통과할 수 없다.
    """
    for key in MAPPING_SECTIONS:
        if key not in spec:
            continue                       # E-REQUIRED 가 이미 잡는다
        val = spec[key]
        if not isinstance(val, dict):
            r.error("E-TYPE", key,
                    f"매핑(mapping)이어야 한다 (현재 {type(val).__name__}: {val!r})")
            spec[key] = {}


def check_structure(spec, r):
    if "skills" in spec:
        r.error("E-SCHEMA-LEGACY", "skills",
                "폐기된 키다. controller_skills 와 agent_skills 로 나눠야 한다 "
                "(워커에는 Agent 도구가 없다)")
    for key in REQUIRED_TOP:
        if key not in spec:
            r.error("E-REQUIRED", key, "필수 최상위 키가 없다")
    # target_environment 는 ENUMS 에 등록돼 있어 check_enums 가 존재 여부와 값을 함께
    # 검사한다 — 여기서 다시 검사하면 같은 결함이 두 줄로 중복 보고된다.
    for field in ("goal", "scope", "acceptance_criteria"):
        if not get(spec, "task", field):
            r.error("E-REQUIRED", f"task.{field}", "비어 있다")


def check_enums(spec, r):
    for (section, field), allowed in ENUMS.items():
        val = get(spec, section, field)
        if val is None:
            r.error("E-REQUIRED", f"{section}.{field}", "값이 없다")
        elif val not in allowed:
            r.error("E-ENUM", f"{section}.{field}",
                    f"'{val}' 는 허용되지 않는다. 가능한 값: {sorted(allowed)}")


def check_axes(spec, r):
    coupling = get(spec, "profile", "coupling")
    parallelism = get(spec, "profile", "parallelism")
    if coupling == "high" and parallelism not in (None, "none"):
        r.error("E-AXIS", "profile",
                f"coupling: high 면 parallelism 은 none 이어야 한다 (현재 '{parallelism}'). "
                "동시 실행이 불가능하다는 뜻이지, 작업 단위가 1개라는 뜻이 아니다")

    level, pattern = get(spec, "harness", "level"), get(spec, "harness", "pattern")
    if level in LEVEL_PATTERN and pattern and pattern != LEVEL_PATTERN[level]:
        r.error("E-ENUM", "harness.pattern",
                f"{level} 의 pattern 은 '{LEVEL_PATTERN[level]}' 여야 한다 (현재 '{pattern}')")

    if not str(get(spec, "harness", "rationale") or "").strip():
        r.error("E-RATIONALE", "harness.rationale",
                "비어 있다. 한 단계 아래가 왜 불충분한지 써야 한다 "
                "(H0 는 STEP 1 세 조건 충족으로 갈음)")


def check_agents(spec, r):
    agents = spec.get("agents") or []
    if not isinstance(agents, list):
        r.error("E-REQUIRED", "agents", "리스트여야 한다")
        return []

    ids = []
    for i, a in enumerate(agents):
        if not isinstance(a, dict) or "id" not in a:
            r.error("E-REQUIRED", f"agents[{i}]", "id 가 없다")
            continue
        aid = a["id"]
        ids.append(aid)
        if aid not in CATALOG:
            r.error("E-AGENT-UNKNOWN", f"agents[{i}].id",
                    f"'{aid}' 는 카탈로그 7종에 없다. 새 역할을 만들지 않는다 — "
                    f"반복 Procedure 라면 Agent 가 아니라 Skill 이다. 가능: {sorted(CATALOG)}")
        if not a.get("model"):
            r.error("E-AGENT-MODEL", f"agents[{i}]({aid})",
                    "model 이 없다. dispatch 시 생략하면 세션의 가장 비싼 모델을 상속한다")
        if not str(a.get("responsibility") or "").strip():
            r.warn("W-RESPONSIBILITY", f"agents[{i}]({aid})", "responsibility 가 비어 있다")

    dup = {x for x in ids if ids.count(x) > 1}
    if dup:
        r.error("E-AGENT-UNKNOWN", "agents", f"중복된 에이전트: {sorted(dup)}")

    level = get(spec, "harness", "level")
    idset = set(ids)
    if level == "H0" and ids:
        r.error("E-LEVEL-AGENTS", "agents",
                f"H0 은 서브에이전트를 스폰하지 않는다 (현재 {sorted(idset)})")
    if level in ("H1", "H2", "H3"):
        for need in ("implementer", "reviewer"):
            if need not in idset:
                r.error("E-LEVEL-AGENTS", "agents", f"{level} 에는 {need} 가 필요하다")
    if level in ("H2", "H3") and "integrator" not in idset:
        r.error("E-LEVEL-AGENTS", "agents",
                f"{level} 은 여러 작업 단위를 합치므로 integrator 가 필요하다")
    if level == "H3" and "orchestrator" not in idset:
        r.error("E-LEVEL-AGENTS", "agents",
                "H3 은 DAG 상태 관리와 재라우팅을 위해 orchestrator 가 필요하다")
    if level in ("H0", "H1", "H2") and "orchestrator" in idset:
        r.error("E-LEVEL-AGENTS", "agents",
                f"{level} 에 orchestrator 는 불필요하다. 조정이 필요하면 H3 로 올린다")
    return ids


def check_skills(spec, agent_ids, r):
    controller = spec.get("controller_skills") or []
    agent_skills = spec.get("agent_skills") or {}

    if "superpowers:verification-before-completion" not in controller:
        r.error("E-SKILL-OWNER", "controller_skills",
                "superpowers:verification-before-completion 은 전 레벨 필수다")

    # worktree 는 만들면 반드시 정리한다 — 격리와 해제는 쌍이다.
    level = get(spec, "harness", "level")
    for skill in LEVEL_REQUIRED_CONTROLLER_SKILLS.get(level, ()):
        if skill not in controller:
            r.error("E-SKILL-WORKTREE", "controller_skills",
                    f"{level} 은 격리된 worktree 에서 작업하므로 '{skill}' 가 필수다. "
                    "격리를 만드는 스킬과 해제하는 스킬은 쌍으로 선언한다 — "
                    "해제를 빼면 고아 worktree 가 남고 브랜치 통합 방식이 정해지지 않는다")

    # H1 은 worktree 를 만들지 않으므로 필수는 아니다. 다만 브랜치에서 작업했다면
    # 통합 방식(머지·PR·유지)은 여전히 사람이 정해야 한다 — references/catalog.md 는
    # 이 스킬의 적용 범위를 H1–H3 으로 적고 있다.
    if level == "H1" and "superpowers:finishing-a-development-branch" not in controller:
        r.warn("W-FINISHING", "controller_skills",
               "H1 은 worktree 를 만들지 않아 필수는 아니지만, 브랜치에서 작업했다면 "
               "superpowers:finishing-a-development-branch 로 통합 방식을 정해야 한다")

    if not isinstance(agent_skills, dict):
        r.error("E-SKILL-OWNER", "agent_skills", "에이전트 id → 스킬 목록 매핑이어야 한다")
        return

    for aid, skills in agent_skills.items():
        if aid not in agent_ids:
            r.error("E-SKILL-OWNER", f"agent_skills.{aid}",
                    f"'{aid}' 는 이 spec 의 agents 에 없다")
        for skill in (skills or []):
            if skill in CONTROLLER_ONLY_SKILLS:
                r.error("E-SKILL-OWNER", f"agent_skills.{aid}",
                        f"'{skill}' 는 Agent 도구가 필요한 controller 스킬이다. "
                        "워커에 주입하면 실행되지 않는다 — controller_skills 로 옮겨라")
            elif skill not in ALLOWED_SKILLS:
                r.error("E-SKILL-UNKNOWN", f"agent_skills.{aid}",
                        f"'{skill}' 는 references/catalog.md 매핑표에 없는 스킬이다")

    for skill in controller:
        if skill not in ALLOWED_SKILLS:
            r.error("E-SKILL-UNKNOWN", "controller_skills",
                    f"'{skill}' 는 references/catalog.md 매핑표에 없는 스킬이다")


def check_verification(spec, r, gates_path=None):
    local = spec.get("verification", {}).get("local") or []
    final = spec.get("verification", {}).get("final") or []
    manual = spec.get("verification", {}).get("manual") or []

    for name, tiers in (("local", local), ("final", final)):
        for t in tiers:
            if t not in TIERS:
                r.error("E-ENUM", f"verification.{name}",
                        f"'{t}' 는 tier 가 아니다. 가능: {sorted(TIERS)}")

    declared = set(local) | set(final)
    criteria = spec.get("task", {}).get("acceptance_criteria") or []
    wants_test = any(any(w in str(c).lower() for w in TEST_WORDS) for c in criteria)

    if wants_test and "feature" not in declared and not manual:
        r.error("E-GATE-COVERAGE", "verification",
                "수용 기준이 테스트 통과를 요구하는데 feature tier 가 local·final 어디에도 없고 "
                "manual 도 비어 있다. detect-stack.sh 는 단위 테스트를 feature 로 분류한다 — "
                "이대로면 테스트가 한 번도 실행되지 않은 채 완료가 선언된다")

    if not declared and not manual:
        r.error("E-GATE-COVERAGE", "verification",
                "실행할 게이트도 수동 확인 항목도 없다. 무엇으로 완료를 판정하는가?")

    if gates_path:
        try:
            rows = [ln.split("\t", 1) for ln in open(gates_path) if "\t" in ln]
        except OSError as e:
            r.warn("W-GATES", "verification.gates_tsv", f"gates.tsv 를 읽을 수 없다: {e}")
        else:
            available = {t.strip() for t, _ in rows}
            for t in sorted(declared - available):
                r.error("E-GATE-COVERAGE", "verification",
                        f"tier '{t}' 를 선언했지만 {gates_path} 에 해당 명령이 없다")
            for t in sorted(available - declared):
                r.warn("W-GATES", "verification",
                       f"gates.tsv 에 tier '{t}' 명령이 있는데 spec 이 실행하지 않는다")


def check_policies(spec, r):
    risk = get(spec, "profile", "risk")
    loops = get(spec, "review_policy", "max_loops")
    if loops is None:
        r.error("E-REQUIRED", "review_policy.max_loops", "값이 없다")
    elif not isinstance(loops, int) or isinstance(loops, bool):
        # int 비교(>)에 바로 쓰이므로 타입부터 확인한다. bool 은 파이썬에서 int 의
        # 서브클래스라 isinstance(True, int) 가 True 다 — YAML 의 true/false 가
        # 숫자로 오인되지 않도록 따로 배제한다.
        r.error("E-TYPE", "review_policy.max_loops",
                f"정수여야 한다 (현재 {type(loops).__name__}: {loops!r})")
    else:
        limit = 3 if risk == "high" else 2
        if loops > limit:
            r.error("E-REVIEW-LOOPS", "review_policy.max_loops",
                    f"risk: {risk} 의 상한은 {limit} 이다 (현재 {loops}). "
                    "루프를 늘리는 것은 Verify–Generate Deadlock 을 부른다")
        if loops < 1:
            r.error("E-REVIEW-LOOPS", "review_policy.max_loops", "1 이상이어야 한다")

    workers = get(spec, "parallelism", "max_workers")
    enabled = get(spec, "parallelism", "enabled")
    if workers is None:
        r.error("E-REQUIRED", "parallelism.max_workers", "값이 없다")
    elif not isinstance(workers, int) or isinstance(workers, bool):
        r.error("E-TYPE", "parallelism.max_workers",
                f"정수여야 한다 (현재 {type(workers).__name__}: {workers!r})")
    elif workers > 3:
        r.error("E-PARALLEL", "parallelism.max_workers",
                f"상한은 3 이다 (현재 {workers}). 4 이상은 병합 비용이 병렬 이득을 잠식한다")
    elif enabled is False and workers != 1:
        r.error("E-PARALLEL", "parallelism",
                f"enabled: false 인데 max_workers 가 {workers} 다")

    side_effect = get(spec, "profile", "side_effect")
    env = get(spec, "task", "target_environment")
    required = get(spec, "human_gate", "required")
    if (side_effect == "irreversible" or env == "production") and required is not True:
        r.error("E-HUMAN-GATE", "human_gate.required",
                f"side_effect={side_effect}, target_environment={env} 이면 "
                "레벨과 무관하게 true 여야 한다 (판정 트리 STEP 5)")
    if required is True and not str(get(spec, "human_gate", "reason") or "").strip():
        r.error("E-HUMAN-GATE", "human_gate.reason",
                "승인을 요구하면서 사유를 적지 않았다. 사람이 무엇을 승인하는지 알 수 없다")


def check_escalation(spec, agent_ids, r):
    esc = spec.get("escalation")
    if esc is None:
        return                             # E-REQUIRED 또는 E-TYPE 이 이미 잡는다
    if not isinstance(esc, dict):
        return                             # check_types 가 이미 E-TYPE 으로 잡았다

    # if_gate_fails_repeatedly 는 레벨·에이전트 구성과 무관하게 항상 필요하다 —
    # H0 도 게이트가 반복 실패할 수 있고, 그때 systematic-debugging 으로 넘어가야 한다.
    # 게이트 반복 실패의 복구 경로는 정확히 하나뿐이다. "superpowers:" 접두사만 보면
    # superpowers:not-a-real-skill 같은 존재하지 않는 이름도 통과해 버린다 —
    # routing.md·SKILL.md·catalog.md 가 전부 이 값으로 고정해 참조하므로 여기서도
    # 정확한 이름을 강제한다.
    gate_target = esc.get("if_gate_fails_repeatedly")
    if gate_target != "superpowers:systematic-debugging":
        r.error("E-ESCALATION", "escalation.if_gate_fails_repeatedly",
                f"'{gate_target}' 가 아니라 정확히 'superpowers:systematic-debugging' "
                "이어야 한다 (게이트 반복 실패의 복구 경로는 이 스킬 하나로 고정되어 있다)")

    # 나머지 세 대상은 **그 실패 원인을 낼 수 있는 에이전트가 이 spec 에 실제로 배정된
    # 경우에만** 요구한다. H0 은 dependency-mapper·baseline-tester·implementer 를
    # 아예 스폰하지 않으므로 "숨은 의존성이 드러나면 dependency-mapper 로" 라는 문장
    # 자체가 의미가 없다 — 없는 에이전트를 재라우팅 대상으로 강제하지 않는다.
    for key, target_agent in ESCALATION_TARGETS.items():
        if target_agent not in agent_ids:
            continue
        val = esc.get(key)
        if not str(val or "").strip():
            r.error("E-ESCALATION", f"escalation.{key}",
                    f"'{target_agent}' 가 이 spec 에 배정되어 있는데 이 실패 원인의 "
                    "재라우팅 대상이 비어 있다")
        elif val != target_agent:
            r.error("E-ESCALATION", f"escalation.{key}",
                    f"'{val}' 가 아니라 '{target_agent}' 로 되돌려야 한다 "
                    "(재라우팅 대상은 카탈로그와 고정 매핑이다)")


def check_context(spec, agent_ids, r):
    ctx = spec.get("context") or {}
    if not isinstance(ctx, dict):
        r.error("E-CONTEXT", "context", "에이전트 id → 예산 매핑이어야 한다")
        return
    for aid in agent_ids:
        if aid not in ctx:
            r.error("E-CONTEXT", f"context.{aid}",
                    "컨텍스트 예산이 없다. 예산 없는 에이전트는 레포 전체를 읽는다")
            continue
        entry = ctx[aid] or {}
        if not entry.get("required"):
            r.error("E-CONTEXT", f"context.{aid}.required", "비어 있다")
        if "full_repository_dump" not in (entry.get("forbidden") or []):
            r.error("E-CONTEXT", f"context.{aid}.forbidden",
                    "full_repository_dump 는 모든 에이전트에서 금지다 (예외 없음)")
    for aid in ctx:
        if aid not in agent_ids:
            r.warn("W-CONTEXT", f"context.{aid}", "이 spec 의 agents 에 없는 에이전트다")


def check_tracking(spec, r):
    t = spec.get("tracking")
    if t is None:
        return                      # E-REQUIRED 가 이미 잡는다
    if not isinstance(t, dict):
        r.error("E-TRACKING", "tracking", "매핑이어야 한다")
        return

    provider = t.get("provider")
    if provider not in TRACKING_PROVIDERS:
        r.error("E-TRACKING", "tracking.provider",
                f"'{provider}' 는 지원하지 않는다. 가능: {sorted(TRACKING_PROVIDERS)}")
        return
    if provider == "none":
        return                      # 추적하지 않으면 나머지는 볼 필요가 없다

    level = get(spec, "harness", "level")
    if level == "H0":
        r.error("E-TRACKING", "tracking.provider",
                "H0 은 추적하지 않는다 (provider: none). 단일 파일·저위험 변경까지 "
                "이슈로 만들면 백로그가 오탈자 수정으로 찬다")
        return

    if not str(t.get("team") or "").strip():
        r.error("E-TRACKING", "tracking.team",
                "provider: linear 면 team 이 필요하다 (Linear 팀 이름 또는 ID)")

    mode = t.get("mode")
    if mode not in TRACKING_MODES:
        r.error("E-TRACKING", "tracking.mode",
                f"'{mode}' 는 지원하지 않는다. 가능: {sorted(TRACKING_MODES)}")
    elif level in LEVEL_TRACKING_MODE and mode != LEVEL_TRACKING_MODE[level]:
        want = LEVEL_TRACKING_MODE[level]
        why = ("작업 단위가 1개이므로 Issue 1건이다"
               if want == "issue" else
               "여러 단위를 하나의 성과물로 묶으므로 Project 다")
        r.error("E-TRACKING", "tracking.mode",
                f"{level} 의 추적 모드는 '{want}' 여야 한다 (현재 '{mode}') — {why}")

    if mode == "project" and not (get(spec, "tracking", "project", "name")
                                  or get(spec, "tracking", "project", "id")):
        r.error("E-TRACKING", "tracking.project",
                "project 모드는 name(신규) 또는 id(기존 프로젝트 재사용) 가 필요하다")

    approval = t.get("human_gate_approval")
    if approval not in APPROVAL_PATHS:
        r.error("E-TRACKING", "tracking.human_gate_approval",
                f"'{approval}' 는 지원하지 않는다. 가능: {sorted(APPROVAL_PATHS)}")

    if get(spec, "human_gate", "required") is True and approval == "linear":
        r.warn("W-TRACKING", "tracking.human_gate_approval",
               "Linear 상태 변경만으로 승인받는다. 사용자가 Linear 를 보지 않으면 "
               "하네스가 대기 상한까지 멈춰 있게 된다")


def main(argv):
    if len(argv) < 2:
        print(__doc__.strip(), file=sys.stderr)
        return EXIT_CANNOT_RUN

    path = argv[1]
    gates_path = None
    if "--gates" in argv:
        i = argv.index("--gates")
        if i + 1 >= len(argv):
            print("ERROR: --gates 뒤에 경로가 없다", file=sys.stderr)
            return EXIT_CANNOT_RUN
        gates_path = argv[i + 1]

    try:
        import yaml
    except ImportError:
        print("검증기를 돌릴 수 없습니다: PyYAML 이 없습니다 (pip install pyyaml).\n"
              "  설치할 수 없는 환경이면 README 의 '승인 게이트 확인' 항목을 손으로 확인하십시오.",
              file=sys.stderr)
        return EXIT_CANNOT_RUN

    try:
        with open(path) as f:
            spec = yaml.safe_load(f)
    except OSError as e:
        print(f"검증기를 돌릴 수 없습니다: {e}", file=sys.stderr)
        return EXIT_CANNOT_RUN
    except yaml.YAMLError as e:
        print(f"검증기를 돌릴 수 없습니다: YAML 파싱 실패 — {e}", file=sys.stderr)
        return EXIT_CANNOT_RUN

    if not isinstance(spec, dict):
        print("검증기를 돌릴 수 없습니다: 최상위가 매핑이 아닙니다", file=sys.stderr)
        return EXIT_CANNOT_RUN

    r = Report()
    check_types(spec, r)          # 다른 모든 검사가 안전하게 .get() 할 수 있도록 먼저 돈다
    check_structure(spec, r)
    check_enums(spec, r)
    check_axes(spec, r)
    agent_ids = check_agents(spec, r)
    check_escalation(spec, agent_ids, r)
    check_skills(spec, agent_ids, r)
    check_verification(spec, r, gates_path)
    check_policies(spec, r)
    check_context(spec, agent_ids, r)
    check_tracking(spec, r)

    for line in r.warnings:
        print(line)
    for line in r.errors:
        print(line)

    if r.errors:
        print(f"\n{path}: 계약 위반 {len(r.errors)}건 — 이 spec 으로 실행하지 마십시오.")
        return EXIT_INVALID
    print(f"{path}: 통과 (경고 {len(r.warnings)}건)")
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main(sys.argv))
