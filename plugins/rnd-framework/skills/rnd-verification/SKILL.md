---
name: rnd-verification
description: "Use when independently verifying built work against pre-registered criteria — information-barrier verification with evidence-based verdicts and failure mode analysis"
user-invocable: false
allowed-tools: [Read, Write, Bash, Grep, Glob]
effort: medium
---

# R&D Verification

Independently verify a Builder's output against pre-registered success criteria — the quality gate checkpoint. Nothing proceeds without your PASS. Assess work purely against the spec, never influenced by the Builder's framing. Default mode for `Criticality: LOW` or `NORMAL` tasks; for `Criticality: HIGH` the orchestrator uses `rnd-framework:rnd-multi-judge`.

## The Iron Laws

```
1. NEVER READ SELF-ASSESSMENT FILES — they bias your judgment
2. EVERY CRITERION GETS A VERDICT WITH EVIDENCE
3. DESCRIBE WHAT IS WRONG, NOT HOW TO FIX IT
```

## Information Barrier

You receive ONLY the pre-registration, Builder's code/tests/artifacts, and codebase context. MUST NOT seek `$RND_DIR/builds/T<id>-self-assessment.md` (blocked by hooks), Builder reasoning, or hints about known issues.

## Two-Stage Evaluation

**Correctness tier:** Must-pass criteria. **Quality tier:** Should-pass criteria. If ANY Correctness criterion fails, Quality results are irrelevant.

| Correctness | Quality | Overall Verdict |
|-------------|---------|-----------------|
| All PASS | All PASS | PASS |
| All PASS | Any FAIL | PASS (quality: NEEDS ITERATION) |
| Any FAIL (fixable) | Any | NEEDS ITERATION |
| Any FAIL (unfixable) | Any | FAIL |

## Process

### 1. Read the Pre-Registration
Understand intent, approach, and success criteria — your ONLY reference for "correct". Note each criterion separately before proceeding.

### 2. Write Independent Experiment Tests
Before reading Builder code or tests, write one experiment test per criterion using `rnd-framework:rnd-experiments`. Derive from spec text alone — **MUST NOT** read Builder test files at this stage. Write to `$RND_DIR/verifications/T<id>-experiments/`, named `exp-<criterion-slug>.test.<ext>`.

### 3. Run Experiments Against Builder's Code
Run experiments against the implementation. Record raw output verbatim — do not paraphrase. Each failing experiment is a Correctness-tier finding. If an experiment was wrong, fix it, note the correction, keep the original.

### 4. Run Builder's Tests and Compare
Read Builder code and tests. Run the full test suite and record verbatim. For each criterion, check whether the Builder's test actually tests the criterion — if a Builder test passes but your experiment fails, flag as spec divergence.

### 5. Code Inspection, Failure Mode Analysis, and Cross-Criterion Sweep
Before writing any verdicts, scan for anti-patterns (see `rnd-framework:rnd-failure-modes`).

**a. Failure Mode Analysis** — probe for: boundary/edge cases, off-by-one errors, error handling, unhappy paths, race conditions, security issues, external contract conformance (query the system independently).

**b. Code Inspection** — check for: dead code, hardcoded values, shortcuts, missing error handling, approach deviation, hardcoded assumptions about external systems (column names, API shapes, env var values) not backed by build manifest evidence. Cross-reference manifest "Evidence Gathered" — contracts without a citation are Correctness-tier failures.

**c. Cross-Criterion Sweep** — before writing any verdicts:
1. **Systemic patterns:** same defect type across multiple criteria → report as systemic
2. **Shared root causes:** multiple failures tracing to one defect → identify explicitly
3. **Fragile passes:** passing criterion resting on assumption invalidated by a failure → flag at-risk
4. **External assumption probe:** confirm manifest has evidence for every external dependency; flag dependent criteria at-risk if missing
5. **Completeness check:** verdict + evidence for EVERY criterion; return to steps 3-4 for any missing

**Do not proceed to Step 6 until this sweep is complete.**

### 6. Produce Verification Report
> If `$RND_DIR` not set, compute via `"${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh"`.

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

A criterion is binary: met or not met. Evidence must be concrete (test output you ran, line references), not impressionistic ("looks right").
- **PASS:** ALL criteria met with reproducible evidence, no failure modes, no deviations.
- **PASS (quality: NEEDS ITERATION):** All Correctness met; one or more Quality unmet. Integration proceeds; quality feedback flagged.
- **NEEDS ITERATION:** Any Correctness unmet with a clear, isolated fix path.
- **FAIL:** Any Correctness unmet without a clear fix path; deviation from declared approach; unhandled failure mode.

**When in doubt between NEEDS ITERATION and FAIL, choose FAIL.** False negatives are recoverable; false positives compound downstream.

## Clean Code Checklist (shell: mandatory; others: advisory)

| Item | Violation indicator |
|------|---------------------|
| **Function purity** — compute or act, not both | Function reads/writes file or calls network API AND returns a computed value to its caller |
| **No unscoped globals** — narrowest scope | Shell: function-only variable declared outside it (no `local`). JS/TS: module-level `let`/`var` mutated by unrelated functions |
| **Side effects at edges** — I/O at call-site, not buried | Pure-looking helper contains `curl`, `read`, `write`, or DB call not reflected in its name |
| **Descriptive names** — identifiers say what they hold | Name ≤3 chars (excluding `i`/`j`/`k`) without comment; or uses undefined domain jargon |
| **No magic numbers/strings** — literals are named constants | Inline literal (e.g., `86400`, `".rnd"`) without a named constant whose meaning is not inferable from context |
| **DRY** — identical blocks appear at most once | Same logical operation in two or more places with only variable names changed |
| **No swallowed errors** — every error handled or explicitly ignored | Shell: fallible command without `\|\|`/`set -e` and exit code unchecked. Other: empty catch block |
| **Immutability by default** — immutable unless mutation required | Shell: set-once variable not `local -r`. JS/TS: once-assigned binding uses `let` |
| **No flag parameters** — booleans in signatures indicate two functions in one | Function signature has a boolean selecting between two distinct code paths |
| **No commented-out code** — dead code deleted | Code block commented out with no explanation (exception: ticket/decision references) |

See `rnd-framework:rnd-failure-modes` for the full catalog of verification anti-patterns and excuses. See `rnd-framework:rnd-multi-judge` for the full multi-judge protocol.

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
- `rnd-framework:rnd-multi-judge` — Full protocol for parallel judge and tiebreaker roles
- `rnd-framework:rnd-debugging` — For root cause analysis of failures found during verification
- `rnd-framework:rnd-iteration` — For how feedback flows back to Builder
