# Claude Code Plugins

A private collection of plugins for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and [Factory Droid](https://docs.factory.ai/welcome).

## Available Plugins

| Plugin | Description |
|---|---|
| [rnd-framework](plugins/rnd-framework/) | Multi-agent coding orchestration with structured decomposition, independent verification, and quality gates |
| [](plugins//) | Creative studio for designing in Framer: brief, moodboard, design tokens, component scaffolding, and code generation |

## Installation

### Add the marketplace

```
/plugin marketplace add git@github.com:oleksify/claude-plugins.git
```

### Install a plugin

```
/plugin install rnd-framework@oleksify-plugins
```

```
/plugin install @oleksify-plugins
```

Or use the interactive plugin manager:

```
/plugin
```

Navigate to the **Discover** tab, select the plugin, and choose an installation scope:

- **user** — active across all projects (default)
- **project** — shared via `.claude/settings.json` (committed to git)
- **local** — per-machine via `.claude/settings.local.json` (not committed)

### Update a plugin

```
/plugin update rnd-framework@oleksify-plugins
```

To enable auto-updates for this marketplace:

```
/plugin
```

Go to the **Marketplaces** tab, select the marketplace, and enable auto-update.

## Per-Project Configuration

Control which plugins are active per-project via the `enabledPlugins` setting.

Add to `.claude/settings.local.json` (per-machine, not committed) or `.claude/settings.json` (shared with team):

```json
{
  "enabledPlugins": {
    "rnd-framework@oleksify-plugins": false,
    "@oleksify-plugins": false
  }
}
```

Settings merge with more specific scopes winning: `.claude/settings.local.json` > `.claude/settings.json` > `~/.claude/settings.json`.

## License

Proprietary. See [LICENSE](LICENSE).
