---
description: "Audit the full codebase with evidence-based rigor. Detects architecture, security, correctness, testing, KISS compliance, style, and pipeline-context-hygiene issues across all tracked files."
argument-hint: "[optional focus area like \"security\" or \"tests\" | empty for full audit]"
effort: high
---

# R&D Framework: Codebase Audit

Audit the entire tracked codebase with evidence-based rigor. `rnd-audit` is a full-codebase coverage pass, not a diff review. Use `/rnd-framework:rnd-review` for diff-oriented review of recent changes, and keep `rnd-code-review` as the shared source of truth for the seven review categories, severity levels, verdict taxonomy, and report template.

## Setup

```bash
RND_DIR=$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh" -c)
AUDIT_REPORT="$RND_DIR/audit-report.md"
mkdir -p "$(dirname "$AUDIT_REPORT")"
```

## Audit-Only Boundary

`rnd-audit` is read-only with respect to the tracked project tree. Do not modify, create, delete, format, stage, commit, push, tag, or otherwise mutate tracked project files during the audit. The only permitted write is `$RND_DIR/audit-report.md`, plus creating `$RND_DIR` if it does not exist.

If the user chooses the fix option, stop the audit after recommending the separate `/rnd-framework:rnd-start` command. Do not start the fix pipeline from inside `rnd-audit`.

## Phase 0: Standards Discovery

1. **Build the tracked file tree:** `git ls-files`
2. **Read all CLAUDE.md files** — use Glob with pattern `**/CLAUDE.md`. Read each discovered file.
3. **Detect the tech stack.** Scan file extensions in the tracked file tree. Frontend technology detection is mandatory whenever any tracked UI surface exists.
4. **Partition the tracked tree into auditable file groups.** Use language, package, feature, or infrastructure boundaries that let you prove every tracked path was considered, then carry those groups into the coverage ledger.

If `$ARGUMENTS` is non-empty, treat it as a focus area hint (judges still examine the full codebase).

## Phase 1: Context Loading

1. **Load KISS practices.** Invoke `rnd-framework:rnd-kiss-practices` for the detected tech stack.
2. **Read only the relevant language-specific KISS files.** After stack detection, read only the KISS guidance files for languages actually present in the tracked tree. Do not load irrelevant language files.
3. **Load review criteria.** Invoke `rnd-framework:rnd-code-review` to load the shared categories, severity levels, verdict taxonomy, and report template.
4. **Load language-design guidance when relevant.** If the codebase defines or changes a DSL, grammar, parser, interpreter, compiler, renderer, executor, or validator, invoke `rnd-framework:rnd-language-design` before auditing those paths.

## Phase 2: Audit

Systematically examine the full tracked codebase against the seven review categories defined in `rnd-code-review`:
- Architecture, Security, Correctness, Testing, KISS compliance, Style, Pipeline-context hygiene

Use Read, Grep, and Glob tools to inspect every tracked file group, not just changed files. When a broad codebase sweep warrants a subagent, spawn `rnd-framework:rnd-explorer` (narrow read-only grant, spawns reliably) — never the built-in `Explore` or `general-purpose` agents, which inherit the full MCP tool surface and fail to spawn with "Prompt is too long" in MCP-heavy sessions. Produce findings with severity levels (critical, major, minor, info).

For each group, cover the shared seven categories and run these audit-specific subchecks:
- secrets exposure or committed credentials
- shell safety
- information barriers and read gates
- artifact contracts and report-path expectations
- dependency trust, supply chain assumptions, and pinning gaps
- accessibility
- code-inferable UI/UX/design quirks
- package-manager-aware frontend and backend vulnerable dependency checks
- package-manager-aware frontend and backend outdated dependency checks
- stale docs or stale canonical guidance
- test adequacy for the code under audit

When the tracked tree includes frontend code, frontend technology detection, accessibility, and code-inferable UI/UX/design quirks are mandatory parts of the audit. Separate code-inferable findings from runtime, browser, or screenshot evidence. Do not present runtime, browser, or screenshot evidence as though it came from static source inspection.

Save the audit report to `$RND_DIR/audit-report.md` with Scope set to "Full codebase audit" and an `## Overall Verdict: CLEAN | ISSUES_FOUND | CRITICAL_ISSUES` line.

## Required Audit Report Contents

Write `$RND_DIR/audit-report.md` using the report structure from `rnd-code-review`, without copying its full category table into this command.

The report must include `## Audit Coverage Ledger` with evidence-bearing entries for every tracked file group, including skipped groups. Each ledger entry must record:
- the tracked file groups examined, including tracked paths or patterns
- the review categories covered
- the audit-specific subchecks run
- commands or evidence used
- whether the group was examined or skipped, and the reason when skipped
- unavailable checks, if any, with reasons
- unavailable checks caused by missing tools, permissions, credentials, unsupported ecosystems, or runtime evidence gaps, and whether package-manager-aware frontend and backend vulnerable dependency checks or package-manager-aware frontend and backend outdated dependency checks were completed or unavailable
- resulting findings, or an explicit "no findings" note backed by file paths, line references, or equivalent reproducible evidence

Do not imply coverage you did not achieve. If a group or check could not be examined, record that limit explicitly in the ledger. Record unavailable checks in the coverage ledger rather than treating them as clean.

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

This command produces the report artifact at `$RND_DIR/audit-report.md`. Surface it per the **Report Surfacing Protocol** in your active output style: print the file path followed by the file's complete contents verbatim BEFORE any next-step prompt — in the same turn, including in autonomous/loop mode. Summarizing or merely referencing the file ("Audit complete — see audit-report.md") without printing it verbatim is a defect.
