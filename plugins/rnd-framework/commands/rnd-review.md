---
description: "Review recent code changes with evidence-based rigor. Detects architecture, security, correctness, testing, KISS compliance, style, and pipeline-context-hygiene issues."
argument-hint: "[commit range like HEAD~3..HEAD | directory path | empty for uncommitted changes]"
effort: high
---

# R&D Framework: Code Review

Review code changes using structured review criteria — single-pass, thorough inline analysis.

**Distinct from Claude Code's native `/code-review`** (correctness + reuse/simplification cleanups at a chosen effort level, with an optional `--fix` to apply findings to the working tree). This pipeline-style review covers **seven categories** (architecture, security, correctness, testing, KISS, style, pipeline-context hygiene), writes a **persistent report** at `$RND_DIR/review-report.md`, and offers `/rnd-framework:rnd-start` as the recommended next step so findings flow into the full plan → build → verify pipeline. Reach for native `/code-review` when you want a focused single-pass diff scan; reach for this when you want a broader audit that produces an artifact and integrates with the framework.

## Setup

```bash
RND_DIR=$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh" -c)
REVIEW_REPORT="$RND_DIR/review-report.md"
mkdir -p "$(dirname "$REVIEW_REPORT")"
```

## Review-Only Boundary

`rnd-review` is read-only with respect to the project tree. Do not modify, create, delete, format, stage, commit, push, tag, or otherwise mutate project files during the review. The only permitted write is `$RND_DIR/review-report.md`, plus creating `$RND_DIR` if it does not exist.

If the user chooses the fix option, stop the review after recommending the separate `/rnd-framework:rnd-start` command. Do not fix findings inline from inside `rnd-review`.

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
2. **Load KISS practices.** Invoke `rnd-framework:rnd-kiss-practices` and read the language files matching the project's stack.
3. **Load review criteria.** Invoke `rnd-framework:rnd-code-review` to load the seven review categories, four severity levels, verdict taxonomy, and report template.
4. **Load language-design guidance when relevant.** If the diff touches a DSL, grammar, parser, interpreter, compiler, renderer, executor, or validator, invoke `rnd-framework:rnd-language-design` before reviewing those changes.

## Phase 2: Review

Systematically examine the diff against the seven review categories:
- Architecture, Security, Correctness, Testing, KISS compliance, Style, Pipeline-context hygiene

For each category, check every changed file. Use Read/Grep to inspect surrounding context. If a large diff warrants a broad codebase sweep, spawn `rnd-framework:rnd-explorer` (narrow read-only grant, spawns reliably) — never the built-in `Explore` or `general-purpose` agents, which inherit the full MCP tool surface and fail to spawn with "Prompt is too long" in MCP-heavy sessions. Produce findings with severity levels (critical, major, minor, info).

Save the review report to `$RND_DIR/review-report.md` with an `## Overall Verdict: CLEAN | ISSUES_FOUND | CRITICAL_ISSUES` line.

## Required Review Report Contents

Write `$RND_DIR/review-report.md` using the report structure from `rnd-code-review`, without copying its full category table into this command.

The report must include `## Review Coverage Ledger` with an evidence-bearing entry for every changed file, including files that were skipped. Each ledger entry must record:
- the changed file examined
- the review categories covered
- commands or evidence used
- whether the file was examined or skipped, and the reason when skipped
- unavailable checks, if any, with reasons
- resulting findings, or an explicit "no findings" note backed by file paths, line references, or equivalent reproducible evidence

Do not imply coverage you did not achieve. If a file or check could not be examined, record that limit explicitly in the ledger. Record unavailable checks in the coverage ledger rather than treating them as clean.

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

This command produces a report artifact at `$RND_DIR/review-report.md`. Surface it per the **Report Surfacing Protocol** in your active output style: print the file path followed by the file's complete contents verbatim BEFORE any next-step prompt — in the same turn, including in autonomous/loop mode. Summarizing or merely referencing the file ("Review complete — see review-report.md") without printing it verbatim is a defect.
