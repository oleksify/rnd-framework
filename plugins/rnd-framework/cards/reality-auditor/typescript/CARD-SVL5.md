---
id: SVL5
role: reality-auditor
language: typescript
tags: [anomaly, skepticism, validation]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Pre-rune patterns ($:, export let) are valid Svelte 4 syntax but are the wrong model for Svelte 5 components.
specializes: [P-IMPOSSIBLE-01]
---

**Good audit output:**
> The component declares `export let count = 0`. In Svelte 5, props are declared with `$props()` — `export let` still compiles under a compatibility shim, but it does not participate in the runes reactivity model. Any `$derived` or `$effect` in the same component that depends on `count` may not update correctly because the value is not tracked as a rune. Flag: migrate `export let count` → `let { count = 0 } = $props()`.

**Worse audit output:**
> The component uses `export let` for its props. This is valid Svelte syntax.

**Why good is better:** Specializes the impossible-states principle for the Svelte 4→5 migration boundary. Svelte 5 introduces a dual-mode: legacy `export let` and `$:` reactive declarations still compile (for backward compat) but they operate in a separate reactivity system from runes. Mixing the two in the same component produces subtle update ordering bugs that are hard to reproduce. An auditor must flag any `export let` or `$:` in a Svelte 5 codebase as a migration hazard — not just as "valid but old syntax."
