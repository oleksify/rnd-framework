---
description: "Run only the Planning phase: decompose a task into sub-tasks with pre-registration documents, dependency matrix, and execution schedule."
argument-hint: "<description of the feature, refactor, or bug fix>"
---

# R&D Framework: Plan Only

Run ONLY the planning phase for: $ARGUMENTS

1. Create `.rnd/` directory if needed.
2. Spawn the `rnd-planner` agent with the task description.
3. Review the output in `.rnd/plan.md`.
4. Validate that every task has:
   - Testable success criteria (not vague)
   - Clear dependencies
   - Appropriate verification level
5. **Create native tasks:** For each task in the plan, use `TaskCreate` with:
   - `subject`: Task name (e.g., "T1: Design API contracts")
   - `description`: The full pre-registration content for that task
   - `activeForm`: Present-continuous form (e.g., "Designing API contracts")
   - Then use `TaskUpdate` with `addBlockedBy` to wire up dependencies matching the plan's dependency matrix
6. Present the plan to the user for review before proceeding.

Do NOT proceed to build/verify/integrate. The user will decide when to continue.
