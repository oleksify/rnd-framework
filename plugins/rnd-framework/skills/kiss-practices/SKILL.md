---
name: kiss-practices
description: Language-specific KISS (Keep It Simple) rules to prevent over-engineering. Load during Phase 0 discovery — detect project languages and read only the relevant .md files from this skill's directory.
---

# KISS Practices

## General Rules (always apply)

- Don't add features nobody asked for
- Don't add error handling for scenarios that can't happen — trust internal code and framework guarantees
- Don't create abstractions for one-time operations — three similar lines is better than a premature helper
- Don't design for hypothetical future requirements — solve today's problem
- Don't add backwards-compatibility shims — just change the code
- Don't wrap framework calls in service layers unless there's real business logic to encapsulate
- Simple, readable code beats clever, compact code
- Validate at system boundaries (user input, external APIs), not at every internal function

## How to Use

**During Phase 0 (Discovery):**
1. Detect which languages/frameworks are present in the project (by file extensions, config files, or dependencies)
2. Read only the relevant language files from this skill's directory (e.g., `elixir.md`, `javascript.md`)
3. Include the language-specific KISS rules in the discovery context passed to the Planner

**Language detection heuristics:**

| Files present | Load |
|---|---|
| `*.ex`, `*.exs`, `mix.exs` | `elixir.md` |
| `*.js`, `*.ts`, `*.jsx`, `*.tsx`, `*.css`, `*.html` | `javascript.md` |
| `*.svelte`, `svelte.config.*` | `svelte.md` |
| `mix.exs` with `:postgrex` or `:ecto`, or `*.sql` files | `postgresql.md` |
| DuckDB usage, `*.duckdb` files, or analytical/data tasks | `duckdb.md` |

**Overriding:** Projects can ship their own `kiss-practices` skill in `.claude/skills/kiss-practices/SKILL.md` to override these defaults with project-specific rules.
