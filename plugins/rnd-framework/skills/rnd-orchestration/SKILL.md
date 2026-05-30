---
name: rnd-orchestration
description: "Use when coordinating multi-agent R&D pipeline execution — provides pipeline overview, agent roles, information barriers, and gate criteria"
user-invocable: false
effort: medium
---

# R&D Orchestration Framework

## When to activate
Activate when the user invokes any `/rnd-framework:*` command, mentions "rnd framework", or when you detect a complex multi-step coding task that would benefit from structured decomposition and verification.

## Epistemic Foundation

This is a scientific process. Treat every claim — including your own — with skepticism until proven by evidence.

- **A result is true or false.** There is no "almost true", "mostly works", or "close enough".
- **Evidence must be reproducible.** If you can't reproduce it, it doesn't count.
- **First results are hypotheses, not conclusions.** Tests passing on the first run is a data point, not proof. What about the second run? Edge cases? Adversarial inputs?
- **Disconfirmation over confirmation.** Actively try to break things. A result that survives attempts to disprove it is stronger than one you only tried to confirm.
- **No one is served by false positives.** Passing broken work is worse than blocking correct work. When in doubt, FAIL.

## Framework Overview

This framework applies the scientific method to structured coding:

| Scientific Method | Principle | Role |
|---|---|---|
| Hypothesis declaration | Pre-registration | Declare intent + success criteria BEFORE coding |
| Structured experimentation | Hierarchical decomposition | Break tasks into System → Module → Unit with paired verification |
| Blinded peer review | Independent verification | Builder and Verifier are separate — Verifier never sees Builder reasoning |
| Reproducible evidence | Evidence-based gates | No work proceeds without reproducible evidence |
| Dependency analysis | Parallel scheduling | Identify parallel vs sequential work |

## Agent Roles & Information Barriers

The framework defines 10 specialized agent roles. Dedicated agents are spawned for each role.

**Planner** — Decomposes tasks, writes pre-registration docs with testable success criteria. Uses `rnd-framework:rnd-decomposition` skill.
**Orchestrator** — Analyzes dependencies, schedules parallel waves, enforces iteration budgets. Uses `rnd-framework:rnd-orchestration` skill.
**Builder** — Writes code + tests + honest self-assessment. Uses `rnd-framework:rnd-building` skill. Does NOT verify own work.
**Reality Auditor** — Adversarially verifies external service contracts (SQL schemas, HTTP endpoints, env vars, SDK behavior). Blocking — INVALID_FOUND routes the task back to the Builder before the Verifier sees it.
**Verifier** — Checks output against pre-registered criteria. Uses `rnd-framework:rnd-verification` skill. Does NOT read Builder's self-assessment (enforced by `read-gate.sh` hook).
**Cleanup** — Post-verification per-task entropy reduction: dead code, orphan files, duplicate implementations, stale comments. Applies mutations in-place and rolls back automatically if re-verification breaks. Uses `rnd-framework:rnd-cleanup` skill.
**Polisher** — Wave-level cross-task seam fixer: detects cross-task duplication, naming and API drift across the wave, helpers that should be lifted to shared locations, and structural inconsistencies. Runs after all per-task cleanup completes. Applies mutations in-place and rolls back automatically if re-verification breaks. Reports written to `$RND_DIR/polish/wave-<N>-polish-report.md`.
**Integrator** — Merges verified outputs, runs integration/system tests. Uses `rnd-framework:rnd-integration` skill.
**Data Scientist** — Handles numerical analysis, financial calculations, data wiring, chart generation. Uses `rnd-framework:rnd-data-science` skill. Spawned on-demand when the task requires Julia, DuckDB, or statistical analysis.

### Critical Information Flow Rules

These barriers are what make the framework work. Violating them defeats the purpose.

- Builder → Verifier: Send code, tests, artifacts. BLOCK reasoning, self-assessment, internal notes.
- Verifier → Builder (on fail): Send actionable feedback. BLOCK suggested fixes, internal reasoning.
- The Verifier must assess work purely against the pre-registered spec.

## Pre-Registration Document Format

Every task must have this BEFORE any code is written:

```
Task ID: T<number>
Intent: One sentence — what and why.
Approach: Brief planned implementation.
Expected outputs: Files/functions to produce.
Success criteria:
  Correctness:
  - [ ] Specific, testable condition 1
  Quality:
  - [ ] Specific, testable condition 2
Verification level: inline | unit | system
Dependencies: [list of task IDs]
Preconditions:
  - [File/content assertion verified before build starts — omit if none]
External dependencies:
  - system: [DB | API | file | env | service]
    contract: [What is assumed about this system — schema, response shape, format, presence]
    verification: [How this will be confirmed — e.g., Read actual schema, query endpoint, inspect file sample]
Assumptions:
  - Assumption: [What is assumed to be true — a property of an external system, codebase, or environment]
    Refuted by: [What the Builder will do to verify or disprove this assumption — e.g., read a file, grep a pattern, query an endpoint]
  - None  ← use exactly this placeholder when no assumptions exist (omission is not permitted)
Properties:  # optional — omit when no invariants are expressible
  - prop_name: forall input matching X, output satisfies Y
fulfills: [VAL-AREA-NNN, ...]
```

**The `Assumptions` section is REQUIRED in every pre-registration.** When no assumptions exist, the section must contain the literal placeholder `- None`. Omitting the section entirely is not permitted — it signals the Planner did not consider whether the task rests on unverified beliefs about the environment.

Each assumption has two sub-fields:
- `Assumption:` — a falsifiable claim about an external system, file, API shape, or codebase property that the task relies on.
- `Refuted by:` — the concrete action the Builder takes (Glob, Grep, Read, query) to confirm or disprove the assumption before writing code. If the assumption proves false, the Builder must STOP and report to the orchestrator.

## Properties (optional)

When a task has expressible invariants, the Planner adds a `Properties` block to the pre-registration. Absence means prose-mode verification (the current default) — do not require it on every pre-reg.

Three shapes are available; the Verifier dispatches based on which is present:

| Shape | When to use |
|---|---|
| markdown bullets | `docs`, `config` tasks — simple claims, no runner needed |
| YAML block | `refactor`, `bugfix` — structured claims, machine-parseable |
| sibling file | `new-feature`, `infra` — executable from day one |

**Shape 1 — markdown bullets:** Prose-shaped claims written directly in the pre-reg body.

```
Properties:
  - encode_decode_roundtrip: forall input matching valid_utf8, decode(encode(input)) == input
```

**Shape 2 — YAML block:** Structured claims parsed and executed by the Verifier's property runner (StreamData for Elixir, fast-check for TypeScript).

```
Properties:
  runner: elixir
  properties:
    - name: encode_decode_roundtrip
      generator: StreamData.binary()
      invariant: "Codec.decode(Codec.encode(x)) == x"
```

**Shape 3 — sibling file `T<id>-properties.{exs,ts}`:** Executable code the Planner sketches and the Verifier runs independently. The Builder never executes it.

```typescript
// T7-properties.ts
import * as fc from "fast-check"
import { encode, decode } from "./codec"

fc.assert(fc.property(fc.string(), (input) => decode(encode(input)) === input))
```

**Execution is verifier-only.** Properties run exclusively in the Verifier agent. Counter-examples appear in `T<id>-verification.md` as shrunk reproducers.

**Calibration write — `verification_mode`.** When a pre-registration contains any of the three Properties shapes, the orchestrator MUST set `verification_mode: property` in the per-verdict calibration record it writes to `calibration.jsonl`. Pre-regs without a `## Properties` section default to `verification_mode: prose`. Reality-audit schema checks use `verification_mode: schema`. Property runs that are skipped due to a missing runtime use `verification_mode: skipped`.

## Execution Mode

Dedicated agents are spawned for each pipeline role. The orchestrator session coordinates them, enforcing information barriers and gate criteria.

### Dispatch Policy: Criticality-Driven Model Selection

Four agents support **per-spawn model override** based on the per-task `Criticality` field in the pre-registration. Non-adaptive agents always run at their fixed model/effort regardless of criticality.

**Per-agent criticality matrix:**

| Agent | LOW | NORMAL | HIGH | Adaptive? |
|---|---|---|---|---|
| `rnd-planner` | opus/high | opus/high | opus/xhigh | yes |
| `rnd-verifier` | sonnet/high | opus/high | opus/xhigh | yes |
| `rnd-builder` | sonnet/high | sonnet/high | opus/high | yes |
| `rnd-debugger` | sonnet/high | sonnet/high | opus/high | yes |
| `rnd-polisher` | opus/high | opus/high | opus/xhigh | no (per-wave, fixed) |

> **Note on non-adaptive agents:** `rnd-polisher` always runs at its listed model and effort — the criticality column shows the same value in every tier to make this explicit. Auxiliary agents not in this table (integrator, cleanup, reality-auditor, data-scientist) are also non-adaptive and always use their frontmatter `model:`.

**Fallback rule.** If the task has no `Criticality` field (or no pre-reg), the orchestrator does NOT override — the agent's frontmatter `model:` is used. Effort is NOT per-spawn overridable; it stays at the agent's frontmatter value.

**Granularity.** Builder/Verifier/Debugger spawns read the criticality of the specific task they are working on (per-task). Planner uses the overall task tree's max-criticality at plan time (or the user-stated complexity at `/rnd-start`).

**Dispatch example:**

```
// Task T7 has `Criticality: HIGH` in plan.md → spawn Builder with model="opus"
Agent({
  description: "Build task T7",
  subagent_type: "rnd-framework:rnd-builder",
  model: "opus",
  mode: "acceptEdits",
  prompt: "Task: T7\nRND_DIR: ...\n..."
})
```

**Frontmatter defaults (used when criticality is absent OR for non-adaptive agents):**

| Agent | Default model | Effort | Adaptive? |
|---|---|---|---|
| `rnd-planner` | opus | high | yes |
| `rnd-builder` | sonnet | high | yes |
| `rnd-verifier` | sonnet | high | yes |
| `rnd-debugger` | sonnet | high | yes |
| `rnd-reality-auditor` | sonnet | low | no |
| `rnd-cleanup` | sonnet | medium | no |
| `rnd-polisher` | opus | high | no |
| `rnd-integrator` | haiku | low | no |
| `rnd-data-scientist` | sonnet | medium | no |

> **Note on RND_DIR:** Compute the artifact directory via `"${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh"`. This outputs an absolute path like `~/.claude/.rnd/<dirname>-<hash>/sessions/<YYYYMMDD-HHMMSS-XXXX>/`. Use `-c` flag to create directory structure.

### task_type Inference Policy

When recording a calibration entry for a completed task, the orchestrator infers `task_type` from the task's title and pre-registration `Intent` field. Match the first rule that fires; default to `infra` on no match.

| task_type | Trigger keywords (substring match, case-insensitive) |
|-----------|------------------------------------------------------|
| `refactor` | refactor, restructure, rename, reorganize, cleanup, extract, move, split |
| `new-feature` | feature, add, introduce, implement, new, build, create, support |
| `bugfix` | fix, bug, defect, broken, wrong, incorrect, regression, patch |
| `docs` | docs, documentation, readme, changelog, comment, annotate, describe |
| `config` | config, setting, env, environment, flag, toggle, threshold, parameter |
| `infra` | (default — no keyword match; also explicit: infra, scaffold, pipeline, hook, gate, schema, telemetry) |

Evaluation order matches the table above — first match wins. Concatenate title + Intent value, then scan. Write the matched tag as `task_type` in the calibration record.

### Calibration Auto-Escalation

Before spawning any adaptive agent (planner, builder, verifier, debugger), the orchestrator MUST run:

```bash
"${CLAUDE_PLUGIN_ROOT}/lib/calibration.sh" should_promote <original_tier>
```

- **Exit 0 (promotion warranted):** set the effective tier to the output of `calibration.sh promote_tier <original_tier>`, use the effective tier for model selection in the dispatch table, and emit:
  ```bash
  "${CLAUDE_PLUGIN_ROOT}/lib/audit-event.sh" tier_escalated <task_id> <orig>-><new>
  ```
- **Exit non-zero (no promotion):** use the original tier as the effective tier; emit no audit event.
- **`RND_DISABLE_AUTO_ESCALATION=1`:** disables the entire mechanism — `should_promote` always exits non-zero when this variable is set.

Rationale: auto-escalation closes the calibration loop on model-quality drift. `FALSE_PASS_PROXY` records (see `rnd-framework:rnd-calibration` skill) feed the false-pass rate; when the rolling rate reaches 20%, the next spawn upgrades one tier automatically.

### Shape-Validity Fast Path

The framework earns the right to move fast in a task-shape only after a feedback-confirmed track record proves it is reliably good there. Before spawning a **Builder** for a build task, the orchestrator runs a pre-spawn gate that decides whether to emit a **fast profile**. Speed is the *output* of demonstrated expertise — never a lever pulled against quality.

**Determining the task's shape.** The shape is the dominant assertion shape of the task: read the task's `assertionIds[]` from `features.json`, look up each assertion's `Shape:` field in `validation-contract.md` (equivalently, the `assertion_shape` events in `audit.jsonl`), and take the first assertion's shape as the task-shape (ties broken by document order). This is the **same** shape used by the post-review attribution chain and the validity ledger, so the gate, the ledger, and the immune system all agree on one shape per task.

**The gate (mirrors the should_promote gate: call helper → branch on exit code):**

```bash
# 1. Criticality is a HARD FLOOR — check it FIRST, before consulting validity.
#    HIGH NEVER fast-paths regardless of validity.
if [[ "$criticality" == "HIGH" ]]; then
  : # full path — do NOT consult the validity ledger
else
  # 2. LOW/NORMAL only: consult the live validity ledger for the task-shape.
  if "${CLAUDE_PLUGIN_ROOT}/lib/calibration.sh" validity "<task-shape>"; then
    : # exit 0 + "expert" → emit the FAST PROFILE
  else
    : # exit non-zero + "novice <n>" → full path
  fi
fi
```

- **Exit 0 (expert) AND criticality ∈ {LOW, NORMAL}:** emit the **fast profile** for this task's Builder and Verifier spawns.
- **Exit non-zero (novice), OR criticality == HIGH:** use the **full path** (standard Builder TDD ceremony + standard Verifier rigor + normal iteration budget).
- **Models stay at the criticality tier.** The fast path does NOT drop the model a tier — model selection still follows the criticality-driven dispatch table above. The fast profile reduces *ceremony*, never model strength.

**Skip-condition table (every combination):**

| Shape validity | Criticality | Dispatch |
|----------------|-------------|----------|
| non-expert (novice) | LOW | full path |
| non-expert (novice) | NORMAL | full path |
| non-expert (novice) | HIGH | full path |
| expert | LOW | **fast profile** |
| expert | NORMAL | **fast profile** |
| expert | HIGH | full path (HIGH is a hard floor — never fast-paths) |

**The fast profile — three explicit imperatives (the no-slop floor):**

1. **The builder STILL writes a `## Files written` manifest** (named by the `M<NN>-T<NN>-<uuid>` convention). This is load-bearing: post-review attribution maps each finding back to its owning task through this manifest, so a skipped manifest would silently orphan every finding for the task. The fast profile reduces builder ceremony to *recognition + a lightweight self-check* but NEVER skips the manifest write.
2. **Verification ALWAYS runs.** The Verifier is ALWAYS spawned — lighter (prose / reduced-experiment rigor), never absent. The fast profile lowers verifier *rigor*, it does NOT skip verification.
3. **Iteration collapses to a SINGLE build-verify pass.** No multi-round iteration budget under the fast profile — one build, one verify.

The fast profile reduces ceremony and rigor; it NEVER skips the manifest or the verifier. That is the inviolable no-slop floor.

**One-strike demotion is real — via recomputation, not a shadow record.** The gate reads `calibration.sh validity` **live on every dispatch**. The validity subcommand recomputes the consecutive-clean streak directly from `post-review.jsonl` each call with no persisted/cached streak state. So the moment a new post-review finding lands for a shape (a dirty session), the next dispatch's recomputation mechanically drops that shape's streak below 5, and the shape reads `novice` again — without writing any separate demotion or shadow record. The reset falls out of the stateless ledger: a shape at 5 consecutive clean (expert) plus one appended dirty row reads `novice 0` at the very next gate read. There is no stale-state window, because nothing is persisted to go stale.

## Stop Conditions

Two post-hoc checks guard against pathological pipeline trajectories. Both fire after a Verifier wave completes or after the Planner writes `plan.md` — not in PreToolUse hooks, because they require LLM interpretation of context.

### Verdict-Flip Detection

After every Verifier wave, run:

```bash
"${CLAUDE_PLUGIN_ROOT}/lib/audit-scan.sh" verdict_history <task_id>
```

The `verdict_history` subcommand (see `lib/audit-scan.sh`) reads all `verifications/T<id>-verification*.md` files for the given task and returns the space-separated verdict sequence. When it detects a PASS→FAIL→PASS or FAIL→PASS→FAIL pattern, it prints `FLIP_DETECTED` and exits 0.

**When `FLIP_DETECTED` is received:** halt the pipeline and use `AskUserQuestion` with these options:

```
AskUserQuestion(
  question: "Task T<id> has a verdict-flip (PASS→FAIL→PASS or FAIL→PASS→FAIL), indicating non-determinism in the Verifier or instability in the implementation. How should we proceed?",
  options: [
    { label: "Pause and inspect (Recommended)",   description: "Review T<id>-verification*.md files to find the root cause before continuing." },
    { label: "Force a fresh re-verification",      description: "Run one more Verifier pass treating prior verdicts as noise." },
    { label: "Accept current verdict and continue", description: "Treat the latest verdict as authoritative and proceed to the next phase." }
  ]
)
```

**Tuning:** set `RND_STOP_VERDICT_FLIPS=0` to disable the check entirely. Future: the env var may accept a count threshold (default: 1 flip triggers the halt).

**Emit `gateFired` on halt:** append to `calibration.jsonl` with:

```json
{ "gateFired": { "gate": "stop_condition_verdict_flip", "outcome": "halted", "task_id": "<task_id>" } }
```

See `rnd-framework:rnd-calibration` for the full `gateFired` schema and producer registry.

### Plan-Size Check

After the Planner writes `plan.md`, the orchestrator reads the `Heuristic ceiling: N` meta-field from the top of `plan.md` (see planner agent for format) and compares it to the actual task count:

```
task_count > RND_STOP_PLAN_RATIO * Heuristic ceiling   →   halt
```

**Default:** `RND_STOP_PLAN_RATIO=1.5`. A plan with ceiling 4 halts when task count exceeds 6.

**When the check fires:** halt and use `AskUserQuestion` with these options:

```
AskUserQuestion(
  question: "The plan has <task_count> tasks but the Heuristic ceiling is <N> (ratio <actual> vs allowed <RND_STOP_PLAN_RATIO>). An oversized plan risks runaway builds. How should we proceed?",
  options: [
    { label: "Trim the plan (Recommended)", description: "Go back to the Planner and coalesce or drop low-priority tasks until task_count ≤ ceiling × ratio." },
    { label: "Raise the ceiling",           description: "Accept the larger plan; update Heuristic ceiling in plan.md." },
    { label: "Proceed anyway",              description: "Continue with the oversized plan and accept the higher build risk." }
  ]
)
```

**Tuning:** `RND_STOP_PLAN_RATIO=0` disables the check. Increase the value to tolerate larger plans (e.g., `RND_STOP_PLAN_RATIO=2.0`).

**Emit `gateFired` on halt:** append to `calibration.jsonl` with:

```json
{ "gateFired": { "gate": "stop_condition_plan_size", "outcome": "halted", "task_id": null } }
```

## Subagent Coordination

### Agent Permission Mode

All pipeline agents are spawned with `mode: "acceptEdits"`:

- **Planner** — decomposes tasks and writes pre-registrations
- **Builder** — implements tasks with TDD discipline
- **Verifier** — independently checks outputs against pre-registered criteria
- **Cleanup** — sweeps dead code and stale artifacts per task after PASS
- **Integrator** — merges verified outputs and runs integration tests

**Rationale:** The framework's own quality gates (pre-registration, information barriers, independent verification, evidence-based pass/fail gates) provide robust quality control. `acceptEdits` auto-approves Edit/Write on project files — the exact surface pipeline agents need — while leaving Bash under the normal classifier. Observed on Claude Code 2.1.112: `mode: "auto"` denied project-file Edit/Write for team-spawned subagents (see audit log), and `mode: "bypassPermissions"` was not honored for tmux-backed team agents.

### Do Not Spawn the `Explore` Subagent

During rnd phases (Phase 0 discovery, Phase 1 planning, Phase 5 re-plan), the `Explore` subagent has been observed to return with `0 tool uses` — no work performed, no findings, the spawn slot wasted. When the orchestrator or a pipeline agent needs to search the codebase, call `Glob`, `Grep`, and `Read` **inline** in the current context. Reserve subagent spawns for pipeline roles (`rnd-planner`, `rnd-builder`, `rnd-verifier`, `rnd-reality-auditor`, `rnd-cleanup`, `rnd-polisher`, `rnd-integrator`, `rnd-debugger`, `rnd-data-scientist`, `rnd-premortem-imaginer`, `rnd-replan-differ`, `rnd-assertion-paraphraser`).

### Blocking Behavior

**The Agent tool is blocking** — it returns only when the subagent completes. Do not poll, sleep, or manually check `$RND_DIR` files for progress. Spawn agents and process their results when the tool returns.

- **Never** use `sleep` to wait for subagents
- **Never** write bash loops to check if build artifacts exist yet
- **Never** scan `$RND_DIR/builds/` to see if a builder is done — the Agent tool tells you
- **Do** spawn multiple agents in parallel (multiple Agent tool calls in one message) for independent tasks within a wave
- **Do** use `run_in_background: true` on Agent calls if you want to continue working while agents run, then process results when notified

## Execution Phases

1. **Plan** — Run environment discovery (structured checklist scan for package manager, test framework, CI, external services, env vars, secrets). Decompose the task, write pre-registrations with `fulfills` traceability, build dependency matrix. Generate Validation Contract (numbered VAL-AREA-NNN assertions with exact evidence commands). Produce enriched plan.md with sections: Task Tree, Environment Setup, Infrastructure, Testing Strategy, Worker Guidelines, Validation Contract, Pre-Registration Documents, Dependency Matrix, Execution Schedule, Iteration Budgets. Write exploration cache to `$RND_DIR/exploration/`. In multi-agent mode, the Planner agent handles this phase.
2. **Schedule** — Create execution waves from dependency matrix. In multi-agent mode, the Orchestrator session handles scheduling directly.
3. **Build** — Work tasks in parallel within waves. Produce code + tests + self-assessment. Builder agents are spawned per task.
3.5. **Reality Audit** (blocking, conditional) — Run only when:
   - Task has `External dependencies` declared in pre-registration AND
   - User has not disabled via `--skip-reality-checks`
   Adversarially verifies declared external references. INVALID_FOUND routes back to build.
   If no external dependencies declared → auto-SKIPPED.
4. **Verify** — Check each task against pre-registered criteria. PASS/FAIL/ITERATE. In multi-agent mode, Verifier agents are spawned independently.
4. **Cleanup** (per task, after PASS) — Spawn a Cleanup agent for each task that passed verification. The agent detects and removes: dead functions/variables, orphan files, duplicate implementations, and stale comments. Applies mutations in-place and rolls back automatically if re-verification breaks. Reports written to `$RND_DIR/cleanup/T<id>-cleanup-report.md`. A `cleanup: rolled_back` result is not a pipeline failure.
4.5. **Polish** (wave-level, after all per-task cleanup) — Spawn ONE Polisher agent for the entire wave. The agent detects and fixes cross-task seam issues: cross-task duplication, naming and API drift across the wave, helpers that should be lifted to a shared location, and structural inconsistencies. Applies mutations in-place and rolls back if re-verification breaks. Reports written to `$RND_DIR/polish/wave-<N>-polish-report.md`. A `polish: skipped` result is not a pipeline failure.
5. **Iterate** — On FAIL, build phase gets feedback only (not fixes). Iteration budget is wave-scoped and tier-keyed (LOW=2, NORMAL=3, HIGH=5, by highest-criticality task in the wave); see `rnd-framework:rnd-iteration` for the table. Budget exhausted → escalate.
6. **Integrate** — Merge verified outputs, run integration tests, system validation. In multi-agent mode, the Integrator agent handles this phase.

## Gate Criteria

**Gate 1 (post-plan):** Every task has complete pre-registration with testable criteria, `fulfills` field linking to VAL assertions, and all Validation Contract assertions are covered.
**Gate 2 (post-build):** Code + tests + artifacts submitted. Tests pass locally.
**Gate 2.5 (post-reality-audit):** Reality Audit complete for every task in the wave. Any INVALID verdict blocks pipeline progression for that task — it must return to build before proceeding to verification.
**Gate 3 (post-verify):** Verification PASS on all criteria with evidence.
**Gate 4 (post-integrate):** Integration tests pass. No regressions. System validation passes.

## Task Status Determination

Task status is derived from artifact files — no separate state file is needed. At each gate, check:

| Artifact exists? | Status |
|-----------------|--------|
| `$RND_DIR/integration/wave-<N>-report.md` contains SHIP | integrated |
| `$RND_DIR/verifications/T<id>-verification.md` contains `Overall Verdict: PASS` | verified |
| `$RND_DIR/verifications/T<id>-verification.md` contains NEEDS_ITERATION | iterating |
| `$RND_DIR/builds/<ref>-manifest.md` exists and is non-empty | built |
| Task in plan.md but no build artifact | planned |

**Build-manifest naming.** Build manifests are named by the task's canonical unique reference `M<NN>-T<NN>-<uuid>` — `$RND_DIR/builds/M<NN>-T<NN>-<uuid>-manifest.md` (e.g. `M02-T03-f6d3915b-manifest.md`). The `uuid` (from `features.json`) makes the filename globally unique, so two tasks that share a `T<NN>` slot across milestones (`M1.T01` and `M2.T01`) produce DISTINCT manifest files and never overwrite each other. The filename is the canonical attribution key: the post-review writer extracts the `uuid` from it and matches `features.json .uuid` exactly, never a substring on the bare `T<NN>` slot.

**At each gate**, validate the expected artifact exists and is non-empty (use Bash `test -s`). If missing, report to the user via `AskUserQuestion` and do not proceed with that task.

**Always use pipeline IDs in user-facing output.** When displaying task references, blocked-by relationships, or status updates, always use `T<n>` pipeline IDs — never raw Claude Code internal IDs (`#<n>`). Resolve internal IDs by matching against `metadata.pipelineId` set during `TaskCreate`, or by extracting the `T<n>` prefix from the task subject.

**Before scheduling each wave**, scan `$RND_DIR/builds/` and `$RND_DIR/verifications/` to determine which tasks are complete. Skip tasks that already have the expected artifacts for the current phase.

## User Decision Points

When a phase completes and the user needs to decide what happens next, **use `AskUserQuestion` with structured options** instead of open-ended text like "Would you like me to...?". This eliminates decision fatigue.

Rules:
- Always include 2-4 concrete options
- Mark the recommended option first with "(Recommended)" in the label
- Use short, action-oriented labels (e.g., "Fix P0 blockers first", "Verify wave-1", "Re-plan T3")
- Put context in the `description` field, not the label
- Never ask the user to type out what to do next — give them options to pick from

Common decision points:
- **Post-plan:** "Approve plan", "Revise criteria for T2", "Add more tasks"
- **Post-build:** "Verify this wave", "Re-build T3", "Review findings first"
- **Post-verify (mixed results):** "Fix P0 issues first (Recommended)", "Fix all issues", "Ship as-is with known issues"
- **Post-integrate:** "Ship it", "Run another verification pass", "Fix integration failures"

## Scaling Rules

- **Small tasks (<1hr):** Collapse — one Builder + one Verifier (single judge). Lightweight pre-registration.
- **Medium tasks:** Full framework with parallel waves. Use 2-judge consensus verification per task.
- **Large tasks (multi-day):** Add design review gate between Plan and Schedule. Add sub-waves. Use 2-judge consensus verification.
- **Exploratory:** Add Phase 0 — spike 2-3 approaches with time-box before committing.
- **High-stakes:** Multi-judge verification (2 judges + tiebreaker on disagreement).

## User-Facing Briefs

Briefs are user-facing narratives — plain-language updates the user sees in real time while a non-verifier agent works in the background. They live under `$RND_DIR/briefs/` which is mechanically blocked from Verifier agents via the three PreToolUse gate hooks (`hooks/read-gate.sh`, `hooks/glob-grep-gate.sh`, `hooks/bash-gate.sh`). Only Planner, Builder, Debugger, Integrator, and the orchestrator may read or write briefs.

**Files (per agent):**
- Planner: `$RND_DIR/briefs/plan-briefs.md`
- Builder / Debugger: `$RND_DIR/briefs/T<id>-briefs.md`
- Integrator: `$RND_DIR/briefs/wave-<N>-briefs.md`

All brief files are append-only. Use the Read tool to load existing content, then Write the concatenated result. Never delete prior entries. `mkdir -p "$RND_DIR/briefs"` before first write.

**When to append a brief entry:**
- **On phase completion (always):** one entry summarizing what was built/decided/integrated, surprising findings, unverified assumptions, anything the user should know.
- **Mid-phase, on a non-trivial judgment call:** one entry capturing the choice in plain language. Pair (do not replace) with the structured `decisions.md` entry.

Skip briefs for routine micro-steps, green-tests status, or anything the user can read off the diff or manifest. Signal, not noise.

**Entry template:**

```markdown
## [ISO timestamp] — <Phase> <T<id>|wave-<N>>: [decision|completion] — [short title]

[One paragraph in plain language. What changed, why it matters, what the user should know. Avoid pipeline internals. If there is an unverified assumption or surprising finding, surface it here.]
```

**Notify the orchestrator** via `SendMessage` after each brief append:

```
[user-brief] <context>: <short title> — see <file path>
```

The orchestrator reads the latest entry and surfaces it to user chat. The orchestrator MUST NOT forward brief content into any Verifier spawn prompt — the hook layer also enforces this mechanically by blocking `/briefs/` reads when no agent_type is set or when the agent is the verifier.

## Decisions Log

Persistent, append-only record of non-trivial judgment calls shared across Planner, Builder, Debugger, and Integrator. Survives past the chat transcript so the "why we chose X" thread remains discoverable.

**File:** `$RND_DIR/briefs/decisions.md` (append-only — Read existing content, then Write the concatenated result; never delete prior entries).

**When to log an entry:**
- Architectural fork between meaningfully different approaches (not surface variations).
- Scope cut (deferring or rejecting a requirement).
- Library / framework / primitive choice when there were real alternatives.
- Interface-shape decision (API contract, function signature) callers will depend on.
- Non-obvious ordering or sequencing choice.
- A fork where the LLM-default was rejected in favor of something else — always log these.

**When NOT to log:** variable naming, formatting, micro-refactors within a function, following an already-specified path without divergence, decisions dictated by the pre-registration.

**Entry template:**

```markdown
## D<N>: [one-line title]

- **Phase:** Planning | Building T<id> | Debugging T<id> | Integration wave <N>
- **Context:** [what situation forced a choice — 1 sentence]
- **Considered:**
  - A. [option name] — [tradeoff / why it could work]
  - B. [option name] — [tradeoff / why it could work]
  - C. [option name] (optional) — [tradeoff]
- **Chosen:** [letter + name]
- **Why:** [1-2 sentences, tied to constraints or evidence]
- **Would flip if:** [condition under which a different option becomes better]
```

**Explicit-fork discipline:** when an agent makes a decision that qualifies, the agent's output MUST narrate the fork ("I considered A, B, C; chose A because...") before appending the entry. This forces critical thinking at the decision point instead of post-hoc justification.

## Re-plan Flow

When the user selects "Re-plan failing tasks" from either the Gate 3 FAIL prompt or the Phase 5 budget-exhaustion prompt, the orchestrator runs the re-plan flow defined in `commands/rnd-start.md` (Phase 5 → `### Re-plan flow`). The flow is designed to *hide the previous plan* from the fresh Planner so the new decomposition is not anchored on the failed one.

**Trigger conditions:**

1. **Gate 3 FAIL** — the wave verdict map contains FAIL assertions and the user picks "Re-plan failing tasks (Recommended)" from the post-Gate-3 `AskUserQuestion`.
2. **Phase 5 budget exhaustion** — the wave iteration budget is spent and the wave rebuild still has failures, and the user picks "Re-plan failing tasks" from the budget-exhaustion `AskUserQuestion`.

**Outline:**

1. Archive the four canonical plan artifacts (`protocol.md`, `validation-contract.md`, `features.json`, `AGENTS.md`) under `$RND_DIR/prior-plans/replan-<k>/` via `lib/replan-archive.sh "$RND_DIR"`.
2. Touch the marker file `$RND_DIR/.replan-in-progress`. This enables the `is_replan_artifact_violation` predicate in `hooks/lib.sh`, which mechanically blocks the fresh Planner from reading the four canonical session-root plan paths (`$RND_DIR/{protocol.md,validation-contract.md,features.json,AGENTS.md}`). The archived copies under `$RND_DIR/prior-plans/` remain readable so the differ can compare them against the new plan.
3. Emit `replan-emit.sh started <iteration> <archive_path>`.
4. Build a `${REPLAN_HINT_BLOCK}` containing only the failing task IDs and assertion IDs sliced from the latest `wave-<N>-verdict-map.json`. Do NOT include prior `protocol.md`, `validation-contract.md`, or assertion-body content.
5. Spawn `rnd-planner` with the hint block as the only signal about prior failure. The spawn prompt carries an explicit `MUST NOT` imperative against inlining prior artifact content — this is the FM2 defense-in-depth at the prompt layer; the barrier hook is the mechanical layer.
6. After the Planner returns and writes the new plan artifacts, spawn the `rnd-replan-differ` agent with the old/new path pairs. The differ writes `$RND_DIR/replan-diff.md` summarizing task and assertion-level changes.
7. Emit `replan-emit.sh diff_emitted <task_changes_count> <assertion_changes_count>`.
8. Remove the `.replan-in-progress` marker so the diff and archive are readable again by the orchestrator's narrative phase.
9. Surface the diff to the user via the brief-relay mechanism, then resume from Phase 2 with the fresh plan.

**Audit events.** Two events frame each re-plan cycle: `replan_started` (carries iteration counter and archive path) and `replan_diff_emitted` (carries change counts). Both are emitted via `lib/replan-emit.sh`.

**Cross-references:** the canonical step-by-step lives in `commands/rnd-start.md` under Phase 5's `### Re-plan flow` subsection; the helpers are `lib/replan-archive.sh` and `lib/replan-emit.sh`; the diff agent is `agents/rnd-replan-differ.md`; the barrier predicate is `hooks/lib.sh::is_replan_artifact_violation`, gated by the `.replan-in-progress` marker.

## Session-Local Skill Injection

Session-local skills are narrow, project-specific skills the Planner mints during exploration when the project has a convention, helper library, or domain idiom that no global skill covers. They supplement — not replace — global skills for the duration of a single pipeline session.

### Layout

Skills are placed at:

```
$RND_DIR/skills/<skill-name>/SKILL.md
$RND_DIR/AGENTS.md              ← lists which skills are active this session
```

`AGENTS.md` carries a `## Session Skills` section listing each active skill by name. The orchestrator reads this file on every agent spawn to discover the current skill set.

### Injection Mechanism

Before spawning any agent, the orchestrator reads `$RND_DIR/AGENTS.md` and `$RND_DIR/skills/*/SKILL.md`. The content of each session-local skill is injected into the agent's prompt under two headers:

- **`## Session Context`** — session-wide guidance from `AGENTS.md` (conventions, domain constraints, cross-task rules)
- **`## Session Skills`** — content of each session-local `SKILL.md`, one per skill, titled by skill name

Both sections appear in the agent prompt before the task-specific instructions. This is prompt injection only — session-local skills are NOT registered with the Skill tool and are not invocable by name. In v5.0 of the framework, they are prompt-injected exclusively.

### Audit Event

After injecting session-local context into an agent prompt, the orchestrator emits one audit event per spawn:

```bash
"${CLAUDE_PLUGIN_ROOT}/lib/audit-event.sh" skill_injected <task_id> <agent_type>
```

For example:

```bash
"${CLAUDE_PLUGIN_ROOT}/lib/audit-event.sh" skill_injected M1.T03 rnd-builder
```

The 3-argument form is canonical. `audit-event.sh`'s optional 4th argument is reserved for `assertion_id` semantics and must not be overloaded with a skill name — agent-spawn injection is a per-spawn event, not a per-skill event, so the full session-local fragment is logged once per spawn regardless of how many skills it contains.

### When to Inject

Inject session-local skills into every agent spawn — not selectively. An agent that does not receive a skill it needed produces incorrect output that looks correct, which is worse than a build failure. The injection cost is a few extra prompt tokens; the risk of selective injection is silent divergence.

## Related Skills

- `rnd-framework:premortem` — Phase 1 failure-imagination fan-out before the Planner spawn
- `rnd-framework:outside-view` — Phase 1 reference-class injection into the Planner prompt
- `rnd-framework:rnd-design` — Phase 0.5 architectural alternatives gate
- `rnd-framework:rnd-decomposition` — Planner protocol for task breakdown
- `rnd-framework:rnd-scheduling` — Wave scheduling from the dependency matrix
- `rnd-framework:rnd-local-experts` — Phase 0 project-local agent/skill discovery
- `rnd-framework:rnd-roadmapping` — Multi-session roadmap milestone management
- `rnd-framework:rnd-iteration` — Build–verify feedback loop and re-plan escalation
- `rnd-framework:rnd-failure-modes` — Catalog of pipeline failure modes
- `rnd-framework:rnd-scaling` — Choosing the right ceremony level per task
- `rnd-framework:rnd-formatting` — Pre-commit formatter run (Phase 7)
- `rnd-framework:rnd-doc-polish` — CLAUDE.md / README updates after SHIP (Phase 7)
- `rnd-framework:rnd-narrative` — Development narrative on demand (Phase 7)
- `rnd-framework:rnd-completion` — Branch/PR workflow after SHIP
- `rnd-framework:rnd-debug-pipeline` — Bug-fix pipeline variant for diagnosis-first work
- `rnd-framework:rnd-doctor` — Runtime environment readiness check
