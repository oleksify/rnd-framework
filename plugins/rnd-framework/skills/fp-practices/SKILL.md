---
name: fp-practices
description: "Use alongside KISS practices to guide agents toward functional programming patterns — pure functions, data transformations, composition, command-query separation, and immutability"
effort: low
---

# Functional Programming Practices

## Overview

Concrete rules for writing code in a functional style. These complement KISS practices — KISS prevents over-engineering, FP practices guide _how_ to structure the code that remains.

**Core principle:** Separate what you compute from what you do. Pure logic in, effects out.

## When to Use

- Load during Phase 0 alongside KISS practices
- Loaded during the build phase for all builds
- Apply to any language — these are structural principles, not syntax rules

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

## When to Break These Rules

These rules have legitimate exceptions:

- **Performance-critical loops** — mutation in a tight loop is acceptable when measured profiling shows the functional version is too slow
- **Language idioms** — if the language strongly favors imperative style (Go, C), adapt the principles to the idiom rather than fighting it
- **Framework constraints** — React hooks, ORM callbacks, and similar framework patterns may require mutation or mixed command-query; follow the framework's conventions
- **Startup/initialization code** — building up configuration objects during app boot is naturally imperative; don't force it into a pipeline
