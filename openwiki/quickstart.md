---
type: wiki entrypoint
title: Harness engineering examples
description: Entry point for navigating chapter-scoped Claude Code harness exercises, executable controls, and source-grounded operational guidance.
tags: [quickstart, agents, skills]
---

# Harness engineering examples

This repository is a companion collection of independent Claude Code harness exercises. It is **not** one deployable application or a manifest-backed monorepo. Most directories contain static agent/skill contracts and instructional dry-run material; only a few scripts are directly executable. Start from the source-grounded pages below rather than assuming every README-named path exists.

## Map

- [Example catalog](catalog.md) — all 24 exercises and their evidence status.
- Foundations: [A/B publishing harness](foundations/harness-ab-comparison.md), [commit-message loop](foundations/commit-message-harness.md).
- Agent contracts: [security analyst](agents/security-analyst.md), [copy editor](agents/copy-editor.md), [definition specimen](agents/agent-definition.md).
- Skill design and execution: [design experiments](skills/design-experiments.md), [CSV evaluation](skills/csv-evaluation.md), [SKILL.md reviewer](skills/reviewing-skill-md.md).
- Review systems: [PR orchestration](review/pr-review-orchestrator.md), [worker roles](review/reviewer-roles.md), [JWT exercise status](review/jwt-fixture.md), [scaling lesson](review/scaling-incident.md).
- Controls and delivery: [bounded retries](automation/bounded-retries.md), [dependency mapper](automation/dependency-mapper.md), [full-stack team](delivery/full-stack-team.md), [application guides](delivery/application-guides.md).
- Repository tooling: [OpenWiki update automation](operations/openwiki-update.md), [OpenWiki skills](extensions/openwiki-skills.md).

## Task routing

| Intent | Canonical page and source entrypoint | Focused validation |
|---|---|---|
| Change the A/B tip-publishing lifecycle | [A/B pipeline](foundations/harness-ab-comparison.md); `ex-02-01-ab-comparison/apply-harness/.claude/` | Inspect one tip and `apply-harness/tips/README.md` for format/index alignment. |
| Change commit-message limits or handoff | [Commit-message harness](foundations/commit-message-harness.md); `ex-02-02-my-first-harness/.claude/skills/commit-message/SKILL.md` | Stage a small change; check no-change stop, PASS, and two-REDO cap. |
| Change read-only security analysis | [Security analyst](agents/security-analyst.md); `ex-04-01-security-analyst/.claude/agents/security-analyst.md` | Run the declared agent invocation when available; confirm source stays unchanged. |
| Change CSV summary semantics | [CSV evaluation](skills/csv-evaluation.md); `ex-05-11-with-without/.claude/skills/csv-summary/bin/run.sh` | Create a temporary CSV; inspect dtypes, blank policy, population deviation, and grouping. |
| Change SKILL.md metric collection | [SKILL.md reviewer](skills/reviewing-skill-md.md); `collect-metrics.sh` | `bash ex-05-13-skill-md-reviewer/.claude/skills/reviewing-skill-md/scripts/tests/test-collect-metrics.sh` |
| Change review-team roles or lifecycle | [PR orchestration](review/pr-review-orchestrator.md) and [worker roles](review/reviewer-roles.md) | Inspect static workspace/permission contracts and resolve the static-analyzer handoff conflict; no complete live runner is tracked. |
| Implement or repair JWT review scenario | [JWT exercise status](review/jwt-fixture.md); `ex-11-06-jwt-pr-bugs/` | Restore missing fixtures/results before running the README grep command. |
| Change retry behavior | [Bounded retries](automation/bounded-retries.md); `ex-08-15-max-retries-code/run/max_retries.py` | `python3 .../max_retries.py success` and `fail`. |
| Implement dependency mapping | [Dependency mapper](automation/dependency-mapper.md); agent spec and `sample-src/` | First add mapper tests for imports, cycle pair, and truncated input. |
| Change OpenWiki updates or LangSmith connection | [OpenWiki update automation](operations/openwiki-update.md); workflow YAML and `openwiki/.langsmith.json` | Use `workflow_dispatch`; review PR scope and verify that no secret value appears. |

## Evidence model

- **Executable**: retry Python program, CSV summary shell/Python implementation, and SKILL.md metric collector plus shell test.
- **Static contract**: most `.claude/agents/*.md` and `SKILL.md` files define intended Claude Code behavior but are not code executed by this repository.
- **Dry-run/mock**: expected reports and checklists illustrate outcomes; they do not prove an LLM, API, or CLI call was executed.
- **Absent claimed artifact**: the README describes a path or command not checked in. Do not use it as validation until restored.

## Backlog

- Chapter 5 READMEs (`ex-05-05` through `ex-05-12`) name absent result/fixture/trace artifacts; only their tracked agent and skill contracts are inspectable. `ex-05-11` additionally names absent `result/bin/run-both.sh`, fixtures, and comparison outputs; only the CSV summary implementation is runnable.
- Review READMEs (`ex-06-12`, `ex-11-03`, `ex-11-04`, `ex-11-05`, and `ex-11-06`) name absent stubs, dry-runs, sample PRs, or result trees; [the orchestration page](review/pr-review-orchestrator.md) and [JWT status page](review/jwt-fixture.md) record the restoration surfaces.
- `ex-13-01-dependency-mapper/README.md` names `mock-mapper.sh`, `verify.sh`, and `batches.json`, but none are tracked; it also uses stale `ex-13-04` wording. Its agent and sample source are a specification/fixture only.
- `ex-14-10-application-guide/README.md` names application guides and `result/verify.sh`, but neither is tracked; the reviewer contract also has a `SendMessage` instruction/tool-list mismatch.
- The metric collector includes a CRLF fixture and CRLF-aware parser, but its focused shell test runs only the LF fixture; add a CRLF test case.

For the repository-wide index and licensing, see `README.md`. For every change, follow the linked page to the owning contract, adjacent evidence, and narrowest honest validation route.
