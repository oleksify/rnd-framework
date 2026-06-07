# R&D Framework Plugin for Claude Code

Multi-agent coding orchestration. Specialized agents handle each pipeline phase in isolated context windows, with structural information barriers enforced at the context-window level — the verifier literally cannot read the builder's reasoning.

The design borrows from scientific method and systems engineering:

| Principle | What it means |
|---|---|
| **Pre-registration** | Declare intent and testable success criteria before coding |
| **Decomposition** | Break tasks into hierarchical sub-tasks with paired verification |
| **Independent verification** | A separate verifier checks the work behind an information barrier |
| **Evidence-based gates** | Quality checkpoints require reproducible evidence, not assertions |
| **Wave scheduling** | Identify parallel vs sequential work for concurrent execution |

> Experimental (0.x). Interfaces, protocols, and quality gates change between releases.

## Install

```
/plugin marketplace add https://tangled.org/oleksify.me/rnd-framework.git
/plugin install rnd-framework@oleksify-plugins
```

Update with `/plugin update rnd-framework@oleksify-plugins`.

### Inline declaration (v2.1.80+)

Declare the plugin directly in `.claude/settings.json` without the marketplace — useful for local development:

```json
{
  "enabledPlugins": {
    "rnd-framework": { "source": "settings", "path": "./plugins/rnd-framework" }
  }
}
```

`path` is resolved relative to the settings file.

### Disable per project

```json
{ "enabledPlugins": { "rnd-framework@oleksify-plugins": false } }
```

Add to `.claude/settings.local.json` (per-machine) or `.claude/settings.json` (shared). Only plugins explicitly set to `false` at a more specific scope are disabled.

### Allow every skill in one rule (v2.1.139+)

```json
{ "permissions": { "allow": ["Skill(rnd-framework:*)"] } }
```

Run `claude plugin details rnd-framework` for per-component token estimates.

## Pipeline

```
Plan → Schedule → Build → [Reality Audit] → Verify → [Iterate] → Cleanup → Polish → Integrate
```

Launch with `/rnd-framework:rnd-start <task>`. The orchestrator dispatches each phase to an agent and aggregates results. Reality Audit runs only when a task declares external dependencies; Iterate runs only on a non-PASS verdict.

## Commands

| Command | Purpose |
|---|---|
| `/rnd-framework:rnd-start <task>` | Full pipeline: Plan → Build → Verify → Integrate |
| `/rnd-framework:rnd-plan <task>` | Planning only — decompose into task specs |
| `/rnd-framework:rnd-build <T3\|wave-2\|next>` | Build a task or wave |
| `/rnd-framework:rnd-verify <T3\|wave-2\|all>` | Independent verification |
| `/rnd-framework:rnd-integrate <wave-2\|final>` | Merge outputs, run integration tests |
| `/rnd-framework:rnd-status` | Pipeline status dashboard |
| `/rnd-framework:rnd-resume` | Resume a partial pipeline |
| `/rnd-framework:rnd-history` | Browse past sessions |
| `/rnd-framework:rnd-debug <bug>` | Reproduce, diagnose, fix, verify |
| `/rnd-framework:rnd-roadmap <goal>` | Multi-session roadmap |
| `/rnd-framework:rnd-scan` | Scan the project, build `project-facts.md` |
| `/rnd-framework:rnd-stats` | Per-shape non-PASS rate, drift, and gap report |
| `/rnd-framework:rnd-remeasure` | Compare current metrics against the baseline |
| `/rnd-framework:rnd-review` | Evidence-based review of recent changes |
| `/rnd-framework:rnd-audit` | Full codebase audit |
| `/rnd-framework:rnd-brainstorm` | Funnel a vague idea into a focused plan |
| `/rnd-framework:rnd-narrative` | Development narrative for a session |
| `/rnd-framework:rnd-calibrate` | Record a ground-truth verdict correction |
| `/rnd-framework:rnd-validate` | Validate plugin structure |
| `/rnd-framework:rnd-doctor` | Runtime environment diagnostics |
| `/rnd-framework:rnd-bump` | Bump version, update CHANGELOG |

## Agents

14 agents — 10 pipeline-phase plus 4 helpers. All preload skills, carry persistent memory, and use narrow tool grants. The orchestrator overrides the model per task based on its `Criticality` field; the models below are the defaults.

| Agent | Model | Role |
|---|---|---|
| `rnd-scoper` | opus / high | Produces the frozen, user-ratified `scope.json` + `scope.md` boundary before planning |
| `rnd-planner` | opus / high | Decomposes the frozen scope; emits the four plan artifacts |
| `rnd-builder` | sonnet / high | Implements one task with TDD; writes a manifest + self-assessment |
| `rnd-reality-auditor` | sonnet / low | Audits declared external references (URLs, APIs, schemas, env vars) |
| `rnd-verifier` | sonnet / high | Independent verification behind the information barrier |
| `rnd-cleanup` | sonnet / medium | Per-task dead-code sweep after PASS; rolls back if it breaks re-verification |
| `rnd-polisher` | opus / high | Wave-level cross-task seam fixer (duplication, naming drift) |
| `rnd-integrator` | haiku / low | Merges verified outputs, runs integration tests, SHIP/NO-SHIP |
| `rnd-debugger` | sonnet / high | Root-cause analysis for failing tasks |
| `rnd-data-scientist` | sonnet / medium | On-demand numerical/analytical work (Julia, DuckDB) |

**Helpers:** `rnd-premortem-imaginer` (parallel failure imagination), `rnd-replan-differ` (old-vs-new plan diff), `rnd-assertion-paraphraser` (decorrelates the verifier's read from the planner's phrasing), `rnd-explorer` (read-only fan-out search).

## Skills

Skills embed structured practices into each phase. Notable ones:

| Skill | Purpose |
|---|---|
| `rnd-using-rnd-framework` | Session bootstrap — lists available skills and commands |
| `rnd-orchestration` | Pipeline overview, agent roles, gate criteria |
| `rnd-decomposition` | Hierarchical decomposition and pre-registration |
| `rnd-premortem` | Pre-planning failure imagination, aggregated into `premortem.md` |
| `rnd-outside-view` | Injects historical per-shape FAIL rates as a calibration anchor |
| `rnd-building` | Builder methodology with TDD discipline |
| `rnd-verification` | Wave-batched independent verification, per-assertion verdict map |
| `rnd-debugging` | Systematic root-cause analysis |
| `rnd-scheduling` | Dependency-based wave scheduling |
| `rnd-scaling` | How much ceremony a task needs |
| `rnd-iteration` | Build-verify feedback loops and budgets |
| `rnd-integration` | Merge and system validation |
| `rnd-completion` | Post-SHIP branch management, PR creation |
| `rnd-formatting` | Detect and run the project formatter pre-commit |
| `rnd-doc-polish` | Update docs and stale comments after SHIP |
| `rnd-reality-auditing` | Adversarial external-contract verification |
| `rnd-calibration` | Verdict-accuracy tracking |
| `rnd-roadmapping` | Multi-session roadmap format and lifecycle |
| `rnd-learning` | Capture pipeline gotchas to the Learning Library |
| `rnd-code-review` | Review categories, severities, verdicts, report format |
| `rnd-kiss-practices` / `rnd-fp-practices` | Language-specific simplicity and FP rules |
| `rnd-prefer-system-tools` / `rnd-bun-scripting` / `rnd-committing` | Tooling and commit discipline |
| `rnd-hook-authoring` / `rnd-lib-sh-patterns` / `rnd-plugin-architecture` / `rnd-plugin-versioning` / `rnd-bash-hook-testing` | Working on the plugin itself |

## Information barrier

The verifier never sees the builder's self-assessment or reasoning. Two layers enforce this:

1. **Structural isolation** — agents run in separate context windows.
2. **PreToolUse hooks** — `read-gate.sh`, `glob-grep-gate.sh`, and `bash-gate.sh` block any read of barrier-protected paths (`self-assessment`, `briefs/`, `cleanup/`) by the verifier or polisher.

Without it, the verifier anchors on the builder's framing and verification degrades into rubber-stamping.

## Artifacts

Artifacts live in a central directory outside the project (computed by `lib/rnd-dir.sh`), so no `.gitignore` entry is needed. Each project gets an isolated slug; each run gets a unique session ID.

```
~/.claude/.rnd/<dirname>-<hash>/          # Project slug
├── calibration.jsonl                     # Verdict-accuracy tracking (project-wide)
├── post-review.jsonl                     # Post-SHIP review ledger
└── branches/<branch>/
    ├── project-facts.md                  # Persistent project scan
    ├── roadmap.md                        # Multi-session roadmap
    └── sessions/<YYYYMMDD-HHMMSS-XXXX>/   # One per run ($RND_DIR)
        ├── premortem.md                  # Failure imagination
        ├── outside-view.md               # Reference-class calibration block
        ├── protocol.md                   # Scope + goals
        ├── validation-contract.md        # One assertion per heading
        ├── features.json                 # Task manifest (IDs, deps, criticality)
        ├── AGENTS.md                      # Per-agent work assignments
        ├── builds/                       # Manifests + self-assessments
        ├── verifications/                # Verdict maps, reports, experiments, evidence
        ├── cleanup/ · polish/            # Cleanup and polish reports
        ├── integration/                  # Integration results, SHIP/NO-SHIP
        ├── briefs/                       # Barrier-protected builder narratives
        ├── audit.jsonl                   # Shared audit log
        └── iteration-log.md              # Build-verify cycle tracking
```

**`lib/rnd-dir.sh` flags:** `-c` (create session), `--finish` (clear session), `--base` (branch-scoped base), `--roadmap` / `--facts` (lazy-inherit from default branch), `--calibration` (slug-root path). Branch is resolved from `HEAD`; detached HEAD → `detached-<sha7>`, non-git → `no-git`.

## Output styles

Three styles in `output-styles/`. Register by symlinking into `.claude/output-styles/`, then `/output-style <name>`.

| Style | Purpose |
|---|---|
| **scientific** | Hypothesis → evidence → conclusion framing |
| **rigorous** | Maximum precision, explicit assumptions, audit-trail quality |
| **pipeline** | Minimal narrative — status blocks, tables, next actions |

All three carry the **Report Surfacing Protocol**: the orchestrator prints report artifacts (plans, verdict maps, reality reports, diagnoses, audits, narratives) verbatim before any next-step prompt.

## Plugin structure

```
rnd-framework/
├── .claude-plugin/plugin.json   # Manifest
├── agents/                      # 14 agents (10 pipeline + 4 helpers)
├── commands/                    # Pipeline commands
├── skills/                      # rnd-* skills
├── hooks/                       # hooks.json + gate/lifecycle scripts
├── lib/                         # rnd-dir.sh, bump.sh, validate.sh, stats/, schemas
├── output-styles/               # scientific, rigorous, pipeline
└── tests/                       # Bash test suite (run via tests/run-tests.sh)
```

## Customization

- **Agent models** — edit each agent's `model:` frontmatter, or rely on criticality-driven dispatch.
- **Iteration budget** — edit the limit in `/rnd-framework:rnd-start` (default 3).
- **New skills** — use the `rnd-writing-skills` skill.

## Requirements & limits

- **Minimum Claude Code:** v2.1.139 (`session-start.sh` warns when below). `--bare` mode skips all hooks, so the framework does not function there.
- **Best-effort enforcement** — the information barrier is path-based; hooks block direct reads but can't catch every indirect access.
- **No persistent session memory** — `.rnd/` provides continuity, but context resets between sessions; use `/rnd-framework:rnd-status` to re-orient.

## Acknowledgements

Ideas drawn from the [V-Model](https://en.wikipedia.org/wiki/V-model), [Design Structure Matrix](https://en.wikipedia.org/wiki/Design_structure_matrix), [NASA IV&V](https://www.nasa.gov/about-nasas-ivv-program/), [Stage-Gate](https://en.wikipedia.org/wiki/Phase-gate_process), and [Pre-Registration](https://en.wikipedia.org/wiki/Preregistration_(science)).
