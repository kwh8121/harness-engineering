---
type: agent team
title: Four review worker roles
description: Defines the static, design, security, and refactoring worker contracts, including their evidence requirements, patch boundary, and unresolved static-analyzer handoff conflict.
tags: [review, agents, security]
---

# Four review worker roles

The four definitions in `ex-11-05-orchestrator-6phase/.claude/agents/` and `ex-11-06-jwt-pr-bugs/.claude/agents/` are the worker API for [PR review orchestration](pr-review-orchestrator.md). They prescribe workspace report paths and peer handoffs, but no complete fixture or runner is tracked to execute them end-to-end.

| Role | Authority and lens | Output and invariant |
|---|---|---|
| `static-analyzer` | Read/search/Bash only; changed lines, tool output, duplicate/cycle patterns. | `_workspace/review/01_static.md`; every finding cites file/line and tool evidence; no edits. |
| `design-reviewer` | Read/search only, no Bash/Edit/Write; compares two files and seven boundary patterns. | `_workspace/review/02_design.md`; findings are cross-file and identify boundary type. |
| `security-auditor` | Read/search/Bash; OWASP, secrets, dependencies, `npm audit`/`semgrep` evidence. | `_workspace/review/03_security.md`; every finding includes CWE; unavailable tools are reported rather than guessed. |
| `refactorer` | Read/search/Edit, with source read-only. | Summary plus `_workspace/patches/*.diff`; P0 patches only, no commit, at most three generate/verify attempts. |

## Review evidence and failure contracts

`static-analyzer` scopes its search to files and lines changed by the PR diff; `security-auditor` also receives the PR diff but applies OWASP, secret, and dependency lenses. Static output must contain a tool-result summary for `tsc --noEmit`, `eslint`, and `npm run lint`, then P0/P1/P2 findings with file/line, raw-tool evidence, and recommendation. If `tsc` or `eslint` is unavailable, it writes “tool unavailable” rather than inventing a finding; if the diff is absent, it asks the leader for input and stops rather than analyzing speculatively. Security output has an `npm audit`/`semgrep` result summary and P0/P1/P2 findings; every finding needs file/line, tool evidence, a CWE, and recommendation. Offline `npm audit` leaves dependency status unconfirmed; missing `semgrep` permits a clearly labeled regex-Grep fallback. Both roles downgrade uncertainty to P2.

Neither reviewer has `Write` or `Edit`, despite declaring a workspace report output. Thus the report paths are required protocol artifacts, but the static contracts do not supply the authority that creates them; a live coordinator/runtime must supply or reconcile that capability. Both agents prohibit source edits. Security directs peer messages to fellow reviewers without leader relay. Static likewise names peer exchange, subject to the completion conflict below.

## Refactorer input, output, and failure contract

`refactorer` requires `_workspace/review/01_static.md`, `02_design.md`, and `03_security.md`. It emits two output classes: `_workspace/review/04_refactor.md`, which records patch list, conflict trade-offs, and P1/P2 “next PR” recommendations; and unified-diff files below `_workspace/patches/*.diff`. Only P0 findings get patch files, and every patch must identify the target file and lines. The agent may edit only those patch files—never `src/` or `prisma/`—and must not commit.

After proposing a patch it requests peer revalidation. It may make at most three generate/revalidate attempts: two rejections trigger a single leader report that human intervention is needed rather than a fourth attempt. Missing any upstream report requires an input request; it must not invent a patch. A missing `_workspace/patches/` directory must be detected before editing, but `Edit` alone cannot create a directory, so a builder/coordinator must create it or the work remains blocked.

## Handoff inconsistency to resolve

`static-analyzer` contains conflicting completion guidance. Its team-protocol section says it communicates with peer reviewers directly, bypassing the leader. Its self-check says it should report directly to the leader after workers agree on a single report. The orchestration skill requires peer evidence exchange during review, while the report integration phase needs final worker artifacts. A live implementation must choose and document one completion rule—for example: peers may exchange scoped evidence, each worker writes its own report, and only the orchestrator consumes completion status—rather than assuming either instruction wins. Do not use the current contract as proof of a single leader-free handoff model.

## Safe extension

Keep report filenames, severity vocabulary, and the source-edit boundary stable. A new lens requires an agent contract plus a task dependency and merge entry in the orchestrator. The README-described JWT fixture is absent; see [JWT exercise status](jwt-fixture.md) for restoration requirements before using it as focused behavior validation.
