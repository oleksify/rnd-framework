---
name: rnd-plugin-versioning
description: "Use when bumping plugin version, updating changelogs, or running validation — covers bump.sh, validate.sh, content parity, and the release workflow"
effort: low
---

# Plugin Versioning

## Overview

rnd-framework uses strict semver (`X.Y.Z`) in its plugin manifest. Version bumping, changelog management, and structural validation are automated via `lib/bump.sh` and `lib/validate.sh`. Always run validation after changes to skills, commands, hooks, or agents.

## Version Bumping

### Usage

```bash
"${CLAUDE_PLUGIN_ROOT}/lib/bump.sh" "Short headline" "Optional longer description"
```

### What It Does

1. Reads current version from `.claude-plugin/plugin.json`
2. Increments patch number (e.g., `1.0.1` -> `1.0.2`)
3. Writes new version to `plugin.json`
4. Prepends a CHANGELOG entry with today's date
5. Stages `plugin.json` and `CHANGELOG.md` via `git add`

### CHANGELOG Format

```markdown
## 1.0.2 — 2026-03-28

### Short headline

Optional longer description
```

### When NOT to Bump

- Pure documentation changes (README, CLAUDE.md edits)
- Test-only changes (no user-facing behavior change)
- Work-in-progress commits during a pipeline run (bump once at the end)

## Versioning Policy

### 0.x by Design

rnd-framework stays on `0.x` while it is an experimental R&D system. This is a deliberate stance following ZeroVer (0ver.org): a `0.` major signals that the interfaces, protocols, and quality gates are actively evolving and that no stability guarantee has been made. The major version will not advance to `1` until the design has stabilised and a compatibility commitment is warranted. Attempting `bump.sh --major` while the version is `0.x` is refused at the script level.

### Bump on Meaningful Releases, Not Every Commit

Bump the version when a release represents a coherent, user-visible change — a new feature, a behaviour fix, a protocol update, or a milestone. Do not bump for every commit, every pipeline run, or every minor editorial edit. The goal is a CHANGELOG that a reader can skim to understand what changed and why, not a log of every file touch.

## Validation

### Usage

```bash
cd plugins/rnd-framework
bash lib/validate.sh
```

Or for machine-readable output:

```bash
bash lib/validate.sh --quiet
```

### What It Validates

| Category | Checks |
|---|---|
| **Manifest** | plugin.json exists, valid JSON, has name/description/version, semver format |
| **Hooks** | hooks.json valid JSON, all referenced scripts exist and are executable |
| **Skills** | SKILL.md exists in each skill dir, has frontmatter with `name` (matches dir) and `description` |
| **Commands** | Frontmatter with `description`, `argument-hint` ↔ `$ARGUMENTS` consistency, valid `model` |
| **Output Styles** | Frontmatter with `name` and `description` |
| **Lib Scripts** | `rnd-dir.sh` and `bump.sh` exist and are executable |
| **Cross-References** | All `rnd-framework:<name>` refs in skills, agents, and commands resolve to actual skills/agents/commands |
| **Content Parity** | Specific markers exist in paired files (see below) |

### Content Parity Table

Validation checks that certain terms appear in both files of a pair. Examples:

- `DONE_WITH_CONCERNS` must appear in both `rnd-building` skill and `rnd-build` command
- `External dependencies` must appear in both `rnd-decomposition` and `rnd-orchestration` skills
- `Local Experts Discovered` must appear in both `rnd-local-experts` skill and `rnd-start` command

When adding new cross-cutting concepts, add a parity entry to the `PARITY_TABLE` array in `validate.sh`.

### Exit Codes

- `0` — all checks passed
- `1` — one or more checks failed

## Release Workflow

1. Make your changes (skills, hooks, commands, etc.)
2. Run tests: `bash tests/run-tests.sh`
3. Run validation: `bash lib/validate.sh`
4. Bump version: `bash lib/bump.sh "What changed"`
5. Commit with a descriptive message (see `rnd-framework:rnd-committing`)

## Related Skills

- `rnd-framework:rnd-plugin-architecture` — manifest format and plugin structure
- `rnd-framework:rnd-writing-skills` — skill file format and frontmatter conventions
- `rnd-framework:rnd-committing` — commit message style
