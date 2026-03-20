---
name: rnd-integration
description: "Use when merging verified task outputs and running integration/system validation — ensures component-level PASS translates to system-level correctness"
user-invocable: false
effort: medium
---

# R&D Integration

## Overview

After all tasks in an execution wave pass their quality gates (Verifier PASS), merge the outputs and validate they work together. Component PASS does not guarantee system PASS.

**Core principle:** Never skip integration testing. Verified components can still fail as a system.

## When to Use

- Integration phase of `/rnd-framework:start` or `/rnd-framework:integrate`
- After all tasks in a wave have PASS verdicts
- For final wave: full system validation against original requirements

## Process

### 1. Confirm All Tasks Verified

> **Note on RND_DIR:** If not already set in session context, compute it by running `"${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh"`.

Check `$RND_DIR/verifications/` for PASS verdicts on every task in the current wave. If any task is not verified, STOP.

### 2. Merge Outputs

Ensure all code from the wave integrates cleanly:
- No merge conflicts or duplicate definitions
- Interfaces match across modules
- Imports and dependencies are correct

### 3. Run Integration Tests

- Do the modules communicate correctly?
- Are API contracts honored across boundaries?
- Do data flows work end-to-end?

### 4. System Validation (final wave only)

- Does the feature work end-to-end per the original task?
- Are all original acceptance criteria met?
- Are there regressions in existing functionality?

### 5. Produce Integration Report

Save to `$RND_DIR/integration/wave-<N>-report.md`:

```markdown
# Integration Report: Wave <N>

## Tasks Merged
- T<id>: [name] — Verified

## Integration Test Results
- [test]: PASS | FAIL — [detail]

## System Validation (final wave only)
- [original criterion]: PASS | FAIL — [detail]

## Regressions
- [none found | list any]

## Verdict: SHIP | NO-SHIP

## If NO-SHIP:
[Which integration points failed and which tasks they trace back to]
```

## Rules

- Never skip integration testing even if individual tasks all passed
- If NO-SHIP, identify root cause: task-level failure (route to Builder) or architectural issue (escalate to Planner)
- Run the existing project test suite to check for regressions

## Related Skills

- `rnd-framework:rnd-orchestration` — Pipeline overview
- `rnd-framework:rnd-verification` — How tasks get PASS verdicts
- `rnd-framework:rnd-scheduling` — Wave execution order
