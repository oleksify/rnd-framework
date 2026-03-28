---
name: plugin-architecture
description: "Use when working with the multi-platform plugin structure — covers Claude Code, Factory Droid, and OpenCode differences, config dir detection, path matching, hooks.json, and the OpenCode bridge"
effort: low
---

# Plugin Architecture

## Overview

rnd-framework runs on three platforms from a single codebase: Claude Code, Factory Droid, and OpenCode. The abstraction layer lives in `plugin-dir-base.sh` (config dir detection), `hooks.json` (tool name matchers), and `opencode-bridge.ts` (JS-to-shell translation). Understanding these layers is required before modifying any platform-sensitive code.

## Plugin Manifest Files

Three manifest files must be kept in sync:

| File | Platform | Extra Fields |
|---|---|---|
| `.claude-plugin/plugin.json` | Claude Code | — |
| `.factory-plugin/plugin.json` | Factory Droid | No `owner` or `category` (validator rejects them) |
| `.opencode-plugin/plugin.json` | OpenCode | No `owner` or `category` |

All three contain `name`, `description`, `version` (strict semver `X.Y.Z`). The root-level `.claude-plugin/marketplace.json` and `.factory-plugin/marketplace.json` are registry files that reference the plugin path.

## Config Directory Detection

`plugin-dir-base.sh` resolves the config directory using this precedence:

```
1. CLAUDE_PLUGIN_ROOT (strip /plugins/cache/* suffix)
2. CLAUDE_CONFIG_DIR
3. DROID_CONFIG_DIR
4. OPENCODE_CONFIG_DIR
5. OPENCODE_CONFIG → ~/.config/opencode/
6. DROID_PLUGIN_ROOT → ~/.factory/
7. Default → ~/.claude/
```

The resolved `CONFIG_DIR` is the base for artifact storage: `$CONFIG_DIR/.rnd/<project-slug>/`.

## Project Slug Computation

```
<basename>-<8-char-sha256-hash>
```

- `basename`: derived from `git rev-parse --git-common-dir` parent directory name
- `hash`: first 8 chars of sha256 of the canonicalized git-common-dir path
- Worktree support: all worktrees of the same repo produce the same slug (git-common-dir is shared)
- Non-git fallback: uses `pwd` basename and hash

## Platform Environment Variables

| Variable | Platform | Purpose |
|---|---|---|
| `CLAUDE_PLUGIN_ROOT` | Claude Code (cached) | Points to cached plugin copy |
| `CLAUDE_CONFIG_DIR` | Claude Code | Config directory (~/.claude) |
| `DROID_CONFIG_DIR` | Factory Droid | Config directory |
| `DROID_PLUGIN_ROOT` | Factory Droid | Plugin root (aliased from CLAUDE_PLUGIN_ROOT) |
| `OPENCODE_CONFIG_DIR` | OpenCode | Explicit config dir override |
| `OPENCODE_CONFIG` | OpenCode | Signals OpenCode runtime (default XDG) |

## Path Matching Regex

Used in `lib.sh`, `bash-gate.sh`, and other hooks to detect plugin artifact paths:

```regex
(\.(claude[^/]*|factory)|\.config/opencode)/
```

This matches:
- `~/.claude/.rnd/` (Claude Code)
- `~/.claude-code/.rnd/` (Claude Code variants)
- `~/.factory/.rnd/` (Factory Droid)
- `~/.config/opencode/.rnd/` (OpenCode)

The `is_plugin_artifact_path` function in `lib.sh` extends this to match `.rnd/` and `.rnd/` subdirs.

## Hook Event Availability by Platform

| Hook Event | Claude Code | Factory Droid | OpenCode |
|---|---|---|---|
| SessionStart | Yes | Yes | Via `session.created` event |
| SessionEnd | Yes | No | No |
| PreToolUse | Yes | Yes | Via `tool.execute.before` |
| PostToolUse | Yes | No | Via `tool.execute.after` |
| PreCompact | Yes | No | Via `experimental.session.compacting` |
| PostCompact | Yes | No | Via `experimental.session.compacting` |
| CwdChanged | Yes (v2.1.83+) | No | No |
| FileChanged | Yes (v2.1.83+) | No | Via `file.edited` event |
| TaskCreated | Yes (v2.1.84+) | No | No |
| InstructionsLoaded | Yes | No | No |
| Setup | Yes | No | No |
| StopFailure | Yes | No | No |

When adding a new hook, check this table. If the event doesn't fire on a target platform, no code change is needed — the hook simply won't run.

## OpenCode Bridge

`opencode-bridge.ts` translates OpenCode's JS hook events to shell script calls:

```
tool.execute.before     → bash-gate.sh / read-gate.sh / write-gate.sh / glob-grep-gate.sh
tool.execute.after      → post-dispatch.sh
event (file.edited)     → file-changed.sh
session.compacting      → pre-compact.sh + post-compact.sh
chat.system.transform   → session-start.sh context injection
shell.env               → sets CLAUDE_PLUGIN_ROOT for shell tool executions
```

Key constraints:
- Advisory context from hooks cannot be injected mid-conversation in OpenCode — only block/allow decisions work via `tool.execute.before`
- The bridge sets `CLAUDE_PLUGIN_ROOT` when spawning scripts so they can locate plugin resources
- Tool names are translated from OpenCode lowercase to Claude Code PascalCase before passing to shell scripts

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
- `rnd-framework:lib-sh-patterns` — shared utilities used across platforms
