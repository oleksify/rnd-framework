---
description: "Debug pipeline: reproduce a bug, diagnose root cause, fix, and verify — all in a single flow."
argument-hint: "<bug description or symptom>"
effort: high
---

# R&D Framework: Debug Mode

For reported bugs that need root cause analysis before fixing. All phases run sequentially in this session. Use `/rnd-framework:rnd-start` if the bug turns out to be architectural.

> **Iteration budget: 2.** If the fix fails verification twice, escalate to `/rnd-framework:rnd-start` for proper decomposition.

## Task Input

If `$ARGUMENTS` is empty (user ran `/rnd-framework:rnd-debug` with no bug description):

Use `AskUserQuestion` to gather the bug report. Present options:
- "Describe the bug" — ask the user to describe what fails, under what conditions, and any error messages
- "Paste an error message or stack trace" — let the user provide raw error output
- "I'll search for recent failures" — run `git log --oneline -10` and check recent test failures; present findings, then ask for the bug to fix

If `$ARGUMENTS` is provided, use it as the bug description and proceed directly.

## Step 0: Setup

Determine the RND artifacts directory and create its structure:

```bash
RND_DIR=$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh" -c)
```

Write a minimal plan skeleton to `$RND_DIR/plan.md`. Use `TaskCreate` to create a single task.

Tell the user: "Starting debug pipeline for: [bug description]"

## Step 1: Diagnose

Invoke `rnd-framework:rnd-debug-pipeline` and `rnd-framework:rnd-debugging` to load debugging discipline.

### Phase 1: Reproduce the Bug

1. **Read the bug report.** Note the exact symptoms, affected files, and reproduction steps.
2. **Reproduce consistently.** Run the reproduction steps. Confirm the failure is deterministic. If the bug does not reproduce, document this and stop.
3. **Capture raw evidence.** Record the exact error output, stack trace, and failing command verbatim.

### Phase 2: Root Cause Analysis

1. **Trace data flow.** Follow the failure backward through the call stack. Use Read, Grep/Glob to identify where the bad value originates.
2. **Form a single hypothesis.** "The root cause is X because Y (evidence Z)."
3. **Validate the hypothesis.** Write a minimal command that confirms. If it does not confirm, form a new hypothesis and repeat.
4. **Check scope.** If 3+ files are implicated or the root cause is a design flaw, consider escalation.

### Phase 3: Produce Diagnosis Report

Save to `$RND_DIR/diagnosis/T1-diagnosis.md` with: bug description, reproduction steps, root cause analysis, affected files, recommended fix approach, and escalation recommendation (PROCEED or ESCALATE).

Check the escalation recommendation:

**PROCEED** → Continue to Step 2.

**ESCALATE** → Use `AskUserQuestion`:
- "Escalate to /rnd-framework:rnd-start" — the bug is architectural
- "Continue anyway" — proceed with partial diagnosis

**CANNOT_REPRODUCE** → Use `AskUserQuestion`:
- "Provide more details"
- "Try a different reproduction approach"
- "Abandon"

## Step 2: Build the Fix

Invoke `rnd-framework:rnd-building` to load build discipline.

Write the full pre-registration to `$RND_DIR/plan.md`, informed by the diagnosis report. Success criteria must include:
- Bug is no longer reproducible using the original reproduction steps
- Fix targets the root cause (not a symptom patch)
- 1-2 criteria specific to the root cause
- Existing tests continue to pass (no regressions)

Implement the fix using TDD. Save manifest and self-assessment.

## Step 3: Verify the Fix

**CRITICAL: Information Barrier.** Do NOT re-read the self-assessment. Verify purely against the pre-registered criteria.

Invoke `rnd-framework:rnd-verification` to load verification discipline.

1. Write independent experiment tests from the spec.
2. Run experiments against the fixed code.
3. Run the built tests.
4. Code inspection and failure mode analysis.
5. Save verification report to `$RND_DIR/verifications/T1-verification.md`.

## Step 4: Iterate or Ship

- **PASS** → Mark task `completed`. **MANDATORY:** Invoke `rnd-framework:rnd-formatting` BEFORE doc-polish. Then invoke `rnd-framework:rnd-doc-polish`. Then use `AskUserQuestion`:
  - "Commit changes (Recommended)"
  - "Bump version, tag and push"
  - "Show development narrative"
  - "Review artifacts"
  - "Finish session"

- **PASS (quality: NEEDS ITERATION)** → Treat as PASS. Show quality feedback. Present same options.

- **FAIL** → Keep task `in_progress`. Track iteration count. Re-implement and re-verify.

  If iteration budget (2) exhausted:
  - "Escalate to full pipeline"
  - "Iterate one more time"
  - "Abandon task"
