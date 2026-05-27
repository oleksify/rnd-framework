# Predictions

A calibration journal. Before each significant change to the framework, log: what's changing, what's predicted (numbers where possible), what would prove it wrong, and the date. Come back later and append what actually happened — **never edit a prediction after the fact**.

---

## M2 — Premortem artifact (fast-tracked) — 2026-05-27

**Changing:** Before `protocol.md` is finalized, the orchestrator spawns N parallel Haikus (predict N=5 fixed framings + 0–2 task-generated), aggregates imagined failures into a new `premortem.md` written before `protocol.md`; the Planner must address or explicitly dismiss each mode; a `premortem_generated` audit event records N + framings + failure-mode count.

**Predicted:** Premortem is planner-side, so per the locked "success metric = verifier FAIL rate, masked by the verifier ceiling" reasoning, I predict **no measurable movement in verifier FAIL rate** (within noise) attributable to M2 over the next ~10 sessions. The real signal: premortem surfaces **~1–3 non-obvious failure modes per planning run** that the planner then converts into validation-contract assertions or protocol scope it would not otherwise have written. Cost: adds one parallel Haiku fan-out (~30–90s wall-clock, negligible token spend) to the planning phase.

**Would prove it wrong:** (a) `premortem.md` is consistently boilerplate — the Planner dismisses all/most modes as "out of scope" with no new assertions or scope across the first ~5 sessions (pure ceremony); or (b) verifier FAIL rate drops sharply right after M2 ships, which would contradict the masking hypothesis and mean the gain is coming from somewhere I didn't model.

**Outcome:** _(to append later)_
