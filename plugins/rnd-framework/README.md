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

## Organization-Wide Seeding

For teams that want to pre-install the plugin across all machines, set `CLAUDE_CODE_PLUGIN_SEED_DIR` to a directory containing the plugin. Multiple seed directories can be separated by `:` (Unix) or `;` (Windows):

```bash
export CLAUDE_CODE_PLUGIN_SEED_DIR="/shared/plugins:/team/plugins"
```

Claude Code will discover and register plugins from all listed directories on startup.

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
| `/rnd-framework:resume` | Resume a partially-completed pipeline from where it left off |
| `/rnd-framework:validate` | Validate plugin structure: frontmatter, hooks, cross-references |
| `/rnd-framework:doctor` | Runtime environment diagnostics: CLI tools, hooks, RND_DIR, version sync, Julia MCP, Lean toolchain |
| `/rnd-framework:bump` | Bump patch version, prepend CHANGELOG entry, stage and commit |
| `/rnd-framework:review` | Review code changes with multi-judge evidence-based rigor |
| `/rnd-framework:audit` | Full codebase audit against project standards |
| `/rnd-framework:brainstorm` | Conversational idea exploration — funnels vague ideas into focused plans |
| `/rnd-framework:narrative` | Generate a development narrative for a pipeline session |
| `/rnd-framework:calibrate` | Record manual ground-truth verdict corrections for calibration |
| `/rnd-framework:debug <bug>` | Debug pipeline: reproduce, diagnose root cause, fix, verify |

## Skills

The plugin provides skills that embed structured practices into every phase of coding:

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
| `rnd-doc-polish` | Post-SHIP documentation check — updates CLAUDE.md, README.md, project docs, and stale inline comments |
| `prefer-system-tools` | Check if a native CLI tool can do the job before writing a script |
| `bun-scripting` | Prefer Bun (TypeScript) over Python for helper scripts when available |
| `committing` | Commit message style, length limits, and user confirmation before committing |
| `writing-skills` | Meta-skill for extending the framework with new skills |
| `rnd-data-science` | Numerical analysis, financial calculations, CSV/XLS handling, chart generation, and insight extraction using Julia |
| `rnd-multi-judge` | Multi-judge consensus verification — 2 independent verifiers with tiebreaker on disagreement |
| `rnd-local-experts` | Discover project-local agents and skills in `.claude/` for Planner reference |
| `rnd-design` | Architectural exploration before planning — generates 2-3 alternatives with trade-offs, produces a design spec, gates on user approval |
| `rnd-failure-modes` | Verification anti-pattern catalog — known failure modes, red-flag phrases, and guidance for avoiding false PASSes |
| `rnd-slop-detection` | PostToolUse slop gate — surfaces LLM anti-patterns (over-commenting, cargo-cult error handling, unnecessary abstractions) as advisory context to agents |
| `rnd-standards` | Extract project-specific coding rules from CLAUDE.md files and convert them into regex-based slop patterns saved to `$RND_DIR/project-patterns.json` |
| `kiss-practices` | Language-specific KISS rules to prevent over-engineering — general rules plus language files for Bash, Markdown, Elixir/Phoenix/Ecto, JS/TS/CSS/HTML, Tailwind, Svelte, PostgreSQL, DuckDB, Lean 4 |
| `fp-practices` | Functional programming principles — pure functions, data transformations, composition, command-query separation, immutability |
| `code-review` | Review categories, severity levels, verdict taxonomy (CLEAN/ISSUES_FOUND/CRITICAL_ISSUES), and structured report format |
| `rnd-experiments` | Experiment protocol — how verifiers write independent tests from specs to catch real bugs |
| `lean-proving` | Lean 4 formal verification — property bridge strategy, criteria-to-proposition translation, proof strategy ranking, companion tests, lake integration |
| `rnd-calibration` | Verdict accuracy tracking — JSONL-based calibration stats with automatic false-verdict detection |
| `rnd-debug-pipeline` | Debug pipeline flow — 4-phase diagnosis-to-fix workflow, diagnosis report format, escalation criteria |

## Agents

All agents have persistent memory (`memory: user`), skills preloaded at startup, distinct UI colors, and KISS rules. The verifier has `disallowedTools: Edit` as defense-in-depth (Write is allowed for experiment files in `$RND_DIR` only).

| Agent | Model | Color | Role |
|---|---|---|---|
| `rnd-framework:rnd-planner` | opus | blue | Decomposes tasks, writes pre-registration documents |
| `rnd-framework:rnd-builder` | sonnet | green | Implements one task with TDD, produces verification artifacts |
| `rnd-framework:rnd-verifier` | opus | amber | Independent verification against pre-registered criteria |
| `rnd-framework:rnd-integrator` | sonnet | purple | Merges verified outputs, runs integration tests |
| `rnd-framework:rnd-data-scientist` | opus | cyan | Standalone specialist for numerical/analytical work, with optional Lean 4 specs |
| `rnd-framework:rnd-proof-gate` | sonnet | pink | Attempts formal Lean 4 proofs of pre-registration criteria (advisory) |
| `rnd-framework:rnd-debugger` | opus | orange | Reproduces bugs, identifies root causes, produces diagnosis report for Builder |

## Pipeline Scaling

Every task goes through the pipeline, scaled to complexity:

| Complexity | Entry Point | What Happens |
|---|---|---|
| Bug (reported symptom) | `/rnd-framework:debug` | Debugger diagnoses → Builder fixes → Verifier confirms |
| Trivial (fix typo) | `/rnd-framework:quick` | Inline plan → build → verify |
| Small (<1hr) | `/rnd-framework:quick` | 1 Builder + 1 Verifier |
| Medium (1-4hr) | `/rnd-framework:start` | Planner + N Builders + N Verifiers + Integrator |
| Large (multi-day) | `/rnd-framework:start` | Full pipeline + design review gate |
| High-stakes | `/rnd-framework:start` | Full pipeline + dual independent verification |

## Typical Workflow

### Big feature

```
> /rnd-framework:start Add OAuth2 login with Google provider
  [Phase 0: Discovery — requirements gathering]
  [Phase 0.5: Design Exploration — 2-3 architectural alternatives with trade-offs, user approves design spec]
  [Planner produces task tree, pre-registrations, dependency matrix from approved design]
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
~/.claude/.rnd/<dirname>-<hash>/         # Project base (dirname + 8-char hash of path)
├── .current-session                    # Active session ID
├── calibration.jsonl                   # Verdict accuracy tracking (cross-session); stored in CLAUDE_PLUGIN_DATA when set
└── sessions/
    └── <YYYYMMDD-HHMMSS-XXXX>/         # One session per pipeline run
        ├── plan.md                     # Task tree, pre-registrations, schedule
        ├── design-spec.md              # Approved architectural design spec (Design phase output)
        ├── diagnosis/
        │   └── T1-diagnosis.md         # Debugger's root cause analysis (debug pipeline only)
        ├── builds/
        │   ├── T1-manifest.md          # What the builder produced
        │   └── T1-self-assessment.md   # Builder's uncertainties (Verifier cannot read)
        ├── verifications/
        │   ├── T1-verification.md      # Verifier report with evidence
        │   └── T1-experiments/         # Verifier-written independent experiment tests
        ├── proofs/
        │   ├── T1-proof-report.md          # Proof Gate results for each task
        │   └── T1-theorems/                # Lean theorem files
        ├── integration/
        │   └── wave-1-report.md        # Integration test results, SHIP/NO-SHIP
        └── iteration-log.md            # Build-verify cycle tracking
```

Since artifacts live outside the project directory, no `.gitignore` changes are needed.

## Plugin Structure

```
rnd-framework/
├── .claude-plugin/plugin.json   # Plugin manifest
├── agents/                      # 7 specialized agents
├── commands/                    # 18 pipeline commands
├── hooks/
│   ├── hooks.json               # SessionStart + SessionEnd + PreToolUse + PostToolUse hook routing
│   ├── lib.ts                   # Shared TypeScript utilities (input parsing, path checks, decision output)
│   ├── chunk-gate.ts            # Write/Edit hook: auto-allows .rnd/, blocks planning-phase writes, enforces 30-line chunks
│   ├── read-gate.ts             # Read hook: information barrier + .rnd/ and plugin cache auto-allow
│   ├── prefer-tools.ts          # Bash hook: blocks sed/cat/grep/find/echo>, auto-allows ls/.rnd
│   ├── session-start.ts         # SessionStart hook: injects skill context
    │   ├── session-end.ts           # SessionEnd hook: clears active RND session on close/switch
│   ├── audit-log.ts             # PostToolUse hook: logs Write/Edit operations to audit.jsonl
│   ├── slop-gate.ts             # PostToolUse hook: surfaces LLM anti-patterns as advisory context
│   ├── evidence-warn.ts         # PostToolUse hook: detects SQL/API references, emits verification reminders
│   ├── setup.ts                 # Setup hook: validates plugin structure and dependencies
│   ├── instructions-loaded.ts   # InstructionsLoaded hook: reminds to extract project standards
│   ├── pre-compact.ts           # PreCompact hook: saves pipeline state before context compaction
│   └── post-compact.ts          # PostCompact hook: restores pipeline state after compaction
├── output-styles/               # 3 custom output styles (scientific, rigorous, pipeline)
├── skills/                      # Skills (rnd-* namespace)
├── lib/
│   ├── rnd-dir.sh               # Artifact directory path computation + session management
│   ├── bump.sh                  # Patch version increment + CHANGELOG entry + git stage
│   └── validate.ts              # Plugin structure validation (frontmatter, hooks, cross-references)
├── proofs/                      # Lean 4 formal verification of pipeline invariants
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
- **Information barrier is path-based.** Hooks block reads of files with `self-assessment` in the path. The `read-gate.ts` hook additionally checks `agent_type` to allow non-verifier agents (e.g., builders, planners) to read their own self-assessments, but the primary enforcement is path-based.

## Acknowledgements

Some ideas in this framework were drawn from established engineering and scientific methodologies:

- [V-Model](https://en.wikipedia.org/wiki/V-model) — hierarchical decomposition with paired verification at each level
- [Design Structure Matrix (DSM)](https://en.wikipedia.org/wiki/Design_structure_matrix) — dependency analysis and parallel scheduling
- [NASA Independent Verification & Validation (IV&V)](https://www.nasa.gov/about-nasas-ivv-program/) — independent verification with strict information barriers
- [Stage-Gate](https://en.wikipedia.org/wiki/Phase-gate_process) — quality checkpoints between phases
- [Pre-Registration](https://en.wikipedia.org/wiki/Preregistration_(science)) — declaring intent and success criteria before execution
