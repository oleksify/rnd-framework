# Claude Code Plugins

A collection of plugins for [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

## Available Plugins

| Plugin | Description |
|---|---|
| [rnd-framework](plugins/rnd-framework/) | Multi-agent coding orchestration with structured decomposition, independent verification, and quality gates |

## Installation

Install a plugin by pointing Claude Code at its directory:

```bash
claude plugin install --dir /path/to/plugins/rnd-framework
```

Or install directly from the repository:

```bash
git clone https://tangled.sh/oleksify.me/claude-plugins
claude plugin install --dir claude-plugins/plugins/rnd-framework
```

## Per-Project Configuration

Control which plugins are active per-project via Claude Code's `enabledPlugins` setting.

Add to `.claude/settings.local.json` (per-machine, not committed) or `.claude/settings.json` (shared with team):

```json
{
  "enabledPlugins": {
    "plugin-name@source": false
  }
}
```

Settings merge with more specific scopes winning: `.claude/settings.local.json` > `.claude/settings.json` > `~/.claude/settings.json`.

## License

[MIT](LICENSE)
