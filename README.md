# rnd-framework — Claude Code Plugin

A multi-agent orchestration plugin for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). It structures coding around pre-registration, independent verification with information barriers, evidence-based quality gates, and structured decomposition.

> Experimental (0.x). Interfaces and quality gates change between releases.

## Install

```
/plugin marketplace add https://tangled.org/oleksify.me/rnd-framework
/plugin install rnd-framework@oleksify-plugins
```

Update with `/plugin update rnd-framework@oleksify-plugins`.

## Use

```
/rnd-framework:rnd-start <task description>
```

This runs the pipeline: **Plan → Build → Verify → Integrate**. Specialized agents handle each phase in isolated context windows, so the verifier can't see the builder's reasoning.

## Disable per project

```json
{
  "enabledPlugins": {
    "rnd-framework@oleksify-plugins": false
  }
}
```

Add to `.claude/settings.local.json` (per-machine) or `.claude/settings.json` (shared).

## Docs

See the [plugin README](plugins/rnd-framework/README.md) for the full reference: commands, agents, skills, artifact layout, and customization.

## License

MIT. See [LICENSE](LICENSE).
