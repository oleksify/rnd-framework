---
name: rnd-local-experts
description: "Use when discovering and surfacing project-local agents and skills from the target project's .claude/ directory — scan, read frontmatter, and present a structured summary for the Planner to reference in pre-registrations"
user-invocable: false
context: fork
effort: low
---

# R&D Local Expert Discovery

## Overview

Some projects ship their own Claude Code agents and skills in `.claude/agents/` and `.claude/skills/`. These "local experts" are specialists tailored to the project's domain — a security reviewer, a domain-specific formatter, a testing harness builder. Surfacing them during planning allows pre-registration documents to route appropriate tasks to the right expert instead of a generic build phase.

**Core principle:** Local experts are optional project-level assets. Their presence enriches the pipeline; their absence never blocks it.

## When to Use

- Phase 0 (Discovery) of `/rnd-framework:rnd-start` — before the Planner runs
- Anytime you need to know what project-specific agents or skills are available
- When the Planner is assembling pre-registration documents and wants to delegate to a local specialist

## Discovery Process

### Step 1 — Scan for local agents

Use Glob to enumerate agent files in the target project:

```
.claude/agents/*.md
```

Each `.md` file in that directory is a potential local agent. Read the YAML frontmatter of each file to extract:
- `name` — the agent identifier
- `description` — what the agent does and when to use it

### Step 2 — Scan for local skills

Use Glob to enumerate skill files in the target project:

```
.claude/skills/*/SKILL.md
```

Each `SKILL.md` file is a potential local skill. Read the YAML frontmatter of each file to extract:
- `name` — the skill identifier
- `description` — what the skill covers and when to invoke it

### Step 3 — Read YAML frontmatter

For every discovered file, read the `name` and `description` fields from the YAML frontmatter block between `---` delimiters. Ignore files that lack valid frontmatter — they are not conformant local experts and should be skipped silently.

### Step 4 — Produce a structured summary

Assemble a structured summary of all discovered experts. If nothing is found, the summary is empty and no further action is required.

**Example summary format:**

```
Local Experts Discovered:

Agents (.claude/agents/):
  - name: security-reviewer
    description: "Reviews authentication, authorization, and input validation changes for vulnerabilities"
  - name: db-migrator
    description: "Generates and validates database migration scripts for the project's schema conventions"

Skills (.claude/skills/):
  - name: project-testing
    description: "Use when writing tests — covers project-specific test helpers, fixture conventions, and CI integration patterns"
```

If no agents directory exists, omit the "Agents" section. If no skills directory exists, omit the "Skills" section. If both are empty or absent, output:

```
Local Experts Discovered: none
```

## How the Planner References Local Experts

When the Planner receives a discovery context that includes local expert information, it may add an optional `Local expert` field to any pre-registration document where a local expert is relevant:

```
Task ID: T<number>
Intent: [One sentence — what this accomplishes and why]
Approach: [Brief planned implementation strategy]
Expected outputs: [List of files/functions/artifacts to produce]
Success criteria:
  - [ ] [Specific, testable condition 1]
Verification level: inline | unit | system
Dependencies: [Task IDs this depends on]
Local expert: security-reviewer  # optional — name of local agent/skill to invoke
```

The planning phase does NOT invoke local experts itself. It only records the reference so downstream phases (verification, integration) know to invoke the expert when they process that task.

**When to add a Local expert field:**
- A security-review agent is available and the task touches authentication or input handling
- A domain-specific testing skill is available and the task requires test generation
- A local style or lint agent is available and the task involves code structure changes

**When to omit the Local expert field:**
- No relevant local expert exists for the task
- The task is purely structural or administrative (file moves, config updates)
- No local experts were discovered at all

## How Verifier and Integrator Invoke a Local Expert

When a pre-registration document contains a `Local expert` field, the Verifier or Integrator checks whether that expert is available and invokes it as part of their process.

**Verifier flow:**

1. Read the `Local expert` field from the pre-registration.
2. Check whether `.claude/agents/<name>.md` or `.claude/skills/<name>/SKILL.md` exists in the target project.
3. If it exists: invoke the local skill as context for an additional review pass.
4. Incorporate the local expert's findings into the verification report as supplemental evidence.
5. If the local expert is absent: note its absence in the verification report and continue without it — the absence does not constitute a verification failure.

**Integrator flow:**

1. Read the `Local expert` field from each task's pre-registration during the integration phase.
2. If a local expert is referenced and present: invoke it as a final domain check before issuing SHIP/NO-SHIP.
3. If the local expert is absent: proceed without it and note the absence in the integration report.

## Absence Policy

Local experts are always optional. The pipeline must not stall or fail because:
- `.claude/agents/` does not exist in the target project
- `.claude/skills/` does not exist in the target project
- A specific agent or skill named in a pre-registration is no longer present

In all absence cases, the responsible phase (planning, verification, integration) silently continues without the local expert and records the absence in its output artifact.

## Related Skills

- `rnd-framework:rnd-decomposition` — Pre-registration template that includes the optional Local expert field
- `rnd-framework:rnd-orchestration` — Pipeline overview showing where discovery fits
