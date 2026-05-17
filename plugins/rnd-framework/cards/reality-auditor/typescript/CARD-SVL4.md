---
id: SVL4
role: reality-auditor
language: typescript
tags: [anomaly, cross-check, skepticism]
applicable_task_types: [new-feature, bugfix, refactor]
scope: $effect runs only in the browser; DOM access inside $effect is safe, but $effect bodies are never executed during SSR.
specializes: [P-EFFECTS-EDGE-01]
---

**Good audit output:**
> The component calls `document.querySelector('.tooltip')` inside a `$effect`. During SSR (SvelteKit rendering on Node.js), `$effect` is not executed — so this specific call is safe. However, a sibling expression `const el = document.body` runs at module evaluation time, outside any `$effect`. That expression will throw a `ReferenceError: document is not defined` on the server. Flag: browser globals must be inside `$effect`, not at the top level of `<script>`.

**Worse audit output:**
> The component uses `$effect` for DOM access. Looks correct for Svelte 5.

**Why good is better:** Specializes the push-effects-to-the-edge principle for Svelte 5 SSR boundaries. `$effect` is the correct guard for browser-only code, but it guards only its callback — code at the `<script>` module top-level runs on the server during SSR and has no DOM. An auditor who sees `$effect` around one DOM call must check whether any DOM access also leaks outside the effect boundary. The guard is narrow; the risk surface is the full `<script>` block.
