---
description: "Debug pipeline: reproduce a bug, diagnose root cause, fix, and verify. Dedicated debugger agent for investigation, Builder for fix."
argument-hint: "<bug description or symptom>"
model: opus
effort: high
---

# R&D Framework: Debug Mode

For reported bugs that need root cause analysis before fixing. A dedicated debugger agent investigates and produces a structured diagnosis report. The Builder receives the report and implements the fix without re-investigating. Use `/rnd-framework:start` if the bug turns out to be architectural.

> **Iteration budget: 2** (same as quick mode). If the fix fails verification twice, escalate to `/rnd-framework:start` for proper decomposition.

## Task Input

If `$ARGUMENTS` is empty (user ran `/rnd-framework:debug` with no bug description):

Use `AskUserQuestion` to gather the bug report. Present options:
- "Describe the bug" — ask the user to describe what fails, under what conditions, and any error messages
- "Paste an error message or stack trace" — let the user provide raw error output as the bug description
- "I'll search for recent failures" — run `git log --oneline -10` and check recent test failures; present findings, then ask for the bug to fix

If `$ARGUMENTS` is provided, use it as the bug description and proceed directly.

**Never fall back to plain text** to ask what to work on. `AskUserQuestion` is mandatory at every decision point.

## Step 0: Setup

Determine the RND artifacts directory and create its structure:

```bash
RND_DIR=$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh" -c)
# Extract project-specific slop patterns from CLAUDE.md files so the Builder avoids them
bun "${CLAUDE_PLUGIN_ROOT}/lib/extract-patterns.ts" "$RND_DIR"
```

Write a minimal plan skeleton to `$RND_DIR/plan.md`:

```markdown
# Debug Pipeline: [bug description — one sentence]

## Task: Fix [bug description]
Intent: Diagnose and fix the reported bug.
Bug description: [from $ARGUMENTS or AskUserQuestion response]
Status: Diagnosing
```

Use `TaskCreate` to create a single task with `subject` set to the bug description, `description` set to the plan content, and `activeForm` set to `"Diagnosing: [bug description]"`.

Tell the user: "Starting debug pipeline for: [bug description]"

## Step 1: Diagnose

Use `TaskUpdate` to update `activeForm` to `"Diagnosing: [bug description]"`.

Spawn the debugger agent using the Agent tool:
- `subagent_type: "rnd-framework:rnd-debugger"`
- Pass the bug description and `$RND_DIR` path in the prompt

Wait for the debugger to complete. Read the diagnosis report from `$RND_DIR/diagnosis/`.

Check the `Escalation Recommendation` field in the report:

**DIAGNOSED (PROCEED)** → Continue to Step 2.

**ESCALATE** → Use `AskUserQuestion` with options:
- "Escalate to /rnd-framework:start" — the bug is architectural; start a full pipeline
- "Continue anyway" — proceed to Step 2 with the partial diagnosis (Builder will have limited context)

**CANNOT_REPRODUCE** → Use `AskUserQuestion` with options:
- "Provide more details" — ask the user for additional reproduction steps or environment details, then re-run Step 1 with the updated description
- "Try a different reproduction approach" — ask the user to suggest alternative ways to trigger the bug
- "Abandon" — stop the debug pipeline; run `"${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh" --finish`

## Step 2: Build

Use `TaskUpdate` to update `activeForm` to `"Building fix: [bug description]"`.

Write the full pre-registration to `$RND_DIR/plan.md` (update the skeleton from Step 0), now informed by the diagnosis report:

```markdown
# Debug Pipeline: [bug description]

## Task: Fix [bug description]
Intent: [one sentence, informed by root cause]
Approach: [one sentence fix approach from diagnosis report]
Success criteria:
  - [ ] Bug is no longer reproducible using the original reproduction steps
  - [ ] Fix targets the root cause identified in the diagnosis (not a symptom patch)
  - [ ] [add 1-2 criteria specific to the root cause from the diagnosis report]
  - [ ] Existing tests continue to pass (no regressions)
```

Spawn the Builder agent using the Agent tool:
- `subagent_type: "rnd-framework:rnd-builder"`
- Pass: the pre-registration, the full diagnosis report content, and `$RND_DIR`
- Do NOT pass your own reasoning or implementation ideas

## Step 3: Verify

Use `TaskUpdate` to update `activeForm` to `"Verifying fix: [bug description]"`.

Spawn the Verifier agent using the Agent tool:
- `subagent_type: "rnd-framework:rnd-verifier"`
- Pass: the pre-registration from Step 2, the code and tests from the Builder
- If Builder status was `DONE_WITH_CONCERNS`, include the brief concerns summary
- Do NOT pass the Builder's full self-assessment or the diagnosis report reasoning

The Verifier returns its report as text output. Save the returned report to `$RND_DIR/verifications/T1-verification.md`.

## Step 4: Iterate or Ship

- **PASS** → Use `TaskUpdate` to mark the task `completed`. **MANDATORY — DO NOT SKIP:** Invoke `rnd-framework:rnd-doc-polish` BEFORE presenting commit options. Report what was updated (or that everything is current). Then use `AskUserQuestion` with options:
  - "Commit changes (Recommended)" — stage and commit the changes
  - "Show development narrative" — generate a narrative explanation: what the bug was and why it existed, how diagnosis found the root cause, what the fix does, and what was verified. Write as prose (2-4 paragraphs, first person plural), not a bullet list. Do NOT spawn agents — generate from your own context (re-read `$RND_DIR` artifacts if context was compressed). After showing, re-present the same menu without this option.
  - "Review artifacts" — show the user the verification report and code changes
  - "Finish session" — run `"${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh" --finish` to clear the current session ID

- **PASS (quality: NEEDS ITERATION)** → Treat as PASS for pipeline purposes. Use `TaskUpdate` to mark the task `completed`. Show the quality feedback. Note: "Quality feedback noted. Review and address manually if needed." Then present the same `AskUserQuestion` options as a full PASS.

- **FAIL** → Keep task `in_progress`. Use `TaskUpdate` with `metadata: {"iteration": N}` and `activeForm: "Iterating fix (N/2)"`. Summarize the verification failure. Pass the failed criteria and evidence back to the Builder (do NOT include the Verifier's internal reasoning or suggested fixes). Spawn a new Builder iteration (Step 2), then re-verify (Step 3).

  If iteration budget (2) is exhausted, use `AskUserQuestion` with options:
  - "Escalate to full pipeline" — the bug needs deeper decomposition; switch to `/rnd-framework:start`
  - "Iterate one more time" — extend budget by 1
  - "Abandon task" — stop work on this bug

Debug mode is focused, not lenient. The Verifier still applies full skepticism. Two failed fix attempts usually signal the diagnosis was incomplete or the bug is more architectural than it appeared — escalate rather than keep iterating.
