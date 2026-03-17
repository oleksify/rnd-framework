# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A Claude Code plugin repository containing the **rnd-framework** — a scientific-method orchestration system for multi-agent coding. It structures workflows around pre-registration, independent verification with information barriers, evidence-based quality gates, and structured decomposition.

The plugin lives at `plugins/rnd-framework/`. The root `.claude-plugin/marketplace.json` is a local plugin registry that references it.

## Repository Layout

```
plugins/rnd-framework/
├── .claude-plugin/plugin.json   # Plugin manifest (name, version, description)
├── agents/                      # Specialized agents (planner, builder, verifier, integrator, data-scientist)
├── commands/                    # Slash commands (/rnd-framework:start, etc.)
├── skills/                      # Skills, each in its own dir with SKILL.md
├── output-styles/               # 3 custom output styles (scientific, rigorous, pipeline)
├── hooks/
│   ├── hooks.json               # SessionStart bootstrap + PreToolUse + PostToolUse hook routing
│   ├── lib.ts                   # Shared TypeScript utilities (input parsing, path checks, decision output)
│   ├── chunk-gate.ts            # Write/Edit hook: auto-allows .rnd/ paths, blocks planning-phase writes, enforces 30-line chunks
│   ├── read-gate.ts             # Read hook: information barrier + .rnd/ and plugin cache auto-allow
│   ├── prefer-tools.ts          # Bash hook: blocks sed/cat/grep/find/echo>, auto-allows ls/.rnd
│   ├── session-start.ts         # SessionStart hook: injects skill context
│   ├── audit-log.ts             # PostToolUse hook: logs Write/Edit operations to audit.jsonl
│   ├── slop-gate.ts             # PostToolUse hook: surfaces LLM anti-patterns as advisory context to agents
│   ├── evidence-warn.ts         # PostToolUse hook: detects SQL/API references, emits verification reminders
│   ├── wellbeing-check.ts       # PostToolUse hook: suggests breaks after 45 minutes
│   ├── setup.ts                 # Setup hook: validates plugin structure and dependencies
│   ├── instructions-loaded.ts   # InstructionsLoaded hook: reminds to extract project standards
│   ├── pre-compact.ts           # PreCompact hook: saves pipeline state before context compaction
│   └── post-compact.ts          # PostCompact hook: restores pipeline state after compaction
├── lib/
│   ├── rnd-dir.sh               # Artifact directory path computation + session management
│   ├── bump.sh                  # Patch version increment + CHANGELOG entry + git stage
│   └── validate.ts              # Plugin structure validation (frontmatter, hooks, cross-references)
├── proofs/                      # Lean 4 formal verification of pipeline invariants
└── README.md
```

## Architecture

### Agent Roles and Models

| Agent | Model | Color | Purpose |
|---|---|---|---|
| `rnd-planner` | opus | blue | Decomposes tasks into pre-registered sub-tasks with testable criteria |
| `rnd-builder` | sonnet | green | Implements one task using TDD; produces build manifest + self-assessment |
| `rnd-verifier` | opus | amber | Independent verification — never sees builder reasoning |
| `rnd-integrator` | sonnet | purple | Merges verified outputs, runs integration tests, issues SHIP/NO-SHIP |
| `rnd-data-scientist` | opus | cyan | Standalone specialist for numerical/analytical work, with optional Lean 4 specs |
| `rnd-proof-gate` | sonnet | pink | Attempts formal Lean 4 proofs of pre-registration criteria (advisory) |

All agents have `memory: user` (persistent cross-project learning), `skills` preloading (domain-specific skills injected at startup), and KISS rules. The verifier additionally has `disallowedTools: Edit` as defense-in-depth (Write is allowed for experiment files in `$RND_DIR` only).

### Information Barrier and Permission Hooks

The `hooks.json` routes each PreToolUse event to an external script. Policies enforced:
- **Information barrier** (`read-gate.ts`): Blocks any `Read` call where the file path contains `self-assessment`, preventing the Verifier from anchoring on Builder reasoning
- **Auto-allow `$RND_DIR` and plugin cache operations** (`chunk-gate.ts`, `read-gate.ts`, `prefer-tools.ts`): All `Read`, `Write`, `Edit`, and `Bash` operations targeting paths containing `.rnd/` are auto-allowed (no permission prompts), except self-assessment reads. `read-gate.ts` additionally auto-allows reads from the plugin cache (`plugins/cache/`) for skill and agent files
- **Tool discipline** (`prefer-tools.ts`): Blocks `sed`, `cat`, `grep`, `find`, and `echo/printf` with file redirects — enforces use of dedicated Claude Code tools
- **Commit protection** (`prefer-tools.ts`): Blocks `git add` of `.rnd/` as defense-in-depth
- **Audit logging** (`audit-log.ts`): PostToolUse hook logs all Write and Edit operations to `$RND_DIR/audit.jsonl` during active pipeline sessions

#### Hook Allow/Deny Precedence (v2.1.77+)

As of Claude Code v2.1.77, a PreToolUse hook returning `allow` no longer bypasses explicit deny rules. The effective precedence is:

**deny rules > hook allow > default permission prompt**

This affects the three hooks that auto-allow `.rnd/` operations: `read-gate.ts`, `chunk-gate.ts`, and `prefer-tools.ts`. If a user or enterprise policy has a deny rule covering `.rnd/` paths, those hooks' auto-allows will be silently overridden and permission prompts will reappear.

**Workaround:** Use the `allowRead` and `allowWrite` sandbox settings to explicitly re-allow `.rnd/` paths. These settings take precedence over deny rules and restore the intended auto-allow behavior:

```json
{ "allowRead": ["~/.claude/.rnd/**"], "allowWrite": ["~/.claude/.rnd/**"] }
```

### Skill System

Skills are directories under `skills/` containing a `SKILL.md` with YAML frontmatter (`name`, `description`). Claude Code's native plugin system discovers skills by directory convention.

**Shadowing rule:** Personal skills (in user's `.claude/skills/`) override rnd-framework skills unless explicitly prefixed with `rnd-framework:`.

### Session Bootstrap

The `SessionStart` hook fires on `startup|resume|clear|compact` and runs `hooks/session-start.ts`, which reads and injects the `using-rnd-framework` skill content into session context as a system reminder.

### Runtime Artifacts

The framework stores artifacts in a centralized directory outside the project tree, computed by `lib/rnd-dir.sh`. Each project gets an isolated artifact space based on a hash of its path. Each pipeline run gets a unique session ID, preserving history across runs.

**Helper:** `"${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh"` — outputs absolute `$RND_DIR` path. Flags: `-c` (create), `--finish` (clear session), `--base` (project base dir).

```
~/.claude/.rnd/<dirname>-<hash>/           # Project base
├── .current-session                       # Active session ID
├── calibration.jsonl                      # Verdict accuracy tracking (cross-session)
└── sessions/<YYYYMMDD-HHMMSS-XXXX>/      # $RND_DIR (one per pipeline run)
    ├── plan.md                            # Task tree, pre-registrations, schedule
    ├── project-patterns.json              # Project-specific slop patterns extracted from CLAUDE.md
    ├── builds/T*-manifest.md              # Builder output records
    ├── builds/T*-self-assessment.md       # Builder uncertainties (blocked from Verifier)
    ├── verifications/T*-verification.md   # Verifier evidence-based verdicts
    ├── verifications/T*-experiments/      # Verifier-written independent experiment tests
    ├── proofs/T*-proof-report.md          # Proof Gate results (Lean 4 formal verification)
    ├── proofs/T*-theorems/                # Lean theorem files
    ├── integration/wave-*-report.md       # Integration results, SHIP/NO-SHIP
    └── iteration-log.md                   # Build-verify cycle tracking
```

Since `$RND_DIR` is outside the project, no `.gitignore` entry is needed.

## Commands

Slash commands use the full plugin namespace: `/rnd-framework:start`, `/rnd-framework:plan`, `/rnd-framework:build`, `/rnd-framework:verify`, `/rnd-framework:integrate`, `/rnd-framework:status`, `/rnd-framework:resume`, `/rnd-framework:quick`, `/rnd-framework:history`, `/rnd-framework:validate`, `/rnd-framework:doctor`, `/rnd-framework:bump`, `/rnd-framework:review`, `/rnd-framework:audit`, `/rnd-framework:brainstorm`, `/rnd-framework:narrative`, `/rnd-framework:calibrate`.

## Key Conventions

- **Skills use YAML frontmatter** — `name` and `description` fields between `---` delimiters
- **Commands are Markdown files** in `commands/` — filename becomes the command name
- **Agents are Markdown files** in `agents/` — YAML frontmatter specifies `model`, `tools`, `memory`, `color`, `skills`, and optionally `disallowedTools`
- **Plugin manifest** at `.claude-plugin/plugin.json` — only `name`, `description`, `version`
- **Test suite** — `tests/` contains Bun tests for hooks and lib scripts; run with `bun test` from `plugins/rnd-framework/`
- **Tooling hierarchy** — system CLI tools first (`prefer-system-tools`), then Bun scripts (`bun-scripting`), then Python as last resort
- **File creation** — always use `Write`/`Edit` tools, never bash heredocs (`cat > file << 'EOF'`)

## Working on This Codebase

When modifying skills, agents, or commands, the content is Markdown processed by Claude Code's plugin system. Changes take effect in new sessions.

To test a hook change, start a new Claude Code session in a project with this plugin enabled.

To verify plugin registration: check that `.claude-plugin/marketplace.json` lists the plugin and the source path resolves to a valid `plugin.json`.
