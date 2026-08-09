---
type: agent specification
title: Mechanical copy editor
description: Defines a narrowly scoped manuscript editor that makes only three mechanical correction classes and reports ambiguity.
tags: [agents, editing, quality]
---

# Mechanical copy editor

`ex-04-02-copy-editor/.claude/agents/copy-editor.md` models a constrained final-pass editor. It changes only: a prose-ending colon to a period, Korean particles outside a bold span, and obvious typos such as repeated syllables/words or keyboard mixing. It explicitly does not perform stylistic rewriting, structural work, or semantic judgment.

Its lifecycle is `structure-reviewer` output → copy editor → human final review or acceptance. The editor modifies the manuscript with small diffs and writes `reviews/copy-edit-report.md` with a summary count table, file-by-file changes, and deferred items. The example README invokes it against `sample-doc/ch-07-draft.md` and expects a correction report plus a change trace.

## Boundaries that preserve safety

Do not alter time notation such as `12:30`, code-block colons such as `key: value`, table-heading colons, or any uncertain issue. Uncertainty is an output condition: record it as a hold rather than “improving” it. The specification notes inherited tools rather than a local `tools` field, so this example teaches scope control through instructions as well as tool declarations.

When extending the checker, add an explicit class, exclusions, report counting rule, and fixture that distinguishes it from prose polishing. Validate on the sample document: only the three allowed classes should change, exceptions should remain, and the report must retain all three sections.