---
name: rnd-decomposition
description: "Use when breaking a complex task into sub-tasks with pre-registration documents — structured hierarchical decomposition, dependency analysis, and testable success criteria"
---

# R&D Decomposition

## Overview

Decompose tasks into structured sub-task trees using hierarchical decomposition. Every sub-task gets a pre-registration document with testable success criteria BEFORE any code is written.

**Core principle:** If you can't write testable success criteria, the task isn't understood well enough to build.

## When to Use

- Starting any non-trivial feature or refactor
- Planning phase of `/rnd-framework:start` or `/rnd-framework:plan`
- When a task has multiple moving parts
- When success criteria are unclear

## The Iron Law

```
NO CODING WITHOUT PRE-REGISTRATION
```

Every task must have testable success criteria declared before implementation begins. This prevents:
- Scope creep during implementation
- Subjective "it looks right" verification
- Builder-Verifier misalignment on what "done" means

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

## Pre-Registration Document

Every task MUST have this before coding:

```
Task ID: T<number>
Intent: [One sentence — what this accomplishes and why]
Approach: [Brief planned implementation strategy]
Expected outputs: [List of files/functions/artifacts to produce]
Success criteria:
  - [ ] [Specific, testable condition 1]
  - [ ] [Specific, testable condition 2]
Verification level: unit | integration | system
Dependencies: [Task IDs this depends on]
Local expert: [optional — name of project-local agent/skill to invoke, e.g., security-reviewer]
External dependencies:
  - system: [DB | API | file | env | service]
    contract: [What is assumed about this system — schema, response shape, format, presence]
    verification: [How this will be confirmed — e.g., Read actual schema, query endpoint, inspect file sample]
```

### Good vs Bad Success Criteria

**Good (testable):**
- "Returns 401 for expired tokens"
- "Processes 1000 records in under 2 seconds"
- "Creates a file at `~/.config/app/settings.json` on first run"
- "Calling `validate(null)` throws `ValidationError`"

**Bad (vague):**
- "Works correctly"
- "Handles errors gracefully"
- "Is performant"
- "Code is clean and well-structured"

## Dependency Analysis

After decomposition, build a dependency matrix:

1. For each task, list what it depends on
2. Identify tasks with zero dependencies -> Wave 1
3. Tasks depending only on Wave 1 -> Wave 2
4. Continue until all tasks are scheduled
5. Flag parallel opportunities within each wave

## Output

> **Note on RND_DIR:** If not already set in session context, compute it by running `"${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh"`. This outputs the absolute path to the current session's artifact directory (e.g., `~/.claude/.rnd/<dirname>-<hash>/sessions/<YYYYMMDD-HHMMSS-XXXX>/`). Use `-c` flag to create the directory structure.

Save the complete plan to `$RND_DIR/plan.md`:

```markdown
# RND Plan: [Feature Name]

## Task Tree
[Hierarchical list of tasks with IDs]

## Pre-Registration Documents
[One per task]

## Dependency Matrix
[Table showing task dependencies]

## Execution Schedule
[Waves with parallel groupings]

## Iteration Budgets
[Default 3 per task, note any exceptions]
```

## Verification Checklist

Before declaring planning complete:

- [ ] Every task has a complete pre-registration document
- [ ] Every success criterion is testable (a Verifier can check it)
- [ ] No circular dependencies in the dependency matrix
- [ ] Waves are correctly ordered
- [ ] Parallel opportunities within waves are identified
- [ ] Tasks too large (>5 criteria) have been split
- [ ] Uncertain approaches have Phase 0 spike tasks
- [ ] Every task that interacts with an external system (DB, API, file format, env var, service) has an "External dependencies" field listing each dependency with: system type, assumed contract, and explicit verification method

## Related Skills

- `rnd-framework:rnd-scheduling` — For detailed wave scheduling
- `rnd-framework:rnd-scaling` — For choosing pipeline scale
- `rnd-framework:rnd-orchestration` — For pipeline overview
- `rnd-framework:rnd-data-science` — When a task involves analytical or numerical work — use as a standalone specialist replacing the standard Build phase
