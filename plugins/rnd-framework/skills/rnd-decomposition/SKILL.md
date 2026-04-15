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
fulfills: [VAL-AREA-NNN, ...]
```

The `fulfills` field creates bidirectional traceability between tasks and Validation Contract assertions.

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

## Related Skills

- `rnd-framework:rnd-scheduling` — For detailed wave scheduling
- `rnd-framework:rnd-scaling` — For choosing pipeline scale
- `rnd-framework:rnd-orchestration` — For pipeline overview
- `rnd-framework:rnd-data-science` — When a task involves analytical or numerical work
