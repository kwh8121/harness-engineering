---
type: design specimen
title: Agent definition structure
description: Uses the Phase 3 security-reviewer specimen to explain required and extended sections of a Claude Code agent definition.
tags: [agents, specifications]
---

# Agent definition structure

`ex-07-13-phase3-agent-5sections` preserves an eight-section `security-reviewer.md` specimen and contrasts a five-required-section definition with definitions that add sections seven and eight. It is a static authoring example, not a runtime service.

The recurring structure visible across this repository is: frontmatter for discovery and authority; a core role; operating principles; an input/output protocol; error behavior; collaboration; and a self-check. The latter sections matter when the agent participates in a workflow: they define what it may infer, where it writes, who receives handoffs, and what completion means.

Use this specimen when adding a role to the harnesses documented in [reviewer roles](../review/reviewer-roles.md) or [the full-stack team](../delivery/full-stack-team.md). Keep the definition proportional: standalone read-only reviewers need explicit evidence and reporting boundaries; editors and implementers need mutation/output constraints. Validate definitions by checking that named tools, output paths, and collaborator names actually exist in the owning exercise. No automated test is supplied for this example.