# Lean 4 — KISS Rules

## Proofs and Tactics

- Don't use `sorry` as a placeholder — either close the proof or mark the claim as `axiom`
- Don't use bare `simp` — use `simp [lemma1, lemma2]` with an explicit lemma list so proofs don't break silently on Mathlib updates
- Don't nest tactic blocks more than 3 levels deep — extract intermediate results as `have` lemmas or standalone `lemma` declarations

## Decision Procedures and Computation

- Don't use `decide` for large finite checks — use `native_decide` for runtime evaluation or write a structural proof
- Don't define custom notation for one-off proofs — use the full name; notation is for reusable domain language, not convenience in a single file

## Imports

- Don't `import Mathlib` — import specific modules (`import Mathlib.Data.List.Basic`) so compile times stay fast and dependencies stay traceable

## Recursion

- Don't write recursive functions without a `termination_by` clause when termination is not structurally obvious — Lean's default heuristic fails silently on complex recursion
- Don't define `partial` functions to silence termination errors — prove termination or restructure the algorithm
