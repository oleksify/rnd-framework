---
name: rnd-building
description: "Use when implementing code within the R&D pipeline — TDD discipline, pre-registration compliance, honest self-assessment, and verification artifact production"
user-invocable: false
effort: medium
---

# R&D Building

## Overview

Implement ONE assigned task against its pre-registered success criteria. Write the test first. Watch it fail. Write minimal code to pass. Produce verification artifacts for the independent Verifier. If you didn't watch the test fail, you don't know if it tests the right thing. If you didn't try to break your own code, you don't know if it works.

## The Iron Laws

```
1. NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST
2. NO SILENT DEVIATIONS FROM THE PRE-REGISTERED APPROACH
3. DO NOT VERIFY YOUR OWN WORK
4. USE WRITE/EDIT TOOLS TO CREATE AND MODIFY FILES — NEVER BASH HEREDOCS
5. IF SLOP-GATE RETURNS WARN OR FAIL WITH ANY SEVERITY 3+ MATCH, RE-EDIT IMMEDIATELY — DO NOT DEFER
6. WHEN YOU HIT AN ERROR OR WARNING, INVESTIGATE AND FIX IT — NEVER DEFLECT WITH "PRE-EXISTING" AS A REASON TO SKIP
7. EXPLAIN BEFORE YOU WRITE — ONE LOGICAL CHANGE PER WRITE/EDIT, NOT WALLS OF CODE
8. DO NOT EMBED PIPELINE TASK IDs IN PROJECT CODE — NO TASK IDs IN COMMENTS, TEST NAMES, OR VARIABLE NAMES (RND ARTIFACT FILES IN $RND_DIR ARE EXEMPT)
```

## Process

### 0. Resolve RND_DIR

```bash
RND_DIR="$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh")"
```

### 1. Read Your Assignment

Find your task in `$RND_DIR/plan.md`. Read its pre-registration — especially success criteria, approach, and the `fulfills` field (which links to specific VAL-AREA-NNN assertions in the Validation Contract). Also read these enriched plan sections:

- **Environment Setup** — runtime, package manager, dependencies, install commands
- **Testing Strategy** — test framework, baseline count, exact run commands for unit/integration/live tests
- **Worker Guidelines** — project boundaries (USE/OFF-LIMITS), coding conventions, architecture notes

These sections tell you HOW to build and test without rediscovering the environment.

### 2. Verify Preconditions

If the pre-registration has a `Preconditions:` field, check each assertion before writing code:

- **File existence:** run Glob for the declared path pattern
- **Content existence:** run Grep for the declared pattern in the declared file
- **Dependency presence:** run Read on the config file and check for the declared key

If **any precondition fails**: report status `BLOCKED` with the specific failing assertion. Do not proceed to coding.

If the pre-registration has no `Preconditions:` field, skip this step silently.

### 2.5. Read Exploration Cache

If `$RND_DIR/exploration/` exists, read it before writing code. The Planner writes structured findings there — file summaries, key patterns, dependencies — so you don't re-explore what was already mapped.

> **Known gotchas:** The orchestrator may inject pitfalls from prior builds. Review them before writing any code.

### 2.75. Verify External Dependencies

Before writing any code, verify every external dependency listed in the pre-registration:

- **Read or query the actual external system** — read DB schema, call API endpoint, inspect file
- **Record evidence in the build manifest** under `### Evidence Gathered` — cite file path, line range, and what was learned
- **Flag any contract mismatch as a STOP condition** — same protocol as a plan deviation
- **If inaccessible**, document as an unverified assumption in your self-assessment

### 3. Red-Green-Refactor (per criterion)

For EACH success criterion, output in your response (not in thinking) — **SCAN** (mandatory):
> SCAN: Working on criterion [N]: [criterion text]. Approach: [approach from pre-registration].

This restores pre-registration attention weight as context grows. At 80K tokens, a 1K instruction block commands ~1% attention — generating criterion text in output restores it. Do not skip.

**RED** — Write one failing test per criterion. Real code, no mocks unless unavoidable. Run it. Watch it fail. Confirm it fails for the right reason.
**GREEN** — Write minimal code to pass. Run tests after each change.
**REFACTOR** — After green only: remove duplication, improve names. Keep tests green. Don't add behavior.

### 4. Handle Plan Deviations

If you believe the pre-registered approach is wrong: **STOP.** Report to the orchestrator. Wait for guidance. Minor adjustments: document in your self-assessment.

### 5. Produce Verification Artifacts

Save to `$RND_DIR/builds/T<id>-manifest.md`:

```markdown
# Build Manifest: T<id>

## Files Created/Modified
- [list with paths]

## Evidence Gathered
- `path/to/file.ext:NN-MM` — [what was learned]

## Tests Written
- [test name]: Tests [criterion text]

## Edge Cases Covered
- [list edge cases and how they're handled]

## External References
- `[reference value]` — type: [URL | email | address | API endpoint | package name | …] — provenance: [verified from user input | from existing codebase file X:line Y | generated from training data]
```

### 6. Write Honest Self-Assessment

Save to `$RND_DIR/builds/T<id>-self-assessment.md`:

```markdown
# Self-Assessment: T<id>

## Confidence per criterion
- [criterion 1]: HIGH / MEDIUM / LOW — [brief reason]

## Assumptions made

### Verified external assumptions
- [system]: [what was verified] — evidence: [where]

### Unverified external assumptions
- [system]: [what was assumed] — reason unverified: [why]

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

## Property-Based Testing

Prefer property-based tests when the criterion describes an invariant, roundtrip, or ordering guarantee.
| Use property-based | Use specific-output |
|--------------------|---------------------|
| Roundtrip/codec invariants | Exact API response shapes |
| Ordering/sorting guarantees | Known edge cases with fixed values |
| Mathematical properties (determinism) | Error messages that must match exactly |
| Serialization preserves all fields | UI rendering assertions |

Use fast-check, hypothesis, or propcheck if available; otherwise a loop over random valid inputs achieves the same effect.

## Context Management

Summarize verbose output rather than processing raw. Test/build output >50 lines: extract pass/fail counts, error messages, stack traces into 5-10 lines. Large files: use offset/limit or Grep. At 80K context tokens, low-signal output crowds out reasoning budget for pre-registration criteria.

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "Too simple to test" | Simple code breaks. Test takes 30 seconds. |
| "I'll test after" | Tests passing immediately prove nothing. |
| "TDD will slow me down" | TDD is faster than debugging. |
| "The approach is wrong but I'll adapt" | STOP. Report deviation. Don't silently diverge. |
| "I'll verify it myself" | That's the Verifier's job. Produce artifacts, not verdicts. |

## Verification Checklist

- [ ] Every success criterion has a corresponding test
- [ ] Watched each test fail before implementing
- [ ] All tests pass
- [ ] Tried to break your own implementation with at least one edge case per criterion
- [ ] Build manifest lists all files and tests
- [ ] Self-assessment is honest about uncertainties
- [ ] No silent deviations from pre-registered approach
- [ ] Output is clean (no errors, warnings)
- [ ] Every external dependency verified against the actual system, evidence in manifest
- [ ] Build manifest `### Evidence Gathered` contains file:line citations for each external contract
- [ ] All external references (URLs, APIs, packages, addresses) declared in the manifest's `## External References` section with type and provenance
- [ ] No pipeline task IDs in project code (comments, test names, variable names)

## Convergent Iteration

When receiving a verification report with NEEDS ITERATION, address **every** failed criterion in a single pass — not just the primary failure. Fixing one criterion while leaving others broken causes "whack-a-mole" cycles that waste iteration budget.

**Process:**
1. **Inventory all failures.** List every criterion marked FAIL or NEEDS ITERATION in the verification report. This is your checklist — nothing ships until every item is addressed.
2. **Diagnose root causes.** Multiple failures often share a root cause. Fix the root cause and you fix several criteria at once.
3. **Check shared code paths.** After making fixes, identify code paths that are shared between fixed (previously failing) and passing criteria. Re-verify that your changes do not regress passing criteria.
4. **Re-run ALL tests.** Run the complete test suite — not just tests related to the flagged criteria. Fixes in one area frequently break assumptions in another.
5. **Update the build manifest and self-assessment** to reflect all changes made in this pass.

**Anti-pattern:** Fixing only the "loudest" failure and hoping the others resolve themselves or will be caught next round. They won't — and you'll burn iteration budget discovering that.

## Status Codes

After completing the Verification Checklist, choose one status code and include it in your completion message:

| Code | When to Use |
|------|-------------|
| `DONE` | All criteria met, all tests pass, no significant concerns. Proceed to verification. |
| `DONE_WITH_CONCERNS` | Criteria met, tests pass, but uncertainty exists about specific areas (e.g., unverified external dependency, tricky edge case). Verifier should pay extra attention to flagged areas. |
| `NEEDS_CONTEXT` | Cannot proceed without additional information — ambiguous requirement, missing dependency, conflicting specs. State exactly what you need. |
| `BLOCKED` | Cannot proceed at all. Hard blocker prevents implementation (e.g., missing file, broken toolchain, contradictory criteria). Requires orchestrator intervention. |

When the status is `DONE_WITH_CONCERNS`, include a brief `concerns:` line in the completion message summarizing what the Verifier should scrutinize.

**Completion message format:**
```
T<id> build complete — status: DONE — manifest at $RND_DIR/builds/T<id>-manifest.md
T<id> build complete — status: DONE_WITH_CONCERNS: [brief summary] — manifest at $RND_DIR/builds/T<id>-manifest.md
```

## Related Skills

- `rnd-framework:rnd-debugging` — unexpected test failures
- `rnd-framework:rnd-iteration` — when Verifier sends back feedback
- `rnd-framework:rnd-data-science` — numerical analysis, financial calculations, data wiring, chart generation (Julia or DuckDB)
