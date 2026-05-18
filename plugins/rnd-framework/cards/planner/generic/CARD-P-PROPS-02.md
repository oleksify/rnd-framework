---
id: P-PROPS-02
role: planner
language: generic
tags: [property, decomposition, scope]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Dispatch to the correct Properties shape based on task type before writing the pre-registration.
specializes: [P-SMALL-MODULES-01]
---

**Good shape dispatch:**
> Task type: `new-feature` — codec module with encode/decode pair.
> Use Shape 3 (sibling file `T<id>-properties.exs`): invariants need StreamData to explore the binary input space; the Verifier executes the file in its worktree.
>
> Task type: `refactor` — extracting a pure helper from an existing function.
> Use Shape 2 (YAML block under `## Verification`): the invariant is machine-parseable and the runner can check it without a full test file.
>
> Task type: `docs` — updating a CLAUDE.md section.
> Use Shape 1 (markdown bullets): the claim is prose-level and no runner is needed.

**Worse shape dispatch:**
> Task type: `new-feature` — codec module.
> Use Shape 1 (markdown bullets): "forall binary input, decode(encode(x)) == x."
> The claim looks correct but the Verifier cannot execute it. A fast-check or StreamData run would shrink a counter-example to the exact failing input; a prose claim cannot.

**Why good is better:** The three shapes differ in how the Verifier checks them. Shape 1 is prose — readable by a human, not runnable by `lib/run-properties.sh`. Shape 2 is YAML — machine-parseable, runner-invocable. Shape 3 is code — directly executable in the Verifier's worktree. Picking the wrong shape means either over-specifying a simple invariant (forcing a sibling file for a one-line `docs` change) or under-specifying a complex one (prose claim for logic that needs 10 000 generated inputs to find the boundary). Match the shape to the execution context the task actually warrants, not the one that takes least effort to write.
