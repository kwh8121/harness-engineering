---
type: review exercise status
title: JWT review exercise status
description: Records the declared JWT PR review scenario, its mock-mode controls, and the missing fixture and result artifacts that prevent it from serving as a runnable review fixture.
tags: [review, jwt, mock]
---

# JWT review exercise status

`ex-11-06-jwt-pr-bugs` declares a four-reviewer JWT-refresh PR exercise, but it is **not currently a complete fixture**. The checked-in directory contains only `.claude/`, `CLAUDE.md`, `README.md`, and `run/checklist.md`. There is no `fixtures/sample-pr-jwt/`, no `result/`, and consequently no source files, `INTENT_BUG_` markers, discovery matrix, comparison table, or cross-domain log to inspect. The README's grep command is therefore not a runnable validation command in this checkout.

## Declared scenario versus available evidence

The prose contract names four defect classes: SQL injection, N+1 querying, an API/client response-shape mismatch, and missing refresh tests. `CLAUDE.md` further assigns the intended locations to `src/api/users.ts`, `src/api/auth/refresh.ts`, and `src/hooks/useUser.ts`; `run/checklist.md` records expected mock coverage. These are design claims only, not fixture evidence. Do not cite them as discovered defects, test results, or evidence that any reviewer ran.

The default declared mode is mock. `EX_11_06_MODE=live` is described as opt-in, with five-thousand-token input and output caps, restricted Bash scope, no automated commits, and a dry-run `gh pr comment`. No executable live-mode launcher is tracked, so setting the variable alone cannot run this repository example.

## Relationship to the review contracts

The available reusable contracts are the four agent definitions and the `code-review-team` skill; see [PR review orchestration](pr-review-orchestrator.md) and [four review worker roles](reviewer-roles.md). The intended division of responsibility is still useful when rebuilding the fixture:

- `security-auditor` should ground an injection finding in a file, line, tool or fallback evidence, and CWE.
- `design-reviewer` should compare the API response with the consumer expectation across two files.
- `static-analyzer` should limit itself to changed-line, tool-backed claims.
- `refactorer` may propose unified diffs only for P0 findings and may not edit source.

## Restore before treating this as a validation route

To make the README contract true, add the five named PR files under `fixtures/sample-pr-jwt/`, preserve each intended marker and its paired note, and add the referenced mock results. Then add an executable verifier that checks the four unique defect IDs rather than merely a marker count. Update the discovery matrix, without-team comparison, and peer-message log from the same fixture revision. Until then, validate changes to the review role definitions against their static contracts—not this absent fixture.
