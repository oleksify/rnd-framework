---
name: rnd-multi-judge
description: "Use when running independent multi-judge verification with consensus logic — spawns 2 verifier agents, aggregates verdicts, and triggers a tiebreaker on disagreement"
user-invocable: false
effort: medium
---

# Multi-Judge Consensus Verification

## When to Use

- Tasks with `Criticality: HIGH` in the pre-registration document
- Any time higher confidence in a verification verdict is required
- When a task's failure would be expensive to fix downstream

## Wave-Batched Multi-Judge Protocol

When a wave contains any HIGH-criticality task, run wave-batched multi-judge verification.

**Wave-level flow:**
1. Spawn 2 parallel Verifier agents — both receive all task pre-registrations.
2. Each returns a per-task verdict map.
3. Compare verdict maps task by task. For each task:
   - Both agree → use shared verdict for that task.
   - Judges disagree on a task → spawn a tiebreaker for that specific task only.
4. Assemble final verdict map from agreed verdicts plus tiebreaker verdicts.
5. On PASS write `T<id>-pass-receipt.json`; on FAIL/NEEDS_ITERATION/PASS_QUALITY_NEEDS_ITERATION write `T<id>-verification.md`. Save verdict map to `$RND_DIR/verifications/wave-<N>-verdict-map.json`.

## Protocol

### Step 1 — Pre-flight

1. Confirm `$RND_DIR/builds/T<id>-self-assessment.md` exists but do NOT read it.
2. Experiment artifacts save under `$RND_DIR/verifications/T<id>-experiments/judge-a/`, `judge-b/`, `tiebreaker/`.
3. Assemble the shared judge prompt from: pre-registration document and Builder code/tests/artifacts. Do NOT include self-assessment content.

### Step 1.5 — First-Pass Escalation Gate

Before spawning two independent judges, run a single first-pass verifier to determine whether full dual-judge verification is needed.

**Skip this step entirely if `RND_MULTI_JUDGE_ALWAYS=1` is set** — that flag restores exact pre-change behavior: skip the gate and proceed directly to Step 2 with both judges in parallel.

**First-pass spawn:**

```
Spawn one verifier agent:
  subagent_type: "rnd-framework:rnd-verifier"
  mode: "acceptEdits"
  prompt: same shared judge prompt constructed in Step 1
```

**Escalation decision:**

- `PASS` → Skip Steps 2–4. Proceed directly to Step 5 with the first-pass verdict.
- `FAIL`, `NEEDS_ITERATION`, or `PASS_QUALITY_NEEDS_ITERATION` → Escalate to dual-judge. Promote first-pass judge to Judge A; save report to `$RND_DIR/verifications/T<id>-judge-a.md`; continue with Step 2 (spawn Judge B only).

**Calibration write (escalationGate field):** Append or update the calibration record with an `escalationGate` object (see `rnd-framework:rnd-calibration`). No-op if `calibration.jsonl` does not exist.

### Step 2 — Spawn 2 Independent Judges

- Both agents: `subagent_type: "rnd-framework:rnd-verifier"`, `mode: "acceptEdits"`.
- Each receives the same inputs: pre-registration document and Builder code/tests.
- Neither judge's prompt includes the other's report.
- Both are blocked from reading self-assessment files (enforced by the `read-gate` hook).

Save reports to:
- Judge A: `$RND_DIR/verifications/T<id>-judge-a.md`
- Judge B: `$RND_DIR/verifications/T<id>-judge-b.md`

### Step 3 — Compare Verdicts

Read both reports. Extract the `Overall Verdict` line from each.

**Consensus rules:** If both judges return the same verdict (PASS, PASS_QUALITY_NEEDS_ITERATION, NEEDS_ITERATION, FAIL, or AMEND_REQUIRED), that verdict is final. Proceed to Step 5.

**Split-verdict rule:** Any mismatch — including one judge issuing AMEND_REQUIRED — triggers a tiebreaker. Proceed to Step 4.

### Step 4 — Tiebreaker Judge (on disagreement only)

- `subagent_type: "rnd-framework:rnd-verifier"`, `mode: "acceptEdits"`.
- Receives: pre-registration, Builder code/tests, AND both prior judge reports.
- Does NOT receive self-assessment files.
- Must issue a final verdict and justify it by citing specific evidence from both reports.

Save to: `$RND_DIR/verifications/T<id>-tiebreaker.md`

**Tiebreaker resolution for AMEND_REQUIRED splits:**

| Tiebreaker Verdict | Final Verdict |
|--------------------|---------------|
| AMEND_REQUIRED | AMEND_REQUIRED stands |
| Any non-AMEND_REQUIRED verdict | Majority non-AMEND_REQUIRED verdict wins |

When split is AMEND_REQUIRED vs NEEDS_ITERATION and tiebreaker rejects AMEND_REQUIRED, final verdict defaults to NEEDS_ITERATION.

### Step 5 — Produce Output

- **PASS:** Write `T<id>-pass-receipt.json` to `$RND_DIR/verifications/` — no prose report.
- **PASS_QUALITY_NEEDS_ITERATION / NEEDS_ITERATION / FAIL:** Write the aggregated prose report `T<id>-verification.md`.
- Judge A: `$RND_DIR/verifications/T<id>-experiments/judge-a/`
- Judge B: `$RND_DIR/verifications/T<id>-experiments/judge-b/`
- Tiebreaker (if applicable): `$RND_DIR/verifications/T<id>-experiments/tiebreaker/`

```markdown
# Verification Report: T<id>

## Judge A Report
[Full contents of Judge A's per-criterion results and verdict]

---

## Judge B Report
[Full contents of Judge B's per-criterion results and verdict]

---

## Tiebreaker Report (if applicable)
[Full contents of tiebreaker's report, or omit if both judges agreed]

---

## Final Consensus Verdict: PASS | PASS_QUALITY_NEEDS_ITERATION | NEEDS_ITERATION | FAIL | AMEND_REQUIRED

**Consensus method:** Both judges agreed | Tiebreaker required — [Judge A verdict] vs [Judge B verdict]

## Feedback (if not PASS)
[Consolidated actionable feedback. Describe WHAT is wrong. Do NOT suggest fixes.]
```

## Information Barrier Rules

1. **No self-assessments.** No judge prompt includes content from `$RND_DIR/builds/T<id>-self-assessment.md`.
2. **No Builder reasoning.** Judge prompts include code, tests, and artifacts only.
3. **Initial judges are isolated from each other.** Judge A's prompt does not include Judge B's report, and vice versa.
4. **Tiebreaker receives both prior reports.** The tiebreaker must treat both reports as evidence, not as authority.

## Related Skills

- `rnd-framework:rnd-verification` — The verification process each individual judge follows
- `rnd-framework:rnd-iteration` — How feedback flows from a FAIL or NEEDS ITERATION verdict back to the Builder
- `rnd-framework:rnd-orchestration` — Pipeline structure and agent coordination
