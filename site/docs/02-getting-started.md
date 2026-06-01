## Getting started

Start a full pipeline with a task description:

```
/rnd-framework:rnd-start Add OAuth2 login with a Google provider
```

The framework runs the phases below, handing each one to a specialised agent (see [Agents](#agents)) and pulling the results together.

```
   Plan
     │   split the work · write the checks first · group into waves
     ▼
   Build
     │   build one task, with tests
     ▼
  [Reality Audit]        only when the task declares external dependencies
     │   check that cited URLs / APIs / schemas / env vars actually exist
     ▼
   Verify
     │   independent check against the contract, without seeing how it was built
     ▼
  [Iterate]              only on a non-PASS verdict — fix and re-verify
     │
     ▼
   Cleanup ─▶ Polish      remove dead code · tidy the joins between tasks
     │
     ▼
   Integrate
         commit verified work · run integration tests · SHIP / NO-SHIP
```

Brackets mark conditional phases: Reality Audit runs only when a task declares external dependencies; Iterate runs only when verification did not pass.

<details>
<summary>What actually happens in each phase</summary>

- **Plan.** One planner agent splits the task up, writes a validation contract — one testable statement per requirement, locked in *before* any code — and groups the independent pieces into waves. See [the planner in depth](#agents).
- **Build.** One builder agent builds a single task test-first, leaving a manifest of what changed and a private note of where it's unsure.
- **Reality Audit.** *(conditional)* Only when the task cites external things — URLs, APIs, schemas, env vars — an auditor checks each one actually exists before trusting the build.
- **Verify.** A separate verifier, which can't see the builder's reasoning, checks the work against the contract and gives a verdict on each statement, backed by evidence it cites.
- **Iterate.** *(conditional)* On any non-pass verdict, the feedback goes back to a builder or debugger, the fix is made, and the task is re-verified.
- **Cleanup → Polish.** First a per-task sweep for dead code, then a pass across the whole wave to tidy the joins between tasks. Both undo themselves if they break the checks.
- **Integrate.** Verified tasks are committed to the branch in dependency order, integration tests run, and the wave gets a `SHIP` / `NO-SHIP` decision.

</details>

<details>
<summary>What a "wave" is, and how iteration is bounded</summary>

A **wave** is a batch of sub-tasks that don't depend on each other — the planner spots them by looking at what depends on what, the same way a build tool runs independent targets together. Tasks in a wave can be built and checked in parallel; a task that needs another waits for the wave that produces it.

When a task fails its check it enters an **iteration loop**: fix, re-check, repeat — but not forever. The loop runs on a budget, and two stop conditions guard it. If a task's verdict keeps flip-flopping (`PASS` → `FAIL` → `PASS`), or the plan keeps growing past a sensible size limit, the framework stops and asks you what to do instead of spinning. A loop that won't settle usually means the plan is wrong, not that it needs one more lap.

</details>

### How much ceremony

Every task goes through the pipeline, sized to the job — a one-line fix gets a tiny wave; a multi-day feature gets the full treatment, including a design-review gate. The framework never skips the check, but it does match the number of agents to the work.

### Other entry points

| Command | When |
|---|---|
| `/rnd-framework:rnd-debug <bug>` | Reproduce, diagnose, fix, and verify a reported bug |
| `/rnd-framework:rnd-roadmap <goal>` | Plan a large goal across multiple sessions |
| `/rnd-framework:rnd-status` | See where the current pipeline is |
| `/rnd-framework:rnd-resume` | Continue a pipeline that was interrupted |

The full list is in [Commands](#commands).
