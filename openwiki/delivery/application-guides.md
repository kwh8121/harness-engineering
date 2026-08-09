---
type: guidance mapping
title: Application guide mappings
description: Records the declared application-guide exercise and the available read-only blameless post-mortem reviewer contract.
tags: [delivery, postmortem, agents]
---

# Application guide mappings

`ex-14-10-application-guide` is an incomplete static exercise. Its README declares four guide mappings—post-mortem, flaky-test, performance, and solo-work—and refers to `application-*.md` artifacts plus `result/verify.sh`. The checked-in directory instead contains only `.claude/`, `CLAUDE.md`, and `README.md`: no application guide files and no `result/` directory are available. Treat all four mappings and the verification command as declared intent, not inspectable implementation or validation.

## Available contract: the post-mortem reviewer

The one concrete source artifact is `.claude/agents/reviewer.md`. It is a Post-mortem-only agent with `Read` as its sole declared tool. Its intended input set is a reproduction script, hypotheses, patch, completion checklist, timeline, and alert history. It writes `_workspace/bug-{id}/postmortem.md` and reports completion to an orchestrator via `SendMessage`; the latter is an instruction-level protocol even though `SendMessage` is not included in its frontmatter tool list, so it should be reconciled before relying on the agent in a live harness.

Its analysis invariants are:

- Be blameless: investigate how the system allowed an outcome, not who is at fault.
- Preserve multiple contributing factors rather than collapsing an incident to one cause.
- Turn each recommendation into a measurable action and an automated prevention guard such as a test, lint rule, or alert threshold.
- Do not edit code or execute incident artifacts.

## Implementation boundary

There is no incident orchestrator, application-guide content, sample incident, or verifier in this repository. Before implementing a guide, add those artifacts and define the reviewer handoff explicitly—including whether the notification mechanism is added to the tool allowlist or returned through a supported channel. Keep reviewer source authority read-only; remediation implementation and command execution belong to an upstream workflow that does not exist here.
