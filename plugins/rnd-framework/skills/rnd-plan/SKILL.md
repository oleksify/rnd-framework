---
name: rnd-plan
description: "Run only the Planning phase: decompose a task into sub-tasks with pre-registration documents, dependency matrix, and execution schedule."
user-invocable: false
effort: high
---

# R&D Framework: Plan Only

## Task Input

If `$ARGUMENTS` is empty (user ran `/rnd-framework:rnd-plan` with no task description):

1. **Quick codebase scan.** Run a few fast commands to gather context: `git log --oneline -10`, check for TODO/FIXME comments, look at recent changes.

2. **Ask with `AskUserQuestion`.** Present 2-4 concrete task suggestions based on what you found, plus always include a generic "Describe a different task" option.

3. **If the user picks a suggestion**, use it as the task description and continue below. **If they type a custom task**, use that instead.

**Never fall back to plain text** to ask what to work on. `AskUserQuestion` is mandatory at every decision point, including this one.

If `$ARGUMENTS` is provided, skip this section and proceed directly.

## Plan

Run ONLY the planning phase for: $ARGUMENTS

1. Determine the RND artifacts directory and create its structure:
   ```bash
   RND_DIR=$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh" -c)
   ```

2. Invoke `rnd-framework:rnd-decomposition` to load decomposition discipline.

3. **Discover environment and infrastructure.** Run a structured checklist scan:
   - Package manager (Glob for package.json, Cargo.toml, etc.)
   - Test framework (Grep for test runner configs, count existing tests, identify run commands)
   - CI config (Read .github/workflows/ or equivalent)
   - External services (Grep for https:// URLs in source)
   - Environment variables (Read .env.example, Grep for process.env/ENV references)
   - Secrets and off-limits (infer from .gitignore, CI config)

   Present findings to the user via `AskUserQuestion` for confirmation and gap-filling.

4. Explore the codebase using Glob/Grep. Write exploration findings to `$RND_DIR/exploration/`.

5. Decompose the task into a hierarchical task tree with pre-registration documents following the decomposition skill's protocol.

6. Build the dependency matrix and execution schedule.

7. Save to `$RND_DIR/plan.md` with enriched sections: Environment Setup, Infrastructure, Testing Strategy, Worker Guidelines, Validation Contract, Pre-Registration Documents, Dependency Matrix, Execution Schedule, Iteration Budgets.

8. Validate that every task has:
   - Testable success criteria (not vague)
   - Clear dependencies
   - Appropriate verification level
   - Every success criterion tagged as Correctness or Quality
   - `fulfills` field linking to VAL assertions
   - All VAL assertions covered by at least one task

9. **Create native tasks:** For each task in the plan, use `TaskCreate` with:
   - `subject`: Task name (e.g., "T1: Design API contracts")
   - `description`: The full pre-registration content for that task
   - `activeForm`: Present-continuous form (e.g., "Designing API contracts")
   - Then use `TaskUpdate` with `addBlockedBy` to wire up dependencies matching the plan's dependency matrix

10. Summarize the plan to the user: how many tasks, how many waves, key architectural decisions. Then use `AskUserQuestion` with options:
   - "Approve plan and proceed to build (Recommended)" — user can then run `/rnd-framework:rnd-build`
   - "Request plan revisions" — describe what to change and re-run `/rnd-framework:rnd-plan`
   - "Add more tasks" — extend the plan before building

Do NOT proceed to build/verify/integrate. The user will decide when to continue.
