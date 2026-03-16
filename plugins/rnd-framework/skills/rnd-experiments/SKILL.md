---
name: rnd-experiments
description: "Use when independently verifying built work — defines how verifiers write experiment tests from the spec alone before reading Builder code, preventing false PASSes through mandatory independent validation"
user-invocable: false
allowed-tools: [Read, Write, Bash, Grep, Glob]
---

# R&D Experiments

## Overview

Experiments are independent tests written by the Verifier from the pre-registration spec alone — before reading the Builder's code or tests. They shift verification from "does this look right?" to "does this actually work?" by producing evidence that cannot be anchored to the Builder's implementation choices.

**Core principle:** Derive tests from the spec, not from what the Builder built. If your test logic mirrors the Builder's test logic, you haven't independently verified anything — you've just confirmed the Builder was internally consistent.

## When to Use

- Step 2 of the verification process (before reading Builder code)
- Any time a success criterion requires observable behavior that can be executed
- Mandatory for every criterion in the pre-registration — experiments are not on-demand

## The Iron Law

```
EXPERIMENTS ARE MANDATORY FOR EVERY CRITERION — NOT OPTIONAL, NOT ON-DEMAND
```

If the pre-registration lists N criteria, the Verifier writes N experiments. Skipping an experiment for a criterion — because it "looks simple" or "is obviously met" — is a verification failure. The point is to produce independent evidence, not to confirm what already seems true.

## What Makes Experiments Different from Builder Tests

| Dimension | Builder Tests | Verifier Experiments |
|-----------|--------------|---------------------|
| Source of truth | Builder's understanding of the spec | Pre-registration spec text only |
| When written | Before or during implementation | Before reading Builder's code |
| What they prove | Implementation is internally consistent | Implementation meets the declared spec |
| Who writes them | Builder agent | Verifier agent |
| Allowed to read | Anything | Only the pre-registration and external systems |

The distinction matters because a Builder can write tests that pass while implementing the wrong thing. If the Verifier derives tests from the same source as the Builder, the Verifier will reproduce the Builder's blind spots.

**The information barrier:** When writing experiments, the Verifier MUST NOT have read the Builder's test files. Reading them first anchors your experiment logic to the Builder's framing. Write experiments first, then run Builder tests in Step 4.

## Output Directory

Save all experiment files to:

```
$RND_DIR/verifications/T<id>-experiments/
```

Example: `$RND_DIR/verifications/T3-experiments/`

**Multi-judge mode:** When operating as one of two parallel judges, the orchestrator passes your judge identity (`judge-a`, `judge-b`, or `tiebreaker`) in the prompt. Use a subdirectory to avoid path collisions:

```
$RND_DIR/verifications/T<id>-experiments/<judge-id>/
```

Example: `$RND_DIR/verifications/T3-experiments/judge-a/`

If no judge identity is provided (single-verifier mode), use the flat path.

Create this directory before writing any experiment files:

```bash
mkdir -p "$RND_DIR/verifications/T<id>-experiments"
# or in multi-judge mode:
mkdir -p "$RND_DIR/verifications/T<id>-experiments/<judge-id>"
```

## Naming Convention

Name experiment files after the criterion they test, using kebab-case:

```
exp-<criterion-slug>.test.<ext>
```

Examples:
- `exp-file-exists-at-declared-path.test.ts`
- `exp-frontmatter-contains-name-field.test.ts`
- `exp-output-directory-is-created.test.ts`
- `exp-returns-401-for-expired-token.test.ts`

Use the same file extension and test runner as the project's existing test suite. One experiment file per criterion. Do not bundle multiple criteria into one file — if an experiment fails, you need to know exactly which criterion it covers.

## What Makes a Good Experiment

A good experiment:

1. **Is derived from the spec text alone.** Read the criterion. Write a test that checks the criterion's stated observable outcome. Do not look at the implementation first.
2. **Has exactly one assertion.** One experiment, one criterion. If you find yourself writing `expect A` and `expect B` in the same test, split it.
3. **Uses real execution, not inspection.** Run the code. Do not read the source and reason about what it probably does. Observable behavior is evidence; source analysis is interpretation.
4. **Tests the boundary, not the happy path only.** If the criterion says "returns 401 for expired tokens," also test that valid tokens are not rejected. Boundary cases reveal implementation shortcuts.
5. **Is independent of Builder test infrastructure.** Do not import helpers, fixtures, or test utilities written by the Builder. Write your own setup — or use the project's production code directly.

## Experiment Template

```typescript
// exp-<criterion-slug>.test.ts
// Criterion: <exact criterion text from pre-registration>
// Spec source: T<id> pre-registration, <Correctness|Quality> tier

import { describe, test, expect } from "bun:test";
// Import only production code, not Builder test helpers

describe("T<id>: <criterion text>", () => {
  test("<observable outcome — what should happen>", async () => {
    // Arrange: set up the minimum conditions from the spec
    // Act: invoke the behavior the criterion describes
    // Assert: check the observable outcome stated in the criterion
    expect(result).toBe(expectedValue);
  });

  // If the criterion implies a boundary or negative case, add it here
  test("<boundary case — what should NOT happen or edge input>", async () => {
    // ...
  });
});
```

Adapt the test runner imports to the project's conventions (Bun, Jest, Vitest, etc.).

## Process: Writing Experiments

For each criterion in the pre-registration:

1. **Read only the criterion text.** Do not look at Builder files yet.
2. **Identify the observable outcome.** What can be measured or asserted from outside the implementation?
3. **Identify the minimal setup.** What inputs, files, or state does the criterion require to be exercised?
4. **Write the experiment** following the template above.
5. **Identify one boundary or negative case** — what input or condition should produce a different outcome?
6. **Save to `$RND_DIR/verifications/T<id>-experiments/`** with the naming convention above.

After writing all experiments (one per criterion), proceed to Step 3 of the verification process: run experiments against the Builder's code.

## Recording Experiment Results

When running experiments in Step 3, record the output verbatim in the verification report. Do not paraphrase. The raw output is the evidence.

If an experiment fails, this is a Correctness-tier finding — the implementation did not satisfy the spec as the experiment interpreted it. If the experiment itself was wrong (e.g., misread the criterion), fix the experiment and note the correction, but do not delete it. The correction is part of the evidence trail.

## Related Skills

- `rnd-framework:rnd-verification` — Full 6-step verification process; experiments are Step 2 and Step 3
- `rnd-framework:rnd-failure-modes` — Failure modes that experiments are designed to catch (Premature Satisfaction, Trusting Agent Reports)
- `rnd-framework:rnd-iteration` — What happens when experiment failures trigger NEEDS ITERATION
