---
description: Run a task through the tight-loop single-agent rigor ritual
argument-hint: <task description>
effort: medium
---

# Tight-Loop: Start

Use the `tight-loop:tight-loop` skill to execute the three-step ritual on the described task.

If `$ARGUMENTS` is empty, ask the user for a task description via AskUserQuestion before proceeding.

Otherwise, invoke the `tight-loop:tight-loop` skill with the task description as input. The skill enforces:

1. Pre-registration written to `prereg-<task-slug>.md` BEFORE any project file edit
2. Implementation (driven by the model, with hook discipline blocking premature edits)
3. Self-review with evidence-per-criterion in a `<final-report>` block

The skill produces a structured `<final-report>` at the end. Read it carefully and decide whether the task is done or requires another iteration.
