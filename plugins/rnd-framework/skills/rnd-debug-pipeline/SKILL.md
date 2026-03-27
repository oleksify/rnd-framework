---
name: rnd-debug-pipeline
description: "Use when running the debug pipeline for a reported bug — defines the 4-phase flow, diagnosis report format, escalation criteria, and Builder handoff"
user-invocable: false
effort: medium
---

# R&D Debug Pipeline

## Overview

The debug pipeline is a focused workflow for fixing isolated bugs without a full `/start` decomposition. A dedicated debugger diagnoses the bug and hands off a structured report to the Builder — the Builder fixes without re-investigating.

**Core principle:** Diagnosis and fix are separate roles. The Builder receives a complete diagnosis report; they do not re-investigate the root cause.

## When to Use

- A specific bug has been reported and is reproducible
- The bug is isolated (1-2 files, not a design flaw)
- A full `/start` pipeline is unnecessary overhead

## Pipeline Phases

### Phase 1: Reproduce

Confirm the bug is real and understand the exact conditions that trigger it. Document the minimal reproduction steps. If the bug cannot be reproduced after reasonable effort, return status `CANNOT_REPRODUCE`.

### Phase 2: Diagnose

Apply `rnd-framework:rnd-debugging` methodology to find root cause. Produce the diagnosis report (format below) saved to `$RND_DIR/diagnosis/T<id>-diagnosis.md`. Return status `DIAGNOSED` or `ESCALATE`.

### Phase 3: Fix (Builder handoff)

The Builder receives the diagnosis report and the pre-registration from the debugger. The Builder does NOT re-investigate — they implement the fix described in the report using `rnd-framework:rnd-building` discipline.

### Phase 4: Verify

An independent Verifier checks the fix against the success criteria in the pre-registration. Same process as the standard pipeline — the Verifier never sees the Builder's self-assessment.

## Diagnosis Report Format

Save to `$RND_DIR/diagnosis/T<id>-diagnosis.md`. This is the handoff artifact — the Builder reads it instead of re-investigating.

```markdown
# Diagnosis: T<id>

## Bug Description
[One sentence: what the bug is and where it manifests]

## Reproduction Steps
1. [Exact steps to trigger the bug]
2. [Include environment details if relevant]

## Root Cause Analysis
[Where the fault originates and why it causes the observed behavior]

## Affected Files
- `path/to/file.ext` — [what role this file plays in the bug]

## Recommended Fix Approach
[What to change and why — specific enough that the Builder does not need to investigate]

## Escalation Recommendation
PROCEED | ESCALATE — [one sentence reason]
```

## Escalation Criteria

Escalate to `/rnd-framework:rnd-start` instead of proceeding when ANY of the following are true:

- **3 or more files affected** — the bug is systemic, not isolated
- **Design flaw** — the root cause is an architectural decision, not a coding mistake
- **Complex reproduction** — reproduction requires multi-step environment setup that cannot be captured in a simple steps list
- **Reproduction failure** — return `CANNOT_REPRODUCE`; do not guess at a fix

When escalating, save the partial diagnosis report with `ESCALATE` in the recommendation field, then return status `ESCALATE` to the orchestrator.

## Debugger Status Codes

| Code | Meaning |
|------|---------|
| `DIAGNOSED` | Root cause found; Builder handoff ready |
| `ESCALATE` | Too complex; use `/rnd-framework:rnd-start` |
| `CANNOT_REPRODUCE` | Bug not reproducible; user clarification needed |

## Related Skills

- `rnd-framework:rnd-debugging` — Root cause methodology used in Phase 2
- `rnd-framework:rnd-building` — Builder discipline used in Phase 3
- `rnd-framework:rnd-verification` — Verifier protocol used in Phase 4
