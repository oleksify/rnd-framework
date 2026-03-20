---
name: rnd-failure-modes
description: Use when verifying work or reviewing your own reasoning — a catalog of failure modes and anti-patterns that cause false PASSes, missed defects, and broken quality gates
user-invocable: false
effort: low
---

# R&D Failure Modes

## Overview

A catalog of known verification failure modes — anti-patterns that cause agents to issue false PASSes, miss real defects, or abandon quality standards under pressure. Scan this catalog before writing any verdict. The goal is to catch your own reasoning failures before they propagate downstream.

**Core principle:** If you recognize one of these patterns in your own thinking, stop and correct course. Naming the failure mode is the first step to avoiding it.

## When to Use

- Before writing any PASS, FAIL, or NEEDS ITERATION verdict
- When you notice yourself wanting to be done more than wanting to be right
- When reviewing your own reasoning during verification
- When an iteration cycle feels like it should be over but the evidence is thin
- When a Builder's claim sounds plausible and you haven't verified it independently

**Do not use this catalog to**: second-guess legitimate PASSes backed by strong evidence. Its purpose is to surface rationalization, not to manufacture doubt.

---

## Failure Mode Catalog

These are the known failure modes this framework has encountered. Each entry includes how the failure manifests and what correct behavior looks like.

### 1. Premature Satisfaction

**How it manifests:** You read the code, it looks reasonable, and you write PASS without running tests or tracing execution. The "seems fine" feeling replaces evidence. You may say things like "the implementation clearly handles this case."

**Correct behavior:** Every criterion requires concrete, independently produced evidence — test output you ran yourself, code line references with traced execution paths. "Looks right" is not evidence. Run it. Break it. Trace it.

---

### 2. Trusting Agent Reports

**How it manifests:** The Builder's manifest says "all tests pass" and you accept it. You check whether the claim was made, not whether it is true. Verification becomes reading a report about verification rather than doing verification.

**Correct behavior:** Run tests yourself. Read what the tests actually assert — not just that they exist. An agent claiming tests pass does not make them pass, and a test that asserts the wrong thing can pass while the criterion remains unmet.

---

### 3. Should-Work-Now Fallacy

**How it manifests:** After seeing a fix applied, you reason forward: "the bug was X, they fixed X, therefore it works now." You skip re-running the tests because the fix looks right.

**Correct behavior:** Re-run the tests. Fixes introduce regressions. The logical chain "fix looks correct → criterion is met" is not a substitute for execution evidence. The test suite tells you what actually happened.

---

### 4. Anchoring on Builder Self-Assessment

**How it manifests:** You read (or recall) the Builder's self-assessment — their confidence levels, their "known issues" framing — and your verification becomes confirming or refuting their claims rather than independently evaluating the spec. Your findings track the Builder's narrative.

**Correct behavior:** The information barrier exists for this reason. Self-assessment files are blocked by hooks. If you have read one, discard everything you learned from it and restart verification from the pre-registration and artifacts only.

---

### 5. Incomplete Verification

**How it manifests:** You verify 4 of 5 criteria and write a verdict. The 5th criterion was "minor" or "obviously fine" or you ran out of time. You issue PASS or NEEDS ITERATION without evidence for every criterion.

**Correct behavior:** Every criterion listed in the pre-registration gets a verdict with evidence. If you lack evidence for any criterion, go back and produce it before writing the report. An incomplete report is a verification failure — it burns an iteration cycle and sends the pipeline forward with untested assumptions.

---

### 6. Exit Velocity Bias

**How it manifests:** You want to finish. The work looks good. You become motivated to find reasons to PASS rather than reasons to look harder. Your failure mode analysis becomes cursory. You stop probing before you've actually tried to break anything.

**Correct behavior:** The desire to be done is not evidence. Failure mode analysis that "reveals no issues" because you stopped early is not a clean bill of health. If the task is important enough to build, it is important enough to probe properly.

---

### 7. Scope Creep in Verification

**How it manifests:** You test beyond the pre-registered criteria. You find problems that weren't in scope and issue FAIL based on them. Or you invent quality standards not present in the pre-registration and mark criteria as unmet because of style, elegance, or unstated requirements.

**Correct behavior:** Your reference is the pre-registration, nothing else. Criteria are binary and fixed — met or not met against the spec. Note out-of-scope observations separately if useful, but they do not influence the verdict.

---

### 8. Partial Fix Acceptance

**How it manifests:** The Builder fixes the primary failure and resubmits. You check the primary failure is resolved and issue PASS, forgetting that the previous report flagged multiple failures. The other failures are still present but you didn't re-examine them.

**Correct behavior:** When verifying an iteration, re-check every previously failed criterion, not just the one the Builder addressed. Builders sometimes fix one thing and inadvertently break another, or address only the loudest failure and leave others.

---

### 9. False Precision in Evidence

**How it manifests:** You cite a line number as evidence but haven't traced what the code does at that line. You mention a test name as evidence but haven't read what it asserts. The evidence looks specific but is not actually verified.

**Correct behavior:** Evidence must be the result of active verification: code you read and understood, tests you ran and whose output you recorded, execution paths you traced. Citing identifiers without understanding is not evidence — it is the appearance of evidence.

---

### 10. Verbal PASS

**How it manifests:** You express satisfaction about the work in your reasoning ("this is well-structured", "the implementation is clean") and then write PASS. The compliments contaminate the verdict — the positive framing becomes the evidence.

**Correct behavior:** Aesthetic judgments are not criteria. Separate qualitative impressions from criterion verdicts. The only question is: does the artifact meet each pre-registered criterion? Evidence answers that question; positive impressions do not.

---

### 11. Deflection

**How it manifests:** You identify a problem but dismiss it as "pre-existing", "by design", or "not in scope" rather than reporting it. You rationalize that because the issue predates this change, or was intended, it is exempt from your verdict. The issue goes unreported and unfixed.

**Correct behavior:** Every finding must include a proposed fix. Never dismiss a finding as "pre-existing", "by design", or "not in scope" without citing specific documentation that justifies the exception. If an issue exists in the code, it is a finding regardless of when it was introduced.

---

## Red Flag Phrases

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

---

## Using This Catalog During Verification

Before writing any verdict:

1. **Scan the catalog.** Take 30 seconds to read the failure mode names. Ask: "Am I falling into any of these?"
2. **Check your evidence.** For each criterion you are about to mark PASS, ask: "What concrete, independently produced evidence do I have?" If you cannot answer with a specific test output or line reference, you do not have evidence.
3. **Scan the red flag phrases.** Review your draft reasoning. If any red flag phrase appears, revise before submitting.
4. **Check completeness.** Count your verdicts. Count the criteria in the pre-registration. They must match.

---

## Relationship to Other Quality Gates

The failure modes catalog is a **diagnostic tool**, not a process requirement. You do not need to document which failure modes you checked — you need to not commit them.

The `rnd-verification` skill defines the process. This catalog helps you execute that process without rationalizing your way to premature closure.

---

## Related Skills

- `rnd-framework:rnd-verification` — Full verification process; this catalog is a supplement to it
- `rnd-framework:rnd-iteration` — What happens when failure modes cause a false PASS that the next cycle catches
- `rnd-framework:rnd-debugging` — For root cause analysis when a failure mode leads to a real defect
