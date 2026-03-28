---
name: rnd-design
description: "Use when exploring architectural alternatives before planning — generates 2-3 design options with trade-off evaluation, produces a design-spec.md artifact, and gates on explicit user approval before planning proceeds"
user-invocable: false
context: fork
effort: medium
---

# R&D Design Exploration

## Overview

Explore architectural alternatives and produce a design spec before committing to a plan. The goal is to surface real trade-offs between approaches so the user can make an informed architectural decision — not to find the "right" answer on their behalf.

**Core principle:** An architectural decision made without evaluating alternatives is a guess. Design exploration converts guesses into decisions backed by evidence.

**Skill type:** Rigid — the approval gate and iteration cap are non-negotiable. Do not skip alternatives, do not collapse to a single approach, do not proceed to planning without explicit user approval.

## When to Use

- Large tasks (multi-day, multi-feature) where the architectural approach is not obvious
- When the user description leaves the implementation strategy open
- When there are competing approaches with meaningfully different trade-offs (e.g., event-driven vs request-response, monolith vs microservices, SQL vs NoSQL)
- When the orchestrator's scaling rules call for a design review gate (see `rnd-framework:rnd-orchestration`)
- After Discovery/requirements gathering and before Decomposition/planning

**When NOT to use:**

- Small or well-defined tasks where the approach is already specified
- `/rnd-framework:rnd-quick` mode — skip design phase entirely in quick mode
- When the user has already committed to a specific approach ("implement it using X")
- When the task is a refactor with clear scope and no architectural ambiguity

## The Iron Laws

```
1. ALWAYS generate 2-3 alternatives — never a single approach presented as the only option
2. ALWAYS evaluate trade-offs honestly — include weaknesses of the recommended approach
3. NEVER proceed to planning without explicit user approval via AskUserQuestion
4. MAX 3 review iterations — if unresolved after 3 rounds, escalate to orchestrator
5. SAVE the approved spec to $RND_DIR/design-spec.md before planning begins
```

## Process

### 1. Read the Requirements

Read all available requirements: user description, discovery output, existing codebase constraints, and any upstream context. Identify:
- The core problem being solved
- Key constraints (performance, compatibility, team skill, timeline)
- Integration points with existing systems
- Non-functional requirements (scalability, maintainability, security)

### 2. Generate 2-3 Alternatives

For each alternative, define:
- **Name:** Short, memorable identifier (e.g., "Event-Driven Pipeline", "Synchronous REST", "Hybrid Approach")
- **Summary:** One sentence describing the approach
- **How it works:** 3-5 bullet points on implementation mechanics
- **Strengths:** What this approach does particularly well
- **Weaknesses:** What this approach does poorly or makes harder
- **Effort estimate:** Rough complexity relative to the other options
- **Risk level:** LOW / MEDIUM / HIGH with a one-line reason

Guidelines for generating alternatives:
- Alternatives must be meaningfully different — not surface variations of the same approach
- At least one alternative should be a simpler/lighter approach, even if not optimal
- Do not stack-rank alternatives before presenting them to the user
- Cover the space of real trade-offs: performance vs simplicity, flexibility vs predictability, up-front cost vs ongoing cost

### 3. Recommend One Alternative

After presenting all alternatives, identify your recommended approach and explain:
- **Why recommended:** Specific reasons tied to the stated constraints
- **Key assumptions:** What must be true for this recommendation to hold
- **What would change the recommendation:** Conditions under which a different alternative becomes better

The recommendation is advice, not a mandate. The user decides.

### 4. Produce the Design Spec Draft

Format the spec as shown in the "Design-Spec.md Artifact Format" section below. Save the draft to `$RND_DIR/design-spec.md`.

### 5. Present for Approval

**Output the full design summary as regular text first** — include the alternatives comparison table, the recommendation with all reasoning, key assumptions, and conditions that would change it. Do NOT abbreviate or truncate the recommendation. The user needs to read the full rationale before choosing.

**Then** use `AskUserQuestion`/`AskUser` with short option labels for the decision. Do NOT put the recommendation text inside option descriptions — keep descriptions to one short sentence each.

```
Options:
  1. (Recommended) Approve — proceed to planning with recommended approach
  2. Approve with modifications — [ask what to change]
  3. Choose a different alternative — [ask which one]
  4. Request another alternative — [ask what direction]
  5. Reject all — [ask for different framing]
```

### 6. Iterate on Feedback

If the user requests changes, update the spec, save it, and re-present using `AskUserQuestion`/`AskUser`. Track the iteration count.

**Maximum 3 review iterations.** If the user has not approved after 3 rounds, stop and report to the orchestrator:

```
BLOCKED on design approval after 3 iterations. User feedback: [summary].
Awaiting guidance on how to proceed.
```

### 7. Finalize and Gate

Once the user approves:
1. Update `$RND_DIR/design-spec.md` with the approved approach (mark it `STATUS: APPROVED`)
2. Record the approval in the session log
3. Pass the approved spec to the Planner as context for decomposition

The Planner MUST NOT begin pre-registration until `$RND_DIR/design-spec.md` exists with `STATUS: APPROVED`.

## Design-Spec.md Artifact Format

```markdown
# Design Spec: [Feature/Task Name]

STATUS: DRAFT | APPROVED
Iteration: [n of 3]
Approved approach: [name, filled in after approval]

---

## Problem Statement

[1-2 sentences: what problem this solves and for whom]

## Constraints

- [Constraint 1 — e.g., must integrate with existing auth service]
- [Constraint 2 — e.g., response time < 200ms at p99]
- [Constraint 3 — e.g., team has no Go experience]

## Alternatives

### Alternative 1: [Name]

**Summary:** [One sentence]

**How it works:**
- [Bullet 1]
- [Bullet 2]
- [Bullet 3]

**Strengths:**
- [Strength 1]
- [Strength 2]

**Weaknesses:**
- [Weakness 1]
- [Weakness 2]

**Effort estimate:** [LOW / MEDIUM / HIGH relative to other options]
**Risk level:** [LOW / MEDIUM / HIGH — reason]

---

### Alternative 2: [Name]

[Same structure as Alternative 1]

---

### Alternative 3: [Name] (optional)

[Same structure as Alternative 1]

---

## Recommendation

**Recommended approach:** [Name]

**Why:** [Specific reasons tied to stated constraints]

**Key assumptions:**
- [Assumption 1]
- [Assumption 2]

**What would change this recommendation:**
- [Condition under which a different alternative becomes better]

## Revision History

| Iteration | Change | User Feedback |
|-----------|--------|---------------|
| 1 | Initial draft | [summary] |
| 2 | [what changed] | [summary] |
```

## Review Iteration Protocol

Each review round must:
1. Incorporate all user feedback — do not partially apply changes
2. Increment the iteration counter in the spec header
3. Update the revision history table
4. Re-save `$RND_DIR/design-spec.md`
5. Re-present via `AskUserQuestion`/`AskUser` with the same structured options

**Do not** present revisions as inline text. Always use `AskUserQuestion`/`AskUser` so the pipeline tracks approval state, not just text acknowledgment.

**Iteration cap is 3.** After 3 rounds without approval, the orchestrator must decide whether to escalate, restart design with different framing, or bypass design phase with explicit user sign-off.

## Integration with the Pipeline

```
Discovery → Design Exploration → Decomposition/Planning → Build → Verify → Integrate
              (this skill)        (rnd-decomposition)
```

The design spec feeds into decomposition as architectural context. The Planner should:
- Reference the approved approach when writing pre-registrations
- Use the constraints section to set non-functional success criteria
- Use the alternatives section to document rejected paths (so Builders don't re-explore them)

In `/rnd-framework:rnd-quick` mode, this phase is skipped. In `/rnd-framework:rnd-start`, this phase is inserted only when the orchestrator's scaling rules call for it.

## Verification Checklist

Before declaring design phase complete:

- [ ] Spec contains 2-3 meaningfully different alternatives (not surface variations)
- [ ] Each alternative has strengths, weaknesses, effort estimate, and risk level
- [ ] Recommendation includes key assumptions and conditions that would change it
- [ ] User approved via `AskUserQuestion`/`AskUser` (not plain text acknowledgment)
- [ ] `$RND_DIR/design-spec.md` exists and contains `STATUS: APPROVED`
- [ ] Iteration count did not exceed 3
- [ ] Planner has received the spec as context before beginning pre-registration

## Related Skills

- `rnd-framework:rnd-decomposition` — Receives the approved design spec; writes pre-registrations aligned to the chosen approach
- `rnd-framework:rnd-orchestration` — Pipeline overview; scaling rules that determine when design exploration is required
- `rnd-framework:rnd-scaling` — Determines whether design phase applies based on task size and complexity
