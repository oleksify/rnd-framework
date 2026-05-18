---
id: BSH-RA1
role: reality-auditor
language: bash
tags: [anomaly, dependencies, portability]
applicable_task_types: [new-feature, infra, refactor]
scope: Probe each external command with `command -v` before declaring it a dependency; flag any that are absent from the execution environment.
specializes: [P-IMPOSSIBLE-01]
---

Specializes the impossible-states principle by demanding that every external command invocation is grounded in a confirmed runtime presence — not an assumed one.

**Good audit output:**
> `hooks/bash-gate.sh:12` invokes `jq` without verifying it is installed. Running `command -v jq` on the target CI image returns nothing — `jq` is not in PATH. The script will fail at line 12 with "command not found", silently swallowed if the caller does not check exit codes. Flag: add a startup probe (`command -v jq || { echo "jq required" >&2; exit 1; }`) or declare `jq` as a required dependency in the project's setup docs.

**Worse audit output:**
> The script uses `jq` to parse JSON. `jq` is a widely available tool so this should be fine.

**Why good is better:** "Widely available" is not a guarantee — CI images, Alpine containers, and minimal server installs routinely omit `jq`, `bc`, `column`, and other conveniences. The worse output makes an untested assumption that hides a class of environment-specific failures. The good output names the file and line, documents the probe result, and distinguishes between a startup guard (fast fail with a message) and a documentation fix. Every external command is a runtime assumption; audit it.
