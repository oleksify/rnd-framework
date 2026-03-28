# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A multi-platform plugin repository compatible with **Claude Code**, **Factory Droid**, and **OpenCode**. Contains two plugins:

- **rnd-framework** — a scientific-method orchestration system for multi-agent coding. It structures workflows around pre-registration, independent verification with information barriers, evidence-based quality gates, and structured decomposition.
- **** — a creative studio for designing in Framer. Follows a real design process (brief → moodboard → tokens → build → review) to produce design systems and page skeletons.

Plugins live under `plugins/`. The root `.claude-plugin/marketplace.json` is a local plugin registry that references them (includes `owner` and `category` fields for Claude Code discovery). The `.factory-plugin/marketplace.json` omits those fields per Factory Droid's validator requirements. The `.opencode-plugin/marketplace.json` follows the same no-owner format. Alternatively, plugins can be declared inline in `settings.json` using `source: 'settings'` (v2.1.80+).

## Repository Layout

```
lib/
└── plugin-dir-base.sh              # Canonical copy of shared artifact directory logic (each plugin has its own copy for cache compatibility)

plugins/rnd-framework/
├── .claude-plugin/plugin.json   # Plugin manifest (name, version, description)
├── .opencode-plugin/plugin.json # OpenCode plugin manifest
├── agents/                      # Specialized agents (planner, builder, verifier, integrator, data-scientist)
├── commands/                    # Slash commands (/rnd-framework:rnd-start, etc.)
├── skills/                      # Skills, each in its own dir with SKILL.md
├── output-styles/               # 3 custom output styles (scientific, rigorous, pipeline)
├── hooks/
│   ├── hooks.json               # Hook routing: SessionStart/End, PreToolUse, PostToolUse, CwdChanged, FileChanged, TaskCreated
│   ├── opencode-bridge.ts       # OpenCode bridge: translates JS hook events to shell script calls via Bun.spawn
│   ├── lib.sh                   # Shared bash utilities (input parsing, path checks, decision output, FP primitives)
│   ├── read-gate.sh             # Read hook: information barrier + .rnd/, plugin cache, and learnings auto-allow
│   ├── write-gate.sh            # Write/Edit hook: blocks /tmp/ writes, auto-allows .rnd/ path operations
│   ├── prefer-tools.sh          # Bash hook: blocks sed/cat/grep/find/echo>/inline interpreters//tmp redirects, auto-allows .rnd/ paths only
│   ├── session-start.sh         # SessionStart hook: injects skill context
│   ├── session-end.sh           # SessionEnd hook: clears active RND session on close/switch
│   ├── post-tool-use.sh         # PostToolUse hook: audit logging for Write/Edit operations
│   ├── observation-mask.sh      # PostToolUse/Bash hook: advises when output exceeds 50 lines
│   ├── stop-failure.sh          # StopFailure hook: logs API errors to stop-failures.jsonl, emits advisory
│   ├── setup.sh                 # Setup hook: validates plugin structure and dependencies
│   ├── instructions-loaded.sh   # InstructionsLoaded hook: reminds to extract project standards
│   ├── pre-compact.sh           # PreCompact hook: saves pipeline state before context compaction
│   ├── post-compact.sh          # PostCompact hook: restores pipeline state after compaction
│   ├── cwd-changed.sh           # CwdChanged hook (v2.1.83+): warns on cross-repo directory change
│   ├── file-changed.sh          # FileChanged hook (v2.1.83+): advises on external .rnd/ artifact edits
│   ├── task-created.sh          # TaskCreated hook (v2.1.84+): logs task creation to audit.jsonl
│   ├── glob-grep-gate.sh        # Glob/Grep hook: auto-allows .rnd/ and .rnd/ path operations
│   └── statusline.sh            # Statusline script: rate limit usage + pipeline phase (v2.1.80)
├── lib/
│   ├── rnd-dir.sh               # Artifact directory path computation + session management
│   ├── plugin-dir-base.sh       # Local copy of shared artifact dir logic (cache-compatible)
│   ├── bump.sh                  # Patch version increment + CHANGELOG entry + git stage
│   └── validate.sh              # Plugin structure validation (frontmatter, hooks, cross-references)
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
| `rnd-reality-auditor` | sonnet | teal | Adversarial testing of external service assumptions in builder code |
| `rnd-debugger` | opus | orange | Reproduces bugs, identifies root causes, and produces a structured diagnosis report for handoff to the Builder |

All agents have `memory: user` (persistent cross-project learning), `skills` preloading (domain-specific skills injected at startup), KISS rules, `maxTurns` limits to prevent runaway sessions (planner: 250, builder: 200, verifier/debugger/integrator/data-scientist: 150, proof-gate: 100), and `effort` levels (opus agents: high, sonnet agents: medium). The builder additionally has `isolation: worktree` for safe parallel execution. The verifier additionally has `disallowedTools: Edit` as defense-in-depth (Write is allowed for experiment files in `$RND_DIR` only).

### Information Barrier and Permission Hooks

The `hooks.json` routes each PreToolUse event to an external script. Policies enforced:
- **Information barrier** (`read-gate.sh`): Blocks any `Read` call where the file path contains `self-assessment`, preventing the Verifier and Proof Gate from anchoring on Builder reasoning
- **Auto-allow plugin artifact paths and cache operations** (`read-gate.sh`, `write-gate.sh`, `prefer-tools.sh`, `glob-grep-gate.sh`): `Read` operations on plugin artifact paths (`.rnd/`, `.rnd/`) are auto-allowed. `Write` and `Edit` operations on these paths are auto-allowed. `Glob` and `Grep` operations targeting these paths are auto-allowed. For `Bash`, these paths are auto-allowed only for commands that pass tool discipline checks first (sed/cat/grep/find are still blocked even on artifact paths). `read-gate.sh` additionally auto-allows reads from the plugin cache (`plugins/cache/`) for skill and agent files, and from the learnings directory (`$CLAUDE_CONFIG_DIR/learnings/`) for cross-session knowledge
- **Tool discipline** (`prefer-tools.sh`): Blocks `sed`, `cat`, `grep`, `find`, `echo/printf` with file redirects, inline interpreter execution (`python -c`, `node -e`, `bun -e`, bare interpreter as pipe target), and `/tmp/` redirects — enforces use of dedicated Claude Code tools and `$RND_DIR` for temp storage. Splits compound commands (`&&`, `||`, `;`, `|`) and checks each segment, including `$()` and backtick substitutions. File execution (`python file.py`, `bun test`, `python -m pytest`) is allowed.
- **`/tmp` write block** (`write-gate.sh`): Blocks `Write` and `Edit` tool operations targeting `/tmp/` paths, steering agents to the plugin artifact directory
- **Commit protection** (`bash-gate.sh`): Blocks `git add` of plugin artifact directories (`.rnd/`, `.rnd/`) as defense-in-depth; emits an advisory warning on `git push` to main/master/production branches (agents must ask the user for explicit confirmation before proceeding)
- **Audit logging** (`post-tool-use.sh`): PostToolUse hook logs all Write and Edit operations to `$RND_DIR/audit.jsonl`
- **Stop failure logging** (`stop-failure.sh`): StopFailure hook logs API errors (rate limits, auth failures) to `$RND_DIR/stop-failures.jsonl` and emits advisory context
- **Directory change detection** (`cwd-changed.sh`): CwdChanged hook (v2.1.83+) warns when the working directory moves to a different git repository while an RND session is active
- **Artifact change detection** (`file-changed.sh`): FileChanged hook (v2.1.83+) emits advisory context when `.rnd/` artifact files (plan.md, iteration-log.md) are modified externally
- **Task creation logging** (`task-created.sh`): TaskCreated hook (v2.1.84+) logs task creation events to `$RND_DIR/audit.jsonl`

#### Hook Allow/Deny Precedence (v2.1.77+)

As of Claude Code v2.1.77, a PreToolUse hook returning `allow` no longer bypasses explicit deny rules. The effective precedence is:

**deny rules > hook allow > default permission prompt**

This affects the two hooks that auto-allow `.rnd/` operations: `read-gate.sh` and `prefer-tools.sh`. If a user or enterprise policy has a deny rule covering `.rnd/` paths, those hooks' auto-allows will be silently overridden and permission prompts will reappear.

**Workaround:** Use the `allowRead` and `allowWrite` sandbox settings to explicitly re-allow `.rnd/` paths. These settings take precedence over deny rules and restore the intended auto-allow behavior:

```json
{ "allowRead": ["~/.claude/.rnd/**"], "allowWrite": ["~/.claude/.rnd/**"] }
```

### Multi-Platform Support (Claude Code + Factory Droid + OpenCode)

All plugins run on Claude Code, Factory Droid, and OpenCode from a single codebase. Factory Droid claims full Claude Code plugin compatibility and aliases `CLAUDE_PLUGIN_ROOT` to `DROID_PLUGIN_ROOT`. OpenCode uses a fundamentally different hook system (JS/TS plugins instead of shell scripts), bridged via `opencode-bridge.ts`.

- **Config directory detection** (`plugin-dir-base.sh`): Detects platform env vars and resolves to the correct config directory. Precedence: `CLAUDE_PLUGIN_ROOT` (strip cache) > `CLAUDE_CONFIG_DIR` > `DROID_CONFIG_DIR` > `OPENCODE_CONFIG_DIR` > `OPENCODE_CONFIG` (→ `~/.config/opencode/`) > `DROID_PLUGIN_ROOT` (→ `~/.factory/`) > `~/.claude/` (default).
- **Path matching** (`lib.sh`, `prefer-tools.sh`, `artifact-gate.sh`): Regexes match `~/.claude*/`, `~/.factory/`, and `~/.config/opencode/` paths using `(\.(claude[^/]*|factory)|\.config/opencode)/`.
- **Hook matchers** (`hooks.json`): Tool name matchers cover all three platforms — `Bash|Execute|bash`, `Write|Create|write`, `Read|read`, `Edit|edit`, `Glob|glob`, `Grep|grep`. OpenCode uses lowercase tool names; Claude Code uses PascalCase; Factory Droid uses both PascalCase and `Execute`/`Create` variants.
- **OpenCode bridge** (`opencode-bridge.ts`): TypeScript plugin that translates OpenCode hook events (`tool.execute.before`, `tool.execute.after`, `event`, `experimental.session.compacting`) into calls to the existing shell scripts via `Bun.spawn`. Shell scripts remain the single source of truth for all hook logic. The bridge sets `CLAUDE_PLUGIN_ROOT` when spawning scripts so they can locate plugin resources. Context from `session-start.sh` is injected via `experimental.chat.system.transform`.
- **Missing hook events on Factory Droid**: `PostCompact`, `CwdChanged`, `FileChanged`, `TaskCreated`, `InstructionsLoaded`, `Setup`, `StopFailure`. These hooks simply don't fire — no code change needed.
- **OpenCode limitations**: No `TaskCreated`, `CwdChanged`, `InstructionsLoaded`, `Setup`, `StopFailure` equivalents. The `event` bus provides `file.edited` (mapped to `file-changed.sh`) and `session.created`. Advisory context from hooks (e.g., observation-mask.sh) cannot be injected mid-conversation — only block/allow decisions are supported via `tool.execute.before`.

### --bare Mode (v2.1.81+)

When Claude Code is launched with `--bare`, all hooks are skipped — SessionStart, read-gate.sh, prefer-tools.sh, post-tool-use.sh, and all others. Practical consequences:

- The information barrier is not enforced: the Verifier can read Builder self-assessments
- Tool discipline is not enforced: sed/cat/grep/find/inline interpreters bypass is possible
- Session bootstrap does not run: skills are not injected into context

Bottom line: rnd-framework effectively does not work in `--bare` mode. This is expected — `--bare` is designed for scripted `-p` invocations, not interactive multi-agent orchestration.

### Skill System

Skills are directories under `skills/` containing a `SKILL.md` with YAML frontmatter (`name`, `description`, `effort`). Claude Code's native plugin system discovers skills by directory convention. The `effort` field (added in v2.1.80) overrides the model's reasoning effort when the skill is invoked: `low` for reference/guidance skills, `medium` for procedural workflows. Commands also support `effort` frontmatter: `low` for read-only operations, `medium` for moderate reasoning, `high` for deep multi-agent orchestration.

The `rnd-roadmapping` skill defines the roadmap.md format, milestone statuses, and how agents create and update roadmaps across sessions.

The `rnd-learning` skill enables auto-capture of pipeline-discovered gotchas to the user's Learning Library during iteration cycles.

The `rnd-formatting` skill detects the project's code formatter and runs it on pipeline-changed files before doc-polish and committing.

**Shadowing rule:** Personal skills (in user's `.claude/skills/`) override rnd-framework skills unless explicitly prefixed with `rnd-framework:`.

**Plugin freshness (v2.1.81+):** Ref-tracked plugins re-clone on every load, so the cached plugin version is always current. Version mismatch warnings (from `hooks/session-start.sh`) should be rare in v2.1.81+ setups; if they appear, it likely indicates a bug rather than a stale install.

### Session Bootstrap

The `SessionStart` hook fires on `startup|resume|clear|compact` and runs `hooks/session-start.sh`, which reads and injects the `using-rnd-framework` skill content into session context as a system reminder.

The `SessionEnd` hook fires when a session closes or switches (including via `/resume`) and runs `hooks/session-end.sh`, which calls `rnd-dir.sh --finish` to clear the active session marker. This prevents stale `.current-session` files from persisting across sessions.

**Remote pipelines with `--channels` (v2.1.81+):** The `--channels` flag enables permission-relay mode, forwarding tool approval prompts to the Claude mobile app. This is useful when running rnd-framework pipelines on remote or headless machines where interactive terminal input is unavailable.

### Runtime Artifacts

The framework stores artifacts in a centralized directory outside the project tree, computed by `lib/rnd-dir.sh`. Each project gets an isolated artifact space based on a hash of its path. Each pipeline run gets a unique session ID, preserving history across runs.

**Helper:** `"${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh"` — outputs absolute `$RND_DIR` path. Flags: `-c` (create), `--finish` (clear session), `--base` (project base dir), `--roadmap` (path to roadmap.md at project base).

```
~/.claude/.rnd/<basename>-<hash>/          # Project base; slug = git-common-dir basename + 8-char sha256 of canonicalized git-common-dir; falls back to pwd basename + hash when not in a git repo
├── .current-session                       # Active session ID
├── .session-git-root                      # Git root of the project that started the session (written by session-start.sh, read by cwd-changed.sh)
├── roadmap.md                             # Multi-session roadmap (optional, created by /roadmap)
├── calibration.jsonl                      # Verdict accuracy tracking (legacy; new installs use $CLAUDE_PLUGIN_DATA)
└── sessions/<YYYYMMDD-HHMMSS-XXXX>/      # $RND_DIR (one per pipeline run)
    ├── plan.md                            # Task tree, pre-registrations, schedule
    ├── diagnosis/T*-diagnosis.md          # Debugger root cause analysis (debug pipeline only)
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

**Worktree support:** All worktrees of the same repository share the same `.rnd/` base directory. The project slug is derived from `git rev-parse --git-common-dir` (canonicalized to an absolute path via the POSIX `cd + pwd` idiom), so linked worktrees and the main checkout produce identical slugs even though their `pwd` values differ.

## Commands

Slash commands use the full plugin namespace: `/rnd-framework:rnd-start`, `/rnd-framework:rnd-plan`, `/rnd-framework:rnd-build`, `/rnd-framework:rnd-verify`, `/rnd-framework:rnd-integrate`, `/rnd-framework:rnd-status`, `/rnd-framework:rnd-resume`, `/rnd-framework:rnd-quick`, `/rnd-framework:rnd-history`, `/rnd-framework:rnd-validate`, `/rnd-framework:rnd-doctor`, `/rnd-framework:rnd-bump`, `/rnd-framework:rnd-review`, `/rnd-framework:rnd-audit`, `/rnd-framework:rnd-brainstorm`, `/rnd-framework:rnd-narrative`, `/rnd-framework:rnd-calibrate`, `/rnd-framework:rnd-debug`, `/rnd-framework:rnd-roadmap`.

## Key Conventions

- **Skills use YAML frontmatter** — `name`, `description`, and `effort` fields between `---` delimiters
- **Commands are Markdown files** in `commands/` — filename becomes the command name
- **Agents are Markdown files** in `agents/` — YAML frontmatter specifies `model`, `tools`, `memory`, `color`, `skills`, and optionally `disallowedTools`, `maxTurns`
- **Plugin manifest** at `.claude-plugin/plugin.json` — only `name`, `description`, `version`
- **Test suite** — `tests/` contains bash tests for hooks and lib scripts; run with `tests/run-tests.sh` from `plugins/rnd-framework/`
- **Tooling hierarchy** — system CLI tools first (`prefer-system-tools`), then bash scripts, then Python as last resort
- **File creation** — always use `Write`/`Edit` tools, never bash heredocs (`cat > file << 'EOF'`)

## Working on This Codebase

When modifying skills, agents, or commands, the content is Markdown processed by Claude Code's plugin system. Changes take effect in new sessions.

To test a hook change, start a new Claude Code session in a project with this plugin enabled.

To verify plugin registration: check that `.claude-plugin/marketplace.json` lists the plugin and the source path resolves to a valid `plugin.json`.
