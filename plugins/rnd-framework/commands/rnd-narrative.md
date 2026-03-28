---
description: "Generate a development narrative for a pipeline session — a prose story of what was built, key decisions, obstacles, insights, and what's left."
argument-hint: "[session ID like 20260314-090202-b54e | empty for most recent session]"
effort: low
---

# R&D Framework: Development Narrative

Generate a human-readable narrative of a pipeline session from its artifacts. Use this after a session ends, or anytime you want to understand what happened in a past run.

## Step 1: Resolve the Session

Parse `$ARGUMENTS` to find the target session:

- **If `$ARGUMENTS` is a session ID** (matches `YYYYMMDD-HHMMSS-XXXX` format): resolve it to `<base>/sessions/<session-id>/`
- **If `$ARGUMENTS` is empty**: check for an active session first. If none, use the most recent session directory (latest by name sort under `<base>/sessions/`).

```bash
RND_DIR=$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh")
```

If no session directory is found, tell the user: "No pipeline sessions found for this project. Run `/rnd-framework:rnd-start` or `/rnd-framework:rnd-quick` first." and stop.

## Step 2: Read Artifacts

Read all available artifacts from the session directory. Not all may exist (quick mode sessions have fewer artifacts than full pipeline runs). Read what's there:

- `$RND_DIR/plan.md` — task tree, pre-registrations, dependencies, schedule
- `$RND_DIR/builds/T*-manifest.md` — what each builder produced (use Glob: `$RND_DIR/builds/*-manifest.md`)
- `$RND_DIR/verifications/T*-verification.md` — verifier verdicts and findings (use Glob: `$RND_DIR/verifications/*-verification.md`)
- `$RND_DIR/iteration-log.md` — iteration cycles, if any
- `$RND_DIR/integration/wave-*-report.md` — integration results (use Glob: `$RND_DIR/integration/*-report.md`)
- `$RND_DIR/design-spec.md` — architectural alternatives and approved design, if the session used design exploration
- `$RND_DIR/brainstorm.md` — brainstorming output, if the session saved one

If `plan.md` doesn't exist, the session may have been a brainstorming-only or review-only run — adapt the narrative accordingly.

## Step 3: Generate Narrative

From the artifacts, produce a prose narrative. Do NOT spawn agents — write this yourself. Cover:

1. **What was built and why** — the original task from the plan, how many tasks/waves, what the final deliverables are
2. **Key decisions** — architectural choices from the design spec (if present), scope decisions from planning, trade-offs chosen
3. **Obstacles and iterations** — verification failures from the iteration log, any NEEDS ITERATION or FAIL verdicts, re-plans, blocked tasks
4. **Insights gained** — interesting patterns from verification reports, unexpected findings, quality feedback
5. **What's left** — deferred quality feedback, open questions from the plan, known limitations noted in verification reports

**Format:** Write as prose paragraphs, not a bullet list. Use first person plural ("we"). Keep it concise — 3-5 paragraphs. The goal is a story that gives the developer a sense of connection to the process.

**Adapt to what's available.** A quick-mode session might only have a plan and one verification report. A full pipeline run will have everything. A brainstorm session will only have brainstorm.md. Write the narrative from whatever artifacts exist — don't complain about missing files.

## Step 4: Present

Output the full narrative as regular text. Then use `AskUserQuestion`/`AskUser`:

- "Done" — end the command
- "Save to file" — save the narrative to `$RND_DIR/narrative.md` for future reference
- "Browse session artifacts" — show the full list of files in the session directory
