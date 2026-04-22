# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A Claude Code plugin repository containing **rnd-framework** — a scientific-method orchestration system for structured coding. It structures workflows around pre-registration, independent verification with information barriers, evidence-based quality gates, and structured decomposition. Uses a multi-agent execution model: 8 specialized agents with structural isolation enforce the information barrier at the context-window level.

The plugin lives under `plugins/rnd-framework/`. The root `.claude-plugin/marketplace.json` is a local plugin registry. Plugins can also be declared inline in `settings.json` using `source: 'settings'` (v2.1.80+).

## Repository Layout

```
lib/
└── plugin-dir-base.sh              # Canonical copy of shared artifact directory logic (each plugin has its own copy for cache compatibility)

plugins/rnd-framework/
├── .claude-plugin/plugin.json   # Plugin manifest (name, version, description)
├── agents/                      # 8 specialized agents for multi-agent execution mode
├── commands/                    # Slash commands (/rnd-framework:rnd-start, etc.)
├── skills/                      # Skills, each in its own dir with SKILL.md
├── output-styles/               # 3 custom output styles (scientific, rigorous, pipeline)
├── hooks/
│   ├── hooks.json               # Hook routing: SessionStart/End, Setup, InstructionsLoaded, PreToolUse, PostToolUse, PreCompact/PostCompact, StopFailure, CwdChanged, FileChanged, TaskCreated, SubagentStart/Stop, PermissionDenied
│   ├── lib.sh                   # Shared bash utilities (input parsing, path checks, decision output incl. defer, FP primitives)
│   ├── read-gate.sh             # Read hook: information barrier + .rnd/, plugin cache, and learnings auto-allow
│   ├── bash-gate.sh             # Bash hook: blocks sed/awk/echo>/inline interpreters/for-while-until loops//tmp redirects (including after env-var prefixes), auto-allows .rnd/ paths only; also handles commit protection (git add .rnd/ block, git push advisory)
│   ├── session-start.sh         # SessionStart hook: injects skill context + Claude Code version check
│   ├── session-end.sh           # SessionEnd hook: clears active RND session on close/switch
│   ├── post-dispatch.sh         # PostToolUse hook: audit logging for Write/Edit operations + advises when output exceeds 50 lines
│   ├── stop-failure.sh          # StopFailure hook: logs API errors to stop-failures.jsonl, emits advisory
│   ├── setup.sh                 # Setup hook: validates plugin structure and dependencies
│   ├── instructions-loaded.sh   # InstructionsLoaded hook: reminds to extract project standards
│   ├── pre-compact.sh           # PreCompact hook: saves pipeline state before context compaction
│   ├── post-compact.sh          # PostCompact hook: restores pipeline state after compaction
│   ├── cwd-changed.sh           # CwdChanged hook (v2.1.83+): warns on cross-repo directory change
│   ├── file-changed.sh          # FileChanged hook (v2.1.83+): advises on external .rnd/ artifact edits
│   ├── task-created.sh          # TaskCreated hook (v2.1.84+): logs task creation to audit.jsonl
│   ├── permission-denied.sh     # PermissionDenied hook (v2.1.89+): logs auto-mode denials to audit.jsonl, returns {retry: true}
│   ├── write-gate.sh             # Write/Edit hook: auto-allows .rnd/ path operations
│   ├── glob-grep-gate.sh        # Glob/Grep hook: information barrier + .rnd/ auto-allow
│   ├── format-on-save.sh        # PostToolUse hook (v2.1.90+): auto-formats code files after Write/Edit using detected project formatter
│   ├── session-title.sh         # UserPromptSubmit hook (v2.1.94+): sets session title to pipeline phase + project name
│   ├── subagent-lifecycle.sh    # SubagentStart/SubagentStop hook: logs agent lifecycle to audit.jsonl
│   └── statusline.sh            # Statusline script: rate limit usage + pipeline phase + worktree indicator (v2.1.80)
├── lib/
│   ├── rnd-dir.sh               # Artifact directory path computation + session management
│   ├── plugin-dir-base.sh       # Local copy of shared artifact dir logic (cache-compatible)
│   ├── bump.sh                  # Patch version increment + CHANGELOG entry + git stage
│   ├── validate.sh              # Plugin structure validation (frontmatter, hooks, cross-references)
│   └── validate-xrefs.sh        # Cross-reference and content parity validation (sourced by validate.sh)
├── proofs/                      # Lean 4 formal verification of pipeline invariants
└── README.md
```

## Architecture

### Execution Model

Eight specialized agents handle each pipeline phase in isolated context windows. The orchestrator dispatches work to agents, enforcing structural information barriers — the Verifier literally cannot see the Builder's reasoning because they run in separate context windows.

| Phase | Agent | Purpose |
|---|---|---|
| Planning | `rnd-planner` (sonnet/high) | Decomposes tasks into pre-registered sub-tasks with testable criteria |
| Building | `rnd-builder` (sonnet) | Implements tasks using TDD; produces build manifest + self-assessment |
| Reality Audit | `rnd-reality-auditor` (sonnet) | Per-task audit of declared external references (URLs, APIs, schemas, env vars, data); only runs when the task declares `External dependencies` |
| Proof Gate | `rnd-proof-gate` (sonnet) | Formal Lean 4 proofs of pre-registration criteria (advisory); only runs when the task has `Proof: lean` and Lean is on PATH |
| Verification | `rnd-verifier` (sonnet/high) | Checks output against pre-registered criteria (information barrier enforced); single-judge by default, multi-judge consensus available via `--multi-judge` |
| Integration | `rnd-integrator` (sonnet) | Merges verified outputs, runs integration/system tests |
| Debugging | `rnd-debugger` (sonnet/high) | Root cause analysis for failing tasks |
| Data Science | `rnd-data-scientist` (sonnet) | Standalone specialist for numerical/analytical work |

### Information Barrier and Permission Hooks

The `hooks.json` routes each PreToolUse event to an external script. Policies enforced:
- **Information barrier** (`read-gate.sh`, `glob-grep-gate.sh`, `bash-gate.sh`): Blocks any tool call where the file path or command string contains `self-assessment` OR the path segment `/briefs/` when the agent is a verifier or has no agent_type, preventing the verification phase from anchoring on build-phase reasoning. Both patterns share the same barrier semantics. The `/briefs/` segment (with slashes) is matched so the bare word "brief" in a grep pattern is not flagged. Enforced across all file-reading tools: `Read` (path check), `Grep`/`Glob` (path and pattern check), `Bash` (command string check). The `/briefs/` protection covers the Planner/Builder/Debugger/Integrator user-facing brief artifacts under `$RND_DIR/briefs/` and the cross-phase `decisions.md` log located there.
- **Auto-allow plugin artifact paths and cache operations** (`read-gate.sh`, `write-gate.sh`, `bash-gate.sh`, `glob-grep-gate.sh`, `settings.json`): `Read` operations on `.rnd/` artifact paths are auto-allowed via hook. `Write` and `Edit` operations on `.rnd/` paths are auto-allowed via hook (`write-gate.sh`) with `settings.json` `allowWrite` as belt-and-suspenders. `Glob` and `Grep` operations targeting these paths are auto-allowed via hook. For `Bash`, `.rnd/` auto-allow fires at the command level after tool-discipline segment checks have all passed — so sed and inline interpreters are still blocked even when a `.rnd/` path appears in the command. `read-gate.sh` additionally auto-allows reads from the plugin cache (`plugins/cache/`) for skill and agent files, and from the learnings directory (`$CLAUDE_CONFIG_DIR/learnings/`) for cross-session knowledge
- **Tool discipline** (`bash-gate.sh`): Blocks `sed`, `awk`, `echo/printf` with file redirects, inline interpreter execution (`python -c`, `node -e`, `bun -e`, bare interpreter as pipe target), shell loops (`for`/`while`/`until`), and `/tmp/` redirects — enforces use of dedicated Claude Code tools and `$RND_DIR` for temp storage. Read-side commands (`cat`, `head`, `tail`, `grep`, `rg`, `find`) pass through without opinion. Splits compound commands (`&&`, `||`, `;`, `|`) and checks each segment, including `$()` and backtick substitutions. Strips environment-variable prefixes (`FOO=bar command`) before checking each segment, ensuring tool discipline applies regardless of env-var assignments. File execution (`python file.py`, `bun test`, `python -m pytest`) is allowed. Also handles commit protection: blocks `git add` of `.rnd/` artifact directories and emits an advisory warning on `git push` to main/master/production branches. **Note on Edit-without-Read (v2.1.89+):** Claude Code v2.1.89 allows Edit on files viewed via `sed -n` or `cat` without a separate Read call. Since bash-gate blocks `sed`, this upstream feature does not affect rnd-framework users — the model must still use Read → Edit.
- **Audit logging** (`post-dispatch.sh`): PostToolUse hook logs all Write and Edit operations to `$RND_DIR/audit.jsonl` and advises when command output exceeds 50 lines
- **Stop failure logging** (`stop-failure.sh`): StopFailure hook logs API errors (rate limits, auth failures) to `$RND_DIR/stop-failures.jsonl` and emits advisory context
- **Directory change detection** (`cwd-changed.sh`): CwdChanged hook (v2.1.83+) warns when the working directory moves to a different git repository while an RND session is active
- **Artifact change detection** (`file-changed.sh`): FileChanged hook (v2.1.83+) emits advisory context when `.rnd/` artifact files (plan.md, iteration-log.md) are modified externally
- **Task creation logging** (`task-created.sh`): TaskCreated hook (v2.1.84+) logs task creation events to `$RND_DIR/audit.jsonl`
- **Agent lifecycle logging** (`subagent-lifecycle.sh`): SubagentStart and SubagentStop hooks log agent spawn/completion events to `$RND_DIR/audit.jsonl` for pipeline observability. No-opinion — does not affect permission flow.
- **Permission denial handling** (`permission-denied.sh`): PermissionDenied hook (v2.1.89+) fires after auto-mode classifier denials. Logs the denied tool name and timestamp to `$RND_DIR/audit.jsonl` and returns `{retry: true}` so the model can retry the tool call with adjusted parameters. This prevents auto-mode denials from silently breaking pipeline execution.
- **Format-on-save** (`format-on-save.sh`): PostToolUse hook (v2.1.90+) for Write and Edit events. Auto-detects the project's code formatter and runs it on changed code files. Detection is cached at session level. Skips non-code files and `.rnd/` artifacts. Non-blocking — formatting errors do not affect the pipeline.
- **Session title** (`session-title.sh`): UserPromptSubmit hook (v2.1.94+) that dynamically sets the session title to reflect the current pipeline phase and project name. When no active RND session exists, the title is `RND: <project>`. During pipeline execution, it becomes `RND: <phase> | <project>` (e.g., `RND: Building | my-project`). This makes sessions identifiable in the `/resume` picker. Always exits 0 — does not block prompt submission.

#### Claude Code Version Check

The `session-start.sh` hook checks the installed Claude Code version (via `claude --version`) and emits a warning in `additionalContext` if the version is below the minimum recommended (currently v2.1.117). The warning lists features that may not work correctly on older versions. If `claude` is not in PATH or returns an error, the check degrades gracefully with no warning.

#### Symlink Resolution for Allow Rules (v2.1.89+)

As of v2.1.89, Claude Code's `allowWrite` and `allowRead` rules check the resolved symlink target, not just the requested path. The plugin's `settings.json` rule `allowWrite: ["~/.claude*/.rnd/**"]` will correctly match even if the `.claude` or `.rnd` directories are symlinks, as long as the resolved target matches the pattern.

#### Hook Output Size Limit (v2.1.89+)

Hook output exceeding 50K characters is saved to disk with a file path + preview instead of being injected directly into context. The `session-start.sh` output (skill content + warnings) is well below this threshold (~5-10K chars). If a future change increases hook output significantly, the 50K behavior ensures context is not bloated.

#### Format-on-Save Hook (v2.1.90+)

The `format-on-save.sh` hook fires as a PostToolUse handler for Write and Edit events. It auto-detects the project's code formatter by scanning for config files (biome, prettier, deno, mix, cargo, ruff, black, gofmt, clang-format, or a `format`/`fmt` script in package.json) and runs the detected formatter on the changed file. Formatter detection is cached at session level in `$RND_DIR/.formatter-cache` to avoid re-scanning on every write. The hook skips non-code files and `.rnd/` artifact paths, and is non-blocking — formatting errors do not affect the pipeline. This hook requires v2.1.90+ because earlier versions had a bug where `Edit`/`Write` would fail with "File content has changed" when a PostToolUse hook rewrote the file.

#### Auto-Mode Boundary Respect (v2.1.90+)

As of v2.1.90, Claude Code's auto mode respects explicit user boundaries (e.g., "don't push", "wait for X before Y") even when the action would otherwise be allowed by the auto-mode classifier. Pipeline agents are now spawned with `mode: "acceptEdits"` (empirically `mode: "auto"` denied project-file Edit/Write on 2.1.112 team-spawned subagents), but Bash still routes through the classifier — so the boundary-respect behavior still applies to agent shell commands.

#### Offline Plugin Resilience (v2.1.90+)

The `CLAUDE_CODE_PLUGIN_KEEP_MARKETPLACE_ON_FAILURE` environment variable (v2.1.90+) preserves the existing marketplace plugin cache when a `git pull` fails during plugin refresh. This is useful for offline environments, CI pipelines, or unreliable networks — the plugin continues to work from its last cached version rather than failing entirely.

#### Exit-Code-2 Hook Fix (v2.1.90+)

v2.1.90 fixed a bug where PreToolUse hooks that emitted JSON to stdout and exited with code 2 did not correctly block the tool call. **This bug did not affect rnd-framework hooks** because `block_msg` in `lib.sh` writes plain text to stderr (not JSON to stdout) when blocking. The information barrier (`read-gate.sh`) and tool discipline (`bash-gate.sh`) were working correctly on versions below v2.1.90.

#### Subagent Spawning Fix (v2.1.92+)

v2.1.92 fixed subagent spawning permanently failing with "Could not determine pane count" after tmux windows are killed or renumbered during a long-running session. This directly improves multi-agent mode reliability — prior to this fix, killing or rearranging tmux panes mid-pipeline could permanently break agent spawning for the rest of the session.

#### Stop Hook Semantics Fix (v2.1.92+)

v2.1.92 restored `preventContinuation:true` semantics for non-Stop prompt-type hooks and fixed prompt-type Stop hooks incorrectly failing when the small fast model returns `ok:false`. This ensures hook-driven control flow works correctly in pipeline contexts.

#### Tool Input Validation Fix (v2.1.92+)

v2.1.92 fixed tool input validation failures when streaming emits array/object fields as JSON-encoded strings. This prevents spurious validation errors in hooks that parse `tool_input` from stdin during streaming responses.

#### Write Tool Performance (v2.1.92+)

Write tool diff computation is 60% faster for files containing tabs, `&`, or `$` characters. This benefits pipeline builds that write to files with these characters (common in bash scripts and shell tests).

#### Default Effort Level Change (v2.1.94+)

v2.1.94 changed the default effort level from medium to high for API-key, Bedrock/Vertex/Foundry, Team, and Enterprise users. This affects pipeline agents spawned without an explicit effort level — they now reason more deeply by default. Users can control this with `/effort`.

#### keep-coding-instructions Output Style Frontmatter (v2.1.94+)

v2.1.94 added `keep-coding-instructions` frontmatter field support for plugin output styles. When set to `true`, the coding instructions section of the output style is preserved across context compaction rather than being discarded. All three rnd-framework output styles (scientific, rigorous, pipeline) have this field set to `true`.

#### Skill Invocation Name from Frontmatter (v2.1.94+)

v2.1.94 changed plugin skills declared via `"skills": ["./"]` to use the skill's frontmatter `name` field for the invocation name instead of the directory basename. This gives a stable name across install methods (marketplace vs local). rnd-framework skills already use explicit directory names matching their frontmatter names, so this change has no practical impact on the plugin.

#### UserPromptSubmit Session Title (v2.1.94+)

v2.1.94 added `hookSpecificOutput.sessionTitle` support for `UserPromptSubmit` hooks. The hook can return `{hookSpecificOutput:{sessionTitle:"..."}}` to set the session title dynamically. The rnd-framework `session-title.sh` hook uses this to display the current pipeline phase and project name in the `/resume` picker.

#### Plugin Skill Hooks Fix (v2.1.94+)

v2.1.94 fixed plugin skill hooks defined in YAML frontmatter being silently ignored. Skills that declare hooks in their frontmatter now have those hooks correctly registered. rnd-framework skills do not currently use frontmatter-defined hooks, but this fix unblocks future use.

#### CLAUDE_PLUGIN_ROOT Resolution Fix (v2.1.94+)

v2.1.94 fixed `${CLAUDE_PLUGIN_ROOT}` resolving to the marketplace source directory instead of the installed cache for local-marketplace plugins on startup. This ensures hooks and lib scripts receive the correct plugin root path regardless of install method.

#### Statusline refreshInterval and git_worktree (v2.1.97+)

v2.1.97 added `refreshInterval` as a per-status-line setting — an integer specifying seconds between automatic statusline re-runs. The rnd-framework `settings.json` sets `refreshInterval: 5` so the statusline auto-refreshes every 5 seconds during pipeline execution.

v2.1.97 also added `workspace.git_worktree` to the statusline JSON input, set when the current directory is inside a linked git worktree. The rnd-framework `statusline.sh` extracts this and appends `[wt: <name>]` to the status text when present.

#### Subagent Working Directory Isolation Fix (v2.1.97+)

v2.1.97 fixed subagents with worktree isolation or `cwd:` override leaking their working directory back to the parent session's Bash tool. This directly improves multi-agent mode — prior to this fix, an agent spawned with a different cwd could corrupt the orchestrator's working directory state.

#### Compaction Transcript Dedup Fix (v2.1.97+)

v2.1.97 fixed compaction writing duplicate multi-MB subagent transcript files on prompt-too-long retries. This reduces transcript bloat in multi-agent pipelines where context compaction triggers mid-run.

#### Stop/SubagentStop Hook Reliability Fix (v2.1.97+)

v2.1.97 fixed prompt-type Stop/SubagentStop hooks failing on long sessions, and hook evaluator API errors displaying "JSON validation failed" instead of the actual message. This improves hook reliability in long-running pipeline sessions.

#### 429 Retry Exponential Backoff Fix (v2.1.97+)

v2.1.97 fixed 429 retries burning all attempts in ~13 seconds when the server returns a small Retry-After. Exponential backoff now applies as a minimum. This prevents pipeline agents from exhausting retry budget on transient rate limits.

#### Accept Edits Mode Env-Var Improvement (v2.1.97+)

v2.1.97 improved Accept Edits mode to auto-approve filesystem commands prefixed with safe env vars or process wrappers (e.g., `LANG=C rm foo`, `timeout 5 mkdir out`). This is orthogonal to the rnd-framework `bash-gate.sh` `strip_env_prefix()` function, which strips env-var prefixes for tool discipline enforcement (determining which tool to use), not for permission decisions.

#### Plugin Update Fix (v2.1.97+)

v2.1.97 fixed `claude plugin update` reporting "already at the latest version" for git-based marketplace plugins when the remote had newer commits.

#### Bash find -exec/-delete Security Tightening (v2.1.113+)

v2.1.113 stopped auto-approving destructive `find` invocations (`-exec`, `-delete`) under `Bash(find:*)` allow rules. The plugin's `bash-gate.sh` already blocks `find` unconditionally in favor of the `Glob` tool, so this upstream change has no impact on rnd-framework users — the blanket block remains load-bearing for non-destructive `find` patterns too.

#### Subagent Stall Timeout (v2.1.113+)

v2.1.113 added a 10-minute stall timeout for subagents stuck mid-stream; prior to this, they could hang silently. This surfaces a concrete error when an agent wedges, improving pipeline observability. It does **not**, on its own, resolve the `rnd-integrator` hang documented in project memory — the integrator still requires a live re-test before any decision to re-enable spawned integration.

#### Native CLI Binary (v2.1.113+)

v2.1.113 shipped Claude Code as a native per-platform binary (via optional dependencies) rather than bundled JavaScript. This reduces cold-start latency for `claude` invocations, including the `claude --version` check in `session-start.sh`.

#### sandbox.network.deniedDomains (v2.1.113+)

v2.1.113 added `sandbox.network.deniedDomains` to `settings.json` — a blocklist that overrides broader `allowedDomains` wildcards. The plugin now ships a conservative default denylist (`pastebin.com`, `hastebin.com`, `0x0.st`, `transfer.sh`) as defense-in-depth against accidental exfiltration of evidence or self-assessments by Builder / Reality-Auditor agents using `WebFetch` or `Bash`. Users can prune or extend the list in their local settings.

#### Opus-4.7 1M-Context Fix (v2.1.117+)

v2.1.117 fixed Opus-4.7 failing to use its full 1M-token context window in Claude Code sessions. This is the primary driver for raising the minimum recommended version to v2.1.117 — pipelines using Opus-4.7 as the orchestrator or a high-reasoning agent could silently truncate context on earlier versions. Update via `claude update`.

#### file_path Handling

Tool schemas require absolute paths and the model typically complies. However, hooks receive raw `tool_input` without mechanical path normalization — relative paths could theoretically reach hooks. The regex matchers in `lib.sh` (`is_plugin_artifact_path`, `is_plugin_cache_path`, `is_learnings_path`) guard against this by rejecting paths that don't start with `/`. If a relative path reaches a hook, the conservative behavior is to not auto-allow (falls through to the default permission prompt).

#### Plugin Settings Defaults

The plugin ships `settings.json` with pipeline-optimized defaults: `showThinkingSummaries: true` (v2.1.88 disabled this by default), `showTurnDuration: true`, `spinnerTipsEnabled: false`, `statusLines` with `refreshInterval: 5` (v2.1.97+). These are defaults — user settings take precedence.

#### Hook Allow/Deny Precedence (v2.1.77+)

As of Claude Code v2.1.77, a PreToolUse hook returning `allow` no longer bypasses explicit deny rules. The effective precedence is:

**deny rules > hook allow > default permission prompt**

This affects the two hooks that auto-allow `.rnd/` operations: `read-gate.sh` and `bash-gate.sh`. If a user or enterprise policy has a deny rule covering `.rnd/` paths, those hooks' auto-allows will be silently overridden and permission prompts will reappear.

**Workaround:** Use the `allowRead` and `allowWrite` sandbox settings to explicitly re-allow `.rnd/` paths. These settings take precedence over deny rules and restore the intended auto-allow behavior:

```json
{ "allowRead": ["~/.claude/.rnd/**"], "allowWrite": ["~/.claude/.rnd/**"] }
```

### --bare Mode (v2.1.81+)

When Claude Code is launched with `--bare`, all hooks are skipped — SessionStart, read-gate.sh, bash-gate.sh, post-dispatch.sh, and all others. Practical consequences:

- The information barrier is not enforced: verification phase can read build-phase self-assessments
- Tool discipline is not enforced: sed/cat/grep/find/inline interpreters bypass is possible
- Session bootstrap does not run: skills are not injected into context

Bottom line: rnd-framework effectively does not work in `--bare` mode. This is expected — `--bare` is designed for scripted `-p` invocations, not interactive pipeline orchestration.

### Skill System

Skills are directories under `skills/` containing a `SKILL.md` with YAML frontmatter (`name`, `description`, `effort`). Claude Code's native plugin system discovers skills by directory convention. The `effort` field (added in v2.1.80) overrides the model's reasoning effort when the skill is invoked: `low` for reference/guidance skills, `medium` for procedural workflows. Commands also support `effort` frontmatter: `low` for read-only operations, `medium` for moderate reasoning, `high` for deep pipeline orchestration.

The `rnd-roadmapping` skill defines the roadmap.md format, milestone statuses, and how to create and update roadmaps across sessions.

The `rnd-learning` skill enables auto-capture of pipeline-discovered gotchas to the user's Learning Library during iteration cycles.

The `rnd-formatting` skill detects the project's code formatter and runs it on pipeline-changed files before doc-polish and committing.

**Shadowing rule:** Personal skills (in user's `.claude/skills/`) override rnd-framework skills unless explicitly prefixed with `rnd-framework:`.

**Plugin freshness (v2.1.81+):** Ref-tracked plugins re-clone on every load, so the cached plugin version is always current. Version mismatch warnings (from `hooks/session-start.sh`) should be rare in v2.1.81+ setups; if they appear, it likely indicates a bug rather than a stale install.

### Session Bootstrap

The `SessionStart` hook fires on `startup|resume|clear|compact` and runs `hooks/session-start.sh`, which reads and injects the `using-rnd-framework` skill content into session context as a system reminder. It also checks the installed Claude Code version against the minimum recommended (v2.1.117) and emits a warning if below threshold.

The `SessionEnd` hook fires when a session closes or switches (including via `/resume`) and runs `hooks/session-end.sh`, which calls `rnd-dir.sh --finish` to clear the active session marker. This prevents stale `.current-session` files from persisting across sessions.

**Remote pipelines with `--channels` (v2.1.81+):** The `--channels` flag enables permission-relay mode, forwarding tool approval prompts to the Claude mobile app. This is useful when running rnd-framework pipelines on remote or headless machines where interactive terminal input is unavailable.

### Runtime Artifacts

The framework stores artifacts in a centralized directory outside the project tree, computed by `lib/rnd-dir.sh`. Each project gets an isolated artifact space based on a hash of its path. Each pipeline run gets a unique session ID, preserving history across runs.

**Helper:** `"${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh"` — outputs absolute `$RND_DIR` path. Flags: `-c` (create), `--finish` (clear session), `--base` (project base dir), `--roadmap` (path to roadmap.md at project base), `--facts` (path to project-facts.md at project base).

```
~/.claude/.rnd/<basename>-<hash>/          # Project base; slug = git-common-dir basename + 8-char sha256 of canonicalized git-common-dir; falls back to pwd basename + hash when not in a git repo
├── .current-session                       # Active session ID
├── .session-git-root                      # Git root of the project that started the session (written by session-start.sh, read by cwd-changed.sh)
├── roadmap.md                             # Multi-session roadmap (optional, created by /roadmap)
├── project-facts.md                       # Persistent project environment scan (created by /rnd-scan)
├── calibration.jsonl                      # Verdict accuracy tracking (legacy; new installs use $CLAUDE_PLUGIN_DATA)
└── sessions/<YYYYMMDD-HHMMSS-XXXX>/      # $RND_DIR (one per pipeline run)
    ├── plan.md                            # Task tree, environment, testing strategy, worker guidelines, validation contract, pre-registrations (with preconditions), schedule
    ├── diagnosis/T*-diagnosis.md          # Debugger root cause analysis (debug pipeline only)
    ├── builds/T*-manifest.md              # Builder output records
    ├── builds/T*-self-assessment.md       # Builder uncertainties (blocked from Verifier)
    ├── verifications/T*-verification.md   # Verifier evidence-based verdicts
    ├── verifications/T*-experiments/      # Verifier-written independent experiment tests
    ├── verifications/T*-evidence/         # Per-VAL-assertion evidence files (raw command output)
    ├── proofs/T*-proof-report.md          # Proof Gate results (Lean 4 formal verification)
    ├── proofs/T*-theorems/                # Lean theorem files
    ├── integration/wave-*-report.md       # Integration results, SHIP/NO-SHIP
    ├── briefs/                             # Barrier-protected Builder-reasoning artifacts (blocked from Verifier by read-gate/glob-grep-gate/bash-gate hooks)
    │   ├── decisions.md                    # Cross-phase structured judgment-call log (Planner/Builder/Debugger/Integrator append when rejecting real alternatives)
    │   ├── plan-briefs.md                  # Planner user-facing narrative briefs
    │   ├── T<id>-briefs.md                 # Per-task user-facing narrative briefs (Builder/Debugger)
    │   └── wave-<N>-briefs.md              # Per-wave user-facing integration briefs
    └── iteration-log.md                   # Build-verify cycle tracking
```

Since `$RND_DIR` is outside the project, no `.gitignore` entry is needed.

**Worktree support:** All worktrees of the same repository share the same `.rnd/` base directory. The project slug is derived from `git rev-parse --git-common-dir` (canonicalized to an absolute path via the POSIX `cd + pwd` idiom), so linked worktrees and the main checkout produce identical slugs even though their `pwd` values differ.

## Commands

Slash commands use the full plugin namespace: `/rnd-framework:rnd-start`, `/rnd-framework:rnd-plan`, `/rnd-framework:rnd-build`, `/rnd-framework:rnd-verify`, `/rnd-framework:rnd-integrate`, `/rnd-framework:rnd-status`, `/rnd-framework:rnd-resume`, `/rnd-framework:rnd-history`, `/rnd-framework:rnd-validate`, `/rnd-framework:rnd-doctor`, `/rnd-framework:rnd-bump`, `/rnd-framework:rnd-review`, `/rnd-framework:rnd-audit`, `/rnd-framework:rnd-brainstorm`, `/rnd-framework:rnd-narrative`, `/rnd-framework:rnd-calibrate`, `/rnd-framework:rnd-debug`, `/rnd-framework:rnd-roadmap`, `/rnd-framework:rnd-scan`.

## Key Conventions

- **Skills use YAML frontmatter** — `name`, `description`, and `effort` fields between `---` delimiters
- **Commands are Markdown files** in `commands/` — filename becomes the command name
- **Plugin manifest** at `.claude-plugin/plugin.json` — only `name`, `description`, `version`
- **Test suite** — `tests/` contains bash tests for hooks and lib scripts; run with `tests/run-tests.sh` from `plugins/rnd-framework/`
- **Tooling hierarchy** — system CLI tools first (`prefer-system-tools`), then bash scripts, then Python as last resort
- **File creation** — always use `Write`/`Edit` tools, never bash heredocs (`cat > file << 'EOF'`)

## Working on This Codebase

When modifying skills or commands, the content is Markdown processed by Claude Code's plugin system. Changes take effect in new sessions.

To test a hook change, start a new Claude Code session in a project with this plugin enabled.

To verify plugin registration: check that `.claude-plugin/marketplace.json` lists the plugin and the source path resolves to a valid `plugin.json`.
