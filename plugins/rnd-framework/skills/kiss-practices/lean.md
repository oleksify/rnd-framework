# Lean 4 — KISS Rules

## Proofs and Tactics

- Don't use `sorry` as a placeholder — either close the proof or mark the claim as `axiom`
- Don't use bare `simp` — use `simp [lemma1, lemma2]` with an explicit lemma list so proofs don't break on Mathlib updates
- Don't nest tactic blocks more than 3 levels deep — extract intermediate results as `have` lemmas
- Place `by` at the end of the preceding line, never on its own line
- Use focusing dots `·` for subgoals — one tactic per line, indent everything in the block
- Don't squeeze terminal `simp` calls — unsqueezed is shorter and survives lemma renames

## Types and Definitions

- Always explicitly declare argument types and return types — implicit inference obscures intent on GitHub/docs
- Use `where` syntax for structure/class instances — not enclosing braces
- Prefer arguments left of the colon over universal quantifiers
- Default definitions to semireducible — use `abbrev` for reducible, `irreducible_def` only when profiling justifies it

## Decision Procedures

- Don't use `decide` for large finite checks — use `native_decide` for runtime evaluation
- Don't define custom notation for one-off proofs — notation is for reusable domain language

## Imports

- Don't `import Mathlib` — import specific modules (`import Mathlib.Data.List.Basic`) so compile times stay fast and dependencies stay traceable

## Recursion

- Don't write recursive functions without `termination_by` when termination is not structurally obvious
- Don't define `partial` functions to silence termination errors — prove termination or restructure

## Style

- Prefer `fun x ↦` over `λ` syntax — and `<|` over `$`
- Keep lines to 100 characters maximum
- Don't orphan parentheses — keep them with their arguments
- Use `<|` and `|>` to reduce parenthesis nesting

## Polish

- Order definitions by dependency: helper lemmas and definitions before the theorems that use them — never require a reader to jump forward to understand a proof
- Name lemmas after the property they establish, not the tactic used — `list_length_positive` not `simp_length_proof`
- Within a file, pick one naming convention for related theorems: either `noun_property` (e.g., `list_nil_length`) or `property_of_noun` — don't mix both styles
- Use `-- ` comments to explain non-obvious tactic choices or why a particular lemma is chosen; omit comments that only name the tactic being applied
