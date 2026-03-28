---
name: code-review
description: "Use when reviewing code changes for quality, correctness, and security — defines review categories, severity levels, verdicts, and the structured report format"
effort: low
---

# Code Review

## Overview

A structured code review framework with six categories, four severity levels, and three verdicts. Use this as the shared specification when performing code reviews or interpreting review output.

## Review Categories

Reviews must address exactly these six categories:

| Category | What to examine |
|----------|----------------|
| **Architecture** | Module boundaries, dependency flow, coupling, cohesion |
| **Security** | Input validation, authentication, authorization, data exposure |
| **Correctness** | Edge cases, error handling, race conditions, off-by-one errors |
| **Testing** | Coverage, test quality, edge case tests, test independence |
| **KISS compliance** | Over-engineering, unnecessary abstractions, unused code, premature generalization |
| **Style** | Naming, consistency, readability, formatting |

## Severity Levels

Each finding is tagged with exactly one severity level:

| Severity | When to use | Effect on verdict |
|----------|-------------|-------------------|
| **Critical** | Must fix before merge — bugs, security holes, data loss risk | Triggers CRITICAL_ISSUES |
| **Major** | Should fix — logic errors, missing validation, poor error handling | Triggers ISSUES_FOUND |
| **Minor** | Nice to fix — naming, style inconsistency, minor simplification | No verdict change |
| **Info** | Informational — trade-off notes, alternative approaches | No verdict change |

## Verdicts

Exactly three possible verdicts for the overall review:

| Verdict | Condition |
|---------|-----------|
| **CLEAN** | No critical or major findings across all categories |
| **ISSUES_FOUND** | At least one major finding; no critical findings |
| **CRITICAL_ISSUES** | At least one critical finding |

Verdict is determined by the highest severity finding: critical beats major, major beats minor/info.

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

## Summary

| Category | Critical | Major | Minor | Info |
|----------|----------|-------|-------|------|
| Architecture | 0 | 0 | 0 | 0 |
| Security | 0 | 0 | 0 | 0 |
| Correctness | 0 | 0 | 0 | 0 |
| Testing | 0 | 0 | 0 | 0 |
| KISS Compliance | 0 | 0 | 0 | 0 |
| Style | 0 | 0 | 0 | 0 |

## Overall Verdict: CLEAN | ISSUES_FOUND | CRITICAL_ISSUES

[One sentence justifying the verdict, referencing the highest-severity finding.]
```

## Review Rules

- Every finding must include a proposed fix. Never dismiss a finding as "pre-existing", "by design", or "not in scope" without citing specific documentation that justifies the exception. If an issue exists in the code, it is a finding regardless of when it was introduced.

## Related Skills

- `rnd-framework:rnd-verification` — Evidence-based verification process; code review applies the same evidence standards
