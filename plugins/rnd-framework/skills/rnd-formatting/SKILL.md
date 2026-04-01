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

## When to Use

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
