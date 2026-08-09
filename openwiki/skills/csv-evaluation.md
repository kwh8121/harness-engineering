---
type: executable example
title: CSV skill evaluation
description: Documents the With/Without comparison exercise and the standard-library CSV summary implementation it invokes.
tags: [skills, csv, evaluation]
---

# CSV skill evaluation

`ex-05-11-with-without` describes a `csv-summary` skill-assisted result versus an unassisted result along pass rate, duration, and estimated token count. Its README names `bash result/bin/run-both.sh`, `fixtures/sample.csv`, and comparison outputs, but the inspected exercise tree contains neither `fixtures/` nor `result/`; treat the comparison/orchestrator as unavailable captured-artifact evidence. Token totals are described as stub estimates, not model telemetry.

The directly executable implementation is `.claude/skills/csv-summary/bin/run.sh <csv_path> <out_md>`. It runs embedded Python with the standard library and writes Markdown.

## Data contract

It reads all `csv.DictReader` rows. The header list is empty for an empty file; otherwise it emits row and column counts, a dtype table, and a statistics table. A column is numeric when every **non-empty** cell converts with `float`; empty values are ignored in both inference and numeric-statistic input. Numeric values get mean, median, and `statistics.pstdev`—population, not sample, standard deviation—rounded to two decimals.

If and only if both `department` and `salary` headers exist, it groups every row by department, converts each salary with `float`, sorts department names, and writes average salary and count. Thus missing grouping headers skip that section; an empty salary in a present grouping would fail conversion rather than being skipped. The script writes only the requested output path and prints `wrote <path>`.

## Change and validation

Keep CLI positional arguments and Markdown headings/tables stable for the claimed comparison artifacts. If changing numeric or blank-cell policy, add a fixture that covers mixed text, blanks, and grouping. There is no tracked input fixture to run today; create a temporary CSV and run `bash .claude/skills/csv-summary/bin/run.sh <csv_path> /tmp/csv-summary.md`, then inspect dtype, population deviation, and department table. Treat the With/Without comparison as an experiment description, not a general benchmark.