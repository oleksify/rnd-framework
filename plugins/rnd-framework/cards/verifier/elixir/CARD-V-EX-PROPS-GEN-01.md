---
id: V-EX-PROPS-GEN-01
role: verifier
language: elixir
tags: [property, critique-evidence, shrinking, StreamData]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Cite the shrunk reproducer from a StreamData failure, not the first or mid-run failing value.
specializes: [P-PROPS-01]
---

**Good Feedback entry:**
> FAIL. `lib/run-properties.sh` returned `PROPERTY_COUNTER_EXAMPLE` for property `sum_is_non_negative`. Shrunk reproducer: `{left: -1, right: 0}` (seed 83741). StreamData reduced a 14-node tree to this 2-node tree — the minimal structure where `Tree.sum/1` returns a negative value. The implementation applies `abs/1` only to leaf values, not to the intermediate accumulator, so a single negative leaf at any depth produces a negative sum. Fix: apply the non-negativity guard at the accumulator level, or constrain the generator to `StreamData.positive_integer()` if negative values are out of scope.

**Worse Feedback entry:**
> FAIL. StreamData found a failing tree with several nodes. The sum function returned a negative number. The implementation is incorrect.

**Why good is better:** StreamData's shrinking reduces the initial (often large) counter-example to the minimal structure that still fails. The shrunken reproducer is always smaller and more diagnostically useful than the first-found failing value — it pinpoints the exact shape that triggers the bug. A good Feedback entry cites the shrunk reproducer verbatim (not "several nodes"), names the seed for deterministic replay, explains what the implementation did wrong at the specific failing input, and proposes the narrowest fix boundary. The worse entry discards the shrunk value and forces the Builder to re-run the suite to recover what the Verifier already observed.
