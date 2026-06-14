# rnd-framework — Claude Code Plugin

A multi-agent orchestration plugin for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). It structures coding around pre-registration, independent verification with information barriers, evidence-based quality gates, and structured decomposition.

## ⚠️ Before you install

This is a **highly experimental personal project**, built and dogfooded for my own workflow. No support, no stability promise, and it may not behave the way you expect.

- **It burns a lot of tokens.** Every task fans out across multiple agents — planning, building, verifying, cleanup, integration — each in its own context window. A single run can cost many times what one Claude session would. This is the point of the design, not a bug, but budget accordingly.
- **It's slow.** Sequential agent spawns and independent verification add real wall-clock time. It trades speed for rigor.
- **It's opinionated.** The pipeline imposes pre-registration, information barriers, and quality gates whether or not your task needs them. Small tasks get heavy ceremony.
- **It changes without notice.** Versioned 0.x on purpose — interfaces, protocols, and quality gates shift between releases, and things break.

If you want a fast, cheap, lightweight assistant, this isn't it. If you want maximum verification rigor and don't mind paying for it, read on.

## Install

```
/plugin marketplace add https://tangled.org/oleksify.me/rnd-framework.git
/plugin install rnd-framework@oleksify-plugins
```

Update with `/plugin update rnd-framework@oleksify-plugins`.

## Use

```
/rnd-framework:rnd-start <task description>
```

This runs the pipeline: **Scope → Plan → Schedule → Build → [Reality Audit] → Verify → [Iterate] → Cleanup → Polish → Integrate → [Post-Review]**. Specialized agents handle each phase in isolated context windows, so the verifier can't see the builder's reasoning.

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

**[rndf.tngl.io](https://rndf.tngl.io)** — the documentation site: concepts, getting started, commands, agents, skills, artifacts, and the information barrier.

Or read the [plugin README](plugins/rnd-framework/README.md) for the same reference in the repo.

## License

MIT. See [LICENSE](LICENSE).
