---
name: rnd-building
description: "Use when implementing code within the R&D pipeline — TDD discipline, pre-registration compliance, honest self-assessment, and verification artifact production"
user-invocable: false
effort: medium
---

# R&D Building

Implement ONE assigned task against its pre-registered success criteria. Write the test first. Watch it fail. Write minimal code to pass. Produce verification artifacts for the independent Verifier.

## The Iron Laws

```
1. NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST
2. NO SILENT DEVIATIONS FROM THE PRE-REGISTERED APPROACH
3. DO NOT VERIFY YOUR OWN WORK
4. USE WRITE/EDIT TOOLS TO CREATE AND MODIFY FILES — NEVER BASH HEREDOCS
5. IF SLOP-GATE RETURNS WARN OR FAIL WITH ANY SEVERITY 3+ MATCH, RE-EDIT IMMEDIATELY — DO NOT DEFER
6. WHEN YOU HIT AN ISSUE (ERROR, WARNING, BROKEN TEST, BUG, GAP), FIX IT OR LOG IT TO found-issues.jsonl WITH decision="fixed"|"escalated" — SILENT DISMISSAL IS NOT AN OPTION
7. EXPLAIN BEFORE YOU WRITE — ONE LOGICAL CHANGE PER WRITE/EDIT, NOT WALLS OF CODE
8. DO NOT EMBED PIPELINE TASK IDs IN PROJECT CODE — NO TASK IDs IN COMMENTS, TEST NAMES, OR VARIABLE NAMES (RND ARTIFACT FILES IN $RND_DIR ARE EXEMPT)
```

### 0. Resolve RND_DIR

```bash
RND_DIR="$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh")"
```

### 1. Read Your Assignment

Find your task in `$RND_DIR/plan.md`. Read its pre-registration — especially success criteria, approach, and the `fulfills` field (which links to specific VAL-AREA-NNN assertions in the Validation Contract). Also read:
- **Environment Setup** — runtime, package manager, dependencies, install commands
- **Testing Strategy** — test framework, baseline count, exact run commands for unit/integration/live tests
- **Worker Guidelines** — project boundaries (USE/OFF-LIMITS), coding conventions, architecture notes

### 2. Verify Preconditions

If the pre-registration has a `Preconditions:` field, check each assertion before writing code:
- **File existence:** run Glob for the declared path pattern
- **Content existence:** run Grep for the declared pattern in the declared file
- **Dependency presence:** run Read on the config file and check for the declared key
- **On failure:** report status `BLOCKED` with the specific failing assertion. Do not proceed.

### 2.5. Read Exploration Cache

If `$RND_DIR/exploration/` exists, read it before writing code — file summaries, key patterns, dependencies. The orchestrator may also inject pitfalls from prior builds; review them before writing any code.

### 2.75. Verify External Dependencies

Before writing any code, verify every external dependency listed in the pre-registration:
- **Read or query the actual external system** — read DB schema, call API endpoint, inspect file
- **Record evidence in the build manifest** under `### Evidence Gathered` — cite file path, line range, and what was learned
- **Flag any contract mismatch as a STOP condition** — same protocol as a plan deviation
- **If inaccessible**, document as an unverified assumption in your self-assessment

### 3. Red-Green-Refactor (per criterion)

For EACH success criterion, output in your response (not in thinking) — **SCAN** (mandatory):
> SCAN: Working on criterion [N]: [criterion text]. Approach: [approach from pre-registration].

**RED** — Write one failing test per criterion. Real code, no mocks unless unavoidable. Run it. Watch it fail. Confirm it fails for the right reason.
**GREEN** — Write minimal code to pass. Run tests after each change.
**REFACTOR** — After green only: remove duplication, improve names. Keep tests green. Don't add behavior.
**DEVIATION** — If the pre-registered approach is wrong: **STOP.** Report to the orchestrator. Minor adjustments: document in your self-assessment.

### 4. Produce Verification Artifacts

Save the build manifest to `$RND_DIR/builds/T<id>-manifest.md`. **Terse format: structured bullets only — no narrative, no recap of what you did.** Manifest depth scales with task Criticality.

**For `Criticality: LOW` tasks (config changes, doc edits, renaming, log lines, style fixes) — skinny manifest:**

```markdown
# Build Manifest: T<id>

## Files Created/Modified
- [list with paths]

## Tests Written
- [test name]: Tests [criterion text]
```

Omit Evidence Gathered, Edge Cases Covered, and External References entirely — LOW-criticality tasks don't interact with external systems by definition, and edge-case sections on trivial changes are boilerplate, not signal.

**For `Criticality: NORMAL` and `Criticality: HIGH` tasks — full manifest:**

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

Sections with genuinely no content may be written as `(none)` on a single line. Do NOT omit section headers entirely from the full-manifest form — Verifier scans for presence.

**Do not game the skinny form.** If a task is tagged LOW but you discover during implementation that it touches an external system (API call, schema assumption, env var contract), upgrade to the full manifest and flag the misclassification to the orchestrator.

**Note on Verifier output:** When your task passes verification, the Verifier writes a `T<id>-pass-receipt.json` to `$RND_DIR/verifications/` instead of a full prose report. A full prose report is only materialized on FAIL or NEEDS_ITERATION. You do not need to write the pass-receipt — the Verifier produces it.

### 5. Write Honest Self-Assessment

Save to `$RND_DIR/builds/T<id>-self-assessment.md` (Verifier will NOT see this — be honest). The format depends on your build status.

**For plain `DONE` status (no concerns, all criteria met with HIGH confidence, no deviations, no unverified assumptions):** write a minimal one-line file. No sections, no boilerplate.

```markdown
# Self-Assessment: T<id>

All criteria met with HIGH confidence. No deviations. No unverified assumptions.
```

**For `DONE_WITH_CONCERNS`, `NEEDS_CONTEXT`, or `BLOCKED`:** write the full template. Any genuine uncertainty, any confidence below HIGH on any criterion, any unverified external assumption, or any deviation from plan means you are NOT plain `DONE` — use the full template even if it feels borderline.

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

**Do not game the minimal form.** If you are tempted to write the one-liner to avoid effort but you have an unverified external assumption or a MEDIUM-confidence criterion, that is dishonesty — downgrade the status to `DONE_WITH_CONCERNS` and use the full template.

## Found Issues Ledger

For every issue encountered during a build — error, warning, broken test, bug, or gap — you MUST either fix it or record it. Silently skipping or rationalizing away an issue is not allowed.

**Path:** `$RND_DIR/builds/T<id>-found-issues.jsonl`

**JSON-line schema:**
```json
{"issue": "<description>", "location": "<path:line>", "decision": "fixed"|"escalated", "reason": "<why fixed or why escalated>"}
```

**Rules:**
- Append one line per issue, even if you fix it immediately.
- `decision="escalated"` is the only legal path for issues you cannot fix within this task scope.
- Never omit an issue from the ledger because it seems minor or pre-existing.

**Example:**
```json
{"issue": "TypeScript strict null check failure on optional field access", "location": "src/parser.ts:47", "decision": "fixed", "reason": "added null guard before property access"}
```

## Good Tests

| Quality | Good | Bad |
|---------|------|-----|
| **Minimal** | One thing. "and" in name? Split it. | `test('validates and processes')` |
| **Clear** | Name describes behavior | `test('test1')` |
| **Real** | Tests actual code | Tests mock behavior |
| **Intent** | Shows what SHOULD happen | Shows what DOES happen |

Prefer property-based tests for invariants, roundtrips, ordering guarantees. Use fast-check, hypothesis, or propcheck if available. For specific-output tests: exact API shapes, known edge cases, error messages, UI rendering. Summarize verbose output: test/build output >50 lines → extract pass/fail counts + error messages. Large files: use offset/limit or Grep.

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

When receiving NEEDS ITERATION, address **every** failed criterion in a single pass:
1. **Inventory all failures.** List every criterion marked FAIL or NEEDS ITERATION. Nothing ships until every item is addressed.
2. **Diagnose root causes.** Multiple failures often share a root cause.
3. **Check shared code paths.** Re-verify that fixes do not regress passing criteria.
4. **Re-run ALL tests.** Run the complete test suite — not just tests related to flagged criteria.
5. **Update the build manifest and self-assessment** to reflect all changes made in this pass.

## Status Codes

| Code | When to Use |
|------|-------------|
| `DONE` | All criteria met, all tests pass, no significant concerns. |
| `DONE_WITH_CONCERNS` | Criteria met, tests pass, but uncertainty exists. Include `concerns:` line summarizing what Verifier should scrutinize. |
| `NEEDS_CONTEXT` | Cannot proceed without additional information — ambiguous requirement, missing dependency, conflicting specs. |
| `BLOCKED` | Hard blocker prevents implementation. Requires orchestrator intervention. |

**Completion message format:**
```
T<id> build complete — status: DONE — manifest at $RND_DIR/builds/T<id>-manifest.md
T<id> build complete — status: DONE_WITH_CONCERNS: [brief summary] — manifest at $RND_DIR/builds/T<id>-manifest.md
```

## Evidence Pack (when RND_EVIDENCE_PACK=1)

When the orchestrator sets `RND_EVIDENCE_PACK=1`, wrap tool invocations through `run-tool.sh` to capture a reproducible evidence artifact for each test run. This is opt-in — normal builds do not require it.

**Invocation syntax:**

```bash
RND_EVIDENCE_PACK=1 RND_DIR="$RND_DIR" RND_TASK_ID="<id>" \
  run-tool.sh [--task-id <id>] -- <command> [args...]
```

**Artifact location:** `$RND_DIR/evidence/T<id>/` — contains `stdout.txt`, `stderr.txt`, and `manifest.json` (tool name, argv, exit code, timestamps, and sha256 hashes of all tracked input files).

**Validation:** Before the Verifier reads the pack, `evidence-pack-gate.sh` schema-validates `manifest.json`. Packs that fail validation are rejected; the Verifier receives an error rather than stale or malformed data.

**When to use:** Only when instructed by the pre-registration or the orchestrator. Do not wrap every command — only the test runner or tool that produces the primary verification artifact.

## Related Skills

- `rnd-framework:rnd-debugging` — unexpected test failures
- `rnd-framework:rnd-iteration` — when Verifier sends back feedback
- `rnd-framework:rnd-data-science` — numerical analysis, financial calculations, data wiring, chart generation (Julia or DuckDB)
