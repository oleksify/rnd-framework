---
name: rnd-multi-judge
description: "Use when running independent multi-judge verification with consensus logic — spawns 2 verifier agents, aggregates verdicts, and triggers a tiebreaker on disagreement"
user-invocable: false
---

# Multi-Judge Consensus Verification

## Overview

Multi-judge verification increases confidence in verdicts by requiring independent agreement between two verifiers. A single verifier's PASS or FAIL may reflect blind spots; two independent judges who agree are significantly more reliable. When they disagree, a third tiebreaker judge resolves the conflict.

This skill defines the protocol shared by `/rnd-framework:verify` and the Verify phase of `/rnd-framework:start`.

## When to Use

- Standard and large pipeline tasks (default behavior for `/rnd-framework:start` Phase 3)
- Any time higher confidence in a verification verdict is required
- When a task's failure would be expensive to fix downstream

Single-verifier mode (as used in `/rnd-framework:quick`) is acceptable only for trivial tasks.

## Protocol

### Step 1 — Pre-flight

Before spawning any judges:

1. Run the self-assessment scan: confirm `$RND_DIR/builds/T<id>-self-assessment.md` exists but do NOT read it. The information barrier hook blocks reads of self-assessment files regardless — this step confirms the build is complete.
2. Assemble the shared judge prompt from: the pre-registration document (from `$RND_DIR/plan.md`) and the Builder's code, tests, and artifacts. Do NOT include self-assessment content in any judge prompt.

### Step 2 — Spawn 2 Independent Judges

Spawn exactly 2 independent verifier agents in parallel:

- Both agents use `subagent_type: "rnd-framework:rnd-verifier"` and `mode: "bypassPermissions"`.
- Each judge receives the same inputs: pre-registration document and Builder code/tests.
- Neither judge's prompt includes the other judge's report. The two judges operate with no knowledge of each other.
- Both judges are blocked from reading self-assessment files (enforced by the `read-gate` hook).

The orchestrator saves each judge's returned report to:
- Judge A: `$RND_DIR/verifications/T<id>-judge-a.md`
- Judge B: `$RND_DIR/verifications/T<id>-judge-b.md`

### Step 3 — Compare Verdicts

Read both reports. Extract the `Overall Verdict` line from each.

**Consensus rules (both judges agree):**

| Judge A | Judge B | Final Verdict |
|---------|---------|---------------|
| PASS    | PASS    | PASS          |
| FAIL    | FAIL    | FAIL          |
| NEEDS ITERATION | NEEDS ITERATION | NEEDS ITERATION |

When both judges agree, their shared verdict is the final verdict. Proceed to Step 5.

**Split-verdict rule (judges disagree):**

Any combination where the two verdicts differ — PASS/FAIL, PASS/NEEDS ITERATION, FAIL/NEEDS ITERATION — triggers a tiebreaker. Proceed to Step 4.

### Step 4 — Tiebreaker Judge (on disagreement only)

Spawn a third verifier agent as tiebreaker:

- Uses `subagent_type: "rnd-framework:rnd-verifier"` and `mode: "bypassPermissions"`.
- Receives: the pre-registration document, the Builder's code and tests, AND both prior judge reports (Judge A and Judge B).
- Does NOT receive self-assessment files. The information barrier applies to the tiebreaker identically to the initial judges.
- The tiebreaker must issue a final verdict (PASS, FAIL, or NEEDS ITERATION) and justify it by citing specific evidence from the two prior reports — not just picking a side.

The orchestrator saves the tiebreaker's returned report to: `$RND_DIR/verifications/T<id>-tiebreaker.md`

The tiebreaker's verdict is the final verdict.

### Step 5 — Produce Aggregated Report

The orchestrator saves the aggregated report to `$RND_DIR/verifications/T<id>-verification.md`:

```markdown
# Verification Report: T<id>

## Judge A Report

[Full contents of Judge A's per-criterion results and verdict]

---

## Judge B Report

[Full contents of Judge B's per-criterion results and verdict]

---

## Tiebreaker Report (if applicable)

[Full contents of tiebreaker's report, or omit this section if both judges agreed]

---

## Final Consensus Verdict: PASS | FAIL | NEEDS ITERATION

**Consensus method:** Both judges agreed | Tiebreaker required — [Judge A verdict] vs [Judge B verdict]

## Feedback (if not PASS)

[Consolidated actionable feedback from the deciding report(s). Describe WHAT is wrong. Do NOT suggest fixes.]
```

## Information Barrier Rules

These rules apply to ALL judges — initial judges and the tiebreaker:

1. **No self-assessments.** No judge prompt includes content from `$RND_DIR/builds/T<id>-self-assessment.md`. The `read-gate` hook blocks any attempt to read self-assessment files regardless.
2. **No Builder reasoning.** Judge prompts include code, tests, and artifacts only — not the Builder's internal reasoning or chain-of-thought.
3. **Initial judges are isolated from each other.** Judge A's prompt does not include Judge B's report, and vice versa. This isolation is what makes their agreement meaningful.
4. **Tiebreaker receives both prior reports.** This is the only case where a judge sees another judge's report. The tiebreaker must treat both reports as evidence, not as authority.

## Rationale

Independent judges who agree are much less likely to share the same blind spot than a single judge. When they disagree, that disagreement is itself a signal — it means the verdict is genuinely uncertain and warrants a third opinion. The tiebreaker, seeing both reports, can identify which reasoning is better supported by evidence.

## Related Skills

- `rnd-framework:rnd-verification` — The verification process each individual judge follows
- `rnd-framework:rnd-iteration` — How feedback flows from a FAIL or NEEDS ITERATION verdict back to the Builder
- `rnd-framework:rnd-orchestration` — Pipeline structure and agent coordination
