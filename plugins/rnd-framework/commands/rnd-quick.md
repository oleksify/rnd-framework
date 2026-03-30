---
description: "Quick R&D for small tasks (<1hr). Plan → build → inline verify. No agents."
argument-hint: "<description of the small task>"
effort: medium
---

# Quick Mode

Single-flow R&D for small tasks. Same principles, minimal ceremony. Iteration budget: **2** — escalate to `/rnd-framework:rnd-start` if exceeded. Apply KISS + FP principles from context; do NOT invoke skills during quick mode startup.

## Task Input

If `$ARGUMENTS` is empty:
1. Quick scan: `git log --oneline -10`, TODO/FIXME, recent changes.
2. Present 2-4 suggestions via `AskUserQuestion`/`AskUser` plus "Describe a different task".
3. Use the selected or typed task and continue to Step 1.

If `$ARGUMENTS` is provided, skip to Step 1.

## Step 1: Quick Plan

```bash
RND_DIR=$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh" -c)
```

Write a brief pre-registration to `$RND_DIR/plan.md`: intent (1 sentence), approach (1 sentence), 2-4 success criteria as checkboxes. Tell the user: "Starting build for: [task] — [N] criteria."

Use `TaskCreate` with `subject` = task name, `description` = pre-registration, `activeForm` = present-continuous form.

## Step 2: Build

`TaskUpdate` → `in_progress` with `activeForm: "Building [task]"`.

Implement code + tests. Save a one-line self-assessment to `$RND_DIR/builds/` noting uncertainties.

- **DONE** — all criteria met, tests pass → proceed to Step 3.
- **DONE_WITH_CONCERNS** — criteria met, uncertainty exists → record concerns, proceed to Step 3.

## Step 3: Inline Verify

`TaskUpdate` → `activeForm: "Verifying [task]"`.

For each criterion: run an evidence-producing command, record PASS/FAIL with raw output. Save report to `$RND_DIR/verifications/T1-verification.md`. Quick mode trades the information barrier for speed — use `/rnd-framework:rnd-start` for independent verification.

## Step 4: Ship or Iterate

**PASS** → `TaskUpdate` → `completed`. Invoke `rnd-framework:rnd-formatting` then `rnd-framework:rnd-doc-polish`. Use `AskUserQuestion`/`AskUser`:
- "Commit changes (Recommended)"
- "Bump version, tag and push"
- "Show development narrative" — prose (3-5 paragraphs, "we"); after showing, re-present menu without this option
- "Review artifacts"
- "Finish session" — run `"${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh" --finish`

**PASS (quality: NEEDS ITERATION)** → Treat as PASS. Mark `completed`. Show quality feedback. Present same options above.

**FAIL** → Keep `in_progress`. `TaskUpdate` with `metadata: {"iteration": N}`, `activeForm: "Iterating [task] (N/2)"`. Fix, re-verify. If budget (2) exhausted, `AskUserQuestion`/`AskUser`: "Escalate to full pipeline", "Iterate one more time", "Abandon task".

Verify each criterion with real evidence — not "it looks correct".
