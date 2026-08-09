---
type: executable skill
title: SKILL.md reviewer and metric collector
description: Reviews a SKILL.md using measured structural metrics and a four-category checklist, with a focused shell test for collector output.
tags: [skills, testing, shell]
---

# SKILL.md reviewer and metric collector

`ex-05-13-skill-md-reviewer` synthesizes chapter 5 criteria into `reviewing-skill-md`. The skill invokes `scripts/collect-metrics.sh <SKILL.md>`, reads `references/checklist.md`, then assigns pass/warn/fail across frontmatter/discovery, structure/content, size/separation, and anti-pattern categories. It produces an overall high/med/low/pass assessment and top three improvements; the bundled reports review `sql-query`, `csv-summary`, and `pr-review-orchestrator`.

## Collector contract

`collect-metrics.sh` requires exactly one existing file and exits nonzero otherwise. It emits, in a stable textual sequence, `line_count`, `word_count`, `frontmatter_chars`, `name_value`, `description_value`, `branch_keyword_count`, `imperative_count`, `reason_count`, `dot_block_count`, `has_references_dir`, and a multi-line `headers:` block. The block contains indented level-two headings or `  (none)`. It extracts only the first delimiter-bounded frontmatter block, uses `awk '/^---\r?$/'`, and strips trailing carriage returns from name/description. Keyword count pipelines end in `|| true` because a zero-match `grep` would otherwise make `set -euo pipefail` abort; zero matches therefore serialize as `0`. A CRLF fixture exists at `scripts/tests/fixture-sample-SKILL-crlf.md`.

The focused test is `bash .claude/skills/reviewing-skill-md/scripts/tests/test-collect-metrics.sh`. It exercises only `fixture-sample-SKILL.md` (the LF fixture), asserting exact counts, fields, headers, and computed frontmatter character count. It **does not invoke the CRLF fixture**. Therefore CRLF support is implementation/fixture evidence, not currently test-proved behavior.

## Safe changes

Metric key names are a consumer contract for review reports and the test. When adding a metric, retain existing output and test both an ordinary fixture and—currently missing—an explicit CRLF invocation. Avoid hardcoding secrets or treating metrics as quality conclusions; the skill intentionally combines measurements with direct file review.