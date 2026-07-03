---
description: "Debug pipeline: reproduce a bug, diagnose root cause, fix, and verify using specialized agents."
argument-hint: "<bug description or symptom>"
effort: high
---

# R&D Framework: Debug Mode

For reported bugs that need root cause analysis before fixing. Diagnosis runs inline; build and verify phases spawn specialized agents. Use `/rnd-framework:rnd-start` if the bug turns out to be architectural.

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

Write a minimal plan skeleton to `$RND_DIR/protocol.md`. Use `TaskCreate` to create a single task.

Tell the user: "Starting debug pipeline for: [bug description]"

## Step 1: Diagnose

Invoke `rnd-framework:rnd-debug-pipeline` and `rnd-framework:rnd-debugging` to load debugging discipline. If the bug involves a DSL, grammar, parser, interpreter, compiler, renderer, executor, or validator, also invoke `rnd-framework:rnd-language-design` before analyzing those paths.

**Diagnosis-Only Boundary.** Diagnosis is read-only with respect to the project tree — the only permitted writes are `$RND_DIR` artifacts (`diagnosis/T1-diagnosis.md`, `protocol.md`). All project mutation belongs to the Builder in Step 2.

### Phase 1: Reproduce the Bug

1. **Read the bug report.** Note the exact symptoms, affected files, and reproduction steps.
2. **Reproduce consistently.** Run the reproduction steps. Confirm the failure is deterministic. If the bug does not reproduce, document this and stop.
3. **Capture raw evidence.** Record the exact error output, stack trace, and failing command verbatim.

### Phase 2: Root Cause Analysis

1. **Trace data flow.** Follow the failure backward through the call stack. Use Read, Grep/Glob to identify where the bad value originates. If the trace needs a broad codebase sweep, spawn `rnd-framework:rnd-explorer` (narrow read-only grant, spawns reliably) — never the built-in `Explore` or `general-purpose` agents, which fail to spawn with "Prompt is too long" in MCP-heavy sessions.
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

Write the full pre-registration to `$RND_DIR/protocol.md`, informed by the diagnosis report. Success criteria must include:
- Bug is no longer reproducible using the original reproduction steps
- Fix targets the root cause (not a symptom patch)
- 1-2 criteria specific to the root cause
- Existing tests continue to pass (no regressions)

Spawn an `rnd-builder` agent to implement the fix:

```
subagent_type: "rnd-framework:rnd-builder"
mode: "acceptEdits"
prompt: |
  You are building the fix for: [bug description]

  RND_DIR: [value of $RND_DIR]

  Pre-registration: [paste the pre-registration from $RND_DIR/protocol.md]

  Diagnosis report: [paste $RND_DIR/diagnosis/T1-diagnosis.md]

  Implement the fix using TDD. Save the build manifest to $RND_DIR/builds/M<NN>-T<NN>-<uuid>-manifest.md
  and the self-assessment to $RND_DIR/builds/<task-id>-self-assessment.md, where <task-id>
  is the task's canonical `features.json` id `M<N>.T<NN>.<slug>`.

  ${SESSION_SKILLS_FRAGMENT}
```

The agent completes and returns via `SendMessage`. Wait for it before proceeding.

## Step 3: Verify the Fix

**CRITICAL: Information Barrier.** Do NOT pass the self-assessment to the verifier agent. The verifier must assess work purely against the pre-registered criteria.

Spawn an `rnd-verifier` agent to verify the fix:

```
subagent_type: "rnd-framework:rnd-verifier"
mode: "acceptEdits"
prompt: |
  You are verifying the fix for: [bug description]

  RND_DIR: [value of $RND_DIR]

  Pre-registration: [paste the pre-registration from $RND_DIR/protocol.md]

  Builder artifacts:
  - Build manifest: $RND_DIR/builds/M<NN>-T<NN>-<uuid>-manifest.md

  Do NOT read $RND_DIR/builds/<task-id>-self-assessment.md — information barrier.

  Write independent experiment tests from the spec, run them, inspect the code,
  and save the verification report to $RND_DIR/verifications/T1-verification.md.

  ${SESSION_SKILLS_FRAGMENT}
```

The agent completes and returns its verdict via `SendMessage`. Wait for it before proceeding.

## Step 4: Iterate or Ship

- **PASS** → Mark task `completed`. **MANDATORY:** Invoke `rnd-framework:rnd-formatting` BEFORE doc-polish. Then invoke `rnd-framework:rnd-doc-polish`. Then use `AskUserQuestion`:
  - "Commit changes (Recommended)"
  - "Bump version, tag and push"
  - "Review artifacts or narrative" — follow up with a sub-menu: "Show development narrative" or "Review artifacts"
  - "Finish session"

- **PASS (quality: NEEDS ITERATION)** → Treat as PASS. Show quality feedback. Present same options.

- **FAIL** → Keep task `in_progress`. Track iteration count. Before re-iterating, check for a verdict flip:

  ```bash
  RND_DIR="$RND_DIR" "${CLAUDE_PLUGIN_ROOT}/lib/audit-scan.sh" verdict_history T1
  ```

  If the output is `FLIP_DETECTED` (the verdict history oscillated, e.g. PASS → FAIL → PASS), the fix is churning rather than converging. Stop and use `AskUserQuestion`:
  - "Escalate to full pipeline" — `/rnd-framework:rnd-start` with proper decomposition
  - "Abandon task"

  Otherwise re-implement and re-verify. If iteration budget (2) exhausted:
  - "Escalate to full pipeline"
  - "Iterate one more time"
  - "Abandon task"

## Output Discipline

This command produces report artifacts (`T<id>-diagnosis.md`, `M<NN>-T<NN>-<uuid>-manifest.md`, `T<id>-verification.md`, `wave-<N>-verdict-map.json`). Each MUST be surfaced per the **Report Surfacing Protocol** in your active output style: print the file path followed by the file's complete contents verbatim BEFORE the next-step prompt — in the same turn, including in autonomous/loop mode. Summarizing a verdict ("Verifier returned PASS — proceed?") without first printing the report verbatim is a defect.
