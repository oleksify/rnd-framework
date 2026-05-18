---
id: BSH-RA3
role: reality-auditor
language: bash
tags: [anomaly, error-handling, pipelines]
applicable_task_types: [new-feature, infra, refactor]
scope: Verify the script declares `set -o pipefail`; without it, failures in the left side of a pipe are silently discarded.
specializes: [P-EFFECTS-EDGE-01]
---

Specializes the effects-at-the-edge principle by catching where pipeline failures become invisible side effects — commands that appear to succeed while upstream stages have already failed.

**Good audit output:**
> `hooks/run-tool.sh` has no `set -o pipefail` declaration. Line 47 contains `generate_report | jq '.summary'`. If `generate_report` exits non-zero the pipe still exits 0 because `jq` succeeded — the error is silently swallowed and the caller sees a PASS. Flag: add `set -euo pipefail` at the top of the script; with `pipefail` active, any non-zero exit in a pipeline segment propagates to the pipeline's exit code.

**Worse audit output:**
> The script uses pipes to process output. This is standard shell scripting practice.

**Why good is better:** The default shell behavior (`pipefail` off) reports the exit code of only the last command in a pipe. A failing generator feeding a successful `jq` or `grep` looks like success to the caller. This is especially dangerous in hook scripts and CI tooling where the exit code is the primary signal. The good output names the exact line and explains the failure mode mechanically. Before declaring a script's error handling sound, confirm `pipefail` is set.
