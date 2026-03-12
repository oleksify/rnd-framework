---
name: rnd-debugging
description: "Use when encountering any bug, test failure, or unexpected behavior within the R&D pipeline — systematic root cause analysis before proposing fixes"
---

# R&D Debugging

## Overview

Random fixes waste time and create new bugs. Quick patches mask underlying issues.

**Core principle:** ALWAYS find root cause before attempting fixes. Symptom fixes are failure.

## When to Use

- Any test failure during build or verification phases
- Unexpected behavior during integration
- Bugs found by the Verifier's failure mode analysis
- Performance issues discovered during system validation

## The Iron Law

```
NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST
```

If you haven't completed Phase 1, you cannot propose fixes.

## The Four Phases

### Phase 1: Root Cause Investigation

BEFORE attempting ANY fix:

1. **Read error messages carefully** — Stack traces, line numbers, error codes. Don't skip.
2. **Reproduce consistently** — Can you trigger it reliably? What are the exact steps?
3. **Check recent changes** — Git diff, recent commits, new dependencies
4. **Trace data flow** — Where does the bad value originate? Trace backward through the call stack.
5. **Gather evidence in multi-component systems** — Log what enters/exits each component boundary. Run once to see WHERE it breaks.

### Phase 2: Pattern Analysis

1. **Find working examples** — Similar working code in the same codebase
2. **Compare against references** — Read reference implementations COMPLETELY
3. **Identify differences** — List every difference, however small
4. **Understand dependencies** — What settings, config, environment does this need?

### Phase 3: Hypothesis and Testing

1. **Form single hypothesis** — "I think X is the root cause because Y"
2. **Test minimally** — SMALLEST possible change to test the hypothesis
3. **One variable at a time** — Don't fix multiple things at once
4. **Verify before continuing** — Worked? -> Phase 4. Didn't? -> New hypothesis.

### Phase 4: Implementation

1. **Write failing test** reproducing the bug (use `rnd-framework:rnd-building` methodology)
2. **Implement single fix** addressing the root cause
3. **Verify** — Test passes? Other tests still pass? Issue resolved?
4. **If 3+ fixes failed** — STOP. Question the architecture. Three failed fixes is evidence of a design problem, not bad luck. Escalate to re-planning.

## Iteration Budget in R&D Context

Within the R&D pipeline:
- Max 3 build-verify cycles per task
- If debugging exceeds 3 attempts -> escalate to re-planning
- Report to orchestrator: "Task T<id> may need re-decomposition"

## Red Flags — STOP and Follow Process

- "Quick fix for now, investigate later"
- "Just try changing X and see"
- "I don't fully understand but this might work"
- Proposing solutions before tracing data flow
- "One more fix attempt" (when already tried 2+)

**ALL of these mean: STOP. Return to Phase 1.**

## Related Skills

- `rnd-framework:rnd-building` — For writing the failing test (Phase 4)
- `rnd-framework:rnd-iteration` — For feedback loop management
- `rnd-framework:rnd-verification` — Verifier's perspective on failures
