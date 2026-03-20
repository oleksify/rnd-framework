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

If $ARGUMENTS is empty (user ran `/rnd-framework:build` with no arguments):
- Read `$RND_DIR/plan.md` and inspect `TaskList` to find the next wave where all tasks are `pending` and unblocked (i.e., all their dependencies are `completed`).
- If a clear next wave is found, use `AskUserQuestion` to confirm: "Build wave-N next? (N tasks: T1, T2, …)" with options "Yes, build wave-N (Recommended)" and "Choose a different task or wave".
- If no pending wave is found (all tasks complete, or all remaining are blocked), report the current state and use `AskUserQuestion` to ask the user what to do next.
- If the plan does not exist, prompt the user to run `/rnd-framework:start` first.

If $ARGUMENTS specifies a task ID (e.g., "T3"):
- Use `TaskUpdate` to mark the task `in_progress`.
- Spawn one agent using the Agent tool with `subagent_type: "rnd-framework:rnd-builder"`.

If $ARGUMENTS specifies a wave (e.g., "wave-2"):
- Use `TaskUpdate` to mark ALL tasks in the wave as `in_progress`.
- Spawn agents in parallel for ALL tasks in that wave, each using the Agent tool with `subagent_type: "rnd-framework:rnd-builder"`.

If $ARGUMENTS is "next":
- Use `TaskList` to find the next wave where all tasks are `pending` and unblocked.
- Mark those tasks `in_progress` and build them in parallel.

After each builder agent returns, check its status code from the completion message before proceeding:

| Status | Action |
|--------|--------|
| `DONE` | Proceed to Gate 2 normally. |
| `DONE_WITH_CONCERNS` | Proceed to Gate 2, but record the concerns summary. Pass it to the Verifier prompt when spawning verification — this tells the Verifier which areas need extra scrutiny. Do NOT read the self-assessment. |
| `NEEDS_CONTEXT` | Pause immediately. Use `AskUserQuestion` to present the builder's question to the user and collect the missing context. Resume the builder (spawn a new agent) with the original task plus the clarifying context. |
| `BLOCKED` | Pause immediately. Use `AskUserQuestion` with options: "Provide missing dependency manually", "Re-plan this task", "Skip this task". |

Gate 2: Confirm all `DONE` and `DONE_WITH_CONCERNS` tasks have code, tests, artifacts, and self-assessment. Use `TaskUpdate` to mark each successfully built task as `completed`.

Summarize build results to the user: which tasks completed, any deviations from plan, any escalations. Then use `AskUserQuestion` with options:
- "Proceed to verification (Recommended)" — run `/rnd-framework:verify` for this wave
- "Review build artifacts first" — inspect code and tests before verification
- "Build next wave" — skip verification for now and build the next wave

Do NOT auto-proceed to verification without user confirmation.
