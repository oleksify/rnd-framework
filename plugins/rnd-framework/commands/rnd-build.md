---
description: "Run the Build phase for a specific task or wave from the existing RND plan."
argument-hint: "<task ID like T3 or wave number like wave-2>"
effort: medium
---

# R&D Framework: Build

Determine the RND artifacts directory:

```bash
RND_DIR=$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh")
```

Read the plan from `$RND_DIR/plan.md`. Check `TaskList` to identify current task states.

If $ARGUMENTS is empty (user ran `/rnd-framework:rnd-build` with no arguments):
- Read `$RND_DIR/plan.md` and inspect `TaskList` to find the next wave where all tasks are `pending` and unblocked.
- If a clear next wave is found, use `AskUserQuestion` to confirm: "Build wave-N next? (N tasks: T1, T2, ...)" with options "Yes, build wave-N (Recommended)" and "Choose a different task or wave".
- If no pending wave is found, report the current state and use `AskUserQuestion`.
- If the plan does not exist, prompt the user to run `/rnd-framework:rnd-start` first.

If $ARGUMENTS specifies a task ID (e.g., "T3"):
- Build that one task.

If $ARGUMENTS specifies a wave (e.g., "wave-2"):
- Build ALL tasks in that wave sequentially.

If $ARGUMENTS is "next":
- Use `TaskList` to find the next unblocked wave and build it.

## Build Process

Invoke `rnd-framework:rnd-building` to load build discipline. For each task:

1. Use `TaskUpdate` to mark the task `in_progress`.
2. Read the pre-registration from `$RND_DIR/plan.md`.
3. Read exploration cache from `$RND_DIR/exploration/` if it exists.
4. Verify external dependencies against actual systems.
5. Implement using TDD (Red-Green-Refactor per criterion).
6. Save build manifest to `$RND_DIR/builds/T<id>-manifest.md`.
7. Save honest self-assessment to `$RND_DIR/builds/T<id>-self-assessment.md`.
8. Assess status: DONE, DONE_WITH_CONCERNS, NEEDS_CONTEXT, or BLOCKED.

Route each result:

| Status | Action |
|--------|--------|
| `DONE` | Proceed to Gate 2 normally. |
| `DONE_WITH_CONCERNS` | Proceed to Gate 2, note concerns for verification. |
| `NEEDS_CONTEXT` | Pause. Use `AskUserQuestion` to collect missing context. Resume with user's answer. |
| `BLOCKED` | Pause. `AskUserQuestion`: "Provide missing dependency manually", "Re-plan this task", "Skip this task". |

Gate 2: Confirm all tasks have code, tests, artifacts, and self-assessment. Use `TaskUpdate` to mark each successfully built task as `completed`.

Summarize build results. Then use `AskUserQuestion` with options:
- "Proceed to verification (Recommended)" — run `/rnd-framework:rnd-verify` for this wave
- "Review build artifacts first" — inspect code and tests before verification
- "Build next wave" — skip verification for now and build the next wave

Do NOT auto-proceed to verification without user confirmation.
