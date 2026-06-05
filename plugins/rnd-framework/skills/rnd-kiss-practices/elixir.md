# Elixir / Phoenix / Ecto — KISS Rules

## Language & OTP

- Use pattern matching over conditionals — `case`/`cond`/`with` chains are a smell if a function head match works
- Don't add GenServers when a plain module with functions will do — GenServer is for state, not namespacing
- Don't add supervision trees for processes that don't need restart semantics
- Don't create Behaviours for a single implementation — extract when the second implementation appears
- Don't create Protocol implementations for a single type — protocols are for polymorphism across types
- Use `Enum` pipelines over `Stream` unless you measurably need laziness
- Don't reach for macros when a function works — macros are for compile-time transformations, not DRY

## Phoenix

- Use standard Phoenix generators (`mix phx.gen.html`, `mix phx.gen.json`) and follow their conventions
- Don't replace standard CRUD controllers with LiveView unless there's a real interactivity need
- Keep controllers thin — one context call, render response
- Don't create nested route scopes for simple flat routes
- Use Phoenix's built-in form helpers and changesets before reaching for custom validation layers
- Don't add API versioning until you need it
- Use `Phoenix.Component` for markup reuse — don't build a component library before you have 3+ uses

## Ecto

- Keep schemas lean — schemas define data shape, not business logic
- Use simple `Ecto.Query` — avoid building composable query builder abstractions
- Don't wrap `Repo` calls in context modules unless the context adds real logic beyond pass-through
- Write migrations as simple `alter table` / `create table` — don't create migration helper modules
- Don't add database indexes speculatively — add them when a query is measurably slow
- Use `Ecto.Changeset` validations over custom validation modules
- Don't create separate `Repo` functions for every possible query variation — compose queries at the call site

## Polish

- Order functions within a module: public interface first (`def`), private helpers last (`defp`) — keep the public contract at the top so callers don't have to scroll past implementation details
- Within a context module, use one naming convention for the CRUD layer: `get_user` / `create_user` / `update_user` / `delete_user` — don't mix `fetch_`, `load_`, and `get_` for the same concept
- Comments in Elixir belong in `@doc` and `@moduledoc` — don't add `# ...` comments where a doc attribute would serve; reserve inline comments for non-obvious pattern-match guards or pipeline branch rationale
- Group related `def` clauses together — don't scatter pattern-match heads for the same function across the module interspersed with unrelated functions
