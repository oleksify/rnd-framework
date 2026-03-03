---
description: "Run only the Planning phase: decompose a task into sub-tasks with pre-registration documents, dependency matrix, and execution schedule."
argument-hint: "<description of the feature, refactor, or bug fix>"
---

# R&D Framework: Plan Only

## Task Input

If `$ARGUMENTS` is empty (user ran `/rnd-framework:plan` with no task description):

1. **Quick codebase scan.** Run a few fast commands to gather context: `git log --oneline -10`, check for TODO/FIXME comments, look at recent changes. This takes seconds and informs your suggestions.

2. **Ask with `AskUserQuestion`.** Present 2-4 concrete task suggestions based on what you found, plus always include a generic "Describe a different task" option. Each option should have a short label and a description explaining what the task would involve.

3. **If the user picks a suggestion**, use it as the task description and continue below. **If they type a custom task**, use that instead.

**Never fall back to plain text** to ask what to work on. `AskUserQuestion` is mandatory at every decision point, including this one.

Run ONLY the planning phase for: $ARGUMENTS

1. Determine the RND artifacts directory and create its structure:
   ```bash
   RND_DIR=$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh" -c)
   ```
2. Spawn the `rnd-planner` agent with `mode: "bypassPermissions"`, passing the task description and `RND_DIR`.
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
