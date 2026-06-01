## Concepts

The framework rests on six ideas. Each maps a practice from science or engineering onto coding.

| Idea | In plain terms |
|---|---|
| **Pre-registration** | Write down the success criteria *before* writing code |
| **Decomposition** | Split a task into small sub-tasks, each with its own check |
| **Independent verification** | A separate reviewer checks the work without seeing the author's reasoning |
| **Evidence-based gates** | Each checkpoint requires reproducible proof, not a claim |
| **Wave scheduling** | Figure out what can run in parallel vs. what must wait |
| **Outside view** | Calibrate the plan against how often similar work has actually failed before |

### Pre-registration

In science, *pre-registration* means publishing your hypothesis and your test method before you collect data — so you can't quietly move the goalposts once you see the results.

Here, the planner writes a **validation contract**: one testable assertion per thing the change must do, recorded before any code exists. The builder can't redefine "done" mid-stream, and the verifier checks against the contract, not against whatever got built.

### Decomposition

A large task is broken into a tree of small sub-tasks. Each sub-task is small enough to hold in your head, gets its own success criteria, and is verified on its own. Small units fail in obvious ways; large ones fail in subtle ones.

### Independent verification

Borrowed from independent verification & validation (IV&V) — the reviewer is deliberately *not* the author and deliberately *cannot* see the author's notes. If the reviewer reads the builder's reasoning ("I think this is fine, the edge case probably won't happen"), the reviewer gets anchored and verification turns into rubber-stamping. See [Information barrier](#information-barrier) for how this is enforced.

### Evidence-based gates

A *gate* is a checkpoint between phases. To pass, a phase must produce reproducible evidence — a command that exits 0, a file that exists, a test that runs — not an assertion that it works. "Should be fine" does not pass a gate.

### Wave scheduling

Before building, the planner analyses which sub-tasks depend on which. Independent ones are grouped into a **wave** and built together; dependent ones wait for the wave they depend on. This is the same dependency analysis a build system does.

### Outside view

Borrowed from *reference-class forecasting* (Kahneman and Tversky's **outside view**): instead of estimating a task only from its own details — the *inside view*, which runs optimistic — you first ask how often work *of this kind* has actually turned out.

Right before planning, after the premortem and before the planner writes anything, the framework queries this project's own session log: for each **shape** of assertion (a schema migration, a behaviour change, a doc edit…) it computes how often work of that shape has failed verification, and injects those base rates into the planner's context as a calibration anchor.

It is deliberately a *constraint, not a lever*. A low historical failure rate is not permission to compress decomposition; a high one is not a mandate to shatter the task into micro-assertions. It is a prior to weigh, nothing more. When the project has fewer than five past verdicts to draw on, the framework says so — *thin-corpus mode* — rather than inventing a number from too little data.
