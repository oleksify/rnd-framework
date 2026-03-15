---
name: rnd-doc-polish
description: "Use after SHIP verdict before committing — checks and updates CLAUDE.md, README.md, project docs, and stale inline comments to reflect what the pipeline just built"
user-invocable: false
---

# Documentation Polish

## Overview

After a pipeline run ships verified code, documentation often lags behind. This skill guides the orchestrator through a systematic check-and-update pass before committing.

**Core principle:** If the code changed, the docs might need to change too. Check before committing, not after.

## When to Use

- After SHIP verdict in `/rnd-framework:start` (Phase 6, before commit options)
- After PASS verdict in `/rnd-framework:quick` (Step 4, before commit options)
- Manually via `/rnd-framework:review` or `/rnd-framework:audit` when doc staleness is suspected

## Process

### 1. Scope the Changes

Run `git diff --name-only` (or `git diff --staged --name-only` if files are staged) to get the list of files changed by the pipeline. This scopes what documentation might be affected.

### 2. Check CLAUDE.md

Read the project's root `CLAUDE.md` and any nested `CLAUDE.md` files (use Glob with `**/CLAUDE.md`). For each, verify:

- **Repository layout** — if new files/directories were created, are they reflected in any structure trees?
- **Command/skill/agent lists** — if new commands, skills, or agents were added, are they listed?
- **Artifact layout** — if new artifact types were introduced, are they in the artifact tree?
- **Architecture descriptions** — if architectural patterns changed, do the descriptions match?
- **Conventions** — if new conventions were established, are they documented?

Fix any stale entries in-place. Do not add documentation for things that didn't change.

### 3. Check README.md

If the project has a `README.md`, verify:

- **Feature tables** — counts, rows, and descriptions match the current state
- **Installation/usage** — any new setup steps required?
- **Structure trees** — do they reflect new files?
- **Examples** — are code examples still valid?

Fix stale entries. Do not rewrite sections that are still accurate.

### 4. Check Project-Specific Docs

Use Glob to scan for documentation directories common in the project:

- `docs/**/*.md`
- `*.md` at root (beyond CLAUDE.md and README.md)
- Any `CONTRIBUTING.md`, `ARCHITECTURE.md`, or similar

For each doc file that references areas touched by the pipeline, verify accuracy. Skip docs that are unrelated to the changes.

### 5. Check Stale Inline Comments

For each file in the `git diff --name-only` output that is a code file (not markdown):

- Grep for comments referencing specific counts, version numbers, or file paths that may now be stale
- Check for comments like `// N items`, `// see file X`, or `// matches pattern in Y` that reference things the pipeline changed

Fix stale comments. Do not add new comments.

### 6. Report

After making fixes, briefly summarize what was updated:

```
Doc polish: updated CLAUDE.md structure tree (added lib/validate.sh),
fixed README command count (12→14). No stale inline comments found.
```

If nothing needed updating, say: "Doc polish: all documentation is current."

## What NOT to Do

- Do not add documentation for features that weren't part of this pipeline run
- Do not rewrite prose or improve wording — only fix factual staleness
- Do not add comments to code — only fix existing stale ones
- Do not create new documentation files
- Do not touch CHANGELOG.md — that's handled by `/rnd-framework:bump`
