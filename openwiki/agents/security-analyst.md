---
type: agent specification
title: Read-only security analyst
description: Documents a read-only OWASP and CWE-oriented security-analysis agent and its intentionally vulnerable Flask fixture.
tags: [security, agents, flask]
---

# Read-only security analyst

`ex-04-01-security-analyst/.claude/agents/security-analyst.md` is a review-only agent. Its permitted tools are `Read`, `Grep`, `Glob`, and `Bash`; its instructions restrict Bash to read-only inspection. It reports location, explanation, remediation, severity (`Critical` through `Low`), and preferably an OWASP Top 10/CWE mapping. It must not modify source.

The agent's upstream input is a target codebase; its downstream product is a report, documented by the example README as `result/security-report.md`. Use `claude --agent security-analyst "sample-app/ 의 보안 취약점을 분석하라"` to exercise the intended invocation when Claude Code is available.

## Fixture evidence

`sample-app/app.py` and `db.py` are **deliberately insecure and must not be deployed**. `app.py` exposes hard-coded `SECRET_KEY` and DB password, interpolates request values into login and registration SQL, hashes passwords with MD5, concatenates unescaped profile HTML into `render_template_string`, exposes arbitrary user IDs without authorization, and starts Flask with `debug=True` on all interfaces. `db.py` demonstrates plaintext password flow into a helper but uses a local SQLite connection.

The teaching invariant is evidence-based reporting, not automatic repair: each finding should cite source location and avoid claiming that the fixture is production code. A remediation recommendation may say parameterized query, password hashing, output escaping, authentication/authorization, or secure configuration, but the agent's tool boundary prevents it from applying those changes. Concretely, both SQL paths need parameter binding; password storage needs a credential hashing scheme with registration/login verification; bio must not be concatenated into a template; and user retrieval needs an identity/ownership policy. The ignored `get_connection` password argument, local `app.db` lifecycle, hardcoded configuration, and public debug runtime also need an explicit production design.

## Change and validation

If adding a vulnerability class, update agent scope, report schema, and a corresponding intentional fixture. Do not add `Write` or `Edit` merely to save a report; that changes the read-only demonstration. Focused validation is an agent run against `sample-app/`, checking that reported findings are grounded in the named lines and that the source tree remains unchanged.