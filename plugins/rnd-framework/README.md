# R&D Framework Plugin for Claude Code

A Claude Code plugin that applies the scientific method to software engineering. It replaces ad-hoc coding with structured pipeline orchestration built on principles drawn directly from scientific methodology. Supports two execution modes: **single-flow** (all phases sequential in one session) and **multi-agent** (specialized agents per pipeline phase with structural information barriers).

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
/plugin marketplace add https://tangled.org/oleksify.me/rnd-framework
/plugin install rnd-framework@oleksify-plugins
```

Update to the latest version:

```
/plugin update rnd-framework@oleksify-plugins
```

### Inline declaration via settings.json (v2.1.80+)

Claude Code v2.1.80 added support for declaring plugins directly in `settings.json` without going through the marketplace. This is useful for local development or pinning a specific directory.

Add to `.claude/settings.json` (project-level) or `~/.claude/settings.json` (global):

```json
{
  "enabledPlugins": {
    "rnd-framework": {
      "source": "settings",
      "path": "./plugins/rnd-framework"
    }
  }
}
```

The `path` is resolved relative to the settings file's location. Use an absolute path if the plugin lives outside the project tree.

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
- `/rnd-framework:rnd-status` should work

## Execution Modes

The framework supports two execution modes, selectable via `/rnd-framework:rnd-start`:

### Single-Flow Mode

All pipeline phases run sequentially in a single session. No agents are spawned — the session invokes skills directly for each phase. Best for quick iterations, smaller tasks, or environments where multi-agent overhead is undesirable.

```
Plan → Schedule → Build → Verify → Iterate? → Integrate
```

### Multi-Agent Mode

Specialized agents handle each pipeline phase in isolated context windows. The orchestrator dispatches work to agents, enforcing structural information barriers — agents literally cannot see each other's internal reasoning. Best for complex tasks requiring maximum verification rigor.

```
Plan → Schedule → Build → [Reality Audit] → [Proof Gate] → Verify → Iterate? → Integrate
```

Additional phases in multi-agent mode:
- **Reality Audit** — `rnd-reality-auditor` adversarially verifies external contracts (SQL schemas, API responses, env vars). Blocking — routes back to build on INVALID findings.
- **Proof Gate** — `rnd-proof-gate` attempts formal Lean 4 proofs of pre-registration criteria. Advisory — findings inform but don't block.

Use `/rnd-framework:rnd-start` for the full pipeline with mode selection.

## Commands

| Command | Purpose |
|---|---|
| `/rnd-framework:rnd-start <task>` | Full pipeline: Plan → Build → Verify → Integrate (supports mode selection) |
| `/rnd-framework:rnd-plan <task>` | Planning only — decompose and produce task specifications |
| `/rnd-framework:rnd-build <T3\|wave-2\|next>` | Build a specific task or wave |
| `/rnd-framework:rnd-verify <T3\|wave-2\|all>` | Independent verification with information barriers |
| `/rnd-framework:rnd-integrate <wave-2\|final>` | Merge verified outputs, run integration tests |
| `/rnd-framework:rnd-status` | Show pipeline status dashboard |
| `/rnd-framework:rnd-history` | Browse past pipeline sessions for this project |
| `/rnd-framework:rnd-resume` | Resume a partially-completed pipeline from where it left off |
| `/rnd-framework:rnd-validate` | Validate plugin structure: frontmatter, hooks, cross-references |
| `/rnd-framework:rnd-doctor` | Runtime environment diagnostics: CLI tools, hooks, RND_DIR, version sync, Julia MCP |
| `/rnd-framework:rnd-bump` | Bump patch version, prepend CHANGELOG entry, stage and commit |
| `/rnd-framework:rnd-review` | Review code changes with multi-judge evidence-based rigor |
| `/rnd-framework:rnd-audit` | Full codebase audit against project standards |
| `/rnd-framework:rnd-brainstorm` | Conversational idea exploration — funnels vague ideas into focused plans |
| `/rnd-framework:rnd-narrative` | Generate a development narrative for a pipeline session |
| `/rnd-framework:rnd-calibrate` | Record manual ground-truth verdict corrections for calibration |
| `/rnd-framework:rnd-debug <bug>` | Debug pipeline: reproduce, diagnose root cause, fix, verify |
| `/rnd-framework:rnd-roadmap <goal>` | Create or continue a multi-session roadmap for large tasks |
| `/rnd-framework:rnd-scan` | Scan the project environment and build a persistent project-facts.md |

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
| `rnd-formatting` | Pre-commit formatting — detects project formatter (biome, prettier, mix format, cargo fmt, etc.) and runs it on pipeline-changed files |
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
| `kiss-practices` | Language-specific KISS rules to prevent over-engineering — general rules plus language files for Bash, Markdown, Elixir/Phoenix/Ecto, JS/TS/CSS/HTML, Tailwind, Svelte, PostgreSQL, DuckDB, Koka |
| `fp-practices` | Functional programming principles — pure functions, data transformations, composition, command-query separation, immutability |
| `code-review` | Review categories, severity levels, verdict taxonomy (CLEAN/ISSUES_FOUND/CRITICAL_ISSUES), and structured report format |
| `rnd-experiments` | Experiment protocol — how verifiers write independent tests from specs to catch real bugs |
| `rnd-calibration` | Verdict accuracy tracking — JSONL-based calibration stats with automatic false-verdict detection |
| `rnd-debug-pipeline` | Debug pipeline flow — 4-phase diagnosis-to-fix workflow, diagnosis report format, escalation criteria |
| `rnd-roadmapping` | Multi-session roadmap format, milestone statuses (NOT_STARTED → DONE), and update protocol |
| `rnd-learning` | Auto-capture pipeline-discovered gotchas from iteration cycles to the Learning Library; inject known pitfalls into builder prompts |
| `rnd-reality-auditing` | Adversarial methodology for reality verification — experiment design, evidence chains, report format for external service contract validation |
| `bash-hook-testing` | Test framework patterns for hook scripts — test-helpers.sh, run_hook, assertions, environment mocking |
| `hook-authoring` | Hook anatomy, exit code protocol, stdin parsing, fast-path patterns, hooks.json registration |
| `lean-proving` | Formal Lean 4 proofs of pre-registration criteria — theorem generation, companion tests, proof reports |
| `lib-sh-patterns` | Shared lib.sh utilities — FP primitives, path predicates, response functions, stdin parsing |
| `plugin-architecture` | Plugin structure — config dir detection, path matching, hooks.json, hook events |
| `plugin-versioning` | Version bumping, changelog entries, validation, and the release workflow |

## Agents

Eight specialized agents for the multi-agent execution mode. All have persistent memory (`memory: user`), skills preloaded at startup, distinct UI colors, and KISS rules. The verifier has `disallowedTools: Edit` as defense-in-depth (Write is allowed for experiment files in `$RND_DIR` only).

| Agent | Model | Color | Role |
|---|---|---|---|
| `rnd-framework:rnd-planner` | opus | blue | Decomposes tasks, writes pre-registration documents, builds dependency matrix |
| `rnd-framework:rnd-builder` | sonnet | green | Implements one task with TDD, produces build manifest + self-assessment |
| `rnd-framework:rnd-verifier` | opus | amber | Independent verification against pre-registered criteria with information barrier |
| `rnd-framework:rnd-integrator` | sonnet | purple | Merges verified outputs, runs integration/system tests, SHIP/NO-SHIP verdicts |
| `rnd-framework:rnd-debugger` | opus | orange | Reproduces bugs, identifies root causes, produces diagnosis report for Builder |
| `rnd-framework:rnd-proof-gate` | sonnet | pink | Attempts formal Lean 4 proofs of pre-registration criteria (advisory, non-blocking) |
| `rnd-framework:rnd-reality-auditor` | sonnet | teal | Adversarially verifies external service contracts (SQL, APIs, env vars) |
| `rnd-framework:rnd-data-scientist` | opus | cyan | Standalone specialist for numerical/analytical work, with optional Lean 4 specs |

In single-flow mode, agents are not spawned — the session invokes skills directly. In multi-agent mode, the orchestrator dispatches work to these agents, each running in its own context window with structural isolation.

## Pipeline Scaling

Every task goes through the pipeline, scaled to complexity:

| Complexity | Entry Point | What Happens |
|---|---|---|
| Bug (reported symptom) | `/rnd-framework:rnd-debug` | Debugger diagnoses → Builder fixes → Verifier confirms |
| Trivial to small | `/rnd-framework:rnd-start` | Single-flow: plan → build → verify inline |
| Medium (1-4hr) | `/rnd-framework:rnd-start` | Planner + N Builders + N Verifiers + Integrator |
| Large (multi-day) | `/rnd-framework:rnd-start` | Full pipeline + design review gate |
| High-stakes | `/rnd-framework:rnd-start` | Full pipeline + dual independent verification |

## Roadmapping (Multi-Session Tasks)

For tasks that span multiple days or sessions, use `/rnd-framework:rnd-roadmap` to decompose the work into milestones before starting any pipeline session.

```
> /rnd-framework:rnd-roadmap Add full authentication system with OAuth, RBAC, and audit logging
  [Planner decomposes into milestones and writes roadmap.md at the project base]
  [Shows milestone list with statuses]

> /rnd-framework:rnd-roadmap   # run again to continue
  [Identifies next NOT_STARTED milestone, transitions to IN_PROGRESS]
  [Routes to /rnd-framework:rnd-start with milestone scope]
```

**Milestone lifecycle:** `NOT_STARTED` → `IN_PROGRESS` → `DONE` (or `SKIPPED`)

Each milestone is one `/rnd-framework:rnd-start` session. After a SHIP verdict, the `rnd-completion` skill marks the milestone DONE and records the session ID. The `/rnd-start` command detects an existing roadmap in Phase 0 and scopes the session to the current milestone.

See the `rnd-roadmapping` skill for the roadmap.md format and update protocol.

## Typical Workflow

### Big feature

```
> /rnd-framework:rnd-start Add OAuth2 login with Google provider
  [Phase 0: Discovery — requirements gathering]
  [Phase 0.5: Design Exploration — 2-3 architectural alternatives with trade-offs, user approves design spec]
  [Planner produces task tree, pre-registrations, dependency matrix from approved design]
  [Review the plan, adjust if needed]

> /rnd-framework:rnd-build wave-1
  [Builder agents work on Wave 1 tasks in parallel]

> /rnd-framework:rnd-verify wave-1
  [Independent Verifier checks each task against criteria]

> /rnd-framework:rnd-build wave-2
  [...continues through waves...]

> /rnd-framework:rnd-integrate final
  [System validation, regression check, SHIP/NO-SHIP]
```

### Small task

```
> /rnd-framework:rnd-start Fix the race condition in token refresh
  [Plan → build → independent verify → done]
```

### Check progress

```
> /rnd-framework:rnd-status
```

## How Information Barriers Work

The Verifier never sees the Builder's self-assessment or reasoning. Enforcement varies by execution mode:

**Single-flow mode:**
1. **PreToolUse hook** — `read-gate.sh` blocks any Read call targeting files with `self-assessment` in the path
2. **Skill instructions** — the `rnd-verification` skill explicitly prohibits reading self-assessment files

**Multi-agent mode:**
1. **Structural isolation** — agents run in separate context windows, so the Verifier literally cannot see the Builder's internal reasoning
2. **PreToolUse hook** — same hook enforcement as single-flow (defense-in-depth)
3. **Agent instructions** — each agent's system prompt clearly states what it can and cannot access

Without this barrier:
- The Verifier gets anchored by the Builder's framing
- Known issues get "verified" as acceptable rather than caught
- Verification becomes rubber-stamping

## Project Artifacts

The framework stores pipeline artifacts in a centralized directory outside the project tree, computed by `lib/rnd-dir.sh`. The path is based on a hash of the git common directory (`git rev-parse --git-common-dir`, canonicalized), so each project gets its own isolated artifact space. All worktrees of the same repo share the same base directory. Falls back to `pwd` when not in a git repo.

**Helper script:** `lib/rnd-dir.sh`
- Called as `"${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh"` from hooks and agents
- Outputs an absolute path like `~/.claude/.rnd/<dirname>-<hash>/sessions/<YYYYMMDD-HHMMSS-XXXX>`
- Use `-c` flag to create the directory structure on first use
- Use `--finish` to clear the session ID after a pipeline run
- Use `--base` to get the project base dir (without session path)

Each pipeline run gets a unique session ID. Previous sessions remain on disk and can be browsed with `/rnd-framework:rnd-history`.

**Artifact layout** (`$RND_DIR`):

```
~/.claude/.rnd/<dirname>-<hash>/         # Project base (dirname + 8-char hash of path)
├── .current-session                    # Active session ID
├── project-facts.md                    # Persistent project environment scan (created by /rnd-scan)
├── calibration.jsonl                   # Verdict accuracy tracking (cross-session); stored in CLAUDE_PLUGIN_DATA when set
└── sessions/
    └── <YYYYMMDD-HHMMSS-XXXX>/         # One session per pipeline run
        ├── plan.md                     # Enriched plan: environment, testing strategy, worker guidelines, validation contract, pre-registrations, schedule
        ├── design-spec.md              # Approved architectural design spec (Design phase output)
        ├── diagnosis/
        │   └── T1-diagnosis.md         # Debugger's root cause analysis (debug pipeline only)
        ├── builds/
        │   ├── T1-manifest.md          # What the builder produced
        │   └── T1-self-assessment.md   # Builder's uncertainties (Verifier cannot read)
        ├── verifications/
        │   ├── T1-verification.md      # Verifier report with evidence
        │   ├── T1-experiments/         # Verifier-written independent experiment tests
        │   └── T1-evidence/            # Per-VAL-assertion evidence files (raw command output)
        ├── proofs/
        │   ├── T1-proof-report.md      # Proof Gate results for each task
        │   └── T1-theorems/            # Lean theorem files
        ├── integration/
        │   └── wave-1-report.md        # Integration test results, SHIP/NO-SHIP
        ├── iteration-log.md            # Build-verify cycle tracking
        └── pipeline-state.json         # Persistent per-task status (survives compaction)
```

Since artifacts live outside the project directory, no `.gitignore` changes are needed.

## Plugin Structure

```
rnd-framework/
├── .claude-plugin/plugin.json   # Plugin manifest
├── agents/                      # 8 specialized agents for multi-agent mode
├── commands/                    # 19 pipeline commands
├── hooks/
│   ├── hooks.json               # Hook routing: SessionStart/End, Setup, InstructionsLoaded, PreToolUse, PostToolUse, PreCompact/PostCompact, StopFailure, CwdChanged, FileChanged, TaskCreated, SubagentStart/Stop, PermissionDenied
│   ├── lib.sh                   # Shared bash utilities (input parsing, path checks, decision output incl. defer, FP primitives)
│   ├── read-gate.sh             # Read hook: information barrier + .rnd/, plugin cache, and learnings auto-allow
│   ├── bash-gate.sh             # Bash hook: blocks sed/cat/grep/find/echo>/inline interpreters//tmp redirects, auto-allows .rnd/; commit protection
│   ├── glob-grep-gate.sh        # Glob/Grep hook: auto-allows .rnd/ path operations
│   ├── session-start.sh         # SessionStart hook: injects skill context + Claude Code version check
│   ├── session-end.sh           # SessionEnd hook: clears active RND session on close/switch
│   ├── post-dispatch.sh         # PostToolUse hook: audit logging for Write/Edit/Bash + output size advisory
│   ├── stop-failure.sh          # StopFailure hook: logs API errors to stop-failures.jsonl, emits advisory
│   ├── setup.sh                 # Setup hook: validates plugin structure and dependencies
│   ├── instructions-loaded.sh   # InstructionsLoaded hook: reminds to extract project standards
│   ├── pre-compact.sh           # PreCompact hook: saves pipeline state before context compaction
│   ├── post-compact.sh          # PostCompact hook: restores pipeline state after compaction
│   ├── cwd-changed.sh           # CwdChanged hook: warns on cross-repo directory change
│   ├── file-changed.sh          # FileChanged hook: advises on external .rnd/ artifact edits
│   ├── task-created.sh          # TaskCreated hook: logs task creation to audit.jsonl
│   ├── permission-denied.sh     # PermissionDenied hook: logs auto-mode denials to audit.jsonl, returns {retry: true}
│   ├── format-on-save.sh        # PostToolUse hook: auto-formats code files after Write/Edit using detected project formatter
│   ├── subagent-lifecycle.sh    # SubagentStart/SubagentStop hook: logs agent lifecycle to audit.jsonl
│   └── statusline.sh            # Statusline script: rate limit usage + pipeline phase
├── output-styles/               # 3 custom output styles (scientific, rigorous, pipeline)
├── proofs/                      # Lean 4 formal verification of pipeline invariants
├── skills/                      # Skills (rnd-* namespace)
├── lib/
│   ├── rnd-dir.sh               # Artifact directory path computation + session management
│   ├── plugin-dir-base.sh       # Local copy of shared artifact dir logic (cache-compatible)
│   ├── bump.sh                  # Patch version increment + CHANGELOG entry + git stage
│   ├── validate.sh              # Plugin structure validation (frontmatter, hooks, cross-references)
│   └── validate-xrefs.sh        # Cross-reference and content parity validation (sourced by validate.sh)
├── tests/                       # Bash test suite for hooks and lib scripts
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

Edit the iteration limit in the `/rnd-framework:rnd-start` command (default: 3).

### Create new skills

Use the `writing-skills` skill for guidance on creating new skills that plug into the framework.

## Limitations

- **Hook enforcement is best-effort.** The PreToolUse hook blocks self-assessment reads but can't prevent indirect access (e.g., via inline code execution). Hook discipline is the primary enforcement.
- **No persistent state across sessions.** The `.rnd/` directory provides continuity, but session context resets. Use `/rnd-framework:rnd-status` to re-orient.
- **Token cost.** The full multi-agent pipeline (Planner + Builders + Verifiers + Integrator) is expensive. Use single-flow mode for smaller tasks.
- **Information barrier is path-based.** Hooks block reads of files with `self-assessment` in the path. The `read-gate.sh` hook checks the file path to prevent verification phases from reading build-phase reasoning.

## Acknowledgements

Some ideas in this framework were drawn from established engineering and scientific methodologies:

- [V-Model](https://en.wikipedia.org/wiki/V-model) — hierarchical decomposition with paired verification at each level
- [Design Structure Matrix (DSM)](https://en.wikipedia.org/wiki/Design_structure_matrix) — dependency analysis and parallel scheduling
- [NASA Independent Verification & Validation (IV&V)](https://www.nasa.gov/about-nasas-ivv-program/) — independent verification with strict information barriers
- [Stage-Gate](https://en.wikipedia.org/wiki/Phase-gate_process) — quality checkpoints between phases
- [Pre-Registration](https://en.wikipedia.org/wiki/Preregistration_(science)) — declaring intent and success criteria before execution
