---
description: "Lightweight R&D mode for small tasks (<1hr). Same principles, collapsed workflow: quick plan → build → independent verify. One Builder, one Verifier."
argument-hint: "<description of the small task>"
model: sonnet
effort: medium
---

# R&D Framework: Quick Mode

For small, well-scoped tasks. Same scientific-method principles, minimal ceremony. Design exploration is skipped in quick mode — use `/rnd-framework:start` if the task requires architectural trade-off analysis.

> **Iteration budget: 2** (vs. 3 in the full pipeline). Quick mode is designed for tasks small enough to get right in one or two attempts. If a task needs more than 2 iteration cycles, it is likely too large for quick mode — escalate to `/rnd-framework:start` for proper decomposition.

## Task Input

If `$ARGUMENTS` is empty (user ran `/rnd-framework:quick` with no task description):

1. **Quick codebase scan.** Run a few fast commands to gather context: `git log --oneline -10`, check for TODO/FIXME comments, look at recent changes. This takes seconds and informs your suggestions.

2. **Ask with `AskUserQuestion`.** Present 2-4 concrete task suggestions based on what you found, plus always include a generic "Describe a different task" option. Each option should have a short label and a description explaining what the task would involve.

3. **If the user picks a suggestion**, use it as the task description and continue to Step 1. **If they type a custom task**, use that instead.

**Never fall back to plain text** to ask what to work on. `AskUserQuestion` is mandatory at every decision point, including this one.

If `$ARGUMENTS` is provided, skip this section and proceed directly.

## Step 0: Coding Practices (inline — no Skill tool calls)

Quick mode does NOT invoke skills via the Skill tool during startup. Instead, apply these principles directly:

- **KISS:** Don't add features nobody asked for. Don't create abstractions for one-time operations. Validate at system boundaries only. Prefer native APIs over packages.
- **FP:** Prefer pure functions, immutable data, and composition. Separate commands from queries.
- **Project standards:** Follow the conventions in the project's CLAUDE.md files (already loaded in your context).

The full pipeline (`/rnd-framework:start`) loads language-specific KISS files and extracts project patterns — quick mode trusts the agent to apply these principles from context instead.

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

After building, assess your own work and set a status code based on your confidence:

- `DONE` — all criteria met, tests pass, no significant concerns. Proceed to Step 3.
- `DONE_WITH_CONCERNS` — criteria met but you have uncertainty (e.g., an unverified external dependency, a tricky edge case). Record the concerns in your self-assessment and pass a brief concerns summary to the Verifier in Step 3.

Quick mode does not use `NEEDS_CONTEXT` or `BLOCKED` — as the orchestrator, you can resolve context gaps and dependency issues directly without pausing.

## Step 3: Independent Verify

Update `activeForm` via `TaskUpdate` to reflect verification (e.g., "Verifying [task name]").

Spawn an agent using the Agent tool with `subagent_type: "rnd-framework:rnd-verifier"`, passing:
- The pre-registration from step 1
- Your code and tests
- If your status was `DONE_WITH_CONCERNS`, include the brief concerns summary so the Verifier knows which areas need extra scrutiny
- Do NOT pass your full self-assessment

The verifier returns its report as text output. The orchestrator saves the returned report to `$RND_DIR/verifications/T<id>-verification.md`.

## Step 4: Iterate or Ship

- **PASS** → Use `TaskUpdate` to mark the task `completed`. Summarize what was built and verified. **MANDATORY — DO NOT SKIP:** You MUST invoke `rnd-framework:rnd-doc-polish` BEFORE presenting the commit options below. This checks and updates CLAUDE.md, README.md, project docs, and stale inline comments. Report what was updated (or that everything is current). If you skip this step, the pipeline is incomplete. Use `AskUserQuestion` with options:
  - "Commit changes (Recommended)" — stage and commit the changes
  - "Show development narrative" — generate a narrative explanation of the session: what was built and why, key decisions and trade-offs, obstacles encountered, insights gained, and what's left. Write as prose (3-5 paragraphs, first person plural), not a bullet list. Do NOT spawn agents — generate from your own context (re-read `$RND_DIR` artifacts if context was compressed). After showing, re-present the same menu without this option.
  - "Review artifacts" — show the user the verification report and code changes
  - "Finish session" — run `"${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh" --finish` to clear the current session ID; artifacts are preserved on disk, but the next pipeline run will start a fresh session

- **PASS (quality: NEEDS ITERATION)** → Treat as PASS for pipeline purposes. Use `TaskUpdate` to mark the task `completed`. Show the quality feedback from the verification report to the user. Do NOT trigger an iteration cycle. Note: "Quality feedback noted. For small tasks, quality iteration is optional — review and address manually if needed." Then present the same `AskUserQuestion` options as a full PASS.

- **FAIL** → Keep task `in_progress`. Use `TaskUpdate` with `metadata: {"iteration": N}` and `activeForm: "Iterating [task name] (N/2)"` to track the cycle. Summarize the verification failure to the user. Get feedback, fix, re-verify.

  If iteration budget (2) is exhausted, use `AskUserQuestion` with options:
  - "Escalate to full pipeline" — switch to `/rnd-framework:start` for deeper decomposition
  - "Iterate one more time" — extend budget by 1
  - "Abandon task" — stop work on this task

Quick mode is faster, not less rigorous. The Verifier still applies full skepticism. Do not skip failure mode analysis or accept soft evidence to save time.
