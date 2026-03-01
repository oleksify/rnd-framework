---
description: "Run only the Planning phase: decompose a task into sub-tasks with pre-registration documents, dependency matrix, and execution schedule."
argument-hint: "<description of the feature, refactor, or bug fix>"
---

# R&D Framework: Plan Only

Run ONLY the planning phase for: $ARGUMENTS

1. Determine the RND artifacts directory and create its structure:
   ```bash
   RND_DIR=$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh" -c)
   ```
2. Spawn the `rnd-planner` agent with the task description. Pass `RND_DIR` to it.
3. Review the output in `$RND_DIR/plan.md`.
4. Validate that every task has:
   - Testable success criteria (not vague)
   - Clear dependencies
   - Appropriate verification level
5. **Create native tasks:** For each task in the plan, use `TaskCreate` with:
   - `subject`: Task name (e.g., "T1: Design API contracts")
   - `description`: The full pre-registration content for that task
   - `activeForm`: Present-continuous form (e.g., "Designing API contracts")
   - Then use `TaskUpdate` with `addBlockedBy` to wire up dependencies matching the plan's dependency matrix
6. Summarize the plan to the user: how many tasks, how many waves, key architectural decisions. Then use `AskUserQuestion` with options:
   - "Approve plan and proceed to build (Recommended)" — user can then run `/rnd-framework:build`
   - "Request plan revisions" — describe what to change and re-run `/rnd-framework:plan`
   - "Add more tasks" — extend the plan before building

Do NOT proceed to build/verify/integrate. The user will decide when to continue.
