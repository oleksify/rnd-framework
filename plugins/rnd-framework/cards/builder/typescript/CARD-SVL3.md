---
id: SVL3
role: builder
language: typescript
tags: [boundaries, validation, abstraction]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Two-way binding with bind: requires explicit $bindable(); default props are read-only.
specializes: [P-IMPOSSIBLE-01]
---

**Good:**
```svelte
<!-- TextInput.svelte -->
<script lang="ts">
  let { value = $bindable('') } = $props<{ value?: string }>()
</script>

<input bind:value />

<!-- Parent -->
<script lang="ts">
  let name = $state('')
</script>
<TextInput bind:value={name} />
```

**Worse:**
```svelte
<!-- TextInput.svelte — value is not declared $bindable -->
<script lang="ts">
  let { value = '' } = $props<{ value?: string }>()
</script>

<input bind:value />  <!-- bind: on a non-bindable prop silently breaks -->
```

**Why good is better:** Specializes the impossible-states principle for Svelte 5 two-way binding. Without `$bindable()`, a prop is read-only — the child can read it but not propagate mutations back. Svelte will warn in dev when `bind:` is used on a non-bindable prop, but the failure is silent in prod. Marking `$bindable()` in the destructure makes the contract explicit: callers can see at a glance which props support two-way binding and which are one-way.
