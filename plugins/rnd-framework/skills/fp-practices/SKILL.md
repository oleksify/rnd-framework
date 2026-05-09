---
name: fp-practices
description: "Use alongside KISS practices to guide agents toward functional programming patterns — pure functions, data transformations, composition, command-query separation, and immutability"
effort: low
---

# Functional Programming Practices

## Overview

Concrete rules for writing code in a functional style. These complement KISS practices — KISS prevents over-engineering, FP practices guide _how_ to structure the code that remains.

**Core principle:** Separate what you compute from what you do. Pure logic in, effects out.

## How to Use

**During Phase 0 (Discovery):**
1. Detect which languages/frameworks are present in the project (by file extensions, config files, or dependencies)
2. Read only the relevant language files (e.g., `${CLAUDE_SKILL_DIR}/elixir.md`, `${CLAUDE_SKILL_DIR}/javascript.md`)
3. Include the language-specific FP rules in the discovery context passed to the Planner

**Language detection heuristics:**

| Files present | Load |
|---|---|
| `*.sh`, `*.bash`, `Makefile` | `${CLAUDE_SKILL_DIR}/bash.md` |
| `*.ex`, `*.exs`, `mix.exs` | `${CLAUDE_SKILL_DIR}/elixir.md` |
| `*.js`, `*.ts`, `*.jsx`, `*.tsx`, `*.css`, `*.html` | `${CLAUDE_SKILL_DIR}/javascript.md` |
| `*.py`, `pyproject.toml`, `requirements.txt` | `${CLAUDE_SKILL_DIR}/python.md` |
| `*.lean`, `lakefile.lean` | `${CLAUDE_SKILL_DIR}/lean.md` |
| `*.svelte`, `svelte.config.*` | `${CLAUDE_SKILL_DIR}/svelte.md` |
| `*.kk`, `koka.json` | `${CLAUDE_SKILL_DIR}/koka.md` |
| `mix.exs` with `:postgrex` or `:ecto`, or `*.sql` files | `${CLAUDE_SKILL_DIR}/postgresql.md` |
| DuckDB usage, `*.duckdb` files, or analytical/data tasks | `${CLAUDE_SKILL_DIR}/duckdb.md` |

**Overriding:** Projects can ship their own `fp-practices` skill in `.claude/skills/fp-practices/SKILL.md` to override these defaults with project-specific rules.

## The Rules

### 1. Pure Functions First

A pure function takes inputs and returns outputs. It does not read globals, write files, call APIs, or mutate arguments.

**Do:**
- Write the computation as a pure function that takes data and returns data
- Push side effects (I/O, database, network) to the caller or the edges of the system
- Pass dependencies as arguments, not through closures over mutable state

**Don't:**
- Mix computation and I/O in the same function — a function that calculates a price AND saves it to the database does two things
- Read environment variables or config inside business logic — pass the values in
- Use `Date.now()`, `Math.random()`, or other non-deterministic calls inside pure logic — inject them as arguments

### 2. Data Transformations Over Mutation

Express logic as a pipeline of transformations on data, not a sequence of mutations on state.

**Do:**
- Use map, filter, reduce (or language equivalents) to transform collections
- Return new data structures instead of modifying existing ones
- Chain transformations: `input |> validate |> transform |> format`

**Don't:**
- Build up results with `let result = []; for (...) { result.push(...) }` when `items.map(...)` works
- Mutate function arguments — if you need to change shape, return a new object
- Use index-based loops when the intent is "transform each item" — map expresses intent better

### 3. Composition Over Inheritance

Build behavior by combining small, focused functions — not by extending class hierarchies.

**Do:**
- Write small functions that do one thing and compose them: `const process = compose(validate, transform, save)`
- Use higher-order functions (functions that take or return functions) for shared behavior
- Prefer data + functions over objects + methods — a plain object with helper functions is often simpler than a class

**Don't:**
- Create class hierarchies for code reuse — use composition instead
- Add `extends` or `super` when a function parameter achieves the same thing
- Build "base classes" that child classes override — pass behavior as functions

### 4. Command-Query Separation

A function either returns data (query) or causes an effect (command). Never both.

**Do:**
- Functions that compute or look up data should return the result and have no side effects
- Functions that perform effects (save, send, delete) should not return computed data — return only success/failure status if needed
- Separate "decide what to do" (pure) from "do it" (effectful)

**Don't:**
- Write `getOrCreate` functions that both query and mutate — split into `find` + `create`
- Return a value AND log/save/send as a side effect in the same function
- Mix validation (pure) with rejection actions (effectful) — validate first, act on the result

### 5. Immutability by Default

Declare bindings as immutable unless mutation is specifically needed.

**Do:**
- Use `const` (JS/TS), `val` (Kotlin), `let` (Swift/Rust), or the immutable equivalent in your language
- Use spread/destructuring to create modified copies: `{...user, name: newName}`
- Prefer `readonly` types in TypeScript for function parameters

**Don't:**
- Use `let`/`var` when the value is assigned once and never changed
- Mutate arrays in place (`push`, `splice`) when `map`/`filter`/`concat` works
- Reassign variables to track state through a function — restructure as a pipeline instead

### 6. Polish: Consistency and Organization

**Do:**
- Use one naming convention for pure functions across modules: either `verb_noun` or `noun_verb` as the language dictates — don't mix `computeTotal`/`total_compute` styles within the same codebase
- Extract helpers shared by two or more call sites to a single canonical location — don't let the same pure transformation live in multiple modules with slight variations
- Group pure functions by the domain they operate on, not alphabetically — `user_*` functions together, `order_*` together; alphabetical grouping hides cohesion

**Don't:**
- Duplicate a pure transformation across modules to avoid adding a shared helper file — copy-pasted logic drifts and causes silent inconsistencies at the wave level
- Mix domain-level functions and low-level utility functions in the same module without clear separation — readers should be able to find all business logic in one place and all plumbing in another

## When to Break These Rules

These rules have legitimate exceptions:

- **Performance-critical loops** — mutation in a tight loop is acceptable when measured profiling shows the functional version is too slow
- **Language idioms** — if the language strongly favors imperative style (Go, C), adapt the principles to the idiom rather than fighting it
- **Framework constraints** — React hooks, ORM callbacks, and similar framework patterns may require mutation or mixed command-query; follow the framework's conventions
- **Startup/initialization code** — building up configuration objects during app boot is naturally imperative; don't force it into a pipeline
