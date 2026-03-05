# R&D Framework Plugin for Claude Code

A Claude Code plugin that applies the scientific method to software engineering. It replaces ad-hoc coding with structured multi-agent orchestration built on principles drawn directly from scientific methodology.

| Scientific Method | Framework Principle | Role |
|---|---|---|
| Hypothesis declaration | **Pre-registration** | Declare intent and testable success criteria before coding |
| Structured experimentation | **Decomposition** | Break tasks into hierarchical sub-tasks with paired verification |
| Blinded peer review | **Independent verification** | Separate verifier with strict information barriers |
| Reproducible evidence | **Evidence-based gates** | Quality checkpoints requiring reproducible evidence, not assertions |
| Dependency analysis | **Parallel scheduling** | Identify parallel vs sequential work for concurrent execution |

## Installation

Add the marketplace and install:

```
/plugin marketplace add https://tangled.sh/oleksify.me/claude-plugins
/plugin install rnd-framework@rnd-framework-plugins
```

Update to the latest version:

```
/plugin update rnd-framework@rnd-framework-plugins
```

## Per-Project Plugin Configuration

To control which plugins are active per-project, use Claude Code's `enabledPlugins` setting.

Add to your project's `.claude/settings.local.json` (not committed to git) or `.claude/settings.json` (shared with team):

```json
{
  "enabledPlugins": {
    "plugin-name@source": false
  }
}
```

### How settings precedence works

Settings are merged with more specific scopes winning:

1. **`.claude/settings.local.json`** (per-machine, not committed) — highest priority
2. **`.claude/settings.json`** (per-project, committed) — overrides user settings
3. **`~/.claude/settings.json`** (global) — fallback

Only plugins explicitly set to `false` at a more specific scope are disabled. Plugins not mentioned inherit from the parent scope.

### Verify active plugins

After configuring, start a Claude Code session in the project and check:
- The session should show `rnd-framework` in the startup context
- `/rnd-framework:status` should work

## Commands

| Command | Purpose |
|---|---|
| `/rnd-framework:start <task>` | Full pipeline: Plan → Build → Verify → Integrate |
| `/rnd-framework:plan <task>` | Planning only — decompose and produce task specifications |
| `/rnd-framework:build <T3\|wave-2\|next>` | Build a specific task or wave |
| `/rnd-framework:verify <T3\|wave-2\|all>` | Independent verification with information barriers |
| `/rnd-framework:integrate <wave-2\|final>` | Merge verified outputs, run integration tests |
| `/rnd-framework:status` | Show pipeline status dashboard |
| `/rnd-framework:quick <task>` | Lightweight mode for small tasks |
| `/rnd-framework:history` | Browse past pipeline sessions for this project |
| `/rnd-framework:validate` | Validate plugin structure: frontmatter, hooks, cross-references |
| `/rnd-framework:doctor` | Runtime environment diagnostics: CLI tools, hooks, RND_DIR, version sync, Julia MCP |
| `/rnd-framework:bump` | Bump patch version, prepend CHANGELOG entry, stage and commit |

## Skills

The plugin provides 17 skills that embed structured practices into every phase of coding:

| Skill | Purpose |
|---|---|
| `using-rnd-framework` | Session bootstrap — injected on startup, lists all available skills and commands |
| `rnd-orchestration` | Pipeline overview, agent roles, information barriers, gate criteria |
| `rnd-decomposition` | Hierarchical task decomposition, pre-registration, dependency analysis |
| `rnd-building` | Builder methodology with TDD discipline baked in |
| `rnd-verification` | Independent verification with information barriers and evidence-based verdicts |
| `rnd-debugging` | Systematic root cause analysis (no fixes without investigation) |
| `rnd-scheduling` | Dependency-based wave scheduling, parallel agent dispatch |
| `rnd-scaling` | Pipeline scaling rules: trivial → small → medium → large → high-stakes |
| `rnd-iteration` | Build-verify feedback loops, iteration budgets, escalation |
| `rnd-integration` | Merge verified outputs, integration/system validation |
| `rnd-completion` | Post-SHIP workflow: branch management, PR creation, cleanup |
| `rnd-isolation` | Git worktree isolation for parallel builders |
| `prefer-system-tools` | Check if a native CLI tool can do the job before writing a script |
| `bun-scripting` | Prefer Bun (TypeScript) over Python for helper scripts when available |
| `committing` | Commit message style, length limits, and user confirmation before committing |
| `writing-skills` | Meta-skill for extending the framework with new skills |
| `rnd-data-science` | Numerical analysis, financial calculations, CSV/XLS handling, chart generation, and insight extraction using Julia |

## Agents

| Agent | Model | Tools | Role |
|---|---|---|---|
| `rnd-framework:rnd-planner` | opus | Read, Grep, Glob | Decomposes tasks, writes pre-registration documents |
| `rnd-framework:rnd-builder` | sonnet | Read, Write, Edit, Bash, Glob, Grep | Implements one task with TDD, produces verification artifacts |
| `rnd-framework:rnd-verifier` | opus | Read, Write, Bash, Grep, Glob | Independent verification against pre-registered criteria |
| `rnd-framework:rnd-integrator` | sonnet | Read, Write, Edit, Bash, Glob, Grep | Merges verified outputs, runs integration tests |
| `rnd-framework:rnd-data-scientist` | opus | Read, Write, Edit, Bash, Glob, Grep | Standalone specialist for numerical/analytical work — finances, calculations, data, analytics, charts, insights; uses Julia or DuckDB CLI as computation backend |

## Pipeline Scaling

Every task goes through the pipeline, scaled to complexity:

| Complexity | Entry Point | What Happens |
|---|---|---|
| Trivial (fix typo) | `/rnd-framework:quick` | Inline plan → build → verify |
| Small (<1hr) | `/rnd-framework:quick` | 1 Builder + 1 Verifier |
| Medium (1-4hr) | `/rnd-framework:start` | Planner + N Builders + N Verifiers + Integrator |
| Large (multi-day) | `/rnd-framework:start` | Full pipeline + design review gate |
| High-stakes | `/rnd-framework:start` | Full pipeline + dual independent verification |

## Typical Workflow

### Big feature

```
> /rnd-framework:plan Add OAuth2 login with Google provider
  [Planner produces task tree, pre-registrations, dependency matrix]
  [Review the plan, adjust if needed]

> /rnd-framework:build wave-1
  [Builder agents work on Wave 1 tasks in parallel]

> /rnd-framework:verify wave-1
  [Independent Verifier checks each task against criteria]

> /rnd-framework:build wave-2
  [...continues through waves...]

> /rnd-framework:integrate final
  [System validation, regression check, SHIP/NO-SHIP]
```

### Small task

```
> /rnd-framework:quick Fix the race condition in token refresh
  [Quick plan → build → independent verify → done]
```

### Check progress

```
> /rnd-framework:status
```

## How Information Barriers Work

The Verifier never sees the Builder's self-assessment or reasoning. This is enforced two ways:

1. **Agent instructions** — each agent's system prompt clearly states what it can and cannot access
2. **PreToolUse hook** — `hooks.json` blocks any Read tool call targeting files with `self-assessment` in the path

Without this barrier:
- The Verifier gets anchored by the Builder's framing
- Known issues get "verified" as acceptable rather than caught
- Verification becomes rubber-stamping

## Project Artifacts

The framework stores pipeline artifacts in a centralized directory outside the project tree, computed by `lib/rnd-dir.sh`. The path is based on a hash of the project directory, so each project gets its own isolated artifact space.

**Helper script:** `lib/rnd-dir.sh`
- Called as `"${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh"` from hooks and agents
- Outputs an absolute path like `~/.claude/.rnd/<dirname>-<hash>/sessions/<YYYYMMDD-HHMMSS-XXXX>`
- Use `-c` flag to create the directory structure on first use
- Use `--finish` to clear the session ID after a pipeline run
- Use `--base` to get the project base dir (without session path)

Each pipeline run gets a unique session ID. Previous sessions remain on disk and can be browsed with `/rnd-framework:history`.

**Artifact layout** (`$RND_DIR`):

```
~/.claude/.rnd/<dirname>-<hash>/         # Project base (dirname + 6-char hash of path)
├── .current-session                    # Active session ID
└── sessions/
    └── <YYYYMMDD-HHMMSS-XXXX>/         # One session per pipeline run
        ├── plan.md                     # Task tree, pre-registrations, schedule
        ├── builds/
        │   ├── T1-manifest.md          # What the builder produced
        │   └── T1-self-assessment.md   # Builder's uncertainties (Verifier cannot read)
        ├── verifications/
        │   └── T1-verification.md      # Verifier report with evidence
        ├── integration/
        │   └── wave-1-report.md        # Integration test results, SHIP/NO-SHIP
        └── iteration-log.md            # Build-verify cycle tracking
```

Since artifacts live outside the project directory, no `.gitignore` changes are needed.

## Plugin Structure

```
rnd-framework/
├── .claude-plugin/plugin.json   # Plugin manifest
├── agents/                      # 5 specialized agents
├── commands/                    # 11 pipeline commands
├── hooks/
│   ├── hooks.json               # SessionStart + PreToolUse + PostToolUse hook routing
│   ├── auto-allow-rnd           # Write/Edit hook: auto-allows .rnd/ paths
│   ├── read-gate                # Read hook: information barrier + .rnd/ auto-allow
│   ├── prefer-tools             # Bash hook: blocks sed/cat/grep/find/echo>, auto-allows ls/.rnd
│   ├── session-start            # SessionStart hook: injects skill context via jq
│   └── audit-log                # PostToolUse hook: logs Write/Edit operations to audit.jsonl
├── output-styles/               # 3 custom output styles (scientific, rigorous, pipeline)
├── skills/                      # 17 skills (rnd-* namespace)
├── lib/
│   ├── rnd-dir.sh               # Artifact directory path computation + session management
│   └── bump.sh                  # Patch version increment + CHANGELOG entry + git stage
└── README.md
```

## Output Styles

Three custom output styles optimized for R&D pipeline work. Source files live in `output-styles/` within the plugin.

| Style | Purpose |
|---|---|
| **Scientific** | Hypothesis-driven reasoning — every change framed as experiment → evidence → conclusion |
| **Rigorous** | Maximum precision, zero ambiguity — explicit assumptions, rationale chains, audit-trail quality |
| **Pipeline** | Minimal narrative — structured status blocks, tables, next actions only |

### Registration

Output styles must be in `~/.claude/output-styles/` (user-level) or `.claude/output-styles/` (project-level) to appear in `/output-style`. Symlink from your project:

```bash
mkdir -p .claude/output-styles
ln -sf path/to/rnd-framework/output-styles/scientific.md .claude/output-styles/
ln -sf path/to/rnd-framework/output-styles/rigorous.md .claude/output-styles/
ln -sf path/to/rnd-framework/output-styles/pipeline.md .claude/output-styles/
```

Then switch with `/output-style scientific`, `/output-style rigorous`, or `/output-style pipeline`.

## Customization

### Change agent models

In each agent's YAML frontmatter, change the `model:` field:

- Planner: `opus` (strong reasoning for decomposition)
- Builder: `sonnet` (speed + quality for implementation)
- Verifier: `opus` (strong reasoning to catch subtle issues)
- Integrator: `sonnet` (mostly mechanical merge + test running)

### Adjust iteration budget

Edit the iteration limit in the `/rnd-framework:start` command (default: 3).

### Add domain-specific verification

Create additional Verifier variants in your project's `.claude/agents/`:

- `rnd-verifier-security.md` — Security-focused verification
- `rnd-verifier-perf.md` — Performance-focused verification

### Create new skills

Use the `writing-skills` skill for guidance on creating new skills that plug into the framework.

## Limitations

- **Hook enforcement is best-effort.** The PreToolUse hook blocks self-assessment reads but can't prevent indirect access. Agent instructions are the primary enforcement.
- **No persistent state across sessions.** The `.rnd/` directory provides continuity, but agent context resets. Use `/rnd-framework:status` to re-orient.
- **Token cost.** The full pipeline (Planner + Builders + Verifiers + Integrator) is expensive. Use `/rnd-framework:quick` for small tasks.
- **Cannot identify agents in hooks.** Claude Code hooks see tool inputs but not which agent is calling. Information barriers use path-based blocking (blocks ALL reads of self-assessment files) rather than agent-identity checks.

## Acknowledgements

Some ideas in this framework were drawn from established engineering and scientific methodologies:

- [V-Model](https://en.wikipedia.org/wiki/V-model) — hierarchical decomposition with paired verification at each level
- [Design Structure Matrix (DSM)](https://en.wikipedia.org/wiki/Design_structure_matrix) — dependency analysis and parallel scheduling
- [NASA Independent Verification & Validation (IV&V)](https://www.nasa.gov/about-nasas-ivv-program/) — independent verification with strict information barriers
- [Stage-Gate](https://en.wikipedia.org/wiki/Phase-gate_process) — quality checkpoints between phases
- [Pre-Registration](https://en.wikipedia.org/wiki/Preregistration_(science)) — declaring intent and success criteria before execution
