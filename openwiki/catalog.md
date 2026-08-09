---
type: repository catalog
title: Example catalog
description: Maps all 24 chapter-scoped harness exercises to their canonical wiki homes and evidence status.
tags: [catalog, examples, navigation]
---

# Example catalog

This repository is a book companion made of independent exercise directories. There is no shared package manifest, service runtime, database, or monorepo build. Each exercise carries its own `.claude` definitions, fixtures, README, and sometimes captured output. Read a local README for the intended invocation, then use the canonical pages below for source-grounded behavior.

| Chapters | Exercises | Canonical home |
|---|---|---|
| 2 | A/B comparison; first commit-message harness | [A/B pipeline](foundations/harness-ab-comparison.md); [commit messages](foundations/commit-message-harness.md) |
| 4 and 7 | security analyst; copy editor; agent-definition specimen | [security](agents/security-analyst.md); [copy editor](agents/copy-editor.md); [definitions](agents/agent-definition.md) |
| 5 | six skill design experiments; CSV comparison; SKILL.md reviewer | [design experiments](skills/design-experiments.md); [CSV evaluation](skills/csv-evaluation.md); [skill reviewer](skills/reviewing-skill-md.md) |
| 6 and 11 | PR skill; scaling incident; static analyzer/team frontmatter; six-phase team; JWT fixture | [orchestrator](review/pr-review-orchestrator.md); [roles](review/reviewer-roles.md); [fixture](review/jwt-fixture.md); [scaling](review/scaling-incident.md) |
| 8 and 13 | retry control; dependency mapper | [bounded retries](automation/bounded-retries.md); [dependency mapper](automation/dependency-mapper.md) |
| 12 and 14 | eight-agent delivery team; application guides | [full-stack team](delivery/full-stack-team.md); [application guides](delivery/application-guides.md) |

## Evidence status

**Executable code** includes the retry Python program, CSV shell/Python summary, and metric collector/test. **Static specifications** include most agents/skills and team designs. **Dry-run/mock results** are instructional expected output, not proof that Claude Code or external tools ran. Several READMEs claim absent trees: chapter 5 result/fixture artifacts, With/Without orchestration fixtures, PR review dry-runs and sample PRs, the JWT fixture/results, dependency-mapper scripts/generated batches, and application-guide artifacts/verifier. Preserve these distinctions in changes.

The repository also ships an [OpenWiki update workflow](operations/openwiki-update.md) and [authoring/connector skills](extensions/openwiki-skills.md).