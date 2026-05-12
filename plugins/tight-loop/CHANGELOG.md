# Changelog

## 0.0.2 — 2026-05-12

### Quote CLAUDE_PLUGIN_ROOT in hooks.json to match docs canonical form

Normalized every `${CLAUDE_PLUGIN_ROOT}` path placeholder in `hooks/hooks.json` from the previous single-quote wrap (`'${CLAUDE_PLUGIN_ROOT}'`) to the documented double-quote shell-form (`"${CLAUDE_PLUGIN_ROOT}"`). Aligns with the Claude Code plugins-reference canonical example and with rnd-framework's hooks.json. No behavior change in working sessions; defense against shell-tokenization edge cases.

## 0.0.1 — Initial release

First public version of tight-loop.
