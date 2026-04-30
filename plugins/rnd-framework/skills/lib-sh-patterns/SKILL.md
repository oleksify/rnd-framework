---
name: lib-sh-patterns
description: "Use when writing hooks or lib scripts — covers lib.sh shared utilities, path predicates, response functions, stdin parsing, and the active_session_dir caching pattern"
effort: low
---

# lib.sh Patterns

## Overview

`hooks/lib.sh` is the foundation sourced by every hook script. It provides path predicates, hook response output, stdin parsing, RND directory resolution with caching, and timestamps. Use these functions instead of reimplementing — they handle edge cases (malformed JSON, empty input, missing fields) that raw `jq` calls do not.

## Path Predicates

### is_plugin_artifact_path

Returns 0 if path is under `.rnd/` within a recognized config directory.

```bash
is_plugin_artifact_path "/home/user/.claude/.rnd/proj-abc123/sessions/20260101-120000-abcd/plan.md"  # true
is_plugin_artifact_path "/home/user/project/src/main.ts"  # false
```

Regex: `\.claude[^/]*/.*\.rnd/`

### is_plugin_cache_path

Returns 0 if path contains `plugins/cache/` under a config directory. Used for auto-allowing reads from cached plugin files.

### is_learnings_path

Returns 0 if path contains `learnings/` under a config directory. Used for auto-allowing reads from the cross-session learning library.

### is_code_file

Returns 0 if path has a recognized source code extension (ts, js, py, rb, go, rs, sh, ex, etc.).

## Hook Response Output

### allow_json

Prints the auto-allow JSON. No arguments needed.

```bash
allow_json
# Output: {"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}
```

### advisory_json

Prints advisory JSON with a properly JSON-escaped message.

```bash
advisory_json "Warning: output was 150 lines."
```

Uses `jq -Rs` internally for safe escaping of special characters, newlines, and quotes.

### block_msg

Prints message to stderr and exits 2. This is a terminal function — code after it never executes.

```bash
block_msg "BLOCKED: Do not write to /tmp/"
```

## Stdin Parsing

### parse_input

Reads all stdin, extracts fields via a single `jq` call, sets three globals:

```bash
parse_input
echo "$TOOL_NAME"   # "Read"
echo "$TOOL_INPUT"   # '{"file_path":"/foo/bar"}'
echo "$AGENT_TYPE"   # "assistant" or ""
```

On malformed input, all three are set to empty strings (never fails).

### extract_file_path

Extracts `file_path` from a tool_input JSON string:

```bash
fp="$(extract_file_path "$TOOL_INPUT")"
```

Returns empty string if field is missing. Always returns exit 0.

## RND Directory Resolution

### resolve_rnd_dir

Calls `lib/rnd-dir.sh` and prints the path. Accepts flags (`-c`, `--base`, `--finish`, `--roadmap`). Returns 1 on failure.

```bash
rnd_dir="$(resolve_rnd_dir -c)"     # Create session if needed
base_dir="$(resolve_rnd_dir --base)" # Just the project base dir
```

### active_session_dir

Returns the active session directory when one exists. Uses a two-tier cache for performance:

1. **Process-level cache** (`_ACTIVE_SESSION_CACHE`) — avoids repeated computation within a single hook invocation
2. **File-based fast-path** (`.active-base-dir`) — avoids the expensive `git rev-parse + shasum` computation (~15ms) by reading a cached base directory path written by `session-start.sh`

```bash
session_dir="$(active_session_dir 2>/dev/null || true)"
[[ -n "$session_dir" ]] || exit 0  # Fast-path: no active session
```

Returns 1 and prints nothing when no active session exists. The path always contains `/sessions/` and points to an existing directory.

## FP Primitives

### jq_extract

Fault-tolerant field extraction. Always returns exit 0, prints empty string on failure.

```bash
val="$(jq_extract '{"key":"value"}' '.key')"     # "value"
val="$(jq_extract 'not-json' '.key')"             # ""
val="$(jq_extract '{"a":"b"}' '.missing')"        # ""
```

Prefer this over raw `jq -r` calls — it handles malformed JSON and missing fields without error.

### guard_nonempty

Early-exit pattern for empty values. Returns 0 if non-empty, 1 if empty.

```bash
file_path="$(extract_file_path "$TOOL_INPUT")"
guard_nonempty "$file_path" "no file_path in input" || exit 0
# Only reaches here if file_path is non-empty
```

The optional second argument is printed to stderr when the value is empty.

### strip_frontmatter

Removes YAML frontmatter (lines between first `---` and second `---` inclusive) from stdin:

```bash
body="$(strip_frontmatter < skill.md)"
```

Passes through unchanged if no frontmatter delimiters are found.

## Timestamps

### iso_timestamp

Outputs ISO 8601 UTC timestamp:

```bash
ts="$(iso_timestamp)"  # "2026-03-28T14:30:00Z"
```

## Common Anti-Patterns

- **Raw `jq` instead of `jq_extract`** — `jq_extract` handles malformed JSON and missing fields; raw `jq` will fail on bad input and break hooks under `set -e`
- **Reimplementing path checks** — use `is_plugin_artifact_path`, `is_plugin_cache_path`, etc. The regex patterns handle all Claude Code path variants
- **Not using `guard_nonempty`** — manual `if [[ -z ... ]]` blocks are verbose; `guard_nonempty` enables clean early-exit with `||`
- **Constructing hook JSON manually** — use `allow_json`, `advisory_json`, `block_msg`. They handle JSON escaping correctly
- **Ignoring the `active_session_dir` cache** — calling `resolve_rnd_dir` repeatedly is ~15ms per call. Use `active_session_dir` which caches at process level

## Related Skills

- `rnd-framework:hook-authoring` — hook structure that uses these functions
- `rnd-framework:bash-hook-testing` — how to test these functions
- `rnd-framework:fp-practices` — general FP principles these primitives embody
