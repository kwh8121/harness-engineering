---
type: agent specification
title: Dependency mapper specification
description: Defines a read-only import-analysis agent, its proposed batch contract, sample graph edge cases, stale exercise label, and absent implementation artifacts.
tags: [automation, dependencies, agents]
---

# Dependency mapper specification

The canonical exercise identity is the tracked directory `ex-13-01-dependency-mapper`. Its own README has the stale heading `ex-13-04 dependency-mapper.md + sample-src → batches.json`; use the directory name and catalog entry for links and changes, and treat `ex-13-04` as a README-label inconsistency rather than a separate exercise.

`ex-13-01-dependency-mapper/.claude/agents/dependency-mapper.md` is a specification, not an implemented mapper. It permits `Read`, `Grep`, and `Bash`, says storage belongs to an orchestrator, and returns a proposed `batches.json` draft. Although its README names `bash mock-mapper.sh` and `bash verify.sh`, neither script nor `batches.json` exists in this exercise. Do not claim executable generation or verification.

The specified pipeline collects `target_glob`, extracts static imports, computes `(size/100) + (imports*2) + (functions*3)`, groups dependent files into 10–50-file batches, and topologically orders them. Each batch proposal contains `id`, `files`, `depends_on`, `complexity`, `pattern`, `status`, `attempts`, and `max_attempts`.

## Sample graph and edge cases

The tracked `sample-src/` gives an inspectable import graph. `pages/Dashboard.jsx` reaches `UserList` and `Header`; `UserList` reaches `UserCard` and `utils/api`; `UserCard` and `Profile` reach `hooks/useAuth`; that hook reaches `utils/api`, which reaches `utils/http`. `Header` reaches `utils/format`. `Settings` joins `Profile` and `Footer`; `standalone.jsx` has no imports.

Cycles are not rejected: `cyclic-a.jsx` imports `cyclic-b.jsx` and vice versa. The agent requires grouping a cycle in one batch with `warning: "cyclic"`. Parsing failures are excluded from batches and recorded in `manual-queue`; `truncated.jsx` deliberately ends with an incomplete function. A real implementation must preserve both outcomes rather than silently dropping files.

## Implementation seam

Add a mapper, orchestrator-owned persistence, and tests outside this documentation tree. Test static import extraction and the sample dependency ordering, the cycle pair's shared batch/warning, the truncated file's manual queue, and declared batch fields. Normalize the stale README heading when editing the exercise so invocation/documentation identity cannot drift again.
