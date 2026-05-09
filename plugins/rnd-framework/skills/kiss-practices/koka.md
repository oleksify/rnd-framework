# Koka — KISS Rules

## Effects

- Declare effects explicitly in function signatures — don't use polymorphic effect variables when specific effects are known
- Don't mask effects to make types look simpler — visible effects are the point; hiding them defeats Koka's design
- Let implicit handler resolution work — don't create explicit handlers for effects that have obvious default handlers
- Don't nest handlers without clear semantic intent — prefer flat handler stacking

## Data Types

- Use value types (structs) for small immutable data — the compiler eliminates heap allocation automatically
- Don't wrap everything in reference types — let Perceus reference counting manage memory; unnecessary refs increase GC pressure
- Use `type` for algebraic data, `struct` for simple records — don't conflate them

## Performance

- Write naturally functional code — FBIP analysis optimizes many functional patterns to in-place updates
- Structure recursive functions for TRMC (tail recursion modulo cons) — prevents stack overflow on large data
- Don't hand-optimize what the compiler handles — Perceus reuse analysis is better at spotting in-place update opportunities than manual attempts
- Use `var` blocks explicitly when mutable state is needed — don't mix mutation and functional style implicitly

## Common Pitfalls

- Don't assume functional code is slow — FBIP means tree rebalancing and similar algorithms run in-place
- Don't ignore effect types in signatures — they are the primary tool for reasoning about code behavior
- Don't create utility modules for one-off effect handlers — inline simple handlers at the call site

## Polish

- Group functions by the effect they operate under — functions touching the same effect belong together; don't scatter them across the file
- Use one naming convention for effect-producing functions: either `verb-noun` (`read-line`) or `noun-verb` — Koka's standard library favors `verb` or `verb-noun`; follow it within a module
- Comments on effect signatures should explain the observable contract — what callers can expect from the effect, not just what the handler does internally
- Name handler functions to match their effect type — a handler for `console` effect should read as `console-handler`, not `my-handler`
