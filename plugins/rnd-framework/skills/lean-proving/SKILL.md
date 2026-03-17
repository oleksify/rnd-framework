---
name: lean-proving
description: "Use when verifying mathematical properties of Builder code using Lean 4 — translates pre-registration criteria into formal theorems, generates companion tests, runs lake build, and produces T<id>-proof-report.md for the Verifier"
---

# Lean Proving

## Overview

Formal proofs eliminate entire classes of bugs that tests can only sample. When a Lean theorem is proven, every input satisfying the preconditions satisfies the conclusion — not just the inputs you thought to test.

**Core principle:** Lean proves abstract theorems ("if X then Y"). Companion tests verify the Builder's code satisfies X. Together they give high-confidence verification without translating TypeScript or Python into Lean.

This is the **property bridge strategy**: bridge the gap between abstract math and concrete code using two artifacts — a formal proof and a companion test.

## When to Use

- Verifying mathematical invariants (count preservation, order, bounds)
- Checking type safety properties that TypeScript's type system cannot express
- Proving absence of error states for finite state machines
- Any pre-registration criterion where "all inputs" must be covered, not just sampled
- When the Verifier needs higher-confidence evidence than unit tests alone

## Core Rules

```
1. WRITE THE LEAN THEOREM FROM THE CRITERION TEXT — NOT FROM THE BUILDER'S CODE
2. COMPANION TESTS VERIFY PRECONDITIONS — NEVER SKIP THEM
3. USE PROOF STRATEGY RANKING — DON'T START WITH MANUAL TACTICS
4. NEVER USE sorry IN A SUBMITTED PROOF — sorry IS A PLACEHOLDER, NOT A PROOF
5. RECORD EVERY PROOF ATTEMPT IN T<id>-proof-report.md — FAILURES ARE EVIDENCE TOO
```

## Property Bridge Strategy

The property bridge has two sides:

| Side | Tool | What it proves |
|---|---|---|
| Abstract theorem | Lean 4 | "For all inputs satisfying precondition P, property Q holds" |
| Companion test | Project test framework | "The Builder's concrete code satisfies precondition P" |

Combined evidence: theorem PROVEN + companion test PASSED = high-confidence criterion verification.

**Example — "aggregation must preserve row count":**

Step 1 — Lean theorem (abstract):
```lean
theorem preserve_count (xs : List α) (f : List α → List α)
    (h : ∀ ys, (f ys).length = ys.length) :
    (f xs).length = xs.length := h xs
```

Step 2 — Companion test (concrete, in the project's test framework):
```typescript
test("aggregate preserves row count", () => {
  const data = [1, 2, 3, 4, 5];
  expect(aggregate(data).length).toBe(data.length);
});
```

Step 3 — Record in proof report: theorem PROVEN, companion test PASSED.

## Translating Criteria into Lean Propositions

Read the criterion text. Identify the universally-quantified claim. Express it as a Lean `theorem` or `def` with a `Prop` type.

| Criterion | Lean proposition pattern |
|---|---|
| "output length equals input length" | `(f xs).length = xs.length` |
| "result is non-negative" | `∀ x ∈ output, 0 ≤ x` |
| "sorted output" | `List.Sorted (· ≤ ·) output` |
| "no error state reachable from initial" | `¬ (reachable initial ErrorState)` |

**Four translation examples:**

```lean
-- Data preservation: aggregation preserves count
theorem count_preserved (xs : List Nat) :
    (aggregate xs).length = xs.length := by simp [aggregate]

-- Bounds: all scores in [0, 100]
theorem score_bounded (xs : List Score) :
    ∀ s ∈ normalize xs, 0 ≤ s.value ∧ s.value ≤ 100 := by
  intro s hs; simp [normalize] at hs; omega

-- Type safety: parse never returns None for non-empty input
theorem parse_defined (s : String) (h : s ≠ "") :
    (parse s).isSome = true := by decide

-- Absence of error: state machine stays in valid states
theorem no_invalid_state (s : State) (e : Event) :
    transition s e ≠ .invalid := by aesop
```

## Proof Strategy Ranking

Try strategies in this order. Earlier strategies are more reliable and require less manual reasoning.

1. `simp [specific_lemmas]` — most reliable; provide the exact lemma names
2. `omega` — for linear arithmetic over integers and naturals
3. `aesop` — for structured search over type-class instances and logic
4. `decide` / `native_decide` — for finite, decidable propositions only
5. Manual tactic proof (`intro`, `apply`, `exact`, `cases`, `induction`) — last resort

**Rule:** if `simp` cannot close the goal after adding 3 specific lemmas, move to the next strategy. Do not write 10-lemma `simp` calls.

## Companion Tests

A companion test verifies that the Builder's concrete code satisfies the preconditions of the Lean theorem. Without a companion test, the theorem proves a property of an abstract model — not of the actual code.

**Pattern:** one companion test per theorem, placed in the project's existing test framework.

```typescript
// Companion test for theorem: preserve_count
// Verifies the concrete `aggregate` function satisfies the length-preservation precondition
test("aggregate: length preserved (precondition for preserve_count theorem)", () => {
  const inputs = [[], [1], [1, 2, 3], Array.from({length: 100}, (_, i) => i)];
  for (const data of inputs) {
    expect(aggregate(data).length).toBe(data.length);
  }
});
```

**What companion tests must do:**
- Exercise the actual Builder implementation (not a mock)
- Cover at least 3 representative inputs including edge cases (empty, single, large)
- Assert the exact precondition stated in the theorem's `h` parameter
- Be placed in the project's test directory, not in `$RND_DIR`

## Reading Proof Failures

When `lake build` reports errors, extract signal for the Verifier:

| Error message | What it means | Signal for Verifier |
|---|---|---|
| `type mismatch` | Theorem type doesn't match what the tactic produced | Spec and implementation may diverge |
| `unknown identifier 'X'` | Missing import or typo in lemma name | Check `import Mathlib.X` or rename |
| `unsolved goals` | Tactic proof is incomplete | Try next strategy in ranking |
| `sorry` in output | Proof was left incomplete | UNPROVEN — do not report as evidence |
| `failed to synthesize` | Missing typeclass instance | Add `deriving DecidableEq` or similar |
| `kernel rejected` | `native_decide` found a counterexample | Theorem is FALSE — spec is wrong |

**Key signal:** `kernel rejected` means the proposition is actually false — there exists an input that violates it. This is the most valuable failure: it means the pre-registration criterion is either mis-stated or the Builder's implementation is genuinely incorrect. Report this to the Verifier with the counterexample.

## Lake Build Setup

Create a minimal project in `$RND_DIR/proofs/` for each pipeline run. Two files are required:

**`lean-toolchain`** — pins the Lean version:
```
leanprover/lean4:v4.14.0
```

**`lakefile.lean`** — minimal build config:
```lean
import Lake
open Lake DSL

package proofs where
  name := "proofs"

lean_lib Theorems where
  roots := #[`T1Theorems, `T2Theorems]
```

**Build and check:**
```bash
cd "$RND_DIR/proofs"
lake build 2>&1 | tee build.log
```

A clean build (exit code 0, no `sorry`) means all theorems are proven. Record the build log in the proof report.

## $RND_DIR/proofs/ Layout

One subdirectory per task, one `.lean` file per criterion:

```
$RND_DIR/proofs/
├── lean-toolchain
├── lakefile.lean
├── T1-proof-report.md
├── T1-theorems/
│   ├── preserve-count.lean
│   └── no-nan.lean
├── T2-proof-report.md
└── T2-theorems/
    └── sorted-output.lean
```

**Proof report format** (`T<id>-proof-report.md`):

```markdown
# Proof Report: T<id>

## Properties Attempted

| Property | File | Strategy | Status |
|---|---|---|---|
| preserve_count | T1-theorems/preserve-count.lean | simp | PROVEN |
| no_nan | T1-theorems/no-nan.lean | omega | UNPROVEN |

## Failure Analysis

### no_nan — UNPROVEN
Error: unsolved goals — omega cannot close ¬ isNaN x for Float
Signal for Verifier: NaN handling may be absent from the implementation.

## Build Log
[paste lake build output here]
```

## Artifact Checklist

Before marking proof work complete:

- [ ] `lean-toolchain` and `lakefile.lean` exist in `$RND_DIR/proofs/`
- [ ] One `.lean` file per criterion in `T<id>-theorems/`
- [ ] No `sorry` in any submitted theorem
- [ ] Companion test written for each theorem, placed in project test directory
- [ ] `lake build` exits 0 for all PROVEN theorems
- [ ] Proof report (`T<id>-proof-report.md`) lists all attempted properties with status
- [ ] Failure analysis written for every UNPROVEN property
- [ ] Build log appended to proof report

## Related Skills

- `rnd-framework:rnd-verification` — Full verification process; proofs are supplementary evidence
- `rnd-framework:rnd-building` — TDD discipline; companion tests follow the same red-green pattern
- `rnd-framework:kiss-practices` — Load lean.md rules before writing any Lean code
