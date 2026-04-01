---
description: "Check runtime environment readiness: CLI tools, hook scripts, artifact directory, plugin registration, version sync, and Julia MCP tools."
effort: low
---

# R&D Framework: Doctor

Run environment readiness checks and report status for each category.

## 1. CLI Tools

For each of the following tools, run `which <tool>` to check availability, then capture the version:

- `bash` — run `bash --version | head -1`
- `jq` — run `jq --version`
- `git` — run `git --version`
- `duckdb` — run `duckdb --version` (optional — warn but do not fail if missing)

## 2. Hook Scripts

Read the hooks configuration using the Read tool:

```
Read: "${CLAUDE_PLUGIN_ROOT}/hooks/hooks.json"
```

Extract all hook script paths referenced in the JSON (the `command` or `script` fields). For each script path, check that it exists and is executable:

```bash
ls -la "${CLAUDE_PLUGIN_ROOT}/hooks/"
```

Report how many hook scripts are present and executable out of the total referenced.

## 3. RND Artifact Directory

Run rnd-dir.sh to determine or create the artifact directory:

```bash
RND_DIR=$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh" -c)
```

Check if the command succeeded (exit code 0) and if `$RND_DIR` is a writable directory. Also check for an active session:

```bash
BASE_DIR=$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh" --base)
CURRENT_SESSION_FILE="${BASE_DIR}/.current-session"
```

Report whether `$RND_DIR` is writable and whether an active session exists.

## 4. Plugin Registration

Look for the local marketplace registry file. Check common paths:

- `"${CLAUDE_PLUGIN_ROOT}/../../.claude-plugin/marketplace.json"` (repo root)
- `~/.claude/marketplace.json`

Read the found marketplace.json and check that the `rnd-framework` plugin entry appears in it.

## 5. Version Sync

Read the plugin version from the installed plugin manifest using the Read tool:

```
Read: "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json"
```

Extract the `version` field. If running inside the plugin's own source repository, compare with the source version at the same path. Report whether they match.

## 6. Julia MCP Tools

Use `ToolSearch` with query `"julia eval"` to check whether Julia MCP tools are available at runtime. Report if `mcp__julia__julia_eval` or similar tools appear in the results.

## 7. Agent Health Check

List all agent files in the `agents/` directory:

```bash
ls "${CLAUDE_PLUGIN_ROOT}/agents/"
```

For each `.md` file found, verify:
1. The file has valid YAML frontmatter (starts with `---`, contains `name:`, `model:`, `tools:`, `skills:`, `memory:`, `maxTurns:`)
2. The `name:` field matches the filename stem (e.g., `rnd-builder.md` → `name: rnd-builder`)
3. No `permissionMode` field is present (not supported for plugin agents)
4. Each skill in the `skills:` list corresponds to an existing directory under `skills/`

Report the total number of agents found and how many pass all checks. If any agent has issues, list them.

Expected agents (8): `rnd-builder`, `rnd-verifier`, `rnd-planner`, `rnd-integrator`, `rnd-debugger`, `rnd-proof-gate`, `rnd-reality-auditor`, `rnd-data-scientist`.

## 8. Claude Code Version

Run the following to detect the installed Claude Code version:

```bash
claude --version
```

The output will be in the format `2.1.81 (Claude Code)`. Parse the version number from the first token.

Compare the detected version against these thresholds (in ascending order):

- **v2.1.77** — Hook allow/deny precedence changed: a hook returning `allow` no longer bypasses explicit deny rules. If the installed version is below this, warn that rnd-framework's auto-allow hooks (`read-gate.sh`, `bash-gate.sh`) may not work correctly and permission prompts will appear unexpectedly.
- **v2.1.81** — Plugin re-cloning and worktree resumption added. If the installed version is below this, warn that plugins are not re-cloned on each load (cache staleness is possible) and that `--resume` does not work across git worktrees.
- **v2.1.89** — PermissionDenied hook, defer permission decision, improved compound command `if` condition filtering, Edit-without-Read, symlink resolution for allow rules. **This is the minimum recommended version for full rnd-framework functionality.** If below this, warn that `PermissionDenied` hook will not fire (auto-mode denials are not retried), `defer` permission decision is unavailable (headless pipelines cannot pause), and `hooks.json` `if` conditions may not match compound commands or env-var prefixes correctly.

If the version is >= v2.1.89, report these features as available:
- `PermissionDenied` hook — auto-mode denials are logged and retried
- `defer` permission decision — headless sessions can pause at tool calls
- Improved hook `if` condition filtering for compound commands and env-var prefixes
- `--bare` mode awareness (hooks are skipped in bare mode — rnd-framework does not work in `--bare` sessions)
- `--channels` support for forwarding permission prompts to phone during remote pipeline runs
- Plugin re-cloning on every load (ref-tracked plugins are always fresh)

If the version is >= v2.1.81 but below v2.1.89, report the v2.1.81 features as available but warn about missing v2.1.89 features.

Use `⚠ warn` for any version below v2.1.89, `✅ ok` for v2.1.89+.

## Output Format

Display all results as a table:

```
Check                    | Status  | Details
-------------------------|---------|--------
bash                     | ✅ ok   | /opt/homebrew/bin/bash (5.2.26)
jq                       | ✅ ok   | /opt/homebrew/bin/jq (1.7)
git                      | ✅ ok   | /usr/bin/git (2.39.5)
duckdb                   | ⚠ warn  | not installed (optional)
Hook scripts             | ✅ ok   | 4/4 executable
RND artifact directory   | ✅ ok   | writable, active session exists
Plugin registration      | ✅ ok   | registered in marketplace.json
Version sync             | ✅ ok   | cached v0.8.3 = source v0.8.3
Agents                   | ✅ ok   | 8/8 agents valid (rnd-builder, rnd-verifier, ...)
Julia MCP tools          | ✅ ok   | mcp__julia__julia_eval available
Claude Code version      | ✅ ok   | v2.1.81 (bare/channels/re-cloning available)
```

Use `✅ ok` for passing checks, `⚠ warn` for optional/non-critical issues, and `❌ fail` for critical failures.

After displaying the table, use `AskUserQuestion` to suggest next steps based on results:

- If all checks pass (no `❌ fail`): "Run /rnd-framework:rnd-start (Recommended)", "Run /rnd-framework:rnd-validate"
- If any check fails: "Fix reported issues (Recommended)", and for each failure provide a targeted suggestion:
  - Missing CLI tool: "Install <tool> via homebrew: `brew install <tool>`"
  - Non-executable hook scripts: "Fix permissions: `chmod +x ${CLAUDE_PLUGIN_ROOT}/hooks/*`"
  - RND directory not writable: "Check disk space and permissions for `~/.claude/.rnd/`"
  - Plugin not registered: "Re-register the plugin in marketplace.json"
  - Version mismatch: "Restart Claude Code to reload the updated plugin"
  - Julia MCP unavailable: "Enable the Julia MCP server in your Claude Code settings"
