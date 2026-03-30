---
name: rnd-decomposition
description: "Use when breaking a complex task into sub-tasks with pre-registration documents — structured hierarchical decomposition, dependency analysis, and testable success criteria"
user-invocable: false
effort: medium
---

# R&D Decomposition

## Overview

Decompose tasks into structured sub-task trees using hierarchical decomposition. Every sub-task gets a pre-registration document with testable success criteria BEFORE any code is written.

**Core principle:** If you can't write testable success criteria, the task isn't understood well enough to build.

## When to Use

- Planning phase of `/rnd-framework:rnd-start` or `/rnd-framework:rnd-plan`
- Any non-trivial feature, refactor, or task with multiple moving parts or unclear success criteria

## The Iron Law

```
NO CODING WITHOUT PRE-REGISTRATION
```

Every task must have testable success criteria declared before implementation begins — preventing scope creep, subjective verification, and Builder-Verifier misalignment.

## Hierarchical Decomposition

Break tasks into three levels with paired verification:

```
System Level:  [Feature]  <->  [System Validation]
Module Level:  [Components]  <->  [Integration Tests]
Unit Level:    [Functions]  <->  [Unit Tests]
```

### Process

1. **Start at System level** — What does the feature DO end-to-end?
2. **Identify Modules** — What components are needed?
3. **Break into Units** — What functions/utilities does each module need?
4. **Pair each level with verification** — System validation, integration tests, unit tests

### What "Testable" Means

A criterion is testable if a skeptical Verifier can evaluate it from evidence alone — without asking the Builder what they meant. It must specify:
- An **observable outcome** (return value, output, state change, error thrown)
- **Concrete conditions** (specific inputs, specific thresholds, specific error types)
- A **binary result** (met or not met — no judgment calls)

### Decomposition Heuristics

- **Too big:** If a task has more than 5 success criteria, split it
- **Too small:** If a task is a single function with one criterion, merge it up
- **Too vague:** If criteria require judgment to evaluate ("works correctly", "handles errors", "is performant", "code is clean") — rewrite with observable outcomes or decompose further
- **Uncertain:** If the approach is unclear, add a Phase 0 spike task
- **Unverified external contract:** If a task depends on an external system (DB schema, API response shape, file format, env var, third-party service) whose contract has not been independently verified, add a Phase 0 spike or a dedicated verification step before that task to read/query the actual system and confirm assumptions
- **Local expert available:** If the project has a domain-specific agent or skill (e.g., a `security-reviewer` agent for auth changes, or a `db-migration-expert` skill for schema changes), set the `Local expert` field in the pre-registration so the Builder knows to invoke it during implementation

## Exploration Cache

Before decomposition, the Planner writes structured exploration findings to `$RND_DIR/exploration/` so downstream agents (Builder, Verifier) can reference them instead of re-exploring the same files.

### Output Directory

`$RND_DIR/exploration/`

Create with: `mkdir -p "$RND_DIR/exploration"`

### File Naming

One file per explored area, using descriptive kebab-case names:
- `hooks-architecture.md` — hook system structure and patterns
- `test-patterns.md` — testing conventions and helpers
- `existing-agents.md` — current agent configurations

### File Structure

Each exploration file follows this format:

```markdown
# [Area Name]

## Files Examined
- [file path] — [one-line description of what it contains]

## Key Patterns
- [pattern or convention observed]

## Relevant Dependencies
- [dependency or coupling that builders should know about]

## Notes for Builders
- [anything that would be non-obvious from reading the file alone]
```

Each file contains structured findings about one area of the codebase relevant to the planned tasks.

## Pre-Registration Document

Every task MUST have this before coding:

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
Local expert: [optional — name of project-local agent/skill to invoke, e.g., security-reviewer]
External Dependencies:
  - system: [DB | API | file | env | service]
    contract: [What is assumed about this system — schema, response shape, format, presence]
    verification: [How this will be confirmed — e.g., Read actual schema, query endpoint, inspect file sample]
fulfills: [VAL-AREA-NNN, ...]
```

The `fulfills` field links each task to specific Validation Contract assertions (see Output section). This creates bidirectional traceability: from task to assertions and from assertion to responsible tasks.

### Tiered Criteria: Correctness vs Quality

Every success criterion belongs to exactly one tier:

| Correctness (must-pass) | Quality (should-pass) |
|---|---|
| "Returns 401 for expired tokens" | "Function names follow project naming convention" |
| "Throws ValidationError when input is null" | "Inline comments explain the retry logic" |
| "File exists at the declared output path" | "No magic numbers — constants are named" |
| "All unit tests pass" | "Error messages are user-facing and descriptive" |

**Decision rule:** Ask "does a user or downstream system observe this outcome?" If yes → Correctness. If it only affects maintainability or developer experience → Quality.

Unmet Correctness criteria cause FAIL (blocks progress). Unmet Quality criteria trigger NEEDS ITERATION but do not block integration.

**Good criteria are concrete and observable** — "Returns 401 for expired tokens", "Processes 1000 records in under 2 seconds". **Bad criteria are vague** — "works correctly", "handles errors gracefully", "is performant" — rewrite with specific observable outcomes before using.

## Environment Discovery

Before decomposition, run a structured checklist scan to catalog the project's build environment. Present findings to the user via `AskUserQuestion` for confirmation and gap-filling.

### Checklist

| Area | What to scan | How |
|------|-------------|-----|
| Package manager | package.json, Cargo.toml, mix.exs, go.mod, pyproject.toml | Glob for config files |
| Test framework | vitest, jest, pytest, ExUnit, go test configs | Grep for test runner in configs/scripts |
| CI config | .github/workflows/, .gitlab-ci.yml, Jenkinsfile | Glob for CI files, Read to extract commands |
| External service URLs | https:// references in source code | Grep for URLs in src/ |
| Environment variables | .env.example, .env.template, CI secrets config | Read env templates, Grep for process.env/ENV/os.environ |
| Secrets and off-limits | .gitignore patterns, CI secret names, sensitive file paths | Read .gitignore, infer from CI config |

### Output

Findings feed into three plan.md sections: **Environment Setup**, **Infrastructure**, and **Testing Strategy** (see Output section below).

## Dependency Analysis

After decomposition, build a dependency matrix: list what each task depends on, then assign tasks with zero dependencies to Wave 1, tasks depending only on Wave 1 to Wave 2, and so on. Flag parallel opportunities within each wave.

## Output

Compute `$RND_DIR` via `"${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh"` (use `-c` to create). Save the complete plan to `$RND_DIR/plan.md` with the following sections:

### plan.md Structure

```markdown
# Plan: [Task Title]

## Task Tree
[Hierarchical list with task IDs]

## Environment Setup
[Runtime/language, package manager, dependencies, install commands]
[Detected via Environment Discovery checklist]

## Infrastructure
**External services:**
- [Service name] — [URL] ([auth requirements])
**Off-limits:**
- [Items that must not be modified/exposed]

## Testing Strategy
**Test framework:** [name] ([baseline count] tests)
**Unit tests:** [exact run command]
**Integration tests:** [exact run command, if applicable]
**Live tests:** [exact run command + required env vars, if applicable]
**User testing:** [how an end user would verify the work]

## Worker Guidelines
### Boundaries
- USE: [external service] — [URL] ([auth])
- OFF-LIMITS: [secret/file/service] in [context]
### Coding Conventions
[Project-specific rules extracted from CLAUDE.md, linters, configs]
### Architecture
[Key architectural patterns, module relationships]
### Design Decisions
[Non-obvious choices and their rationale]

## Validation Contract
[Numbered assertions grouped by area — see format below]

## Pre-Registration Documents
[One per task — existing format plus fulfills field]

## Dependency Matrix
[Task dependency table]

## Execution Schedule
[Wave assignments with parallel opportunities]

## Iteration Budgets
[Per-task budgets based on criticality]
```

### Validation Contract Format

The Validation Contract contains numbered, testable assertions grouped by functional area. Each assertion specifies the exact tool and evidence command a Verifier uses to check it.

```markdown
### Area: [Functional Domain]

#### VAL-AREA-NNN: [Assertion title]
[One-sentence description of what must be true]
Tool: [shell | grep | glob | read | code review]
Evidence: [Exact command + expected output pattern]
```

**Assertion ID format:** `VAL-` + area abbreviation (2-6 uppercase chars) + `-` + 3-digit number. Area abbreviations are derived from functional domains (e.g., CI, AUTH, DATA, API, UI, CROSS).

**Evidence must be concrete:** not "tests pass" but `npx vitest run exits 0, reports >= 50 passed`. Not "file exists" but `Glob for src/auth/middleware.ts returns exactly 1 match`.

**Grouping:** Assertions are grouped under `### Area:` headings. Cross-cutting assertions that span multiple tasks go under `### Area: Cross-Area`.

**Traceability:** Every assertion must be fulfilled by at least one task (via the `fulfills` field in pre-registrations). Every task should fulfill at least one assertion. Orphan assertions or unfulfilled tasks indicate a planning gap.

## Verification Checklist

Before declaring planning complete:

- [ ] Every task has a complete pre-registration document
- [ ] Every success criterion is testable (a Verifier can check it)
- [ ] Every success criterion is tagged as Correctness or Quality
- [ ] No circular dependencies in the dependency matrix
- [ ] Waves are correctly ordered
- [ ] Parallel opportunities within waves are identified
- [ ] Tasks too large (>5 criteria) have been split
- [ ] Uncertain approaches have Phase 0 spike tasks
- [ ] Every task that interacts with an external system (DB, API, file format, env var, service) has an "External dependencies" field listing each dependency with: system type, assumed contract, and explicit verification method
- [ ] Environment Setup, Infrastructure, and Testing Strategy sections are populated from Environment Discovery
- [ ] Worker Guidelines section contains boundaries, coding conventions, and architecture notes
- [ ] Validation Contract contains numbered VAL-AREA-NNN assertions with Tool and Evidence for every Correctness criterion
- [ ] Every task has a `fulfills` field linking to at least one VAL assertion
- [ ] Every VAL assertion is fulfilled by at least one task

## Related Skills

- `rnd-framework:rnd-scheduling` — For detailed wave scheduling
- `rnd-framework:rnd-scaling` — For choosing pipeline scale
- `rnd-framework:rnd-orchestration` — For pipeline overview
- `rnd-framework:rnd-data-science` — When a task involves analytical or numerical work — use as a standalone specialist replacing the standard Build phase
