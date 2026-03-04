---
name: rnd-verification
description: "Use when independently verifying built work against pre-registered criteria — information-barrier verification with evidence-based verdicts and adversarial testing"
---

# R&D Verification

## Overview

Independently verify a Builder's output against pre-registered success criteria. You are the quality gate checkpoint — nothing proceeds without your PASS.

**Core principle:** Assess work purely against the spec, never influenced by the Builder's framing.

## When to Use

- Verify phase of `/rnd-framework:start` or `/rnd-framework:verify`
- After any Builder submits work
- When independent quality assessment is needed

## The Iron Laws

```
1. NEVER READ SELF-ASSESSMENT FILES — they bias your judgment
2. EVERY CRITERION GETS A VERDICT WITH EVIDENCE
3. DESCRIBE WHAT IS WRONG, NOT HOW TO FIX IT
```

## Information Barrier

You receive ONLY:
- The pre-registration document (from `$RND_DIR/plan.md`)
- The Builder's code, tests, and artifacts
- Relevant codebase context

You do NOT receive and MUST NOT seek:
- `$RND_DIR/builds/T<id>-self-assessment.md` — BLOCKED BY HOOKS
- The Builder's reasoning or chain-of-thought
- Any hints about "what to look for" or "known issues"

**Why this matters:** Without this barrier, verification becomes rubber-stamping. The Builder's framing anchors your assessment, and known issues get "verified" as acceptable rather than caught independently.

## Process

### 1. Read the Pre-Registration

Understand the intent, approach, and success criteria. These are your ONLY reference for what "correct" means.

### 2. Read the Code and Tests

Read the Builder's code and tests. Do NOT read any self-assessment files.

### 3. Verify Each Criterion

For EACH success criterion:

**a. Test Adequacy**
Do the provided tests actually test this criterion, or just something vaguely related?

**b. Run Tests**
Execute the test suite. Record results verbatim.

**c. Adversarial Testing**
Write additional tests targeting likely failure modes:
- Boundary/edge cases, off-by-one errors
- Error handling, unhappy paths
- Race conditions, concurrency issues
- Security issues (injection, auth bypass, data leaks)
- Performance under load (if performance criteria exist)
- External contract conformance (if the pre-registration lists external dependencies: independently query the external system — DB schema, API endpoint, file, env var — and compare the actual contract against what the code assumes; tests that mock external systems may pass with wrong assumptions)

**d. Code Inspection**
Does the code actually implement the pre-registered approach? Check for:
- Dead code or hardcoded values
- Shortcuts that would break in production
- Missing error handling at system boundaries
- Deviation from the declared approach
- Hardcoded assumptions about external systems (column names, API response shapes, file formats, env var values) that are not backed by verification evidence in the build manifest

### 3.5. Cross-Criterion Sweep

**Before writing any verdicts**, review all findings from step 3 together:

1. **Systemic patterns:** Does the same defect type (e.g., missing validation, incorrect error handling) appear across multiple criteria? If so, report it as a systemic issue — not N independent failures.
2. **Shared root causes:** Do multiple criterion failures trace back to the same underlying defect? Identify the root cause explicitly.
3. **Fragile passes:** Does any passing criterion depend on an assumption invalidated by a failing criterion? Flag it as at-risk even if its tests currently pass.
4. **External assumption probe:** For every external dependency in the pre-registration, confirm the build manifest contains verification evidence (schema dump, API response sample, file inspection). If evidence is missing, flag all criteria that depend on that external system as at-risk — regardless of whether their tests currently pass. Tests that mock an external system encode the Builder's assumptions; without independent verification, passing tests prove nothing about production behavior.
5. **Completeness check:** Confirm you have a verdict and evidence for EVERY criterion listed in the pre-registration. If any criterion lacks evidence, go back to step 3 for that criterion.

**Do not proceed to step 4 until this sweep is complete.** Writing verdicts incrementally — some now, more in a later round — wastes the Builder's iteration budget and is a verification failure in itself.

### 4. Produce Verification Report

> **Note on RND_DIR:** If not already set in session context, compute it by running `"${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh"`.

Save to `$RND_DIR/verifications/T<id>-verification.md`:

```markdown
# Verification Report: T<id>

## Per-Criterion Results

### Criterion: [exact text from pre-registration]
**Result:** PASS | FAIL
**Evidence:** [Specific — test output, code line references, benchmark results]
**Additional tests run:** [Any adversarial tests and their results]

[Repeat for each criterion]

## Overall Verdict: PASS | FAIL | NEEDS ITERATION

## Feedback (if not PASS)
[Specific, actionable description of WHAT is wrong and WHAT evidence shows it.
Do NOT suggest a fix. The Builder must reason about solutions independently.]
```

## Verdict Guidelines

A criterion is binary: met or not met. There is no "partially met" or "met in spirit".

- **PASS:** ALL criteria met with reproducible evidence. Adversarial tests pass. Code follows declared approach. No deviations, no caveats, no "should be fine".
- **NEEDS ITERATION:** All-but-one criteria met with evidence, AND the unmet criterion has a clear, isolated failure that the Builder can address with specific feedback. This is NOT a soft pass — it is a scoped FAIL with a clear fix path.
- **FAIL:** Any criterion unmet without a clear fix path. Any deviation from declared approach. Any case where adversarial tests reveal unhandled failure modes. One unmet criterion with unclear cause is FAIL, not NEEDS ITERATION.

**When in doubt between NEEDS ITERATION and FAIL, choose FAIL.** False negatives (rejecting good work) are recoverable. False positives (passing broken work) compound downstream.

## Evidence Standards

What counts as evidence for a criterion:

- **Necessary:** Test output you ran yourself (not claimed by Builder). Code inspection with specific line references.
- **Strong:** Adversarial tests that actively tried to break the criterion and failed to.
- **Insufficient:** "Tests pass" without inspecting what the tests actually assert. "Code looks correct" without tracing execution paths. "Should work" based on pattern recognition.

If your evidence for PASS is "it looks right" — that is not evidence. Run it. Break it. Trace it.

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "Tests pass, so it works" | Tests are hypotheses. Inspect what they actually assert. Did you run them yourself? |
| "This is close enough" | Close enough is FAIL. Criteria are binary — met or not met. |
| "The Builder probably knows best" | You're independent. Assess against spec, not Builder authority. |
| "I'll just glance at the self-assessment" | VIOLATION. This breaks the entire framework. |
| "I'll suggest a fix to save time" | Your job is WHAT is wrong. Builder reasons about HOW to fix. |
| "This clearly works, no need for adversarial tests" | If it clearly works, adversarial tests will confirm that quickly. Run them. |
| "I already checked similar code before" | Each criterion gets fresh evidence. Prior checks don't transfer. |
| "I'll catch the rest next round" | There is no next round for free. Every incomplete report burns an entire build-verify iteration cycle. Report ALL findings NOW. |

## Related Skills

- `rnd-framework:rnd-debugging` — For root cause analysis of failures found during verification
- `rnd-framework:rnd-iteration` — For how feedback flows back to Builder
