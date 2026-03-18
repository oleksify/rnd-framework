# Svelte 5 — KISS Rules

## Runes and Reactivity

- Use `$state` only for variables that trigger effects, derived values, or template updates — don't make every variable reactive
- Use `$state.raw` for large objects that are only reassigned (never mutated) — avoids proxy overhead on API responses
- Use `$derived` for computed values, not `$effect` — derived is cleaner, side-effect-free, and expresses intent
- `$effect` is an escape hatch — avoid it; put logic in event handlers, use `$derived`, or use `$inspect` for debugging
- Never update `$state` inside `$effect` — this creates reactive loops; restructure as `$derived` instead
- Treat `$props` as values that will change — always derive dependent values with `$derived`, don't compute once at init

## Components

- Keep components small and flat — extract a child component only when it's used 3+ times or manages independent state
- Don't create wrapper components that just pass props through — use snippets or direct rendering
- Use `{#snippet}` and `{@render}` for reusable markup chunks — don't create components for template-only reuse
- Use keyed `{#each}` blocks — improves performance; key must uniquely identify items, never use array index
- Don't destructure `{#each}` items if you bind to them — `bind:value={item.count}` needs the reference

## State Sharing

- Use `createContext` for state scoped to a component subtree — prevents state leakage during SSR
- Don't use module-level `$state` for shared state — use context or classes with `$state` fields instead
- Don't create stores (`writable`/`readable`) — use classes with `$state` fields for shared reactivity in Svelte 5

## Events

- Use `onclick={handler}` attribute syntax — not the legacy `on:click={handler}` directive
- Use `<svelte:window>` and `<svelte:document>` for global listeners — not `onMount` or `$effect`

## Styling

- Use Svelte's scoped `<style>` blocks — don't add CSS-in-JS or global stylesheet frameworks unless the project already uses them
- Use `style:--property={value}` to pass JS variables to CSS — not inline style strings
- Style child components via CSS custom properties (`<Child --color="red" />`) — use `:global` only as last resort
- Don't create utility CSS classes within a component — if a style is used once, put it inline in the style block

## SvelteKit

- Use standard load functions (`+page.ts`, `+layout.ts`) — don't build custom data fetching abstractions
- Use form actions for mutations — don't reach for client-side API calls when a form action works
- Don't add API route wrappers — `+server.ts` files are already simple enough
- Use the built-in error/redirect helpers — don't create custom response utilities

## Legacy Patterns to Avoid

- `$:` reactive declarations → use `$derived` and `$effect`
- `export let` → use `$props`
- `<slot>` and `$$slots` → use `{#snippet}` and `{@render}`
- `on:click` directive → use `onclick` attribute
- `use:action` → use `{@attach}`
- `<svelte:component this={X}>` → use dynamic component `<X />`
