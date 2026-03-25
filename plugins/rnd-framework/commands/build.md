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
- Call `TeamCreate` with `team_name: "rnd-build-task-T{id}-{SESSION_ID}"`, where `{id}` is the task number and `{SESSION_ID}` is the last path segment of `$RND_DIR` (e.g., `20260325-212836-137f`).
- Spawn one agent using the Agent tool with `subagent_type: "rnd-framework:rnd-builder"`, `team_name` set to the team name created above, and `name: "builder-T{id}"`.
- After the builder completes and Gate 2 passes, call `TeamDelete` with the same team name to clean up.

If $ARGUMENTS specifies a wave (e.g., "wave-2"):
- Use `TaskUpdate` to mark ALL tasks in the wave as `in_progress`.
- Call `TeamCreate` with `team_name: "rnd-build-wave-{N}-{SESSION_ID}"`, where `{N}` is the wave number and `{SESSION_ID}` is the last path segment of `$RND_DIR` (e.g., `20260325-212836-137f`).
- Spawn agents in parallel for ALL tasks in that wave, each using the Agent tool with `subagent_type: "rnd-framework:rnd-builder"`, `team_name` set to the team name created above, and `name` set to `builder-T{id}` (e.g., `builder-T3`).
- After all builders complete and Gate 2 passes, call `TeamDelete` with the same team name to clean up.

If $ARGUMENTS is "next":
- Use `TaskList` to find the next wave where all tasks are `pending` and unblocked.
- Mark those tasks `in_progress` and build them using the same wave Team Mode pattern above (TeamCreate → parallel Agent spawns with team_name and name → Gate 2 → TeamDelete).

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
