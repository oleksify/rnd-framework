---
id: SVL2
role: builder
language: typescript
tags: [control-flow, abstraction, boundaries]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Use $derived for computed values and $effect for side-effects; never compute values inside $effect.
specializes: [P-EFFECTS-EDGE-01]
---

**Good:**
```svelte
<script lang="ts">
  let items = $state<string[]>([])

  let total = $derived(items.length)

  $effect(() => {
    document.title = `Cart (${total})`
  })
</script>
```

**Worse:**
```svelte
<script lang="ts">
  let items = $state<string[]>([])
  let total = $state(0)

  $effect(() => {
    total = items.length           // computing state inside an effect
    document.title = `Cart (${total})`
  })
</script>
```

**Why good is better:** Specializes the push-effects-to-the-edge principle for Svelte 5 runes. `$derived` is a pure reactive computation — Svelte knows exactly which state it depends on and can re-run it surgically. Writing state inside `$effect` conflates computation with I/O, creates timing hazards (the effect runs after the paint), and can trigger infinite update loops. Keep derived values in `$derived`; reserve `$effect` for side-effects that touch the outside world (DOM, timers, subscriptions).
