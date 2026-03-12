---
name: rnd-verification
description: "Use when independently verifying built work against pre-registered criteria — information-barrier verification with evidence-based verdicts and failure mode analysis"
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

## Two-Stage Evaluation

Evaluate criteria in two stages, in order:

**Stage 1 — Correctness tier:** Verify all criteria tagged as Correctness. These are must-pass criteria: functional requirements, test passing, contract conformance.

**Stage 2 — Quality tier:** Verify all criteria tagged as Quality. These are should-pass criteria: code quality, naming conventions, patterns, documentation.

**Tier interaction rules:**
- If ANY Correctness criterion fails: overall verdict is FAIL or NEEDS ITERATION (Quality results are irrelevant to the overall verdict).
- If ALL Correctness criteria pass AND any Quality criterion fails: overall verdict is `PASS (quality: NEEDS ITERATION)`. Quality failures do NOT block a PASS on Correctness — they produce NEEDS ITERATION on the quality tier only.
- If ALL criteria (both tiers) pass: overall verdict is PASS.

**Tiered Verdict Table:**

| Correctness | Quality | Overall Verdict |
|-------------|---------|-----------------|
| All PASS | All PASS | PASS |
| All PASS | Any FAIL | PASS (quality: NEEDS ITERATION) |
| Any FAIL (fixable) | Any | NEEDS ITERATION |
| Any FAIL (unfixable) | Any | FAIL |

## Process

### 1. Read the Pre-Registration

Understand the intent, approach, and success criteria. These are your ONLY reference for what "correct" means.

### 2. Read the Code and Tests

Read the Builder's code and tests. Do NOT read any self-assessment files.

### 3. Verify Each Criterion (Correctness tier first, then Quality tier)

For EACH success criterion:

**a. Test Adequacy**
Do the provided tests actually test this criterion, or just something vaguely related?

**b. Run Tests**
Execute the test suite. Record results verbatim.

**c. Failure Mode Analysis**
Identify likely failure modes through code inspection:
- Boundary/edge cases, off-by-one errors
- Error handling, unhappy paths
- Race conditions, concurrency issues
- Security issues (injection, auth bypass, data leaks)
- Performance under load (if performance criteria exist)
- External contract conformance (if the pre-registration lists external dependencies: independently query the external system — DB schema, API endpoint, file, env var — and compare the actual contract against what the code assumes; tests that mock external systems may pass with wrong assumptions)

Before writing any verdict, also scan your own reasoning for known verification anti-patterns. The `rnd-framework:rnd-failure-modes` skill catalogs these failure modes (premature satisfaction, trusting agent reports, incomplete verification, and others) along with red-flag phrases to watch for.

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

Return the following report as your text output to the orchestrator:

```markdown
# Verification Report: T<id>

## Per-Criterion Results

### Correctness Tier
- [PASS] [exact criterion text] — [evidence]
- [FAIL] [exact criterion text] — [evidence]

### Quality Tier
- [PASS] [exact criterion text] — [evidence]
- [FAIL] [exact criterion text] — [evidence]

## Overall Verdict: PASS | PASS (quality: NEEDS ITERATION) | NEEDS ITERATION | FAIL

## Feedback (if not PASS)
[Specific, actionable description of WHAT is wrong and WHAT evidence shows it.
Do NOT suggest a fix. The Builder must reason about solutions independently.]
```

## Verdict Guidelines

A criterion is binary: met or not met. There is no "partially met" or "met in spirit".

- **PASS:** ALL criteria (both tiers) met with reproducible evidence. Failure mode analysis reveals no issues. Code follows declared approach. No deviations, no caveats, no "should be fine".
- **PASS (quality: NEEDS ITERATION):** All Correctness criteria met, but one or more Quality criteria are unmet. Quality failures do NOT block a PASS on Correctness — they produce NEEDS ITERATION on the quality tier only. Integration proceeds, but quality feedback is flagged for a non-blocking iteration round.
- **NEEDS ITERATION:** Any Correctness criterion unmet, AND the failure has a clear, isolated fix path. This is NOT a soft pass — it is a scoped FAIL with a clear fix path.
- **FAIL:** Any Correctness criterion unmet without a clear fix path. Any deviation from declared approach. Any case where failure mode analysis reveals unhandled failure modes.

**When in doubt between NEEDS ITERATION and FAIL (for Correctness criteria), choose FAIL.** False negatives (rejecting good work) are recoverable. False positives (passing broken work) compound downstream.

## Evidence Standards

What counts as evidence for a criterion:

- **Necessary:** Test output you ran yourself (not claimed by Builder). Code inspection with specific line references.
- **Strong:** Failure mode analysis that actively probed the criterion and revealed no issues.
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
| "This clearly works, no need for failure mode analysis" | If it clearly works, failure mode analysis will confirm that quickly. Inspect it. |
| "I already checked similar code before" | Each criterion gets fresh evidence. Prior checks don't transfer. |
| "I'll catch the rest next round" | There is no next round for free. Every incomplete report burns an entire build-verify iteration cycle. Report ALL findings NOW. |

## Multi-Judge Mode

The orchestrator may spawn two verifier agents in parallel and use a tiebreaker when they disagree. This section defines how to behave in each role.

### Regular Judge

When you are spawned as one of two parallel judges:

- Produce your verification report **independently**, following the standard Process above from start to finish.
- You have **no knowledge of the other judge** — their findings, verdicts, or reasoning. Do not speculate about what they will find.
- The information barrier applies in full: you MUST NOT read self-assessment files, even in multi-judge mode.
- Return your report as text output (the orchestrator will distinguish reports by agent identity and save them).

### Tiebreaker

When the two regular-judge verdicts disagree and you are spawned as the tiebreaker:

- You will receive **both prior verification reports** as input.
- Your task is to issue a **final verdict** (PASS, FAIL, or NEEDS ITERATION) for the task.
- You must **justify your decision by citing specific evidence from both reports** — which findings you find convincing, which you find unpersuasive, and why.
- You are not re-running the full verification from scratch; you are adjudicating between two completed independent assessments. However, you may inspect code or run tests to resolve a specific factual dispute if needed.
- **The information barrier still applies:** even as tiebreaker, you MUST NOT read any `$RND_DIR/builds/T<id>-self-assessment.md` file. The two judge reports are the only Builder-adjacent material you receive beyond the pre-registration and artifacts.
- Return your tiebreaker report as text output (the orchestrator saves it to `$RND_DIR/verifications/T<id>-tiebreaker.md`).

## Related Skills

- `rnd-framework:rnd-failure-modes` — Catalog of verification anti-patterns and red-flag phrases; scan before writing any verdict
- `rnd-framework:rnd-debugging` — For root cause analysis of failures found during verification
- `rnd-framework:rnd-iteration` — For how feedback flows back to Builder
