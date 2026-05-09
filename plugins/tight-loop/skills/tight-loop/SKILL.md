---
name: tight-loop
description: Single-agent three-step ritual — pre-register, implement, self-review — with evidence-per-criterion requirements and hook-enforced honesty.
effort: medium
---

# Tight Loop

A disciplined single-agent workflow for tasks where you want rigor without multi-agent ceremony. You pre-register what you will do, implement it, then review your own work honestly — with concrete evidence per criterion.

**When to use:** Any non-trivial task where you want a structured record of intent and evidence of completion. One task at a time.

---

## The Three-Step Ritual

### Step 1 — Pre-Register

Before writing a single line of production code or editing any project file, write a pre-registration document. This is the contract you will hold yourself to in Step 3.

**Why first:** The prereg-gate hook blocks all Write/Edit operations on project files until a `prereg-<task-slug>.md` file exists in the artifact directory. You cannot skip this step.

**Where to write it:** `~/.claude/.tight-loop/<project-slug>/prereg-<task-slug>.md`

Compute `<project-slug>` from the git root basename + an 8-character hash of the canonicalized git path. Compute `<task-slug>` as a short kebab-case label for the task (e.g., `add-retry-logic`, `fix-null-check`). Use only lowercase letters, digits, and hyphens.

**Pre-registration template:**

```markdown
# Pre-Registration: <task-slug>

## Task
One or two sentences describing the task. Be specific — vague descriptions produce vague reviews.

## Approach
Bullet list of the concrete steps you will take. Not aspirations — actual steps.

## Success Criteria
Numbered list. Each criterion must be:
- Testable (you can run a command or read a file and know if it passes)
- Concrete (no "should work" — say what exact output or behavior you expect)

Example:
1. `grep -c 'function retry' src/http.ts` outputs 1
2. `bun test src/http.test.ts` exits 0 with "retry" test passing
3. Log output contains "Retrying attempt N" for N=1,2,3

## Verification Plan
For each criterion above, state how you will verify it. Command to run, file to read, or output to check.

## Artifacts
- Pre-reg: this file
- Report: `~/.claude/.tight-loop/<project-slug>/report-<task-slug>.md`
- Found-issues ledger: `~/.claude/.tight-loop/<project-slug>/found-issues.jsonl`
```

---

### Step 2 — Implement

Implement the task following your pre-registered approach.

**Rules during implementation:**

- Write tests before the code they test. Watch each test fail before making it pass.
- One logical change at a time. Explain the change before making it.
- When you hit an issue (error, warning, broken test, bug, gap), you must either fix it or log it to the found-issues ledger. Silent dismissal is not an option.
- Do not deviate from the pre-registered approach without documenting the deviation. If the approach is fundamentally wrong, update the pre-reg before continuing — do not silently adapt.

**Found-issues ledger:** `~/.claude/.tight-loop/<project-slug>/found-issues.jsonl`

One JSON line per issue encountered, even if you fix it immediately:

```json
{"issue": "<what went wrong>", "location": "<file:line or 'general'>", "decision": "fixed", "reason": "<what you did to fix it>"}
{"issue": "<what you cannot fix here>", "location": "<file:line>", "decision": "escalated", "reason": "<why it is out of scope for this task>"}
```

`decision: "escalated"` is the only honest way to declare a problem out of scope. It surfaces the issue to the user rather than burying it.

---

### Step 3 — Self-Review

Walk each success criterion from Step 1 and verify it. For every criterion, attach concrete evidence — a command you ran, the exact output, or a file:line reference. Do not assert; demonstrate.

**Evidence format per criterion:**

```
Criterion N: <criterion text>
Status: PASS | FAIL | PARTIAL
Evidence: <command run> → <exact output or summary>
```

If a criterion fails or is only partially met, fix it before producing the final report. Self-review is silent-iterating: the user only sees the clean final report after all gaps are closed.

If you cannot close a gap, log it to the found-issues ledger with `decision: "escalated"` and include it in the final report. This is the only honest alternative to a full PASS.

---

## The Final Report

When all criteria are verified (or honestly escalated), emit the final report wrapped in the `<final-report>` marker. The dismissal-gate Stop hook fires only when this marker is present — if you do not emit it, the hook does not fire.

**Structure:**

```
<final-report>
# Final Report: <task-slug>

## Summary
One or two sentences on what was done and the outcome.

## Criteria Review
<paste the evidence block from Step 3 here — one entry per criterion>

## Found Issues
<paste any found-issues ledger entries here, or write "None.">

## Artifacts
- Pre-reg: `~/.claude/.tight-loop/<project-slug>/prereg-<task-slug>.md`
- Report: `~/.claude/.tight-loop/<project-slug>/report-<task-slug>.md`
</final-report>
```

Also write the report to `~/.claude/.tight-loop/<project-slug>/report-<task-slug>.md` so it persists beyond the session.

---

## What the Hooks Enforce

**prereg-gate (PreToolUse Write/Edit):** Blocks any Write or Edit to a non-artifact project file unless a `prereg-*.md` file exists in the artifact directory. You cannot edit project code before completing Step 1. Writes to `~/.claude/.tight-loop/` are always allowed.

**dismissal-gate (Stop):** Fires only when the most recent assistant message contains a `<final-report>` marker. When it fires, it checks for:

1. **Dismissal phrases** — `pre-existing`, `out of scope`, `not my task`, `unrelated to this task`, `won't fix here`, `outside scope`. Any of these in the final report blocks the stop with an error.
2. **Unacknowledged problems** — If the report mentions an error, failure, or problem term but the found-issues ledger is missing or empty, the stop is blocked. The ledger is the proof that the issue was addressed honestly.

The only legal path past the dismissal-gate when a problem exists is a ledger entry with `decision: "escalated"` that names the issue explicitly. This makes honest escalation structurally easier than dismissal.

---

## Quick Reference

| Step | What you produce | Where |
|------|-----------------|-------|
| Pre-register | `prereg-<task-slug>.md` | `~/.claude/.tight-loop/<project-slug>/` |
| Implement | Code, tests, fixes | Project files |
| Self-review | `<final-report>` in chat + `report-<task-slug>.md` | Chat + artifact dir |
| Found issues | `found-issues.jsonl` | `~/.claude/.tight-loop/<project-slug>/` |

**The user is the final judge.** There is no automated PASS gate. The agent produces a structured, evidence-backed report; the user reads it and decides.
