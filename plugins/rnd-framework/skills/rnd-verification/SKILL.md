---
name: rnd-verification
description: "Use when independently verifying built work against pre-registered criteria — information-barrier verification with evidence-based verdicts and failure mode analysis"
user-invocable: false
allowed-tools: [Read, Write, Bash, Grep, Glob]
effort: medium
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

**Output:** A clear mental model of what the task requires, with each criterion noted separately before proceeding.

### 2. Write Independent Experiment Tests

Before reading the Builder's code or tests, write one experiment test per success criterion using the `rnd-framework:rnd-experiments` skill. Derive tests from the pre-registration spec text alone.

**CRITICAL:** You MUST NOT read Builder test files at this stage. Write experiments first, then proceed to Step 3.

For each criterion:
1. Identify the observable outcome stated in the criterion
2. Write an experiment test file to `$RND_DIR/verifications/T<id>-experiments/`
3. Name each file `exp-<criterion-slug>.test.<ext>`

**Output:** Experiment test files in `$RND_DIR/verifications/T<id>-experiments/`, one per criterion.

### 3. Run Experiments Against Builder's Code

Run the experiment files written in Step 2 against the Builder's implementation using the project's test runner. Do NOT read the Builder's test files yet.

Record the raw output verbatim. Do not paraphrase results. Each failing experiment is a Correctness-tier finding. If an experiment itself was wrong (e.g., misread the criterion), fix it, note the correction, but do not delete the original — corrections are part of the evidence trail.

**Output:** Verbatim experiment run output recorded, with each criterion's result (PASS/FAIL) noted.

### 4. Run Builder's Tests and Compare

Now read the Builder's code and tests. Run the Builder's full test suite using the project's test runner. Record results verbatim.

**Test Adequacy:** For each criterion, does the Builder's test actually test the criterion, or just something vaguely related?

Compare outcomes: if a Builder test passes but your experiment fails for the same criterion, this is a significant finding — the Builder's test may be encoding assumptions that differ from the spec.

**Output:** Builder test results recorded verbatim; divergences with experiment results identified and noted per criterion.

### 5. Code Inspection, Failure Mode Analysis, and Cross-Criterion Sweep

Before writing any verdicts, scan your own reasoning for known verification anti-patterns. The `rnd-framework:rnd-failure-modes` skill catalogs these (premature satisfaction, trusting agent reports, incomplete verification) along with red-flag phrases to watch for.

**a. Failure Mode Analysis**
Identify likely failure modes through code inspection:
- Boundary/edge cases, off-by-one errors
- Error handling, unhappy paths
- Race conditions, concurrency issues
- Security issues (injection, auth bypass, data leaks)
- Performance under load (if performance criteria exist)
- External contract conformance — independently query the external system (DB schema, API endpoint, file, env var) and compare the actual contract against what the code assumes; tests that mock external systems may pass with wrong assumptions

**b. Code Inspection**
Does the code actually implement the pre-registered approach? Check for:
- Dead code or hardcoded values
- Shortcuts that would break in production
- Missing error handling at system boundaries
- Deviation from the declared approach
- Hardcoded assumptions about external systems (column names, API response shapes, file formats, env var values) not backed by verification evidence in the build manifest
- Evidence Gathered: cross-reference the build manifest's "Evidence Gathered" section against every external contract used in code — if a contract is referenced in the code but has no citation in the manifest, treat it as an ungrounded decision, which is a Correctness-tier failure

**c. Cross-Criterion Sweep**

**Before writing any verdicts**, review all findings from steps 3-5b together:

1. **Systemic patterns:** Does the same defect type (e.g., missing validation, incorrect error handling) appear across multiple criteria? Report it as a systemic issue — not N independent failures.
2. **Shared root causes:** Do multiple criterion failures trace back to the same underlying defect? Identify the root cause explicitly.
3. **Fragile passes:** Does any passing criterion depend on an assumption invalidated by a failing criterion? Flag it as at-risk even if its tests currently pass.
4. **External assumption probe:** For every external dependency in the pre-registration, confirm the build manifest contains verification evidence (schema dump, API response sample, file inspection) in its "Evidence Gathered" section. If evidence is missing, flag all criteria that depend on that external system as at-risk — regardless of whether their tests currently pass. Tests that mock an external system encode the Builder's assumptions; without independent verification, passing tests prove nothing about production behavior.
5. **Completeness check:** Confirm you have a verdict and evidence for EVERY criterion listed in the pre-registration. If any criterion lacks evidence, return to steps 3-4 for that criterion.

**Do not proceed to Step 6 until this sweep is complete.** Writing verdicts incrementally wastes the Builder's iteration budget and is a verification failure in itself.

**Output:** All findings consolidated, systemic issues identified, every criterion has a verdict backed by evidence.

### 6. Produce Verification Report

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

## Clean Code Checklist

This checklist applies **mandatorily to shell code** and **advisorily to all other languages**. For each item, a violation indicator is an observable condition the Verifier can confirm by inspecting code — no subjective judgment required.

| Item | Violation indicator |
|------|---------------------|
| **Function purity** — functions compute or act, not both | A function reads/writes a file, calls a network API, or modifies a global AND returns a computed value used by the caller |
| **No unscoped globals** — variables are declared in the narrowest scope that works | Shell: a variable used only inside a function is declared outside it (no `local`). JS/TS: a module-level `let`/`var` is mutated by multiple unrelated functions |
| **Side effects at edges** — I/O and mutations live at call-site level, not buried inside pure logic | A pure-looking helper (e.g., `calculate_total`, `format_name`) contains a `curl`, `read`, `write`, database call, or `console.log`/`echo` that is not in its name or documented in a comment |
| **Descriptive names, no unexplained abbreviations** — identifiers say what they hold or do | A variable or function name is ≤3 characters (excluding loop counters `i`/`j`/`k`) without a comment explaining the abbreviation; or a name uses domain jargon not defined in the pre-registration or a comment |
| **No magic numbers or magic strings** — all non-obvious literals are named constants | A numeric or string literal appears inline (e.g., `86400`, `"application/json"`, `".rnd"`) without a named constant, and its meaning cannot be inferred from context alone |
| **DRY — no copy-pasted logic** — identical or near-identical blocks appear at most once | The same logical operation (same sequence of steps, same condition) appears in two or more places with only variable names changed, and no shared function or abstraction exists |
| **No swallowed errors** — every error is handled, re-raised, or explicitly ignored with a comment | Shell: a command that can fail runs without `|| ...` or `set -e` in effect and its exit code is never checked. Other languages: a caught exception block is empty or contains only a comment saying `// TODO` |
| **Immutability by default** — bindings are declared immutable unless mutation is specifically required | Shell: a variable set once is not declared `local -r`. JS/TS: a binding assigned once uses `let` instead of `const`. Any language: a function parameter is reassigned inside the function body |
| **No flag parameters** — booleans passed to alter function behavior indicate the function does two things | A function signature contains a boolean parameter (e.g., `process(data, true)`, `run(verbose=False)`) where `true`/`false` selects between two distinct code paths inside the function |
| **No commented-out code** — dead code is deleted, not retained as comments | A block of code is commented out with no explanation (e.g., `# old approach`, `// TODO: remove`). Exception: explanatory comments that reference a ticket or decision are acceptable |

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
| "This is pre-existing" / "by design" / "not in scope" | Every finding must include a proposed fix. Never dismiss a finding without citing specific documentation that justifies the exception. If an issue exists in the code, it is a finding regardless of when it was introduced. |

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

## Critical Failure Modes

Scan these before writing any verdict. If you recognize one of these patterns in your own reasoning, stop and correct course. The full catalog of 18 failure modes is in `rnd-framework:rnd-failure-modes` — this appendix covers the six most common in verification contexts.

### 1. Premature Satisfaction
**Manifestation:** Code looks reasonable so you write PASS without running tests — "seems fine" replaces evidence. You may say "the implementation clearly handles this case."
**Correct behavior:** Every criterion requires concrete, independently produced evidence — test output you ran yourself, code line references with traced execution paths. Run it. Break it. Trace it.

### 2. Trusting Agent Reports
**Manifestation:** Builder's manifest says "all tests pass" and you accept it — you check if the claim was made, not if it is true. Verification becomes reading a report about verification.
**Correct behavior:** Run tests yourself. Read what the tests actually assert. An agent claiming tests pass does not make them pass, and a test asserting the wrong thing can pass while the criterion is unmet.

### 3. Should-Work-Now Fallacy
**Manifestation:** After seeing a fix applied, you reason "bug was X, they fixed X, therefore it works now" and skip re-running tests because the fix looks right.
**Correct behavior:** Re-run the tests. Fixes introduce regressions. The logical chain "fix looks correct → criterion met" is not a substitute for execution evidence.

### 4. Anchoring on Builder Self-Assessment
**Manifestation:** You read the Builder's self-assessment and your verification becomes confirming their claims rather than independently evaluating the spec. Your findings track the Builder's narrative.
**Correct behavior:** Self-assessment files are blocked by hooks. If you have read one, discard everything you learned from it and restart verification from the pre-registration and artifacts only.

### 5. Incomplete Verification
**Manifestation:** You verify 4 of 5 criteria and issue a verdict — the 5th was "minor" or "obviously fine" or you ran out of time.
**Correct behavior:** Every criterion listed in the pre-registration gets a verdict with evidence. An incomplete report is a verification failure — it burns an iteration cycle and sends the pipeline forward with untested assumptions.

### 6. Exit Velocity Bias
**Manifestation:** You want to finish; the work looks good; you become motivated to find reasons to PASS. Failure mode analysis becomes cursory and you stop probing before trying to break anything.
**Correct behavior:** The desire to be done is not evidence. Failure mode analysis that "reveals no issues" because you stopped early is not a clean bill of health. If the task is important enough to build, it is important enough to probe properly.

---

### Red Flag Phrases

When you find yourself writing or thinking any of the following, stop and check your reasoning:

1. **"should work now"** — assertion without evidence; run the tests
2. **"probably passes"** — probability is not evidence; verify it
3. **"clearly handles this"** — "clearly" hides an unverified assumption; trace it
4. **"looks correct"** — appearances are not evidence; execute and observe
5. **"the Builder addressed this"** — the Builder's claim is not the same as the criterion being met
6. **"this is obviously fine"** — obvious things still need evidence; if it's obvious, verification is fast
7. **"I'll check the rest next round"** — there is no free next round; report all findings now
8. **"close enough"** — criteria are binary; close enough is FAIL
9. **"the tests pass, so it works"** — inspect what the tests assert, not just that they pass
10. **"I already checked something similar"** — prior checks do not transfer; each criterion gets fresh evidence
11. **"Great!"** (before issuing verdict) — positive affect before evidence is a warning sign
12. **"I'm confident this is correct"** — confidence without evidence is the definition of Premature Satisfaction
13. **"too simple to need verification"** — the scaling skill defines minimum ceremony for every tier; nothing is exempt
14. **"I remember the requirement says..."** — memory degrades; re-read the pre-registration file, don't recall from context

---

### Before Writing Any Verdict: Quick Scan

1. **Name any failure mode you are falling into.** If you notice one, stop and correct before continuing.
2. **Check your evidence.** For each criterion you are about to mark PASS, ask: "What concrete, independently produced evidence do I have?" If you cannot answer with a specific test output or line reference, you do not have evidence.
3. **Scan the red flag phrases above.** Review your draft reasoning. If any phrase appears, revise before submitting.
4. **Count criteria.** Count your verdicts. Count the criteria in the pre-registration. They must match.

---

## Related Skills

- `rnd-framework:rnd-experiments` — How to write independent experiment tests from spec in Step 2
- `rnd-framework:rnd-failure-modes` — Full catalog of 18 verification anti-patterns; scan before writing any verdict
- `rnd-framework:rnd-debugging` — For root cause analysis of failures found during verification
- `rnd-framework:rnd-iteration` — For how feedback flows back to Builder
