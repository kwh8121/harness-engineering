---
type: extension guide
title: OpenWiki authoring and connector skills
description: Documents the root Mermaid diagram and connector-authoring skills, including their invocation boundaries and security contracts.
tags: [openwiki, extensions, mermaid]
---

# OpenWiki authoring and connector skills

The root `skills/` directory contains reusable OpenWiki instructions, not repository application code. Use `mermaid-diagrams/SKILL.md` when documentation explains a real runtime/request flow, lifecycle/state machine, data model, or non-trivial control flow. It requires every participant and edge to be source-grounded; chooses sequence/state/ER/flowchart syntax by purpose; requires a caption; and gives parser-safe label rules. A malformed diagram is stale documentation: repair any `openwiki: mermaid parse failed` degradation instead of preserving it.

Use `write-connector/SKILL.md` only when asked to add a built-in OpenWiki source connector. Its target is the OpenWiki OSS source layout: add types and registry entries, implement `src/connectors/sources/<connector>.ts`, expose `ConnectorRuntime` metadata and `ingest()`, and add tests. It is not a plugin marketplace or arbitrary runtime loader.

## Connector contract and security

Connector raw data belongs below `~/.openwiki/connectors/<id>/raw/<run-id>/`; state and config are `state.json` and `config.json` in the same connector directory; secrets are referenced by environment-variable name from `~/.openwiki/.env`. Never read, return, log, hardcode, or store secret values in config, raw data, state, logs, or tests. Validate IDs and paths to prevent escaping the connector directory. Credentialed fetching must be deterministic; MCP wrapping is read-only and allowlisted; untrusted manifests must not launch arbitrary commands/endpoints.

Ingestion should retain provenance, pagination/cursor state, metadata/content hashes, and compact manifests for local repositories. Finish a connector change by naming changed files, required env names, config steps, provider permissions, and `openwiki personal --update` invocation. Validate registration, path containment, secret non-disclosure, and a focused ingestion test.