# Svelte — KISS Rules

## Components

- Use Svelte's built-in reactivity (`$:`) over manual state management — don't reach for stores when a reactive declaration works
- Keep components small and flat — extract a child component only when it's used 3+ times or manages independent state
- Don't create wrapper components that just pass props through — use slots or direct rendering
- Use `{#each}`, `{#if}`, `{#await}` template blocks — don't replicate logic in JS that Svelte handles in markup
- Don't add TypeScript generics to component props when concrete types work

## State

- Use `let` bindings for local state — don't create a store for component-scoped data
- Use `writable`/`readable` stores only for state shared across components — not for prop drilling avoidance
- Don't create derived stores when a reactive declaration (`$:`) does the job
- Don't wrap store access in custom functions unless there's real transformation logic

## Styling

- Use Svelte's scoped `<style>` blocks — don't add CSS-in-JS or global stylesheet frameworks unless the project already uses them
- Don't create utility CSS classes within a component — if a style is used once, put it inline in the style block
- Use CSS custom properties for theme values shared across components, not for every single value

## SvelteKit

- Use standard load functions (`+page.ts`, `+layout.ts`) — don't build custom data fetching abstractions
- Use form actions for mutations — don't reach for client-side API calls when a form action works
- Don't add API route wrappers — `+server.ts` files are already simple enough
- Use the built-in error/redirect helpers — don't create custom response utilities
