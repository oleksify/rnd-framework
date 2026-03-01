---
description: "Lightweight R&D mode for small tasks (<1hr). Same principles, collapsed workflow: quick plan → build → independent verify. One Builder, one Verifier."
argument-hint: "<description of the small task>"
---

# R&D Framework: Quick Mode

For small, well-scoped tasks. Same scientific-method principles, minimal ceremony.

## Step 1: Quick Plan (inline, no subagent needed)

Determine the RND artifacts directory and create its structure:

```bash
RND_DIR=$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh" -c)
```

Write a brief pre-registration directly:

```markdown
# Quick Plan: [task name]
Intent: [one sentence]
Approach: [one sentence]
Success criteria:
  - [ ] [criterion 1]
  - [ ] [criterion 2]
```

Save to `$RND_DIR/plan.md`.

Tell the user: "Starting build for: [task name] — [number] success criteria to meet."

Use `TaskCreate` to create a single task with `subject` set to the task name, `description` set to the pre-registration content, and `activeForm` set to the present-continuous form (e.g., "Implementing quick fix").

## Step 2: Build

Use `TaskUpdate` to mark the task `in_progress` (with `activeForm: "Building [task name]"`).

Implement the task yourself. Write code + tests. Save a one-line self-assessment to `$RND_DIR/builds/` noting any uncertainties.

## Step 3: Independent Verify

Update `activeForm` via `TaskUpdate` to reflect verification (e.g., "Verifying [task name]").

Spawn the `rnd-verifier` agent with `mode: "bypassPermissions"`, passing:
- The pre-registration from step 1
- Your code and tests
- Do NOT pass your self-assessment or any notes about concerns

## Step 4: Iterate or Ship

- **PASS** → Use `TaskUpdate` to mark the task `completed`. Summarize what was built and verified. Use `AskUserQuestion` with options:
  - "Commit changes (Recommended)" — stage and commit the changes
  - "Review artifacts" — show the user the verification report and code changes
  - "Clean up" — remove `$RND_DIR` artifacts only

- **FAIL** → Keep task `in_progress`. Use `TaskUpdate` with `metadata: {"iteration": N}` and `activeForm: "Iterating [task name] (N/2)"` to track the cycle. Summarize the verification failure to the user. Get feedback, fix, re-verify.

  If iteration budget (2) is exhausted, use `AskUserQuestion` with options:
  - "Escalate to full pipeline" — switch to `/rnd-framework:start` for deeper decomposition
  - "Iterate one more time" — extend budget by 1
  - "Abandon task" — stop work on this task

Quick mode is faster, not less rigorous. The Verifier still applies full skepticism. Do not skip adversarial testing or accept soft evidence to save time.
