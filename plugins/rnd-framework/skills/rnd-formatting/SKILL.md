---
name: rnd-formatting
description: "Use before doc-polish and committing — detects the project's formatter and runs it on files changed by the pipeline"
user-invocable: false
effort: low
---

# Code Formatting

## Overview

After a pipeline run produces code, run the project's formatter before doc-polish and committing. This ensures pipeline-written code matches the project's style without manual intervention.

**Core principle:** Detect, don't assume. Every project has its own formatter (or none). Check config files first, then run the detected formatter on changed files only.

## Automatic Formatting (v2.1.90+)

The `format-on-save.sh` PostToolUse hook automatically formats code files after every Write/Edit operation during an active RND session — **except inside linked git worktrees**. Worktrees lack the project's gitignored toolchain dirs (`deps/`, `_build/`, `node_modules/`, `target/`), so the formatter would error or diverge there; the hook skips them. It uses the same formatter detection logic described below, cached at session level.

Because write-side agents (builder, verifier, cleanup, polisher, debugger) run in worktrees, their writes are **not** auto-formatted — this manual step at merge time (Phase 6, in the main checkout where the toolchain is whole) is what formats that code. In the main checkout, auto-format still runs, so manual formatting of orchestrator-written files is typically redundant.

Use this skill's manual process when:
- Formatting code written by worktree agents after the integrator merges to main (the primary case)
- You need to format files changed outside the pipeline (e.g., git merge)
- You want to format the entire project, not just individual files
- The auto-format hook is not available (Claude Code < v2.1.90)

## When to Use (Manual)

- In `/rnd-framework:rnd-start` Phase 6, before `rnd-doc-polish`

## Process

### 1. Get Changed Files

Run `git diff --name-only` to get files changed by the pipeline. Filter to code files only.

### 2. Detect Formatter

Check the project root for formatter config files. Stop at the **first match**:

| Config File | Formatter | Command |
|---|---|---|
| `biome.json`, `biome.jsonc` | Biome | `biome format --write <files>` |
| `.prettierrc`, `.prettierrc.*`, `prettier.config.*` | Prettier | `npx prettier --write <files>` |
| `deno.json` (with `fmt` key) | Deno | `deno fmt <files>` |
| `mix.exs` | Mix | `mix format <files>` |
| `Cargo.toml` | Rustfmt | `cargo fmt` |
| `pyproject.toml` with `[tool.ruff]`, or `ruff.toml` | Ruff | `ruff check --fix <files> && ruff format <files>` |
| `pyproject.toml` with `[tool.black]` (no ruff config) | Black | `black <files>` |
| `go.mod` | Gofmt | `gofmt -w <files>` |
| `.clang-format` | ClangFormat | `clang-format -i <files>` |

Also check `package.json` for a `format` or `fmt` script — if present, prefer `npm run format` or `bun run format`.

### 3. Run Formatter

Run the detected formatter on changed files only (not the entire project). If the formatter exits non-zero, report the error but do not block the pipeline. If no formatter is detected, skip silently: "No formatter detected — skipping."

### 4. Report

Summarize: `Formatting: ran biome on 5 files (3 reformatted).` or `Formatting: no formatter detected — skipping.`

## What NOT to Do

- Do not install formatters that aren't already in the project
- Do not format files that weren't changed by the pipeline
- Do not format if no formatter config is detected — never assume a default
- Do not block the pipeline on formatting errors
