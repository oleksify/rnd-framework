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
5. Present the plan to the user for review before proceeding.

Do NOT proceed to build/verify/integrate. The user will decide when to continue.
