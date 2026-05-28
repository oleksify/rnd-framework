---
description: "Review recent code changes with evidence-based rigor. Detects architecture, security, correctness, testing, KISS compliance, and style issues."
argument-hint: "[commit range like HEAD~3..HEAD | directory path | empty for uncommitted changes]"
effort: high
---

# R&D Framework: Code Review

Review code changes using structured review criteria — single-pass, thorough inline analysis.

**Distinct from Claude Code's native `/code-review`** (correctness + reuse/simplification cleanups at a chosen effort level, with an optional `--fix` to apply findings to the working tree). This pipeline-style review covers **six categories** (architecture, security, correctness, testing, KISS, style), writes a **persistent report** under `$RND_DIR/review/`, and offers `/rnd-framework:rnd-start` as the recommended next step so findings flow into the full plan → build → verify pipeline. Reach for native `/code-review` when you want a focused single-pass diff scan; reach for this when you want a broader audit that produces an artifact and integrates with the framework.

## Setup

```bash
RND_DIR=$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh" -c)
mkdir -p "$RND_DIR/review"
```

## Phase 0: Scope Detection

Parse `$ARGUMENTS` to determine what to review:

- **Empty / no arguments** — review uncommitted changes:
  ```bash
  git diff
  git diff --staged
  ```
- **Contains `..`** (e.g. `HEAD~3..HEAD`) — review a commit range:
  ```bash
  git diff <range>
  ```
- **Otherwise** — treat as a file or directory path:
  ```bash
  git diff HEAD -- <path>
  ```

Collect the full diff output and the list of changed files. If the diff is empty, tell the user: "No changes found for the given scope. Nothing to review." and stop.

## Phase 1: Context Loading

1. **Detect tech stack.** Scan changed file extensions to identify the project's languages and frameworks.
2. **Load KISS practices.** Invoke `rnd-framework:kiss-practices` and read the language files matching the project's stack.
3. **Load review criteria.** Invoke `rnd-framework:code-review` to load the six review categories, four severity levels, verdict taxonomy, and report template.

## Phase 2: Review

Systematically examine the diff against the six review categories:
- Architecture, Security, Correctness, Testing, KISS compliance, Style

For each category, check every changed file. Use Read/Grep to inspect surrounding context. Produce findings with severity levels (critical, major, minor, info).

Save the review report to `$RND_DIR/review-report.md` with an `## Overall Verdict: CLEAN | ISSUES_FOUND | CRITICAL_ISSUES` line.

## Phase 3: Report

Present findings using `AskUserQuestion`:

- If **CLEAN**: "Review complete — no issues found." Options:
  - "Finish review"
  - "Review report details"

- If **ISSUES_FOUND**: "Review complete — issues found. See `$RND_DIR/review-report.md`." Options:
  - "Fix with /rnd-framework:rnd-start (Recommended)"
  - "Review report details"
  - "Dismiss"

- If **CRITICAL_ISSUES**: "Review complete — critical issues found." Options:
  - "Fix with /rnd-framework:rnd-start (Recommended)"
  - "Review report details"
  - "Dismiss"

## Output Discipline

This command produces a report artifact under `$RND_DIR/review/`. Surface it per the **Report Surfacing Protocol** in your active output style: print the file path followed by the file's complete contents verbatim BEFORE any next-step prompt — in the same turn, including in autonomous/loop mode. Summarizing or merely referencing the file ("Review complete — see review.md") without printing it verbatim is a defect.
