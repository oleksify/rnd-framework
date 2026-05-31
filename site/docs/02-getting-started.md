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
