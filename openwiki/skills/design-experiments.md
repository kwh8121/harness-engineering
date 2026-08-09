---
type: design guide
title: Skill design experiments
description: Maps six chapter 5 skill-design contracts while distinguishing tracked routing definitions from README-declared fixtures and dry-run results that are absent.
tags: [skills, agents, experiments]
---

# Skill design experiments

These six chapter 5 directories are related design studies, not one executable system. Across `ex-05-05`, `05-06`, `05-08`, `05-09`, `05-10`, and `05-12`, the tracked evidence is their README, `CLAUDE.md`, and one or more agent or skill definitions. Their READMEs refer to result, fixture, trace, comparison, and checklist trees that are **not checked in**. Therefore a defined heuristic or router is inspectable; a claimed diagnosis, repeated trial, before/after result, or extension artifact is not runnable evidence in this checkout.

| Exercise | Tracked canonical contract | README-declared but absent evidence |
|---|---|---|
| `ex-05-05-separation-signals` | `skill-size-auditor` defines three signals: 500+ lines, multiple domain branches, and long conditional detail; it emits evidence and a split recommendation. | Sample SKILL.md fixtures, diagnosis reports, post-split samples, and diff summary. |
| `ex-05-06-domain-references` | `sql-query/SKILL.md` routes revenue requests to `references/finance.md`, inventory requests to `references/inventory.md`, and leaves simple SELECT local. | Quote, Mermaid diagram, invocation traces, marketing extension, and checklist. |
| `ex-05-08-generalization` | Two `column-normalizer` contracts contrast exact `Q4 매출` matching with keywords for sales, amount, or quantity. | Seven-column input, repeated results CSV, and analysis. |
| `ex-05-09-context-savings` | `prose-pruner` classifies general knowledge, missing domain convention, and long prose, then recommends delete/add/compress. | Principles note, verbose sample, diagnosis, pruned result, conversion, and diff summary. |
| `ex-05-10-book-writer-skill` | `mini-multi-mode/SKILL.md` routes README, changelog, and PR-body requests to three tracked workflow recipes. | Book-writer frontmatter comparisons, mode table, repository audit, and checklist. |
| `ex-05-12-antipatterns` | `antipattern-detector` applies bloat, missing-references, and no-rationale rules and assigns low/med/high severity. | Crafted samples, diagnoses, severity guide, cross-reference, and checklist. |

## Design seams that are actually present

The router/reference pattern in `sql-query` is the clearest extension seam: add a new domain reference and one conditional route while keeping unrelated recipes unloaded. The mini multi-mode skill has the same three-layer shape: its short router selects one focused workflow file. The two normalizer variants demonstrate the trade-off between a precise literal match and bounded keyword generalization; neither proves accuracy against an absent dataset.

The auditor and anti-pattern detector are static heuristics. Their thresholds and keyword rules are implementation details of the teaching contracts, not universal quality measurements. The more operational, tested review path is [SKILL.md reviewer and metric collector](reviewing-skill-md.md), which combines measured metrics with direct inspection.

## Safe changes and validation

Preserve each tool's declared output boundary and explain any threshold change in the agent contract. Validate a router change by reading the new reference, its route condition, and the existing two routes; no tracked trace suite can prove conditional loading. Do not claim a fixture diagnosis, a 42-row experiment, a marketing extension, or a before/after pruning result unless those absent artifacts are restored and tested.
