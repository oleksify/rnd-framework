---
name: rnd-multi-judge
description: "Use when running independent multi-judge verification with consensus logic — spawns 2 verifier agents, aggregates verdicts, and triggers a tiebreaker on disagreement"
user-invocable: false
effort: medium
---

# Multi-Judge Consensus Verification

## Overview

Multi-judge verification increases confidence in verdicts by requiring independent agreement between two verifiers. A single verifier's PASS or FAIL may reflect blind spots; two independent judges who agree are significantly more reliable. When they disagree, a third tiebreaker judge resolves the conflict.

This skill defines the protocol shared by `/rnd-framework:rnd-verify` and the Verify phase of `/rnd-framework:rnd-start`.

## When to Use

- Tasks with `Criticality: HIGH` in the pre-registration document
- Any time higher confidence in a verification verdict is required
- When a task's failure would be expensive to fix downstream

## Wave-Batched Multi-Judge Protocol

When a wave contains any HIGH-criticality task, the orchestrator runs wave-batched multi-judge verification: both judges each receive all task pre-registrations for the wave, each returns a per-task verdict map, and the tiebreaker is triggered per-task (only for tasks where the two judges disagree).

**Wave-level flow:**
1. Spawn 2 parallel Verifier agents — both receive all task pre-registrations for the wave.
2. Each judge returns a per-task verdict map for all tasks in the wave.
3. Compare verdict maps task by task. For each task:
   - Both agree → use shared verdict for that task.
   - Judges disagree on a task → spawn a tiebreaker for that specific task only.
4. Assemble the final per-task verdict map from agreed verdicts plus tiebreaker verdicts where applicable.
5. For each task: on PASS write `T<id>-pass-receipt.json` to `$RND_DIR/verifications/` (no prose). On FAIL/NEEDS_ITERATION/PASS_QUALITY_NEEDS_ITERATION write `T<id>-verification.md`. Save the final per-task verdict map to `$RND_DIR/verifications/wave-<N>-verdict-map.json`.

The information barrier applies identically in wave-batched mode — no judge prompt includes self-assessment content for any task.

## Protocol

### Step 1 — Pre-flight

Before spawning any judges:

1. Run the self-assessment scan: confirm `$RND_DIR/builds/T<id>-self-assessment.md` exists but do NOT read it. The information barrier hook blocks reads of self-assessment files regardless — this step confirms the build is complete.
2. Note that experiment artifacts from each judge will be saved under `$RND_DIR/verifications/T<id>-experiments/judge-a/`, `judge-b/`, and `tiebreaker/` (if a tiebreaker is triggered). These directories are created by the judges themselves during verification.
3. Assemble the shared judge prompt from: the pre-registration document (from `$RND_DIR/plan.md`) and the Builder's code, tests, and artifacts. Do NOT include self-assessment content in any judge prompt.

### Step 2 — Spawn 2 Independent Judges

Spawn exactly 2 independent verifier agents in parallel:

- Both agents use `subagent_type: "rnd-framework:rnd-verifier"` and `mode: "acceptEdits"`.
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
| PASS_QUALITY_NEEDS_ITERATION | PASS_QUALITY_NEEDS_ITERATION | PASS_QUALITY_NEEDS_ITERATION |
| NEEDS_ITERATION | NEEDS_ITERATION | NEEDS_ITERATION |
| FAIL    | FAIL    | FAIL          |
| AMEND_REQUIRED | AMEND_REQUIRED | AMEND_REQUIRED |

When both judges agree, their shared verdict is the final verdict. Proceed to Step 5.

**Split-verdict rule (judges disagree):**

Any combination where the two verdicts differ — including any case where one judge issues AMEND_REQUIRED and the other issues any different verdict — triggers a tiebreaker Verifier (not the user). Proceed to Step 4.

| Judge A | Judge B | Action |
|---------|---------|--------|
| AMEND_REQUIRED | PASS / NEEDS_ITERATION / FAIL / PASS_QUALITY_NEEDS_ITERATION | Spawn tiebreaker Verifier |
| PASS / NEEDS_ITERATION / FAIL / PASS_QUALITY_NEEDS_ITERATION | AMEND_REQUIRED | Spawn tiebreaker Verifier |
| (any other mismatch) | (any other mismatch) | Spawn tiebreaker Verifier |

### Step 4 — Tiebreaker Judge (on disagreement only)

Spawn a third verifier agent as tiebreaker:

- Uses `subagent_type: "rnd-framework:rnd-verifier"` and `mode: "acceptEdits"`.
- Receives: the pre-registration document, the Builder's code and tests, AND both prior judge reports (Judge A and Judge B).
- Does NOT receive self-assessment files. The information barrier applies to the tiebreaker identically to the initial judges.
- The tiebreaker must issue a final verdict (PASS, PASS_QUALITY_NEEDS_ITERATION, NEEDS_ITERATION, FAIL, or AMEND_REQUIRED) and justify it by citing specific evidence from the two prior reports — not just picking a side.

The orchestrator saves the tiebreaker's returned report to: `$RND_DIR/verifications/T<id>-tiebreaker.md`

**Tiebreaker resolution for AMEND_REQUIRED splits:**

| Tiebreaker Verdict | Final Verdict |
|--------------------|---------------|
| AMEND_REQUIRED | AMEND_REQUIRED stands |
| Any non-AMEND_REQUIRED verdict | Majority non-AMEND_REQUIRED verdict wins |

When the split is AMEND_REQUIRED vs NEEDS_ITERATION and the tiebreaker disagrees with AMEND_REQUIRED, the final verdict defaults to NEEDS_ITERATION.

For all other splits (not involving AMEND_REQUIRED), the tiebreaker's verdict is the final verdict.

### Step 5 — Produce Output

**Lazy-prose contract:** Apply the same rules as single-judge verification.

- **PASS:** Write `T<id>-pass-receipt.json` to `$RND_DIR/verifications/` — no prose report.
- **PASS_QUALITY_NEEDS_ITERATION / NEEDS_ITERATION / FAIL:** Write the aggregated prose report `T<id>-verification.md`.

When a prose report is required, save to `$RND_DIR/verifications/T<id>-verification.md`:

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

## Experiment Summary

[Reference experiment results from each judge. Experiment artifacts are stored at:
- Judge A: `$RND_DIR/verifications/T<id>-experiments/judge-a/`
- Judge B: `$RND_DIR/verifications/T<id>-experiments/judge-b/`
- Tiebreaker (if applicable): `$RND_DIR/verifications/T<id>-experiments/tiebreaker/`

Omit this section if no experiment artifacts were produced.]

---

## Final Consensus Verdict: PASS | PASS_QUALITY_NEEDS_ITERATION | NEEDS_ITERATION | FAIL | AMEND_REQUIRED

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
