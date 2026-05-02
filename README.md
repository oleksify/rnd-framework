# rnd-framework — Claude Code Plugin

A scientific-method orchestration plugin for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). Structures coding workflows around pre-registration, independent verification with information barriers, evidence-based quality gates, and structured decomposition.

## Features

- **Dual execution modes:** single-flow (sequential in one session) or multi-agent (9 specialized agents with structural isolation)
- **Pre-registration:** testable success criteria declared before implementation begins
- **Information barriers:** verification phase cannot read build-phase self-assessments
- **Quality gates:** evidence-based PASS/FAIL verdicts at every phase boundary
- **Structured decomposition:** hierarchical task trees with dependency-based scheduling
- **Reality auditing:** adversarial verification of external service contracts (SQL, APIs, env vars)
- **Formal proofs:** optional Lean 4 verification of pre-registration criteria
- **Multi-session roadmaps:** decompose large tasks into milestones spanning multiple days

## Installation

### Add the marketplace

```
/plugin marketplace add https://tangled.org/oleksify.me/rnd-framework
```

### Install the plugin

```
/plugin install rnd-framework@oleksify-plugins
```

Or use the interactive plugin manager:

```
/plugin
```

Navigate to the **Discover** tab, select the plugin, and choose an installation scope:

- **user** — active across all projects (default)
- **project** — shared via `.claude/settings.json` (committed to git)
- **local** — per-machine via `.claude/settings.local.json` (not committed)

### Update the plugin

```
/plugin update rnd-framework@oleksify-plugins
```

## Usage

Start a full pipeline:

```
/rnd-framework:rnd-start <task description>
```

The framework guides you through: **Plan → Build → Verify → Integrate**.

## Commands

| Command | Purpose |
|---|---|
| `/rnd-framework:rnd-start <task>` | Full pipeline with mode selection |
| `/rnd-framework:rnd-plan <task>` | Planning only — decompose into task specifications |
| `/rnd-framework:rnd-build <T3\|wave-2\|next>` | Build a specific task or wave |
| `/rnd-framework:rnd-verify <T3\|wave-2\|all>` | Independent verification with information barriers |
| `/rnd-framework:rnd-integrate <wave-2\|final>` | Merge verified outputs, run integration tests |
| `/rnd-framework:rnd-status` | Pipeline status dashboard |
| `/rnd-framework:rnd-resume` | Resume a partially-completed pipeline |
| `/rnd-framework:rnd-history` | Browse past pipeline sessions |
| `/rnd-framework:rnd-debug <bug>` | Reproduce, diagnose, fix, verify |
| `/rnd-framework:rnd-roadmap <goal>` | Multi-session roadmap for large tasks |
| `/rnd-framework:rnd-scan` | Scan project environment, build project-facts.md |
| `/rnd-framework:rnd-review` | Evidence-based code review |
| `/rnd-framework:rnd-audit` | Full codebase audit |
| `/rnd-framework:rnd-brainstorm` | Funnel vague ideas into focused plans |
| `/rnd-framework:rnd-narrative` | Development narrative for a pipeline session |
| `/rnd-framework:rnd-bump` | Bump patch version, update CHANGELOG |
| `/rnd-framework:rnd-validate` | Validate plugin structure |
| `/rnd-framework:rnd-doctor` | Runtime environment diagnostics |
| `/rnd-framework:rnd-calibrate` | Record verdict corrections for calibration |

## Architecture

The framework applies scientific method principles to software engineering:

| Scientific Method | Framework Principle |
|---|---|
| Hypothesis declaration | **Pre-registration** — declare intent and criteria before coding |
| Structured experimentation | **Decomposition** — hierarchical sub-tasks with paired verification |
| Blinded peer review | **Information barriers** — verifier cannot see builder reasoning |
| Reproducible evidence | **Quality gates** — checkpoints requiring reproducible evidence |
| Dependency analysis | **Wave scheduling** — parallel vs sequential work identification |

### Execution Modes

**Single-flow mode** runs all phases sequentially in one session. No agents are spawned. Best for smaller tasks and quick iterations.

**Multi-agent mode** uses 9 specialized agents (planner, builder, verifier, cleanup, integrator, debugger, proof-gate, reality-auditor, data-scientist), each in isolated context windows with structural information barriers. Best for complex tasks requiring maximum verification rigor.

### Pipeline

```
Plan → Schedule → Build → [Reality Audit] → [Proof Gate] → Verify → Iterate? → Integrate
```

## Per-Project Configuration

Control whether the plugin is active per-project via the `enabledPlugins` setting.

Add to `.claude/settings.local.json` (per-machine) or `.claude/settings.json` (shared):

```json
{
  "enabledPlugins": {
    "rnd-framework@oleksify-plugins": false
  }
}
```

## Documentation

See the [plugin README](plugins/rnd-framework/README.md) for full documentation including skills, agents, artifact layout, and customization.

## License

MIT. See [LICENSE](LICENSE).
