---
name: code-review
description: "Use when reviewing code changes for quality, correctness, and security — defines review categories, severity levels, verdicts, and the structured report format"
effort: low
---

# Code Review

## Overview

Seven categories, four severity levels, three verdicts.

## Review Categories

| Category | What to examine |
|----------|----------------|
| **Architecture** | Module boundaries, dependency flow, coupling, cohesion |
| **Security** | Input validation, authentication, authorization, data exposure |
| **Correctness** | Edge cases, error handling, race conditions, off-by-one errors |
| **Testing** | Coverage, test quality, edge case tests, test independence |
| **KISS compliance** | Over-engineering, unnecessary abstractions, unused code, premature generalization |
| **Style** | Naming, consistency, readability, formatting |
| **Pipeline-context hygiene** | Session-specific tags leaking into canonical artifacts — see detection rules below |

## Pipeline-Context Hygiene — Detection Rules

R&D pipeline sessions emit identifiers (milestone, task, wave, framing-mode IDs) that are meaningful inside a session but rot once it ends. When these survive in canonical project artifacts they confuse future readers who never saw the run. Treat as **Minor** by default; **Major** when found in `CLAUDE.md`, `README.md`, or top-level `AGENTS.md` (high-visibility canonical docs).

**Flag these patterns:**
- **Narrative milestone-tag prefixes** in tree-diagram comments, section headers, or inline descriptions: `# M6: PreToolUse hook`, `# M5: archive helper`, `# M4 outside-view injector`, parentheticals like `(M3)` describing what a file does. Findings: strip the prefix, keep the description.
- **Test-comment trace tags** above test blocks or after `# Test N:` headings that key tests back to validation-contract assertion IDs from a specific session: `# M4.wiring.foo`, `(M2.calib.bar)`. Findings: strip the tag, keep the natural-language description.
- **Task / wave / framing identifiers** as narrative tokens in comments or docstrings: `T1`, `T01`, `T14`, `M2`, `wave-3`, `FM6`.
- **Session artifact paths or meta-references** in non-pipeline files: `research/*.md`, `plan.md`, `T<id>-manifest.md`, "the R&D session", "the pipeline".
- **Variable names** carrying session tags: `m4_section`, `wave3_helper`. Findings: rename to a domain-grounded identifier.

**Do NOT flag (these are framework-own guidance):**
- ID-format documentation in agent/skill specs: `M<N>.<area>.<slug>`, `T<id>`, `wave-<N>`, `FM<k>` — these document the canonical schema.
- Example IDs inside example JSON/code blocks in agent or skill spec files (didactic snippets showing what a valid verdict-map or features.json looks like).
- Sample IDs inside test fixture data — heredoc/printf content creating validation-contract.md or features.json fixtures (these test the parser; the IDs are the payload, not narrative pollution).
- Roadmap-template placeholder rows (`### M1: [Title]`, `### M2: [Title]`) demonstrating the roadmap format.

## Severity Levels

| Severity | When to use | Effect on verdict |
|----------|-------------|-------------------|
| **Critical** | Must fix before merge — bugs, security holes, data loss risk | Triggers CRITICAL_ISSUES |
| **Major** | Should fix — logic errors, missing validation, poor error handling | Triggers ISSUES_FOUND |
| **Minor** | Nice to fix — naming, style inconsistency, minor simplification | No verdict change |
| **Info** | Informational — trade-off notes, alternative approaches | No verdict change |

## Verdicts

| Verdict | Condition |
|---------|-----------|
| **CLEAN** | No critical or major findings across all categories |
| **ISSUES_FOUND** | At least one major finding; no critical findings |
| **CRITICAL_ISSUES** | At least one critical finding |

## Review Report Template

```markdown
# Code Review Report

**Scope:** [commit range, branch, or path reviewed]
**Reviewed by:** [agent identity]
**Date:** [ISO date]

## Findings

### Architecture
- [severity] [finding] — [file:line if applicable]

### Security
- [severity] [finding] — [file:line if applicable]

### Correctness
- [severity] [finding] — [file:line if applicable]

### Testing
- [severity] [finding] — [file:line if applicable]

### KISS Compliance
- [severity] [finding] — [file:line if applicable]

### Style
- [severity] [finding] — [file:line if applicable]

### Pipeline-Context Hygiene
- [severity] [finding] — [file:line if applicable]

## Overall Verdict: CLEAN | ISSUES_FOUND | CRITICAL_ISSUES

[One sentence justifying the verdict, referencing the highest-severity finding.]
```

## Review Rules

- Every finding must include a proposed fix. Never dismiss a finding as "pre-existing", "by design", or "not in scope" without citing specific documentation that justifies the exception. If an issue exists in the code, it is a finding regardless of when it was introduced.

## Related Skills

- `rnd-framework:rnd-verification` — Evidence-based verification process
