---
name: rnd-decomposition
description: "Use when breaking a complex task into sub-tasks with pre-registration documents — structured hierarchical decomposition, dependency analysis, and testable success criteria"
user-invocable: false
effort: medium
---

# R&D Decomposition

## Overview

Decompose tasks into structured sub-task trees. Every sub-task gets a pre-registration document with testable success criteria BEFORE any code is written.

**Core principle:** If you can't write testable success criteria, the task isn't understood well enough to build.

## When to Use

- Planning phase of `/rnd-framework:rnd-start` or `/rnd-framework:rnd-plan`
- Any non-trivial feature, refactor, or task with multiple moving parts or unclear success criteria

## The Iron Law

```
NO CODING WITHOUT PRE-REGISTRATION
```

## Hierarchical Decomposition

```
System Level:  [Feature]  <->  [System Validation]
Module Level:  [Components]  <->  [Integration Tests]
Unit Level:    [Functions]  <->  [Unit Tests]
```

1. Start at System level — what does the feature DO end-to-end?
2. Identify Modules — what components are needed?
3. Break into Units — what functions/utilities does each module need?
4. Pair each level with verification — system validation, integration tests, unit tests

A criterion is testable if a skeptical Verifier can evaluate it from evidence alone: **observable outcome** (return value, state change, error thrown), **concrete conditions** (specific inputs, thresholds, error types), **binary result** (met or not met).

### Decomposition Heuristics

- **Too big:** >5 success criteria → split
- **Too small:** single function with one criterion → merge up
- **Too vague:** "works correctly", "handles errors" → rewrite with observable outcomes
- **Uncertain:** approach unclear → add Phase 0 spike task
- **Unverified external contract:** DB schema, API shape, env var not confirmed → add Phase 0 spike or dedicated verification step before that task
- **Local expert available:** set the `Local expert` field in the pre-registration so the Builder knows to invoke it

## Decomposition Caps

Hard limits that apply after heuristics:

- **Maximum 4 tasks per wave** — if a wave would contain more, split into sub-waves or coalesce tasks.
- **Minimum task scope: 1 hour of work** — tasks smaller than this must coalesce with a sibling. A task that touches one line or one config key is below the minimum scope.
- **Coalescing rule:** when two tasks share the same file set and could be reviewed in a single pass, merge them unless their success criteria require different verification levels.

## Exploration Cache

Before decomposition, write structured findings to `$RND_DIR/exploration/` (`mkdir -p`). One kebab-case file per area (e.g., `hooks-architecture.md`). Each file: `## Files Examined`, `## Key Patterns`, `## Relevant Dependencies`, `## Notes for Builders`.

## Session-Local Skills

During exploration, the Planner may discover project conventions that no global skill covers. When that happens, mint a session-local skill so every Builder and Verifier in the session gets the same context automatically — without requiring each agent to re-explore the same files.

**Mint a session-local skill when any of these triggers fires:**

- **Non-obvious testing helper.** The project wraps test assertions in a custom helper (e.g., `assertInvariant`, `expectSnapshot`) that is not self-documenting from its name alone — Builders will reach for the wrong idiom without guidance.
- **Custom assertion library not in the global skill set.** The project uses a test-doubles, schema-validation, or matcher library (e.g., a bespoke `assert_schema/2` module, a vendor-forked copy of a popular library) that differs from the ecosystem default in ways that cause silent test failures if used incorrectly.
- **Unusual build pipeline or domain idiom.** The project has a non-standard compile step, code-generation phase, or domain-specific convention (e.g., a custom asset pipeline, protocol buffer generation, domain event naming rules) that Builders must follow to produce correct outputs.
- **Project-specific error handling contract.** The codebase enforces a consistent error shape or exception hierarchy that Builders must conform to — deviating produces code that compiles but breaks callers silently at runtime.

Place skill files at `$RND_DIR/skills/<skill-name>/SKILL.md`. Use the same frontmatter format as global skills:

```markdown
---
name: <skill-name>
description: "<one sentence — when to invoke and what it teaches>"
effort: low
---

# <Skill Title>

[Concise description of the convention, helper, or idiom. Include concrete examples — a function signature, a code snippet, a naming rule. Builders read this in full before writing code.]
```

Set `effort: low` for reference skills (read-once for orientation). Only raise effort if the skill documents a multi-step workflow.

After writing a session-local skill, list it in `$RND_DIR/AGENTS.md` under a `## Session Skills` section so the orchestrator picks it up for injection.

## Pre-Registration Document

```
Task ID: M<N>.T<NN>.<slug>
Intent: [One sentence — what this accomplishes and why]
Approach: [Brief planned implementation strategy]
Expected outputs: [List of files/functions/artifacts to produce]
Criticality: LOW | NORMAL | HIGH
Success criteria:
  Correctness:
  - [ ] [Functional requirement, test passing, or contract conformance condition]
  - [ ] [Another must-pass condition]
  Quality:
  - [ ] [Code quality, naming, patterns, or documentation condition]
Verification level: unit | integration | system
Dependencies: [Task IDs this depends on — M<N>.T<NN>.<slug> format]
Preconditions:
  - [File/content assertion verified before build starts]
  - [Another assertion — if any fails, task is BLOCKED]
Local expert: [optional — name of project-local agent/skill to invoke, e.g., security-reviewer]
External Dependencies:
  - system: [DB | API | file | env | service]
    contract: [What is assumed about this system — schema, response shape, format, presence]
    verification: [How this will be confirmed — e.g., Read actual schema, query endpoint, inspect file sample]
Assumptions:
  - Assumption: [What is assumed to be true — a property of an external system, codebase, or environment]
    Refuted by: [What the Builder will do to verify or disprove this assumption — e.g., read a file, grep a pattern, query an endpoint]
  - None  ← use exactly this placeholder when no assumptions exist (omission is not permitted)
Properties:  # optional — omit when no invariants are expressible
  - prop_name: forall input matching X, output satisfies Y
fulfills: [M<N>.<area>.<slug>, ...]
```

The `fulfills` field creates bidirectional traceability between tasks and Validation Contract assertions.

**Criticality field values:**

| Value | When to use | Model boost |
|---|---|---|
| `LOW` | Trivial config, doc edits, renaming | none — Verifier runs at sonnet/high |
| `NORMAL` | Standard feature/refactor work | Verifier runs at opus/high |
| `HIGH` | Security-relevant, data-integrity, or architectural changes | Verifier runs at opus/xhigh |

## Properties (optional)

When a task has expressible invariants, the Planner adds a `Properties` block to the pre-registration. Absence means prose-mode verification (the current default) — do not require it on every pre-reg.

Three shapes are available. Choose based on task type:

| Task type | Recommended shape |
|---|---|
| `docs`, `config` | markdown bullets |
| `refactor`, `bugfix` | YAML block |
| `new-feature`, `infra` | sibling file |

### Shape 1 — markdown bullets

Prose-shaped claims written directly in the pre-reg. Use for documentation tasks, config changes, or simple invariants that don't need a runner.

```
Properties:
  - encode_decode_roundtrip: forall input matching valid_utf8, decode(encode(input)) == input
  - empty_input_returns_empty: forall input matching empty_string, encode(input) == ""
```

### Shape 2 — YAML block under `## Verification`

Structured, machine-parseable claims. The Verifier parses these and runs them via its property runner (StreamData for Elixir, fast-check for TypeScript).

```
Properties:
  runner: elixir
  properties:
    - name: encode_decode_roundtrip
      generator: StreamData.binary()
      invariant: "Codec.decode(Codec.encode(x)) == x"
    - name: encode_never_raises
      generator: StreamData.term()
      invariant: "is_binary(Codec.encode(x))"
```

### Shape 3 — sibling file `<task-id>-properties.{exs,ts}`

Executable property test code living alongside the pre-registration as a build artifact. The Planner writes a skeleton; the Verifier executes it independently. The Builder never runs it.

For Elixir (StreamData):

```elixir
# M1.T07.codec-properties.exs
defmodule CodecProperties do
  use ExUnitProperties

  property "encode/decode roundtrip" do
    check all input <- StreamData.binary() do
      assert Codec.decode(Codec.encode(input)) == input
    end
  end
end
```

For TypeScript (fast-check):

```typescript
// M1.T07.codec-properties.ts
import * as fc from "fast-check"
import { encode, decode } from "./codec"

fc.assert(
  fc.property(fc.string(), (input) => {
    return decode(encode(input)) === input
  })
)
```

**Execution is verifier-only.** Properties run exclusively in the Verifier agent. The Builder never executes them and never sees the runner output. Counter-examples, when found, appear in `T<id>-verification.md` as shrunk reproducers.

**The `Assumptions` section is REQUIRED in every pre-registration.** When no assumptions exist, the section must contain the literal placeholder `- None`. Omitting the section entirely is not permitted — it signals the Planner did not consider whether the task rests on unverified beliefs about the environment.

Each assumption has two sub-fields:
- `Assumption:` — a falsifiable claim about an external system, file, API shape, or codebase property that the task relies on.
- `Refuted by:` — the concrete action the Builder takes (Glob, Grep, Read, query) to confirm or disprove the assumption before writing code. If the assumption proves false, the Builder must STOP and report to the orchestrator.

`Preconditions` declares file/content assertions the Builder verifies before writing code — if any fail, task is immediately BLOCKED. Use concrete, tool-checkable assertions (Glob for file existence, Grep for function presence, Read for dependency key). Omit if the task creates new files from scratch.

### Tiered Criteria

| Correctness (must-pass) | Quality (should-pass) |
|---|---|
| "Returns 401 for expired tokens" | "Function names follow project naming convention" |
| "Throws ValidationError when input is null" | "Inline comments explain the retry logic" |
| "File exists at the declared output path" | "No magic numbers — constants are named" |

**Decision rule:** "Does a user or downstream system observe this outcome?" Yes → Correctness. Maintainability/DX only → Quality. Unmet Correctness → FAIL. Unmet Quality → NEEDS ITERATION.

## Environment Discovery

Check if `project-facts.md` exists (`"${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh" --facts`). If fresh (commit hash matches HEAD), use it directly. Otherwise run the checklist below and confirm findings with the user via `AskUserQuestion`.

| Area | What to scan | How |
|------|-------------|-----|
| Package manager | package.json, Cargo.toml, mix.exs, go.mod, pyproject.toml | Glob for config files |
| Test framework | vitest, jest, pytest, ExUnit, go test configs | Grep for test runner in configs/scripts |
| CI config | .github/workflows/, .gitlab-ci.yml, Jenkinsfile | Glob for CI files, Read to extract commands |
| External service URLs | https:// references in source code | Grep for URLs in src/ |
| Environment variables | .env.example, .env.template, CI secrets config | Read env templates, Grep for process.env/ENV/os.environ |
| Secrets and off-limits | .gitignore patterns, CI secret names, sensitive file paths | Read .gitignore, infer from CI config |

Findings feed into **Environment Setup**, **Infrastructure**, and **Testing Strategy** sections of plan.md.

## Dependency Analysis

Build a dependency matrix. Assign tasks with zero dependencies to Wave 1, tasks depending only on Wave 1 to Wave 2, and so on. Flag parallel opportunities within each wave.

## Output

Compute `$RND_DIR` via `"${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh"` (use `-c` to create). Write four artifact files to `$RND_DIR`:

**`protocol.md`** — strategic prose with `Heuristic ceiling: <N>` on line 2 (the orchestrator greps this value to enforce the plan-size stop condition). Contains: scope, milestones, task tree (using `M<N>.T<NN>.<slug>` IDs), environment setup, infrastructure, testing strategy, worker guidelines, dependency matrix, execution schedule, iteration budgets, and pre-registration documents.

**`validation-contract.md`** — one `### M<N>.<area>.<slug>` heading per assertion. The heading is the assertion ID; the orchestrator slices by heading to extract assertion text. Contains: `Claim` and `Verified-by` fields per assertion.

**`features.json`** — machine-readable task manifest consumed by the orchestrator with `jq`. Each task entry includes `id` (`M<N>.T<NN>.<slug>`), `slug`, `milestone`, `dependsOn` (array of task IDs), `assertionIds` (array of assertion IDs from `validation-contract.md`), `criticality`, and `status`.

**`AGENTS.md`** — session-local agent guidance authored from scratch. Not a copy of global agent prompts; contains only session-scoped context, domain constraints, and cross-task conventions for builders and verifiers on this decomposition.

### Validation Contract Format

The validation contract is written to `validation-contract.md`. Each assertion gets its own `### <assertion-id>` heading — the heading IS the assertion ID. The orchestrator slices assertions by heading, so do not nest assertion IDs within body prose.

```markdown
## Area: [Functional Domain]

### M<N>.<area>.<slug>
[One-sentence description of what must be true]
Claim: [precise statement of the invariant]
Verified-by: [exact command or observable evidence; not "tests pass" but `npx vitest run exits 0`]
Shape: [shape value from lib/event-schema.json x-shape-vocab]
Confidence: [high | medium | stretch]
```

`Shape` vocab is the controlled list in `lib/event-schema.json` (`x-shape-vocab` array — 13 values). `Confidence` is one of `high | medium | stretch`. Both fields are required; `hooks/planner-emit-gate.sh` enforces their presence at emit time.

ID format: `M<N>` is the milestone number, `<area>` is a lowercase domain abbreviation (2-6 chars, e.g., `auth`, `planner`), `<slug>` is a kebab-case descriptor (e.g., `emits-protocol-md`). Mint IDs via `id-gen.sh assertion <milestone> <area> "<title>"` — never manually slugify. Cross-cutting assertions use `area: cross`. Every assertion must be referenced in at least one task's `assertionIds` in `features.json`; every task must reference at least one assertion.

## Verification Checklist

- [ ] Every task has a complete pre-registration document with `M<N>.T<NN>.<slug>` ID
- [ ] Every success criterion is testable and tagged Correctness or Quality
- [ ] No circular dependencies; waves correctly ordered; parallel opportunities identified
- [ ] Tasks >5 criteria have been split; uncertain approaches have Phase 0 spikes
- [ ] Every task touching an external system has an `External Dependencies` field with system type, assumed contract, and verification method
- [ ] `protocol.md` Environment Setup, Infrastructure, and Testing Strategy sections populated
- [ ] `protocol.md` Worker Guidelines contains boundaries, conventions, and architecture notes
- [ ] `validation-contract.md` has `M<N>.<area>.<slug>` assertions with `Claim` and `Verified-by` for every Correctness criterion
- [ ] Every task's `fulfills` field references `M<N>.<area>.<slug>` IDs; every assertion is referenced by at least one task
- [ ] `features.json` is valid JSON; every task entry includes `id`, `slug`, `milestone`, `dependsOn`, `assertionIds`, `criticality`, `status`
- [ ] Every `assertionIds` entry in `features.json` matches a `### <id>` heading in `validation-contract.md`
- [ ] `AGENTS.md` written with session-scoped guidance (not a copy of global agent prompts)

## Plan Self-Review

After writing all four artifact files (`protocol.md`, `validation-contract.md`, `features.json`, `AGENTS.md`), reread them with fresh eyes. This is a checklist you run yourself before notifying the orchestrator — not a subagent dispatch. The Verifier cannot save you from plan-level mistakes; they cascade through every downstream phase.

Run these six checks against the finished artifacts. If any fails, fix inline and re-check.

1. **Spec coverage.** For each explicit user requirement or discovery-context constraint, point to the task(s) covering it. Gaps → add a task or explicitly note it as out-of-scope in Worker Guidelines in `protocol.md`.

2. **Placeholder scan.** Grep all four artifacts for `TODO`, `TBD`, `???`, `XXX`, `[...]`, `handle appropriately`, `works correctly`, `as needed`. Any hit → replace with concrete content or remove.

3. **Assertion traceability.** Every `M<N>.<area>.<slug>` heading in `validation-contract.md` appears in at least one task's `assertionIds` in `features.json`, and every task has a non-empty `assertionIds`. Every task's `fulfills` field lists the same IDs as its `assertionIds` entry. A mismatch means the validation contract and pre-registration drifted apart — fix whichever side is wrong.

4. **Identifier consistency.** For each function name, file path, type name, or env var that appears in multiple tasks, confirm the spelling matches across mentions. A function named `clearLayers` in `M1.T03.add-auth` and `clearFullLayers` in `M1.T07.wire-api` is the most common cascading plan error.

5. **External-dependency completeness.** Any task whose Intent, Approach, or Expected outputs references a DB, API, file, env var, or external service MUST have a populated `External Dependencies` block with `system`, `contract`, and `verification`. Missing block → add it (this is also what gates the Reality Auditor).

6. **Verifier test on each Correctness criterion.** Reread each Correctness criterion as if you have no context. If you can't translate it into "run X, expect Y" in under 10 seconds, rewrite it with an observable outcome, concrete condition, and binary result.

After checks 1–6 pass, also verify cross-file consistency: every `id` in `features.json` appears in the pre-registration documents; every `assertionIds` value exists as a `### <id>` heading in `validation-contract.md`; `Heuristic ceiling` is present on line 2 of `protocol.md`.

If the plan has >10 tasks or any HIGH criticality task, consider one additional escalation: dispatch a fresh reviewer via the Task tool with the spec and all four artifacts, asking them to flag only concrete problems from this same checklist. Optional; not required.

## Related Skills

- `rnd-framework:rnd-scheduling` — For detailed wave scheduling
- `rnd-framework:rnd-scaling` — For choosing pipeline scale
- `rnd-framework:rnd-orchestration` — For pipeline overview
- `rnd-framework:rnd-data-science` — When a task involves analytical or numerical work
