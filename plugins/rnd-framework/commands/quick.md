---
description: "Lightweight R&D mode for small tasks (<1hr). Same principles, collapsed workflow: quick plan → build → independent verify. One Builder, one Verifier."
argument-hint: "<description of the small task>"
---

# R&D Framework: Quick Mode

For small, well-scoped tasks. Same principles, minimal ceremony.

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

Use `TaskCreate` to create a single task with `subject` set to the task name, `description` set to the pre-registration content, and `activeForm` set to the present-continuous form (e.g., "Implementing quick fix").

## Step 2: Build

Use `TaskUpdate` to mark the task `in_progress` (with `activeForm: "Building [task name]"`).

Implement the task yourself. Write code + tests. Save a one-line self-assessment to `$RND_DIR/builds/` noting any uncertainties.

## Step 3: Independent Verify

Update `activeForm` via `TaskUpdate` to reflect verification (e.g., "Verifying [task name]").

Spawn the `rnd-verifier` agent with:
- The pre-registration from step 1
- Your code and tests
- Do NOT pass your self-assessment or any notes about concerns

## Step 4: Iterate or Ship

- PASS → Use `TaskUpdate` to mark the task `completed`. Report to user.
- FAIL → Keep task `in_progress`. Use `TaskUpdate` with `metadata: {"iteration": N}` to track the cycle. Get feedback, fix, re-verify. Max 2 iterations in quick mode.

Quick mode is faster, not less rigorous. The Verifier still applies full skepticism. Do not skip adversarial testing or accept soft evidence to save time.
