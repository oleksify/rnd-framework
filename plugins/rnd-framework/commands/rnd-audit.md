---
description: "Audit the full codebase with evidence-based rigor. Detects architecture, security, correctness, testing, KISS compliance, style, and pipeline-context-hygiene issues across all tracked files."
argument-hint: "[optional focus area like \"security\" or \"tests\" | empty for full audit]"
effort: high
---

# R&D Framework: Codebase Audit

Audit the entire codebase using structured review criteria — single-pass, thorough inline analysis.

## Setup

```bash
RND_DIR=$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh" -c)
AUDIT_REPORT="$RND_DIR/audit-report.md"
mkdir -p "$(dirname "$AUDIT_REPORT")"
```

## Phase 0: Standards Discovery

1. **Build the tracked file tree:** `git ls-files`
2. **Read all CLAUDE.md files** — use Glob with pattern `**/CLAUDE.md`. Read each discovered file.
3. **Detect the tech stack.** Scan file extensions in the tracked file tree.

If `$ARGUMENTS` is non-empty, treat it as a focus area hint (judges still examine the full codebase).

## Phase 1: Context Loading

1. **Load KISS practices.** Invoke `rnd-framework:rnd-kiss-practices` for the detected tech stack.
2. **Load review criteria.** Invoke `rnd-framework:rnd-code-review` to load categories, severity levels, verdict taxonomy, and report template.

## Phase 2: Audit

Systematically examine the codebase against the seven review categories:
- Architecture, Security, Correctness, Testing, KISS compliance, Style, Pipeline-context hygiene

Use Read, Grep, Glob tools to explore all tracked files. Examine every area — this is a full audit, not a diff review. When a broad codebase sweep warrants a subagent, spawn `rnd-framework:rnd-explorer` (narrow read-only grant, spawns reliably) — never the built-in `Explore` or `general-purpose` agents, which inherit the full MCP tool surface and fail to spawn with "Prompt is too long" in MCP-heavy sessions. Produce findings with severity levels (critical, major, minor, info).

Save the audit report to `$RND_DIR/audit-report.md` with Scope set to "Full codebase audit" and an `## Overall Verdict: CLEAN | ISSUES_FOUND | CRITICAL_ISSUES` line.

## Phase 3: Report

Present findings using `AskUserQuestion`:

- If **CLEAN**: "Audit complete — no issues found." Options:
  - "Finish audit"
  - "Review audit report details"

- If **ISSUES_FOUND**: "Audit complete — issues found." Options:
  - "Fix with /rnd-framework:rnd-start (Recommended)"
  - "Review audit report details"
  - "Dismiss"

- If **CRITICAL_ISSUES**: "Audit complete — critical issues found." Options:
  - "Fix with /rnd-framework:rnd-start (Recommended)"
  - "Review audit report details"
  - "Dismiss"

## Output Discipline

This command produces a report artifact at `$RND_DIR/audit-report.md`. Surface it per the **Report Surfacing Protocol** in your active output style: print the file path followed by the file's complete contents verbatim BEFORE any next-step prompt — in the same turn, including in autonomous/loop mode. Summarizing or merely referencing the file ("Audit complete — see audit-report.md") without printing it verbatim is a defect.
