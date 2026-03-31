# rnd-framework — Claude Code Plugin

A scientific-method orchestration plugin for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). Structures coding workflows around pre-registration, independent verification with information barriers, evidence-based quality gates, and structured decomposition.

## Features

- **Dual execution modes:** single-flow (sequential in one session) or multi-agent (8 specialized agents with structural isolation)
- **Pre-registration:** testable success criteria declared before implementation
- **Information barriers:** verification phase cannot read build-phase self-assessments
- **Quality gates:** evidence-based PASS/FAIL verdicts at every phase boundary
- **Structured decomposition:** hierarchical task trees with dependency-based scheduling

## Installation

### Add the marketplace

```
/plugin marketplace add https://tangled.sh/oleksify.me/claude-plugins
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

Start a pipeline:

```
/rnd-framework:rnd-start <task description>
```

The framework guides you through: Plan, Build, Verify, Integrate.

See the [plugin README](plugins/rnd-framework/README.md) for full documentation.

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

## License

MIT. See [LICENSE](LICENSE).
