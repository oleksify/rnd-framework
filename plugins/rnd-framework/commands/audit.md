---
description: "Audit the full codebase with multi-judge evidence-based rigor. Detects architecture, security, correctness, testing, KISS compliance, and style issues across all tracked files."
argument-hint: "[optional focus area like \"security\" or \"tests\" | empty for full audit]"
---

# R&D Framework: Codebase Audit

Audit the entire codebase using the multi-judge protocol — two independent verifier agents systematically explore all tracked files against project standards, with a tiebreaker on disagreement.

## Setup

```bash
RND_DIR=$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh" -c)
mkdir -p "$RND_DIR/audit"
```

## Phase 0: Standards Discovery

Build the full picture of the codebase and its standards.

1. **Build the tracked file tree** using `git ls-files` (respects `.gitignore`, excludes untracked files):
   ```bash
   git ls-files
   ```

2. **Read all CLAUDE.md files** — collect project standards from root and all nested locations. Use the `Glob` tool with pattern `**/CLAUDE.md` to discover all instances. Read each discovered `CLAUDE.md` file in full. These are the authoritative standards sources for this codebase.

3. **Detect the tech stack.** Scan the file extensions in the `git ls-files` output to identify the project's languages and frameworks (e.g., `.ts`, `.py`, `.go`, `.rb`, `.md`).

If `$ARGUMENTS` is non-empty, treat it as an optional focus area (e.g., `"security"` or `"tests"`) to pass to judges as a suggested emphasis. Judges still examine the full codebase — the focus area is a hint, not a constraint.

## Phase 1: Context Loading

1. **Load KISS practices.** Invoke `rnd-framework:kiss-practices` and read the language files matching the detected tech stack. Include the applicable KISS rules in the audit prompt.

2. **Load review criteria.** Invoke `rnd-framework:code-review` to load the six review categories, four severity levels, verdict taxonomy, and report template.

## Phase 2: Multi-Judge Audit

Compose the audit prompt for verifier agents. Include:
- The full tracked file tree (output of `git ls-files`)
- All discovered standards: the full contents of every `CLAUDE.md` file found
- The six review categories from the code-review skill (architecture, security, correctness, testing, KISS compliance, style)
- The four severity levels (critical, major, minor, info) and their verdict effects
- The KISS rules for the detected tech stack
- If `$ARGUMENTS` was non-empty: a note that judges should emphasize that focus area while still covering all categories
- Instruction: systematically examine the codebase — this is a full audit, not a diff review. Use the `Read`, `Grep`, and `Glob` tools to explore files freely. Examine every file in the file tree; do not limit examination to a provided diff.
- Instruction: produce a structured report using the review report template, one section per category, with an `## Overall Verdict: CLEAN | ISSUES_FOUND | CRITICAL_ISSUES` line
- Instruction: set the **Scope** field in the report to "Full codebase audit"

**Spawn 2 verifier agents in parallel** using the Agent tool with `subagent_type: "rnd-framework:rnd-verifier"`. Each receives the same audit prompt independently.

After both return:
- Save Judge A's report to `$RND_DIR/audit/judge-a.md`
- Save Judge B's report to `$RND_DIR/audit/judge-b.md`

**Consensus logic:** Compare the `## Overall Verdict` lines from both reports.

- **Both agree** — their shared verdict is the final verdict. Proceed to Phase 3.
- **Disagree** — spawn a tiebreaker: a third agent with `subagent_type: "rnd-framework:rnd-verifier"`, passing the same audit prompt plus both prior reports (Judge A and Judge B). Save the tiebreaker report to `$RND_DIR/audit/tiebreaker.md`. The tiebreaker's verdict is the final verdict.

## Phase 3: Report

Compile the final audit report from the consensus verdict:
- If both judges agreed: synthesize findings from both reports (merge duplicate findings, keep unique ones)
- If tiebreaker was used: use the tiebreaker's findings as the primary report, noting the disagreement

Save the compiled report to `$RND_DIR/audit-report.md`. Ensure the **Scope** line in the report reads "Full codebase audit".

The three possible overall verdicts are: **CLEAN**, **ISSUES_FOUND**, **CRITICAL_ISSUES**.

Present findings using `AskUserQuestion`:

- If **CLEAN**: "Audit complete — no issues found. Codebase looks good." Options:
  - "Finish audit"
  - "Review audit report details" — show the full `$RND_DIR/audit-report.md`

- If **ISSUES_FOUND**: "Audit complete — major issues found. See `$RND_DIR/audit-report.md`." Options:
  - "Fix with /rnd-framework:quick (Recommended)" — lightweight pipeline for small fixes
  - "Fix with /rnd-framework:start" — full pipeline for larger changes
  - "Review audit report details" — show the full report
  - "Dismiss" — acknowledge and exit without action

- If **CRITICAL_ISSUES**: "Audit complete — critical issues found. See `$RND_DIR/audit-report.md`." Options:
  - "Fix with /rnd-framework:start (Recommended)" — full pipeline for systematic fixes
  - "Fix with /rnd-framework:quick" — lightweight pipeline for isolated fixes
  - "Review audit report details" — show the full report
  - "Dismiss" — acknowledge and exit without action
