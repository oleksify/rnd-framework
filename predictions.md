# Predictions

A calibration journal. Before each significant change to the framework, log: what's changing, what's predicted (numbers where possible), what would prove it wrong, and the date. Come back later and append what actually happened — **never edit a prediction after the fact**.

---

## M2 — Premortem artifact (fast-tracked) — 2026-05-27

**Changing:** Before `protocol.md` is finalized, the orchestrator spawns N parallel Haikus (predict N=5 fixed framings + 0–2 task-generated), aggregates imagined failures into a new `premortem.md` written before `protocol.md`; the Planner must address or explicitly dismiss each mode; a `premortem_generated` audit event records N + framings + failure-mode count.

**Predicted:** Premortem is planner-side, so per the locked "success metric = verifier FAIL rate, masked by the verifier ceiling" reasoning, I predict **no measurable movement in verifier FAIL rate** (within noise) attributable to M2 over the next ~10 sessions. The real signal: premortem surfaces **~1–3 non-obvious failure modes per planning run** that the planner then converts into validation-contract assertions or protocol scope it would not otherwise have written. Cost: adds one parallel Haiku fan-out (~30–90s wall-clock, negligible token spend) to the planning phase.

**Would prove it wrong:** (a) `premortem.md` is consistently boilerplate — the Planner dismisses all/most modes as "out of scope" with no new assertions or scope across the first ~5 sessions (pure ceremony); or (b) verifier FAIL rate drops sharply right after M2 ships, which would contradict the masking hypothesis and mean the gain is coming from somewhere I didn't model.

**Outcome:** _(to append later)_

---

## Scope-Lock — split scoping from decomposition — 2026-06-07

**Changing:** A new `rnd-scoper` agent runs in Phase 1 (after premortem/outside-view, before the Planner) and emits a ratified, frozen `scope.json` (user-visible deliverables `D1, D2, …`) + immutable `scope.md`. The user ratifies the boundary (approve/edit/reject the rendered artifact) before decomposition. The Planner loses scope authorship and consumes the frozen scope as input. `features.json` tasks gain `deliverableIds[]`, and a new bidirectional coverage gate flags scope creep (task → no deliverable) and scope miss (deliverable → no task) via `gate_fired` events. Re-plan presents a scope diff. An rnd-stats section aggregates scope-creep/miss rates.

**Predicted:** This is a planner-upstream change, so — per the same "verifier FAIL rate is masked by the verifier ceiling" reasoning as M2 — I predict **no measurable movement in verifier FAIL rate** within noise over the next ~10 sessions. The real signal is scope correctness: I predict the ratification step causes a **user edit to the proposed boundary in ≥30% of runs** (if it never edits, the gate is rubber-stamping; if it always edits, the scoper is mis-grained), and the coverage gate fires `scope_miss`/`scope_creep` on **<1 in 5 sessions** once the deliverable grain settles (user-visible-outcome grain should make orphan tasks and uncovered deliverables rare, not routine). Cost: one added Opus producer spawn + one mandatory ratification prompt per run.

**Would prove it wrong:** (a) the coverage gate fires on most sessions — meaning the deliverable grain is wrong (too fine → 1:1 noise, or too coarse → vacuous) and the gate is theater, not signal; (b) users approve the proposed boundary unedited in nearly every run across the first ~5 sessions — meaning the ratification prompt is pure ceremony and the scoper could be trusted to auto-lock; or (c) verifier FAIL rate moves sharply right after ship, contradicting the masking hypothesis.

**Outcome:** _(to append later)_
