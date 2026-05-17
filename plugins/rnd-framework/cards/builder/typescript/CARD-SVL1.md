---
id: SVL1
role: builder
language: typescript
tags: [boundaries, validation, control-flow]
applicable_task_types: [new-feature, bugfix, refactor]
scope: $state is the reactive primitive in Svelte 5; never reassign the object returned by $props().
specializes: [P-PURE-RENDER-01]
---

**Good:**
```svelte
<script lang="ts">
  let { initialCount = 0 } = $props<{ initialCount?: number }>()

  let count = $state(initialCount)

  const increment = () => {
    count++
  }
</script>

<button onclick={increment}>{count}</button>
```

**Worse:**
```svelte
<script lang="ts">
  let props = $props<{ initialCount?: number }>()
  // mutating the props object directly — Svelte 5 disallows this
  props.initialCount = 10
</script>
```

**Why good is better:** Specializes the pure-render principle for Svelte 5 runes. `$props()` returns a readonly proxy; reassigning its properties either throws in dev or silently fails in prod, because props flow one way — parent to child. Local mutable state belongs in `$state()`, which Svelte tracks for reactivity. Destructure `$props()` once at the top and own your mutations in `$state` variables.
