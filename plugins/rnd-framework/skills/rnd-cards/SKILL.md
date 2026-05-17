---
name: rnd-cards
description: "Use when authoring flash cards, understanding the retrieval contract, or wiring card injection into orchestrator prompts — covers card format, scoring, injection, and tag taxonomy"
user-invocable: false
effort: low
---

# R&D Flash Cards

Reference material for the card priming system: authoring format, retrieval CLI, injection wiring, and tag taxonomy.

## Card authoring format

Cards live under `plugins/rnd-framework/cards/<role>/<language>/CARD-<ID>.md`.

Roles: `builder`, `verifier`, `cleanup`, `reality-auditor`, `planner`.
Languages: `python`, `typescript`, `generic` (for prose-only cards with no code examples).

Each card file begins with a YAML frontmatter block followed by a body:

```
---
id: <CARD-ID>                          # e.g. B1 (role-prefix + local number); see naming convention below
role: <role>                           # matches the directory role
language: <language>                   # matches the directory language
tags: [tag1, tag2]                     # flow-style list; values from the taxonomy below
applicable_task_types: [new-feature, bugfix, refactor, docs, config, infra]
scope: <one sentence — what pattern this card teaches>
specializes: [P-TOPIC-01]             # optional — flow-style array of canon principle IDs this card refines
---

**Good:**

<code or prose showing the preferred pattern>

**Worse:**

<code or prose showing the anti-pattern>

**Why good is better:** <explanation — 2-4 sentences>
```

Six frontmatter fields are required (`id`, `role`, `language`, `tags`, `applicable_task_types`, `scope`). The seventh field, `specializes:`, is optional. Canon cards omit it; specialization cards include it.

`specializes:` accepts a flow-style array of canon principle card IDs (e.g., `[P-IMPOSSIBLE-01]` or `[P-EFFECTS-EDGE-01, B7]`). `card-retrieve.sh` currently ignores this field at retrieval time — v2 lands the data, v3 will light up retrieval behavior.

When a card carries `specializes:`, its body should mention the parent principle in the first sentence so the linkage is visible without tooling (e.g., "specializes the impossible-states principle by…").

Tags must use flow-style (`[a, b, c]`), not block-style (`- a`).

**Card naming convention:** Canon principle cards use the pattern `P-<TOPIC>-<NN>` (e.g., `P-IMPOSSIBLE-01`, `P-EFFECTS-EDGE-01`). Role-specific cards use a role prefix and a local number: `B<N>` (builder), `V<N>` (verifier), `D<N>` (cleanup), `R<N>` (reality-auditor), `P<N>` (planner). Library-specific cards use a lib prefix (e.g., `PHX1`, `ECT2`). The `id:` frontmatter field omits the `CARD-` file prefix — `id: B1`, not `id: CARD-B1`. IDs are globally unique across all roles and languages.

## Agent-optimized style

Cards are read by agents inside a token-constrained context window, not by humans in a documentation browser. Write accordingly:

- **≤40 lines** per card body (soft budget). One sharp example is better than two diluted ones.
- Use **inline bold labels** — `**Good:**`, `**Worse:**`, `**Why good is better:**` — not Markdown headings. This keeps the body scannable without vertical whitespace overhead.
- No warm-up prose. Open with the example or the rule, not a preamble.
- Rationale is 2-4 sentences. State the mechanism, not just the conclusion.

## Retrieval contract

The retrieval helper is at `plugins/rnd-framework/lib/card-retrieve.sh`.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/lib/card-retrieve.sh" \
    --role=<builder|verifier|cleanup|reality-auditor|planner> \
    --task-type=<refactor|new-feature|bugfix|docs|config|infra> \
    [--tags=tag1,tag2,...] \
    [--max=N]            # default: ${RND_CARDS_MAX_PER_SPAWN:-3}
```

Output: one card file path per line, sorted by score DESC then card id ASC. Exits 0 even when no cards match (prints nothing in that case).

Scoring per card:

- Role filter (hard): cards for a different role are excluded entirely.
- +1 if the query `task-type` appears in the card's `applicable_task_types`.
- +N for N tags that overlap between `--tags` and the card's `tags` list.

Ties are broken lexically by card id ASC, producing deterministic output across identical calls.

When `--tags` is absent, only role + task-type filtering applies. The orchestrator derives tags from the pre-registration's `Card tags:` field when present, or falls back to role + task-type filtering alone when absent.

For the Planner spawn, `task-type` is not yet known — pass `--task-type=infra` (the default) and rely on role filtering.

## Injection convention

Card injection is orchestrator-level. The five card-receiving agent spawns are: Planner, Builder, Reality-auditor, Verifier, and Cleanup. The five agent files themselves are never modified.

Before each spawn:

1. Run retrieval for the agent's role, task-type, and Card tags from the pre-registration.
2. Read each returned card file.
3. If any cards were returned, prepend the following block to the agent's task spec, immediately before `Task: T<id>`:

```
# Reference examples for tasks like this one

<concatenated card content, one card after another>

```

4. When retrieval returns empty, omit the header entirely — zero overhead when no cards match.
5. After the spawn, emit a `card_injection` audit event via `lib/audit-event.sh` with the tool field set to `<role>:<comma-separated card ids>` (e.g., `builder:CARD-B1,CARD-B3`).

Verifier and Cleanup spawns operate at wave scope — their role is fixed (`verifier` / `cleanup`); `task-type` is inferred from the wave's pre-registrations.

## How tags get chosen

The Planner derives `Card tags:` from the task's Intent and Approach fields. Pick 0-3 tags per task that match the predominant theme. An empty list (`[]`) is acceptable — it signals "use role + task-type filtering only."

**Tag taxonomy v1:**

| Tag | When to use |
|-----|-------------|
| `error-handling` | Task involves exception handling, error propagation, or failure paths |
| `defensive-programming` | Task adds guards, assertions, or invariant checks |
| `abstraction` | Task introduces new abstractions or layers |
| `premature-abstraction` | Task may be over-abstracting a one-off operation |
| `naming` | Task involves renaming identifiers, modules, or concepts |
| `control-flow` | Task restructures branching or loop logic |
| `early-return` | Task benefits from guard-clause or early-exit patterns |
| `configuration` | Task reads or writes config files, env vars, or flags |
| `critique-evidence` | Verifier task: requires citing concrete evidence, not opinions |
| `fail-case` | Verifier task: requires articulating the strongest case for failure |
| `dead-code` | Cleanup task: removing unused functions, imports, or branches |
| `comments` | Task involves inline comments, docstrings, or rationale prose |
| `wrappers` | Task adds thin wrapper functions or adapter layers |
| `anomaly` | Reality-audit task: spotting discrepancies between claim and evidence |
| `inconsistency` | Reality-audit task: cross-checking references for contradictions |
| `cross-check` | Reality-audit task: verifying a claim against an independent source |
| `skepticism` | Reality-audit task: approaching declared facts with doubt |
| `tedium-delegation` | Planner task: identifying repetitive sub-work to hand off |
| `tooling` | Task involves CLI tools, scripts, or automation |
| `spec-shape` | Planner task: structuring a pre-registration or validation contract |
| `scope` | Task has risk of scope creep or unclear boundaries |
| `decomposition` | Task requires splitting into sub-tasks |
| `verifiability` | Success criteria need observable, binary conditions |
| `validation` | Task adds input validation or contract checking |
| `boundaries` | Task enforces or documents system boundaries |
