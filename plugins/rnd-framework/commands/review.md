---
description: "Review recent code changes with multi-judge evidence-based rigor. Detects architecture, security, correctness, testing, KISS compliance, and style issues."
argument-hint: "[commit range like HEAD~3..HEAD | directory path | empty for uncommitted changes]"
---

# R&D Framework: Code Review

Review code changes using the multi-judge protocol — two independent verifier agents evaluate the diff against structured criteria, with a tiebreaker on disagreement.

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

Collect the full diff output and the list of changed files. If the diff is empty (no changes found), tell the user: "No changes found for the given scope. Nothing to review." and stop.

## Phase 1: Context Loading

1. **Detect tech stack.** Scan changed file extensions to identify the project's languages and frameworks.

2. **Load KISS practices.** Invoke `rnd-framework:kiss-practices` and read the language files matching the project's stack. Include the applicable KISS rules in the review prompt.

3. **Load review criteria.** Invoke `rnd-framework:code-review` to load the six review categories, four severity levels, verdict taxonomy, and report template.

## Phase 2: Multi-Judge Review

Compose the review prompt for verifier agents. Include:
- The full code diff
- The list of changed files
- The six review categories from the code-review skill (architecture, security, correctness, testing, KISS compliance, style)
- The four severity levels (critical, major, minor, info) and their verdict effects
- The KISS rules for the detected tech stack
- Instruction: produce a structured report using the review report template, one section per category, with an `## Overall Verdict: CLEAN | ISSUES_FOUND | CRITICAL_ISSUES` line

**Spawn 2 verifier agents in parallel** using the Agent tool with `subagent_type: "rnd-framework:rnd-verifier"`. Each receives the same review prompt independently.

After both return:
- Save Judge A's report to `$RND_DIR/review/judge-a.md`
- Save Judge B's report to `$RND_DIR/review/judge-b.md`

**Consensus logic:** Compare the `## Overall Verdict` lines from both reports.

- **Both agree** — their shared verdict is the final verdict. Proceed to Phase 3.
- **Disagree** — spawn a tiebreaker: a third agent with `subagent_type: "rnd-framework:rnd-verifier"`, passing the same review prompt plus both prior reports (Judge A and Judge B). Save the tiebreaker report to `$RND_DIR/review/tiebreaker.md`. The tiebreaker's verdict is the final verdict.

## Phase 3: Report

Compile the final review report from the consensus verdict:
- If both judges agreed: synthesize findings from both reports (merge duplicate findings, keep unique ones)
- If tiebreaker was used: use the tiebreaker's findings as the primary report, noting the disagreement

Save the compiled report to `$RND_DIR/review-report.md`.

The three possible overall verdicts are: **CLEAN**, **ISSUES_FOUND**, **CRITICAL_ISSUES**.

Present findings using `AskUserQuestion`:

- If **CLEAN**: "Review complete — no issues found. Code looks good." Options:
  - "Finish review"
  - "Review report details" — show the full `$RND_DIR/review-report.md`

- If **ISSUES_FOUND**: "Review complete — major issues found. See `$RND_DIR/review-report.md`." Options:
  - "Fix with /rnd-framework:quick (Recommended)" — lightweight pipeline for small fixes
  - "Fix with /rnd-framework:start" — full pipeline for larger changes
  - "Review report details" — show the full report
  - "Dismiss" — acknowledge and exit without action

- If **CRITICAL_ISSUES**: "Review complete — critical issues found. See `$RND_DIR/review-report.md`." Options:
  - "Fix with /rnd-framework:start (Recommended)" — full pipeline for systematic fixes
  - "Fix with /rnd-framework:quick" — lightweight pipeline for isolated fixes
  - "Review report details" — show the full report
  - "Dismiss" — acknowledge and exit without action
