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

## Pre-Registration Document

```
Task ID: T<number>
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
Dependencies: [Task IDs this depends on]
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
fulfills: [VAL-AREA-NNN, ...]
Card tags: [tag1, tag2]  # optional, v1 — orchestrator falls back to role + task_type if absent
```

The `fulfills` field creates bidirectional traceability between tasks and Validation Contract assertions.

The `Card tags:` field is optional in v1. When absent, the orchestrator filters cards by role and task_type only. When present, tags narrow retrieval to cards whose `tags` overlap with the query — pick 0-3 tags from the taxonomy in `rnd-framework:rnd-cards` that match the task's predominant theme.

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

Compute `$RND_DIR` via `"${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh"` (use `-c` to create). Save to `$RND_DIR/plan.md` with these sections:

- **Task Tree** — hierarchical list with task IDs
- **Environment Setup** — runtime, package manager, dependencies, install commands
- **Infrastructure** — external services (URL + auth), off-limits items
- **Testing Strategy** — test framework, baseline count, exact run commands for unit/integration/live tests, user testing instructions
- **Worker Guidelines** — `USE`/`OFF-LIMITS` boundaries; coding conventions from CLAUDE.md/linters; architectural patterns; design decisions
- **Validation Contract** — numbered VAL-AREA-NNN assertions (see format below)
- **Pre-Registration Documents** — one per task
- **Dependency Matrix** — task dependency table
- **Execution Schedule** — wave assignments with parallel opportunities
- **Iteration Budgets** — per-task budgets based on criticality

### Validation Contract Format

```markdown
### Area: [Functional Domain]

#### VAL-AREA-NNN: [Assertion title]
[One-sentence description of what must be true]
Tool: [shell | grep | glob | read | code review]
Evidence: [Exact command + expected output pattern]
```

ID format: `VAL-` + area abbreviation (2-6 uppercase chars) + `-` + 3-digit number (e.g., `VAL-AUTH-001`). Evidence must be concrete: not "tests pass" but `npx vitest run exits 0, reports >= 50 passed`. Cross-cutting assertions go under `### Area: Cross-Area`. Every assertion must be fulfilled by at least one task; every task should fulfill at least one assertion.

## Verification Checklist

- [ ] Every task has a complete pre-registration document
- [ ] Every success criterion is testable and tagged Correctness or Quality
- [ ] No circular dependencies; waves correctly ordered; parallel opportunities identified
- [ ] Tasks >5 criteria have been split; uncertain approaches have Phase 0 spikes
- [ ] Every task touching an external system has an `External Dependencies` field with system type, assumed contract, and verification method
- [ ] Environment Setup, Infrastructure, and Testing Strategy sections populated
- [ ] Worker Guidelines contains boundaries, conventions, and architecture notes
- [ ] Validation Contract has VAL-AREA-NNN assertions with Tool and Evidence for every Correctness criterion
- [ ] Every task has a `fulfills` field; every VAL assertion is fulfilled by at least one task

## Plan Self-Review

After writing all sections of plan.md, reread it with fresh eyes. This is a checklist you run yourself before notifying the orchestrator — not a subagent dispatch. The Verifier cannot save you from plan-level mistakes; they cascade through every downstream phase.

Run these six checks against the finished plan.md. If any fails, fix inline and re-check.

1. **Spec coverage.** For each explicit user requirement or discovery-context constraint, point to the task(s) covering it. Gaps → add a task or explicitly note it as out-of-scope in Worker Guidelines.

2. **Placeholder scan.** Grep the plan for `TODO`, `TBD`, `???`, `XXX`, `[...]`, `handle appropriately`, `works correctly`, `as needed`. Any hit → replace with concrete content or remove.

3. **VAL traceability.** Every `VAL-AREA-NNN` is named in at least one task's `fulfills` field, and every task has a non-empty `fulfills`. A VAL with no fulfiller, or a task fulfilling nothing, means the Validation Contract and Pre-Registration drifted apart — fix whichever side is wrong.

4. **Identifier consistency.** For each function name, file path, type name, or env var that appears in multiple tasks, confirm the spelling matches across mentions. A function named `clearLayers` in T3 and `clearFullLayers` in T7 is the most common cascading plan error.

5. **External-dependency completeness.** Any task whose Intent, Approach, or Expected outputs references a DB, API, file, env var, or external service MUST have a populated `External Dependencies` block with `system`, `contract`, and `verification`. Missing block → add it (this is also what gates the Reality Auditor).

6. **Verifier test on each Correctness criterion.** Reread each Correctness criterion as if you have no context. If you can't translate it into "run X, expect Y" in under 10 seconds, rewrite it with an observable outcome, concrete condition, and binary result.

If the plan has >10 tasks or any HIGH criticality task, consider one additional escalation: dispatch a fresh reviewer via the Task tool with the spec and plan.md, asking them to flag only concrete problems from this same checklist. Optional; not required.

## Related Skills

- `rnd-framework:rnd-scheduling` — For detailed wave scheduling
- `rnd-framework:rnd-scaling` — For choosing pipeline scale
- `rnd-framework:rnd-orchestration` — For pipeline overview
- `rnd-framework:rnd-data-science` — When a task involves analytical or numerical work
