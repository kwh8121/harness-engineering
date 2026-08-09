---
type: case study
title: 292-agent scaling incident
description: Documents the unverified book-preserved incident values, the read-only fact-checker workflow, and the bounded-topology design lesson.
tags: [review, agents, scaling]
---

# 292-agent scaling incident

`ex-06-15-292-agent-incident` is a case-note, not a service, benchmark, or executable simulation. Its `run/incident.md` preserves a book quotation about session `9a990de8`, 292 agents, 36.8GB RSS, two minutes, and a per-member message-queue cap of 50. The file explicitly labels the primary source inaccessible and every quoted incident value **UNVERIFIED**. They are book-preserved claims, not repository measurements or externally verified data.

The same note contains a separate, repository-authored illustrative calculation: a full mesh of 292 participants has 42,486 potential channels. That conditional calculation must not be presented as an observed channel count, memory decomposition, or confirmation of the incident. The further per-agent memory and queue-saturation arithmetic is similarly explanatory only.

## Fact-checker evidence workflow

`.claude/agents/fact-checker.md` defines the intended evidence-status protocol. It reads a book claim, searches for first-party material with `WebFetch` or `WebSearch` when available, then:

1. preserves the book number verbatim;
2. labels it `PASS` if first-party evidence verifies it, or `UNVERIFIED` when that evidence is unavailable;
3. records a discrepancy as a separate observation note rather than rewriting the quotation;
4. writes the status to `run/incident.md` or the target exercise's `run/*.md`; and
5. reports a discrepancy to the team leader.

Its declared tools include `Read`, `Write`, `WebFetch`, and `WebSearch`; it is a static agent contract, not evidence that any external lookup succeeded.

## Design lesson

Bound active collaboration topology rather than maximizing role definitions. The review-team specification uses three parallel reviewers followed by one dependent refactorer; [the full-stack team](../delivery/full-stack-team.md) caps a phase at four active participants including PM. Use explicit phases, artifacts, dependencies, and peer messages only when one worker needs another's evidence. No focused automated test is supplied; any future scale claim needs source provenance and an explicit verification status.
