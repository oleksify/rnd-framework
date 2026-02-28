---
description: "Lightweight R&D mode for small tasks (<1hr). Same principles, collapsed workflow: quick plan → build → independent verify. One Builder, one Verifier."
argument-hint: "<description of the small task>"
---

# R&D Framework: Quick Mode

For small, well-scoped tasks. Same principles, minimal ceremony.

## Step 1: Quick Plan (inline, no subagent needed)

Write a brief pre-registration directly:

```markdown
# Quick Plan: [task name]
Intent: [one sentence]
Approach: [one sentence]
Success criteria:
  - [ ] [criterion 1]
  - [ ] [criterion 2]
```

Save to `.rnd/plan.md`.

## Step 2: Build

Implement the task yourself. Write code + tests. Save a one-line self-assessment to `.rnd/builds/` noting any uncertainties.

## Step 3: Independent Verify

Spawn the `rnd-verifier` agent with:
- The pre-registration from step 1
- Your code and tests
- Do NOT pass your self-assessment or any notes about concerns

## Step 4: Iterate or Ship

- PASS → Done. Report to user.
- FAIL → Get feedback, fix, re-verify. Max 2 iterations in quick mode.

Quick mode is faster, not less rigorous. The Verifier still applies full skepticism. Do not skip adversarial testing or accept soft evidence to save time.
