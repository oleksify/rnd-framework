---
name: rnd-building
description: "Use when implementing code within the R&D pipeline — TDD discipline, pre-registration compliance, honest self-assessment, and verification artifact production"
---

# R&D Building

## Overview

Implement ONE assigned task against its pre-registered success criteria. Write the test first. Watch it fail. Write minimal code to pass. Produce verification artifacts for the independent Verifier.

**Core principle:** If you didn't watch the test fail, you don't know if it tests the right thing. If you didn't try to break your own code, you don't know if it works.

## When to Use

- Build phase of `/rnd-framework:start` or `/rnd-framework:build`
- Any implementation task within the R&D pipeline
- When a pre-registration document exists for the task

## The Iron Laws

```
1. NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST
2. NO SILENT DEVIATIONS FROM THE PRE-REGISTERED APPROACH
3. DO NOT VERIFY YOUR OWN WORK
4. USE WRITE/EDIT TOOLS TO CREATE AND MODIFY FILES — NEVER BASH HEREDOCS
```

**On file creation:** Always use the `Write` tool to create files and `Edit` to modify them. Never use `cat > file << 'EOF'`, `echo >`, or other Bash heredoc/redirect patterns to write file content. The dedicated tools are reviewable, diffable, and won't silently mangle content (quoting, escaping, whitespace).

## Process

### 1. Read Your Assignment

Find your task in `.rnd/plan.md`. Read its pre-registration document carefully — especially the success criteria and approach.

### 2. Read Context

Examine upstream artifacts from completed dependencies: API contracts, type definitions, interfaces.

### 3. Red-Green-Refactor (per criterion)

For EACH success criterion in the pre-registration:

**RED — Write a failing test**
- One test per criterion
- Clear name describing the expected behavior
- Real code, no mocks unless unavoidable
- Run it. Watch it fail. Confirm it fails for the right reason.

**GREEN — Write minimal code**
- Simplest code to pass the test
- Don't add features, refactor, or "improve" beyond the test
- Run tests. All green.

**REFACTOR — Clean up**
- After green only: remove duplication, improve names, extract helpers
- Keep tests green. Don't add behavior.

### 4. Handle Plan Deviations

If you believe the pre-registered approach is wrong:
- **STOP.** Do not silently deviate.
- Report to the orchestrator with your reasoning.
- Wait for guidance before continuing.

If you need minor adjustments, document them in your self-assessment.

### 5. Produce Verification Artifacts

Save to `.rnd/builds/T<id>-manifest.md`:

```markdown
# Build Manifest: T<id>

## Files Created/Modified
- [list with paths]

## Tests Written
- [test name]: Tests [criterion text]

## Edge Cases Covered
- [list edge cases and how they're handled]
```

### 6. Write Honest Self-Assessment

Save to `.rnd/builds/T<id>-self-assessment.md`:

```markdown
# Self-Assessment: T<id>

## Confidence per criterion
- [criterion 1]: HIGH / MEDIUM / LOW — [brief reason]

## Assumptions made
- [list assumptions]

## Uncertainties & risks
- [what you're not sure about]

## Deviations from plan
- [any changes from pre-registered approach, with reasons]
```

**The Verifier will NOT see this file.** Be honest — hiding doubts causes harder bugs later.

## Good Tests

| Quality | Good | Bad |
|---------|------|-----|
| **Minimal** | One thing. "and" in name? Split it. | `test('validates and processes')` |
| **Clear** | Name describes behavior | `test('test1')` |
| **Real** | Tests actual code | Tests mock behavior |
| **Intent** | Shows what SHOULD happen | Shows what DOES happen |

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "Too simple to test" | Simple code breaks. Test takes 30 seconds. |
| "I'll test after" | Tests passing immediately prove nothing. |
| "TDD will slow me down" | TDD is faster than debugging. |
| "The approach is wrong but I'll adapt" | STOP. Report deviation. Don't silently diverge. |
| "I'll verify it myself" | That's the Verifier's job. Produce artifacts, not verdicts. |

## Verification Checklist

Before submitting your build:

- [ ] Every success criterion has a corresponding test
- [ ] Watched each test fail before implementing
- [ ] All tests pass
- [ ] Tried to break your own implementation with at least one edge case per criterion
- [ ] Build manifest lists all files and tests
- [ ] Self-assessment is honest about uncertainties — if you have doubts, say so; the Verifier will find them anyway
- [ ] No silent deviations from pre-registered approach
- [ ] Output is clean (no errors, warnings)

## Related Skills

- `rnd-framework:rnd-debugging` — When tests reveal unexpected failures
- `rnd-framework:rnd-iteration` — When Verifier sends back feedback
- `rnd-framework:rnd-isolation` — For working in isolated worktrees
