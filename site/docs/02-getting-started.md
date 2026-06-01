## Getting started

Start a full pipeline with a task description:

```
/rnd-framework:rnd-start Add OAuth2 login with a Google provider
```

The orchestrator runs the phases below, dispatching each to a specialised agent (see [Agents](#agents)) and aggregating the results.

```
   Plan
     │   decompose · pre-register success criteria · schedule waves
     ▼
   Build
     │   implement one task with tests
     ▼
  [Reality Audit]        only when the task declares external dependencies
     │   check that cited URLs / APIs / schemas / env vars actually exist
     ▼
   Verify
     │   independent check against the contract, behind the barrier
     ▼
  [Iterate]              only on a non-PASS verdict — fix and re-verify
     │
     ▼
   Cleanup ─▶ Polish      remove dead code · fix cross-task seams
     │
     ▼
   Integrate
         merge verified work · run integration tests · SHIP / NO-SHIP
```

Brackets mark conditional phases: Reality Audit runs only when a task declares external dependencies; Iterate runs only when verification did not pass.

<details>
<summary>What actually happens in each phase</summary>

- **Plan.** One planner agent decomposes the task, writes a validation contract (one testable assertion per requirement, fixed *before* any code), and groups independent sub-tasks into waves. See [the planner in depth](#agents).
- **Build.** One builder agent implements a single task test-first, leaving a manifest of what changed and a private self-assessment of its own doubts.
- **Reality Audit.** *(conditional)* Only when the task cites external things — URLs, APIs, schemas, env vars — an auditor checks each one actually exists before trusting the build.
- **Verify.** A separate verifier, which cannot see the builder's reasoning, checks the work against the contract and writes a per-assertion verdict with cited evidence.
- **Iterate.** *(conditional)* On any non-pass verdict, the feedback goes back to a builder or debugger, the fix is made, and the task is re-verified.
- **Cleanup → Polish.** Per-task dead-code removal, then a wave-level pass over the seams between tasks. Both roll back if they break re-verification.
- **Integrate.** Verified work is merged, integration tests run, and the wave gets a `SHIP` / `NO-SHIP` decision.

</details>

<details>
<summary>What a "wave" is, and how iteration is bounded</summary>

A **wave** is a batch of sub-tasks with no dependencies on each other — the planner finds them by analysing the dependency graph, exactly as a build system schedules independent targets together. Tasks within a wave can be built and verified in parallel; a task that depends on another waits for the wave that produces it.

When a task fails verification it enters an **iteration loop**: fix, re-verify, repeat — but not forever. The loop runs on a budget, and two stop conditions guard it. If a task's verdict keeps flipping (`PASS` → `FAIL` → `PASS`), or if the plan grows past its heuristic ceiling, the framework stops and asks you what to do rather than churning. A loop that can't converge is a signal the plan is wrong, not that it needs another lap.

</details>

### How much ceremony

Every task goes through the pipeline, scaled to its size — a one-line fix gets a minimal wave; a multi-day feature gets the full treatment with a design-review gate. The framework does not skip verification, but it does right-size the number of agents.

### Other entry points

| Command | When |
|---|---|
| `/rnd-framework:rnd-debug <bug>` | Reproduce, diagnose, fix, and verify a reported bug |
| `/rnd-framework:rnd-roadmap <goal>` | Plan a large goal across multiple sessions |
| `/rnd-framework:rnd-status` | See where the current pipeline is |
| `/rnd-framework:rnd-resume` | Continue a pipeline that was interrupted |

The full list is in [Commands](#commands).
