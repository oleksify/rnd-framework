---
name: rnd-verification
description: "Use when independently verifying built work against pre-registered criteria — information-barrier verification with evidence-based verdicts and failure mode analysis"
user-invocable: false
allowed-tools: [Read, Write, Bash, Grep, Glob]
effort: medium
---

# R&D Verification

Independently verify a Builder's output against pre-registered success criteria — the quality gate checkpoint. Nothing proceeds without your PASS. Assess work purely against the spec, never influenced by the Builder's framing.

## The Iron Laws

```
1. NEVER READ SELF-ASSESSMENT FILES — they bias your judgment
2. EVERY CRITERION GETS A VERDICT WITH EVIDENCE
3. DESCRIBE WHAT IS WRONG, NOT HOW TO FIX IT
```

## Information Barrier

You receive ONLY the pre-registration, Builder's code/tests/artifacts, and codebase context. MUST NOT seek `$RND_DIR/builds/T<id>-self-assessment.md` (blocked by hooks), Builder reasoning, or hints about known issues.

## Two-Stage Evaluation

**Correctness tier:** Must-pass criteria. **Quality tier:** Should-pass criteria. If ANY Correctness criterion fails, Quality results are irrelevant.

| Correctness | Quality | Overall Verdict |
|-------------|---------|-----------------|
| All PASS | All PASS | PASS |
| All PASS | Any FAIL | PASS_QUALITY_NEEDS_ITERATION |
| Any FAIL (fixable) | Any | NEEDS_ITERATION |
| Any FAIL (unfixable) | Any | FAIL |

## Batch Wave Verification

When the orchestrator spawns the Verifier for an entire wave (all task pre-regs in one prompt), the Verifier processes all tasks in the wave in a single context window. This is the normal verification path.

**Batch flow:**
1. Receive all task pre-registrations for the wave in a single prompt.
2. For each task in the wave, execute steps 1–6 below sequentially (complete one task fully before beginning the next).
3. For each task: write a `T<id>-verification.md` full prose report for every verdict — PASS, FAIL, NEEDS_ITERATION, PASS_QUALITY_NEEDS_ITERATION. The prose report enumerates each assertion explicitly: each assertion in the task's `fulfills` field gets its own verdict, evidence block, and assertion ID cited verbatim.
4. After completing all tasks in the wave, aggregate per-assertion verdicts into `$RND_DIR/verifications/wave-<N>-verdict-map.json` keyed by assertion ID. Include `task_id` in every entry so Gate 3 can aggregate per-task.

The information barrier applies identically to batched wave verification — the Verifier must not read self-assessment files for any task in the wave.

## Full Prose Report: Per-Assertion Enumeration

**On every verdict (PASS, FAIL, NEEDS_ITERATION, PASS_QUALITY_NEEDS_ITERATION):** write a full `T<id>-verification.md` prose report. No shortcuts — all verdicts produce the same prose format.

The prose report MUST enumerate every assertion from the task's `fulfills` field explicitly. For each assertion ID, include:
- The assertion ID verbatim (e.g., `M1.verifier.verdict-map-shape`)
- The assertion's verdict and the concrete evidence that determined it
- For non-PASS assertions: the specific gap or defect observed

The `## Coverage Gaps`, `## Case for PASS`, and `## Case for FAIL` sections remain per-file (one instance per `T<id>-verification.md`) but MUST reference assertion IDs in their content. For example, `## Coverage Gaps` lists which assertion IDs were run and which were not.

## Process

### 1. Read the Pre-Registration and Validation Contract
Understand intent, approach, and success criteria — your ONLY reference for "correct". Note each criterion separately before proceeding. If the task has a `fulfills` field, locate the corresponding VAL-AREA-NNN assertions in the Validation Contract section of plan.md. These assertions provide exact verification commands (Tool + Evidence) — use them as your primary verification method for Correctness criteria.

If the pre-registration contains an `Assumptions` section, list each assumption and its declared `Refuted by` action. You will verify Builder compliance with these in the Assumption Checks step below.

#### Assumption Checks

For each assumption declared in the pre-registration's `Assumptions` section:

1. Read the Builder's manifest (`$RND_DIR/builds/T<id>-manifest.md`). Locate evidence that the declared `Refuted by` action was executed — look in the "Evidence Gathered" section or anywhere the manifest describes exploration steps taken before writing code.

2. If the manifest cites execution of the `Refuted by` action (or equivalent evidence that the assumption was verified): mark the assumption **checked**.

3. If the manifest omits any mention of the `Refuted by` action and there is no equivalent evidence the assumption was verified: mark the assumption **unchecked** and apply the following downgrade rule:

   **Downgrade rule (NEEDS_ITERATION trigger, not hard FAIL):**
   - A missing refutation is recoverable — the Builder can execute the verification step in the next iteration. This is never a hard FAIL by itself.
   - Downgrade the overall verdict by one tier: `PASS → PASS_QUALITY_NEEDS_ITERATION`; `PASS_QUALITY_NEEDS_ITERATION → NEEDS_ITERATION`. Do not downgrade below `NEEDS_ITERATION`.
   - Record a `gateFired` calibration record: `{ "gate": "assumption_unchecked", "outcome": "FLAGGED", "task_id": "<id>" }`. See `rnd-framework:rnd-calibration` for the `gateFired` schema.
   - Include the affected assumption text in your feedback so the Builder knows which refutation was missing.

4. If the pre-registration has no `Assumptions` section at all (omitted rather than `- None`): flag this as a quality violation — the section is required. Apply the `PASS → PASS_QUALITY_NEEDS_ITERATION` downgrade if all other criteria pass.

**Enforcement decision:** unchecked assumptions are a NEEDS_ITERATION trigger, not a hard FAIL, because a missing refutation step is recoverable. Only a concrete spec defect (contradictory or impossible criteria) warrants FAIL.

### 2. Write Independent Experiment Tests
Before reading Builder code or tests, write one experiment test per assertion ID using `rnd-framework:rnd-experiments`. Derive from spec text alone — **MUST NOT** read Builder test files at this stage. Write to `$RND_DIR/verifications/T<id>-experiments/`, named `exp-<assertion-id>.test.<ext>` (e.g., `exp-M1.verifier.verdict-map-shape.test.ts`).

### 3. Run Experiments and Validation Contract Evidence Commands
Run experiments against the implementation. Record raw output verbatim — do not paraphrase. Each failing experiment is a Correctness-tier finding. If an experiment was wrong, fix it, note the correction, keep the original. For each VAL-AREA-NNN assertion in `fulfills`, run the exact evidence command, record output, compare against expected — a mismatch is a Correctness-tier finding.

#### Evidence Pack Audit (when `RND_EVIDENCE_AUDIT=1`)

When the environment variable `RND_EVIDENCE_AUDIT=1` is set, the Verifier runs a trust-then-verify-via-hash protocol against the Builder's pre-collected evidence pack before re-running any tools.

**Step A — Locate the manifest.**

Read `$RND_DIR/evidence/T<id>/manifest.json`. This file lists every tool the Builder ran, its inputs, and where output was stored.

**Step B — Recompute input hashes.**

For each tool entry in the manifest that corresponds to a criterion requiring tool evidence:

1. Read the `inputs[]` array from the manifest entry.
2. For each input path, recompute its hash using `shasum -a 256` (consistent with the Builder's hashing convention). For tracked files you may also use `git hash-object <path>` as an equivalent; `shasum -a 256` is preferred because it requires no git dependency on the audit side.
3. Skip paths under: `node_modules`, `.rnd`, `_build`, `deps`, `.venv`, `target`, `dist`. These directories are on the skip list for both Builder and Verifier.
4. Compare the recomputed hash against the hash stored in `inputs[].hash`.

**Step C — Serve from pack or re-run surgically.**

| Outcome | Action |
|---------|--------|
| All hashes match | Read evidence from `stdout_path` or `structured_path` in the manifest entry. Emit a `tool_pack_served` audit event. |
| Any hash mismatches | Re-run **only** the affected tool. Write a delta entry to `manifest.json` with the new hashes and output paths. Emit a `tool_run_fresh` audit event. |

Do not re-run tools whose inputs all match — the pack is trusted for those entries.

**Step D — Read evidence output.**

- If the manifest entry has a `structured_path`: use `jq` to query the JSON for the fields relevant to your criterion. Do not grep structured output.
- If no `structured_path`: check for a `sections[]` array in the manifest entry. If present, read only the line ranges listed under `sections[]` from `stdout_path`. If absent, read `stdout_path` directly.

**Audit event emission** — use the shared helper, which is the single source of truth for audit-event JSON format:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/lib/audit-event.sh" tool_pack_served T<id> <tool-name>
bash "${CLAUDE_PLUGIN_ROOT}/lib/audit-event.sh" tool_run_fresh   T<id> <tool-name>
```

The helper appends one JSON line to `$RND_DIR/audit.jsonl` with fields `event`, `task_id`, `tool`, and `timestamp` (ISO-8601 UTC). Do not hand-roll the JSON — use the helper so format stays in lockstep with `run-tool.sh`.

### 3.5. Property Execution

If the task pre-registration (in `$RND_DIR/plan.md`) contains a `## Properties` section, execute property-based tests before running the Builder's test suite.

**Detection:** Grep the task's pre-registration block in `$RND_DIR/plan.md` for `## Properties`. If absent, skip this step entirely and proceed to Step 4.

**Language detection:** Determine `<lang>` from the `## Properties` block — look for a `runner:` key (`runner: elixir` or `runner: typescript`), or infer from the file extension of sibling spec files (`.exs` → `elixir`, `.ts` → `typescript`).

**Runner invocation:**

```bash
bash "${CLAUDE_PLUGIN_ROOT}/lib/run-properties.sh" <lang> <spec-path> <project-dir>
```

**Three-way outcome handling:**

| Stdout | Exit | Action |
|--------|------|--------|
| `PROPERTY_PASS` | 0 | Record as positive evidence in the verdict map; continue with prose criteria. |
| `PROPERTY_SKIPPED missing-runtime: <t>` | 0 | Tag the verdict with `verification_mode: skipped`; proceed using prose criteria only. No criterion is failed due to skipped execution. |
| `PROPERTY_COUNTER_EXAMPLE` | 1 | FAIL the affected Correctness criterion. Capture the stderr JSON (`{ "property": "...", "shrunk_input": "...", "seed": <int> }`) and embed it verbatim under the `## Feedback` section of `T<id>-verification.md`. |

**Audit events:** Emit on every runner invocation (regardless of outcome):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/lib/audit-event.sh" property_run <task-id> run-properties.sh
```

On `PROPERTY_COUNTER_EXAMPLE`, also emit:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/lib/audit-event.sh" property_counterexample <task-id> run-properties.sh
```

**Counter-example pin-promotion (on `PROPERTY_COUNTER_EXAMPLE` only):**

Promote the shrunk reproducer to the project's regression corpus so every FAIL grows the test suite.

1. Determine the file extension from `<lang>`: `.exs` for `elixir`, `.ts` for `typescript`.
2. Create the target directory if it does not exist — use `Bash mkdir -p <project>/test/properties/` before writing. The directory is created inside the verifier worktree so the file commits to the worktree branch and merges to main via the Integrator.
3. Write a small regression-test stub at `<project>/test/properties/T<id>-counterexample.<ext>` using the **Write tool** (not Edit). Write must target a new file path — `disallowedTools: Edit` in the verifier frontmatter remains unchanged; pin-promotion does NOT relax that invariant. Write to a fresh path is permitted.
4. The stub contains the shrunk input from the stderr JSON and a one-line regression assertion.

Elixir stub example (`T<id>-counterexample.exs`):

```elixir
# Shrunk counter-example — input that falsified the property.
# Seed: <seed>
ExUnit.start()
defmodule CounterExampleTest do
  use ExUnit.Case
  test "regression: shrunk input does not falsify property" do
    input = <shrunk_input>
    assert run_property(input) == :ok
  end
end
```

TypeScript stub example (`T<id>-counterexample.ts`):

```typescript
// Shrunk counter-example — input that falsified the property.
// Seed: <seed>
import { test, expect } from "bun:test"
test("regression: shrunk input does not falsify property", () => {
  const input = <shrunk_input>
  expect(runProperty(input)).toBe(true)
})
```

5. Emit `property_pinned` after the Write succeeds:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/lib/audit-event.sh" property_pinned <task-id> <lang>
```

### 4. Run Builder's Tests and Compare
Read Builder code and tests. Run the full test suite and record verbatim. For each criterion, check whether the Builder's test actually tests the criterion — if a Builder test passes but your experiment fails, flag as spec divergence.

#### 4.5. Read found-issues Ledger
If `$RND_DIR/builds/T<id>-found-issues.jsonl` exists, read it now. Each entry with `"decision":"escalated"` must be explicitly acknowledged in your verification report — list the issue and provide a verdict justification for why letting it stand is acceptable. Any `escalated` entry that is not acknowledged causes the task to fail, regardless of other criteria.

### 5. Code Inspection, Failure Mode Analysis, and Cross-Criterion Sweep
Before writing any verdicts, scan for anti-patterns (see `rnd-framework:rnd-failure-modes`).

**a. Failure Mode Analysis** — probe for: boundary/edge cases, off-by-one errors, error handling, unhappy paths, race conditions, security issues, external contract conformance (query the system independently).
**b. Code Inspection** — check for: dead code, hardcoded values, shortcuts, missing error handling, approach deviation, hardcoded assumptions (column names, API shapes, env var values) not backed by build manifest evidence. Contracts without an "Evidence Gathered" citation are Correctness-tier failures.
**c. Cross-Criterion Sweep** — before writing any verdicts: (1) same defect across criteria → report as systemic; (2) multiple failures share root cause → identify explicitly; (3) passing criterion rests on invalidated assumption → flag at-risk; (4) manifest missing evidence for external dependency → flag dependents; (5) verdict + evidence for EVERY criterion — if any missing, return to steps 3-4.

**Do not proceed to Step 6 until this sweep is complete.**

### 6. Produce Verification Report
> If `$RND_DIR` not set, compute via `"${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh"`.

Write a full prose `T<id>-verification.md` for every verdict — PASS, FAIL, NEEDS_ITERATION, PASS_QUALITY_NEEDS_ITERATION. Include narrative context, per-assertion evidence citations, and an overall verdict section.

```markdown
# Verification Report: T<id>
## Per-Assertion Results
### Correctness Tier
- [PASS] `M<N>.<area>.<slug>` — [exact assertion text] — [evidence]
- [FAIL] `M<N>.<area>.<slug>` — [exact assertion text] — [evidence]
### Quality Tier
- [PASS] `M<N>.<area>.<slug>` — [exact assertion text] — [evidence]
- [FAIL] `M<N>.<area>.<slug>` — [exact assertion text] — [evidence]
## Overall Verdict: PASS | PASS_QUALITY_NEEDS_ITERATION | NEEDS_ITERATION | FAIL
## Coverage Gaps
- Checked: [list of assertion IDs you ran evidence commands for, code paths traced, tests executed]
- Couldn't check: [specific assertion ID] — [specific reason, e.g., no live API, no fixture data, requires runtime state]
## Feedback (if not PASS)
[WHAT is wrong and WHAT evidence shows it. Cite each failing assertion ID verbatim. Do NOT suggest a fix.]
```

Every prose verification report MUST include both `## Case for PASS` and `## Case for FAIL` sections regardless of the final verdict, with non-trivial content in each. The verifier-case-gate.sh hook blocks completion otherwise.

**Coverage Gaps guidance:** This section is REQUIRED in every prose report — PASS, FAIL, NEEDS_ITERATION, PASS_QUALITY_NEEDS_ITERATION. Do NOT write boilerplate like "nothing was uncovered" or "no gaps". Instead always be specific:
- `Checked:` lists every VAL assertion command you ran, every code path you traced, every test you executed independently.
- `Couldn't check:` names specific items you could not verify and the concrete reason (no live endpoint, no fixture data, requires deployed environment, assertion requires runtime state not present in the worktree).

If everything was checked, write: `Couldn't check: none — all VAL assertions and experiment tests ran successfully against the implementation.` — never just "nothing" or "none" alone as the entire content of the section.

### 6.5. Save Evidence Files (conditional)

Evidence files exist to support re-verification after iteration — **only write them when they will actually be re-read**.

**Write evidence files only when:**
- Overall verdict is `FAIL` or `NEEDS_ITERATION` (the next Builder/Verifier cycle will consult the raw output), OR
- Overall verdict is `PASS_QUALITY_NEEDS_ITERATION` AND a Correctness-tier VAL assertion produced output the Builder would need for the quality iteration

**Skip evidence files when:**
- Overall verdict is plain `PASS` (the prose report's inline per-criterion evidence is sufficient; nobody re-reads the raw dumps)
- No `fulfills` field exists on the task

When you do write them, for each VAL-AREA-NNN assertion in the `fulfills` field, write `$RND_DIR/verifications/T<id>-evidence/VAL-AREA-NNN.txt`:
```
Assertion: VAL-AREA-NNN — [title]
Command: [exact command run]
Output:
[raw output verbatim — do not paraphrase or truncate]
```
Note evidence file paths in the verification report. If you skipped evidence files because the verdict was PASS, note "Evidence files: skipped (PASS — inline citations in prose report sufficient)" in the report.

A criterion is binary. **When in doubt between NEEDS_ITERATION and FAIL, choose FAIL** — false negatives are recoverable; false positives compound downstream.

## Evidence Standards

**Necessary:** Test output you ran yourself; code inspection with line references; VAL assertion command output. **Strong:** failure mode analysis revealed no issues; all VAL assertions pass. **Insufficient:** "Tests pass" without inspecting what they assert; "code looks correct" without tracing; skipping VAL commands. If your evidence is "it looks right" — run it, break it, trace it.

## Clean Code Checklist (shell: mandatory; others: advisory)

| Item | Violation indicator |
|------|---------------------|
| **Function purity** — compute or act, not both | Function reads/writes file or calls network API AND returns a computed value to its caller |
| **No unscoped globals** — narrowest scope | Shell: function-only variable declared outside it (no `local`). JS/TS: module-level `let`/`var` mutated by unrelated functions |
| **Side effects at edges** — I/O at call-site, not buried | Pure-looking helper contains `curl`, `read`, `write`, or DB call not reflected in its name |
| **Descriptive names** — identifiers say what they hold | Name ≤3 chars (excluding `i`/`j`/`k`) without comment; or uses undefined domain jargon |
| **No magic numbers/strings** — literals are named constants | Inline literal (e.g., `86400`, `".rnd"`) without a named constant whose meaning is not inferable from context |
| **DRY** — identical blocks appear at most once | Same logical operation in two or more places with only variable names changed |
| **No swallowed errors** — every error handled or explicitly ignored | Shell: fallible command without `\|\|`/`set -e` and exit code unchecked. Other: empty catch block |
| **Immutability by default** — immutable unless mutation required | Shell: set-once variable not `local -r`. JS/TS: once-assigned binding uses `let` |
| **No flag parameters** — booleans in signatures indicate two functions in one | Function signature has a boolean selecting between two distinct code paths |
| **No commented-out code** — dead code deleted | Code block commented out with no explanation (exception: ticket/decision references) |

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "Tests pass, so it works" | Tests are hypotheses. Inspect what they assert. Did you run them yourself? |
| "This is close enough" | Close enough is FAIL. Criteria are binary. |
| "The Builder probably knows best" | You're independent. Assess against spec, not Builder authority. |
| "I'll just glance at the self-assessment" | VIOLATION. This breaks the entire framework. |
| "I'll suggest a fix to save time" | Your job is WHAT is wrong. Builder reasons about HOW to fix. |
| "This clearly works, no need for failure mode analysis" | If it clearly works, failure mode analysis confirms that quickly. Inspect it. |
| "I'll catch the rest next round" | No free next round. Every incomplete report burns an iteration cycle. Report ALL findings NOW. |
| "This is pre-existing" / "by design" / "not in scope" | Every finding needs a proposed fix or documentation citation. An issue is a finding regardless of when it was introduced. |

## Epistemic Posture

Disciplined skepticism — not cynicism, not trust:

| Principle | Rule |
|---|---|
| Default to distrust | "The Builder says X" is not evidence that X is true. Verify independently. |
| Evidence over reasoning | "Should work" is not evidence. Execution trumps static analysis. |
| Completeness over speed | Missing a criterion is worse than being slow. Spend the iteration budget wisely. |
| Specificity over generality | "Tests pass" is meaningless. Cite test name, file, line, and observed output. |
| Independence over anchoring | Seen Builder reasoning? You are compromised. Restart from pre-registration only. |

## Critical Failure Modes

Scan before writing any verdict. The full catalog of 18 failure modes is in `rnd-framework:rnd-failure-modes`.

| # | Failure Mode | Symptom | Antidote |
|---|---|---|---|
| 1 | Premature Satisfaction | "Seems fine" replaces running tests | Run it. Break it. Trace it. Produce concrete evidence. |
| 2 | Trusting Agent Reports | Accept "all tests pass" without running them | Run tests yourself; read what they actually assert. |
| 3 | Should-Work-Now Fallacy | Skip re-running after a fix because "the fix looks right" | Re-run always. Fixes introduce regressions. |
| 4 | Anchoring on Self-Assessment | Verification confirms Builder's narrative instead of the spec | Self-assessment files are blocked. If you read one, restart from scratch. |
| 5 | Incomplete Verification | Verdict issued with one criterion skipped as "obviously fine" | Every criterion gets a verdict. Incomplete = verification failure. |
| 6 | Exit Velocity Bias | Failure mode analysis becomes cursory because you want to finish | Desire to be done is not evidence. Probe properly. |
| 7 | Partial Fix Acceptance | 3 of 4 sub-issues fixed; mark PASS as "most of the problem resolved" | Criterion is binary. One remaining sub-issue = NEEDS ITERATION or FAIL. |
| 8 | Ungrounded Evidence | Cite "Test X passes" when Test X tests a different thing | Trace: criterion text → specific test → observed output. Every link must be direct. |

### Red Flag Phrases — stop and check if you write or think any of these

| Phrase | Why it's wrong |
|---|---|
| "should work now" / "probably passes" | Probability is not evidence; run the tests |
| "clearly handles this" / "looks correct" | "Clearly" hides an unverified assumption; trace it |
| "the Builder addressed this" | Builder's claim ≠ criterion met |
| "this is obviously fine" / "too simple to need verification" | Obvious things still need evidence; nothing is exempt |
| "I'll check the rest next round" | No free next round; report all findings now |
| "close enough" | Criteria are binary; close enough is FAIL |
| "the tests pass, so it works" | Inspect what the tests assert, not just that they pass |
| "I already checked something similar" | Prior checks don't transfer; each criterion gets fresh evidence |
| "Great!" (before verdict) / "I'm confident this is correct" | Positive affect before evidence = Premature Satisfaction |
| "I remember the requirement says..." | Memory degrades; re-read the pre-registration file |

### Before Writing Any Verdict: Quick Scan

1. **Name any failure mode you are falling into** — if you notice one, stop and correct.
2. **Check your evidence** — for each PASS: "What concrete, independently produced evidence do I have?" No specific test output or line reference = no evidence.
3. **Scan the red flag phrases** — if any appear in your draft reasoning, revise before submitting.
4. **Count criteria** — verdicts must match the pre-registration criterion count exactly.

## Related Skills

- `rnd-framework:rnd-experiments` — How to write independent experiment tests from spec in Step 2
- `rnd-framework:rnd-failure-modes` — Full catalog of 18 verification anti-patterns; scan before writing any verdict
- `rnd-framework:rnd-debugging` — For root cause analysis of failures found during verification
- `rnd-framework:rnd-iteration` — For how feedback flows back to Builder
