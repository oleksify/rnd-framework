# Svelte 5 — FP Patterns

Svelte 5-specific patterns for pure component logic using runes. Assumes Svelte 5 with runes mode.

## 1. $derived as Pure Computation

`$derived` is the runes equivalent of a pure function applied to reactive inputs. Never put side effects inside `$derived`.

**Do:**
```svelte
<script>
  let { items } = $props();
  const total = $derived(items.reduce((sum, item) => sum + item.price, 0));
  const discounted = $derived(total > 100 ? total * 0.9 : total);
</script>
```

**Don't:** put mutations or async calls inside `$derived` — use `$effect` for side effects and keep `$derived` to pure transformations only.

## 2. Pure Helper Functions for Component Logic

Extract multi-step transformations into plain functions outside the `<script>` block. Pure functions are testable without mounting a component.

**Do:**
```svelte
<script>
  function filterActive(items) {
    return items.filter(i => i.active);
  }

  function sortByName(items) {
    return [...items].sort((a, b) => a.name.localeCompare(b.name));
  }

  let { items } = $props();
  const visible = $derived(sortByName(filterActive(items)));
</script>
```

**Don't:** inline multi-step logic directly in `$derived` expressions — extract named functions so each transformation is separately testable.

## 3. Immutable State Patterns with $state

Treat `$state` values as immutable: replace the whole value rather than mutating in place. Mutation bypasses Svelte's reactivity for nested objects.

**Do:**
```svelte
<script>
  let todos = $state([]);

  function addTodo(text) {
    todos = [...todos, { id: crypto.randomUUID(), text, done: false }];
  }

  function toggleTodo(id) {
    todos = todos.map(t => t.id === id ? { ...t, done: !t.done } : t);
  }
</script>
```

**Don't:** call `.push()`, `.splice()`, or assign to `array[index]` directly — mutations bypass Svelte's reactivity tracking for object and array values.

## 4. Reactive Pipelines via $derived Chains

Compose a sequence of transformations as a chain of `$derived` values, each named for the stage it represents.

**Do:**
```svelte
<script>
  let { orders } = $props();
  const pending     = $derived(orders.filter(o => o.status === 'pending'));
  const sorted      = $derived([...pending].sort((a, b) => a.createdAt - b.createdAt));
  const displayRows = $derived(sorted.map(o => ({ ...o, label: `#${o.id}` })));
</script>
```

**Don't:** merge all transformation steps into a single large `$derived` expression — named stages make the data flow readable and each stage independently inspectable.

## 5. Snippet Composition

Use snippets (`{#snippet}`) as composable, pure rendering units. Pass data in; emit markup out. Treat snippets like pure functions from data to markup.

**Do:**
```svelte
{#snippet badge(label, variant)}
  <span class="badge badge--{variant}">{label}</span>
{/snippet}

{#each items as item}
  {@render badge(item.status, item.urgent ? 'danger' : 'info')}
{/each}
```

**Don't:** write duplicated inline markup for the same visual pattern — extract it into a named snippet and `@render` it with arguments.

## 6. Command-Query Separation in Event Handlers

Event handlers are commands (they cause mutations). `$derived` values are queries (they compute from state). Never compute derived data inside an event handler.

**Do:**
```svelte
<script>
  let items = $state([]);
  const count    = $derived(items.length);           // query
  const hasItems = $derived(items.length > 0);       // query

  function removeItem(id) {                          // command
    items = items.filter(i => i.id !== id);
  }
</script>
```

**Don't:** compute derived values (counts, labels, totals) inside event handlers — those computations belong in `$derived` so they stay in sync automatically.

