---
name: rnd-building
description: "Use when implementing code within the R&D pipeline — TDD discipline, pre-registration compliance, honest self-assessment, and verification artifact production"
user-invocable: false
effort: medium
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
5. IF SLOP-GATE RETURNS WARN OR FAIL WITH ANY SEVERITY 3+ MATCH, RE-EDIT IMMEDIATELY — DO NOT DEFER
6. WHEN YOU HIT AN ERROR OR WARNING, INVESTIGATE AND FIX IT — NEVER DEFLECT WITH "PRE-EXISTING" AS A REASON TO SKIP
7. EXPLAIN BEFORE YOU WRITE — ONE LOGICAL CHANGE PER WRITE/EDIT, NOT WALLS OF CODE
```

**On file creation:** Always use the `Write` tool to create files and `Edit` to modify them. Never use `cat > file << 'EOF'`, `echo >`, or other Bash heredoc/redirect patterns to write file content. The dedicated tools are reviewable, diffable, and won't silently mangle content (quoting, escaping, whitespace).

## Process

### 0. Resolve RND_DIR

If `$RND_DIR` is not already set in session context, compute it:
```bash
RND_DIR="$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh")"
```

### 1. Read Your Assignment

Find your task in `$RND_DIR/plan.md`. Read its pre-registration document carefully — especially the success criteria and approach.

### 2. Read Context

Examine upstream artifacts from completed dependencies: API contracts, type definitions, interfaces.

### 2.5. Read Exploration Cache

If `$RND_DIR/exploration/` exists, read the files inside before writing any code. The Planner writes structured findings about the codebase there — file summaries, key patterns, relevant dependencies — so you don't need to re-explore what was already mapped.

```bash
ls "$RND_DIR/exploration/" 2>/dev/null && echo "exploration cache found"
```

Read whichever files are relevant to your task. This is faster than re-reading source files the Planner already summarized.

> **Known gotchas:** The orchestrator may inject "Known gotchas" context alongside your assignment — these are language-specific pitfalls captured from previous pipeline runs. Review them before writing any code and avoid the documented patterns. They represent real failures from prior builds, not hypothetical warnings.

### 2.75. Verify External Dependencies

Before writing any code, verify every external dependency listed in the pre-registration's "External dependencies" field:

- **Read or query the actual external system** — read DB schema, call API endpoint, inspect file, check service response
- **Record evidence in the build manifest** under an `### Evidence Gathered` section — cite each finding with file path, line range, and what was learned. Example format:
  ```
  ### Evidence Gathered
  - `path/to/schema.sql:15-20` — users table has string `id` column (not UUID)
  - `lib/api-client.ts:42` — API returns `{ data: User[] }` shape
  ```
- **Flag any contract mismatch as a STOP condition** — same protocol as a plan deviation: stop, report to the orchestrator, wait for guidance before continuing
- **If the system is not accessible**, document this explicitly as an unverified assumption in your self-assessment (see sub-sections below)

### 3. Red-Green-Refactor (per criterion)

For EACH success criterion in the pre-registration:

**SCAN — Re-anchor before each criterion** (mandatory)

Before starting work on a criterion, output a brief compliance statement in your response (not in thinking). This re-states the criterion and approach, costing ~300 tokens but restoring attention to the pre-registration as context grows. Format:

> SCAN: Working on criterion [N]: [criterion text]. Approach: [approach from pre-registration].

This is the SCAN technique (System Compliance Active Notification). Research shows system prompt tokens lose attention weight as context grows — at 80K tokens, a 1K instruction block commands only ~1% of attention. Generating criterion text in output restores the attention weight. Do not skip this step even if it feels redundant.

**RED — Write a failing test**
- One test per criterion
- Clear name describing the expected behavior
- Real code, no mocks unless unavoidable
- Run it. Watch it fail. Confirm it fails for the right reason.

**GREEN — Write minimal code to pass**

- Write the simplest code that makes the failing test pass.
- Run tests after each change to catch regressions early.

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

Save to `$RND_DIR/builds/T<id>-manifest.md`:

```markdown
# Build Manifest: T<id>

## Files Created/Modified
- [list with paths]

## Evidence Gathered
- `path/to/file.ext:NN-MM` — [what was learned about the external contract]
- `path/to/other.ts:NN` — [what was observed]

## Tests Written
- [test name]: Tests [criterion text]

## Edge Cases Covered
- [list edge cases and how they're handled]
```

### 6. Write Honest Self-Assessment

Save to `$RND_DIR/builds/T<id>-self-assessment.md`:

```markdown
# Self-Assessment: T<id>

## Confidence per criterion
- [criterion 1]: HIGH / MEDIUM / LOW — [brief reason]

## Assumptions made

### Verified external assumptions
- [system]: [what was verified] — evidence: [where evidence is recorded]

### Unverified external assumptions
- [system]: [what was assumed] — reason unverified: [why the system couldn't be queried]

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

Prefer property-based tests over specific-output tests when the criterion describes an invariant, roundtrip, or ordering guarantee. Research shows 23-37% relative pass@1 improvements because properties are harder to hallucinate incorrectly than specific test cases.

**When to use property-based tests:**
- Roundtrip/codec: "encode then decode returns the original" instead of `encode('hello') === 'aGVsbG8='`
- Invariants: "sorted output is always in ascending order" instead of `sort([3,1,2]) === [1,2,3]`
- Mathematical properties: "hash is deterministic" (same input always produces same output)
- Preservation: "serialization preserves all fields" instead of testing one specific object

**When specific-output tests are better:**
- Exact API response shapes (snapshot tests)
- Known edge cases with fixed expected values
- Error messages that must match exactly
- UI rendering assertions

**In practice:** Write the property as a test that generates random valid inputs and asserts the invariant holds. If the language has a property-testing library (fast-check, hypothesis, propcheck), use it. Otherwise, a simple loop over random inputs achieves the same effect.

## Context Management

Verbose tool output fills your context window without proportional value. Research shows that **observation masking** — summarizing verbose outputs rather than processing them raw — is the most effective context management technique for coding agents.

**When test/build output exceeds ~50 lines:**
- Extract the key signal: pass/fail counts, specific error messages, failing test names, stack traces
- Summarize in 5-10 lines of your own words before continuing
- Do not paste or re-read the full output — it consumes context that should be spent on reasoning

**When reading large files:**
- Use offset/limit parameters to read only relevant sections
- If you need to understand the full file, read it in chunks and summarize as you go
- Prefer Grep to find specific patterns rather than reading entire files

**Why this matters:** At 80K context tokens, every 1K of verbose output reduces the attention budget available for your actual task. The model's ability to follow pre-registration criteria degrades as context fills with low-signal observations.

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
- [ ] Every external dependency in the pre-registration was verified against the actual system, with evidence recorded in the build manifest
- [ ] Build manifest `### Evidence Gathered` section contains file:line citations for each external contract used

## Status Codes

After completing the Verification Checklist, choose one status code and include it in your completion `SendMessage`:

| Code | When to Use |
|------|-------------|
| `DONE` | All criteria met, all tests pass, no significant concerns. Proceed to verification. |
| `DONE_WITH_CONCERNS` | Criteria met and tests pass, but you have uncertainty about specific areas (e.g., an unverified external dependency, a tricky edge case you couldn't fully exercise). Verifier should pay extra attention to the flagged areas. |
| `NEEDS_CONTEXT` | You cannot proceed without additional information — ambiguous requirement, missing dependency, conflicting specs. State exactly what you need. |
| `BLOCKED` | Cannot proceed at all. A hard blocker prevents implementation (e.g., missing file that must exist, broken toolchain, contradictory success criteria). Requires orchestrator intervention. |

**Completion message format:**

```
T<id> build complete — status: DONE — manifest at $RND_DIR/builds/T<id>-manifest.md
T<id> build complete — status: DONE_WITH_CONCERNS: [brief summary of concerns] — manifest at $RND_DIR/builds/T<id>-manifest.md
```

**Examples:**

- `DONE` — "T7 build complete — status: DONE — manifest at ..."
- `DONE_WITH_CONCERNS` — "T12 build complete — status: DONE_WITH_CONCERNS: external API shape unverified (sandbox only) — manifest at ..."
- `NEEDS_CONTEXT` — "NEEDS_CONTEXT on T5: the pre-registration references schema v2 but the DB is on v1. Which should I target?"
- `BLOCKED` — "BLOCKED on T3: commands/start.md does not exist at the expected path. Cannot proceed."

## Related Skills

- `rnd-framework:rnd-debugging` — When tests reveal unexpected failures
- `rnd-framework:rnd-iteration` — When Verifier sends back feedback
- `rnd-framework:rnd-data-science` — When the task involves numerical analysis, financial calculations, data wiring, chart generation, or any analytical work requiring Julia or DuckDB
