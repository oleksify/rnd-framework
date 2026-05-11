---
name: rnd-doc-polish
description: "Use after SHIP verdict before committing — checks and updates CLAUDE.md, README.md, project docs, and stale inline comments to reflect what the pipeline just built"
user-invocable: false
effort: low
---

# Documentation Polish

## When to Use

- After SHIP verdict in `/rnd-framework:rnd-start` (Phase 6, before commit options)
- Manually via `/rnd-framework:rnd-review` or `/rnd-framework:rnd-audit` when doc staleness is suspected

## Process

### 1. Scope the Changes

Run `git diff --name-only` (or `git diff --staged --name-only`) to get the list of changed files.

### 2. Check CLAUDE.md

Read `CLAUDE.md` and nested ones (Glob `**/CLAUDE.md`). Verify:

- **Repository layout** — new files/directories reflected in structure trees?
- **Command/skill/agent lists** — new additions listed?
- **Artifact layout** — new artifact types in the artifact tree?
- **Architecture descriptions** — patterns match current state?
- **Conventions** — new conventions documented?

Fix stale entries in-place. Do not add docs for things that didn't change.

### 3. Check README.md

Verify:

- **Feature tables** — counts, rows, and descriptions match current state
- **Installation/usage** — new setup steps required?
- **Structure trees** — reflect new files?
- **Examples** — code examples still valid?

Fix stale entries. Do not rewrite accurate sections.

### 4. Check Project-Specific Docs

Use Glob to scan for documentation directories common in the project:

- `docs/**/*.md`
- `*.md` at root (beyond CLAUDE.md and README.md)
- Any `CONTRIBUTING.md`, `ARCHITECTURE.md`, or similar

For each doc file that references areas touched by the pipeline, verify accuracy. Skip docs that are unrelated to the changes.

### 5. Check Stale Inline Comments

For each code file in `git diff --name-only`:

- Grep for comments referencing specific counts, version numbers, or file paths that may now be stale
- Check for comments like `// N items`, `// see file X`, or `// matches pattern in Y` that reference things the pipeline changed

Fix stale comments. Do not add new comments.

### 6. Report

```
Doc polish: updated CLAUDE.md structure tree (added lib/validate.ts),
fixed README command count (12→14). No stale inline comments found.
```

If nothing needed updating, say: "Doc polish: all documentation is current."

## What NOT to Do

- Do not add documentation for features that weren't part of this pipeline run
- Do not rewrite prose or improve wording — only fix factual staleness
- Do not add comments to code — only fix existing stale ones
- Do not create new documentation files
- Do not touch CHANGELOG.md — that's handled by `/rnd-framework:rnd-bump`
