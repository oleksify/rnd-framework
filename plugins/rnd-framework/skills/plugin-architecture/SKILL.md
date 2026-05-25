---
name: plugin-architecture
description: "Use when working with the plugin structure — covers config dir detection, path matching, hooks.json, and hook event availability"
effort: low
---

# Plugin Architecture

## Overview

rnd-framework is a Claude Code plugin. The abstraction layer lives in `plugin-dir-base.sh` (config dir detection) and `hooks.json` (tool name matchers). Understanding these layers is required before modifying any platform-sensitive code.

## Plugin Manifest

The plugin manifest lives at `.claude-plugin/plugin.json` and contains `name`, `description`, `version` (strict semver `X.Y.Z`). The root-level `.claude-plugin/marketplace.json` is a registry file that references the plugin path.

## Config Directory Detection

`plugin-dir-base.sh` resolves the config directory using this precedence:

```
1. CLAUDE_PLUGIN_ROOT (strip /plugins/cache/* suffix)
2. CLAUDE_CONFIG_DIR
3. Default → ~/.claude/
```

The resolved `CONFIG_DIR` is the base for artifact storage: `$CONFIG_DIR/.rnd/<project-slug>/`.

## Project Slug Computation

```
<basename>-<8-char-sha256-hash>
```

- `basename`: derived from `git rev-parse --git-common-dir` parent directory name
- `hash`: first 8 chars of sha256 of the canonicalized git-common-dir path
- Non-git fallback: uses `pwd` basename and hash

## Environment Variables

| Variable | Purpose |
|---|---|
| `CLAUDE_PLUGIN_ROOT` | Points to cached plugin copy |
| `CLAUDE_CONFIG_DIR` | Config directory (~/.claude) |

## Path Matching Regex

Used in `lib.sh`, `bash-gate.sh`, and other hooks to detect plugin artifact paths:

```regex
\.claude[^/]*/
```

This matches:
- `~/.claude/.rnd/` (Claude Code)
- `~/.claude-code/.rnd/` (Claude Code variants)

The `is_plugin_artifact_path` function in `lib.sh` extends this to match `.rnd/` subdirs.

## Hook Event Availability

| Hook Event | Available |
|---|---|
| SessionStart | Yes |
| SessionEnd | Yes |
| PreToolUse | Yes |
| PostToolUse | Yes |
| PreCompact | Yes |
| PostCompact | Yes |
| CwdChanged | Yes (v2.1.83+) |
| FileChanged | Yes (v2.1.83+) |
| TaskCreated | Yes (v2.1.84+) |
| InstructionsLoaded | Yes |
| Setup | Yes |
| StopFailure | Yes |

## settings.json

Plugin-level settings:

```json
{
  "spinnerVerbs": ["Planning", "Building", "Verifying", ...],
  "statusLines": ["${CLAUDE_PLUGIN_ROOT}/hooks/statusline.sh"]
}
```

`statusLines` scripts receive rate limit JSON on stdin and output `{"text":"..."}` for the status bar.

## --bare Mode

When Claude Code launches with `--bare`, all hooks are skipped. rnd-framework effectively does not work — information barrier is not enforced, tool discipline is bypassed, session bootstrap doesn't run. This is expected for scripted `-p` invocations.

## Hook Allow/Deny Precedence (v2.1.77+)

```
deny rules > hook allow > default permission prompt
```

If a user policy has a deny rule covering `.rnd/` paths, hook auto-allows are silently overridden. Workaround:

```json
{ "allowRead": ["~/.claude/.rnd/**"], "allowWrite": ["~/.claude/.rnd/**"] }
```

## Related Skills

- `rnd-framework:hook-authoring` — writing and registering hooks
- `rnd-framework:plugin-versioning` — keeping manifests in sync, version bumping
- `rnd-framework:lib-sh-patterns` — shared utilities used in hooks and lib scripts
