---
name: rnd-build
description: "Run the Build phase for a specific task or wave from the existing RND plan."
user-invocable: false
effort: medium
---

# R&D Framework: Build

Determine the RND artifacts directory:

```bash
RND_DIR=$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh")
```

Read the plan from `$RND_DIR/plan.md`. Check `TaskList` to identify current task states. When displaying blocked tasks or blocked-by references, always translate Claude Code internal IDs (`#<n>`) to pipeline IDs (`T<n>`) by matching against `metadata.pipelineId` or extracting the `T<n>` prefix from the blocking task's subject.

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

**For each task, spawn a Builder agent:**

```
Agent({
  description: "Build task T<id>",
  subagent_type: "rnd-framework:rnd-builder",
  mode: "acceptEdits",
  prompt: "Task: T<id>\nRND_DIR: <path>\nPre-registration: <paste from plan.md>"
})
```

Do NOT build tasks yourself. The Builder agent handles implementation, TDD, manifest, and self-assessment. As part of its process, the Builder will verify external dependencies (APIs, libraries, schemas) against live sources before writing code and record the evidence in its manifest. It returns a status code.

Route each result:

| Status | Action |
|--------|--------|
| `DONE` | Proceed to Gate 2 normally. |
| `DONE_WITH_CONCERNS` | Proceed to Gate 2, note concerns for verification. |
| `NEEDS_CONTEXT` | Pause. Use `AskUserQuestion` to collect missing context. Re-spawn Builder with answer. |
| `BLOCKED` | Pause. `AskUserQuestion`: "Provide missing dependency manually", "Re-plan this task", "Skip this task". |

Gate 2: Verify `$RND_DIR/builds/T<id>-manifest.md` exists and is non-empty. Use `TaskUpdate` to mark each successfully built task as `completed`.

Summarize build results. Then use `AskUserQuestion` with options:
- "Proceed to verification (Recommended)" — run `/rnd-framework:rnd-verify` for this wave
- "Review build artifacts first" — inspect code and tests before verification
- "Build next wave" — skip verification for now and build the next wave

Do NOT auto-proceed to verification without user confirmation.
