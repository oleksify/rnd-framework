---
description: "Audit the full codebase with evidence-based rigor. Detects architecture, security, correctness, testing, KISS compliance, and style issues across all tracked files."
argument-hint: "[optional focus area like \"security\" or \"tests\" | empty for full audit]"
effort: high
---

# R&D Framework: Codebase Audit

Audit the entire codebase using structured review criteria — single-pass, thorough inline analysis.

## Setup

```bash
RND_DIR=$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh" -c)
mkdir -p "$RND_DIR/audit"
```

## Phase 0: Standards Discovery

1. **Build the tracked file tree:** `git ls-files`
2. **Read all CLAUDE.md files** — use Glob with pattern `**/CLAUDE.md`. Read each discovered file.
3. **Detect the tech stack.** Scan file extensions in the tracked file tree.

If `$ARGUMENTS` is non-empty, treat it as a focus area hint (judges still examine the full codebase).

## Phase 1: Context Loading

1. **Load KISS practices.** Invoke `rnd-framework:kiss-practices` for the detected tech stack.
2. **Load review criteria.** Invoke `rnd-framework:code-review` to load categories, severity levels, verdict taxonomy, and report template.

## Phase 2: Audit

Systematically examine the codebase against the six review categories:
- Architecture, Security, Correctness, Testing, KISS compliance, Style

Use Read, Grep, Glob tools to explore all tracked files. Examine every area — this is a full audit, not a diff review. Produce findings with severity levels (critical, major, minor, info).

Save the audit report to `$RND_DIR/audit-report.md` with Scope set to "Full codebase audit" and an `## Overall Verdict: CLEAN | ISSUES_FOUND | CRITICAL_ISSUES` line.

## Phase 3: Report

Present findings using `AskUserQuestion`/`AskUser`:

- If **CLEAN**: "Audit complete — no issues found." Options:
  - "Finish audit"
  - "Review audit report details"

- If **ISSUES_FOUND**: "Audit complete — issues found." Options:
  - "Fix with /rnd-framework:rnd-quick (Recommended)"
  - "Fix with /rnd-framework:rnd-start"
  - "Review audit report details"
  - "Dismiss"

- If **CRITICAL_ISSUES**: "Audit complete — critical issues found." Options:
  - "Fix with /rnd-framework:rnd-start (Recommended)"
  - "Fix with /rnd-framework:rnd-quick"
  - "Review audit report details"
  - "Dismiss"
