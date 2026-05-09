# tight-loop — Claude Code Plugin

A single-agent rigor plugin for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). Enforces a three-step ritual — **pre-register → implement → self-review** — through prompt discipline plus four enforcement hooks. No orchestration, no subagents, no information barrier.

## Why

Multi-agent orchestration produces rigor through structural isolation, at the cost of (a) duplicated context per agent, (b) opaque execution, and (c) latency. For a meaningful share of real tasks, this ceremony is overkill. tight-loop bets that a tight prompt skill plus selectively reused hooks plus a current-generation Claude model is enough — when verification ground truth comes from deterministic external checks (tests, lints, build) rather than a second agent's judgment.

## The three-step ritual

1. **Pre-register.** Write `prereg-<task-slug>.md` to the artifact directory before any project file edit. The `prereg-gate` hook blocks all `Write`/`Edit` on project files until the file exists.
2. **Implement.** Write code following the pre-registered approach. When you hit an issue, you must either fix it or log it to the found-issues ledger — silent dismissal is not an option.
3. **Self-review.** Walk each success criterion with concrete evidence. Wrap the final report in a `<final-report>` marker. The `dismissal-gate` Stop hook blocks any final report containing dismissal phrases (`pre-existing`, `out of scope`, etc.) or unledgered problem terms.

## Installation

```
/plugin marketplace add https://tangled.org/oleksify.me/rnd-framework
/plugin install tight-loop@oleksify-plugins
```

Or use the interactive plugin manager:

```
/plugin
```

## Usage

```
/tight-loop:start <task description>
```

The slash command invokes the `tight-loop:tight-loop` skill, which runs the three-step ritual on the described task.

## Hooks

| Hook | Event | Purpose |
|---|---|---|
| `bash-gate.sh` | PreToolUse Bash | Tool discipline — blocks `sed`/`awk`/`echo>`/inline interpreters/shell loops/`/tmp` redirects, plus `git add` on artifact paths |
| `prereg-gate.sh` | PreToolUse Write\|Edit | Blocks project file edits until a `prereg-*.md` exists in the base dir |
| `format-on-save.sh` | PostToolUse Write\|Edit | Auto-formats code files using the detected project formatter |
| `dismissal-gate.sh` | Stop | Fires only when the assistant message contains `<final-report>`; blocks dismissal phrases and unledgered problems |
| `permission-denied.sh` | PermissionDenied | Logs auto-mode denials and returns `retry: true` |

## Artifact directory

Two persistent files per task in an isolated, project-hashed base directory:

```
~/.claude/.tight-loop/<project-slug>/
├── prereg-<task-slug>.md     # Pre-registration written before any project edit
├── report-<task-slug>.md     # Final report written at end of task
└── found-issues.jsonl        # Per-issue ledger; "escalated" entries are the only honest "out of scope" path
```

The slug is derived from the canonicalized git-common-dir basename plus an 8-character SHA-256 hash. All worktrees of the same repo share one base.

## When to use

- A non-trivial task where you want a structured record of intent and evidence of completion
- One task at a time — invoke the skill once per task, not once per session
- Tasks where the ground truth is a test runner, linter, or build (so deterministic checks substitute for a second-agent reviewer)

When you need multi-agent verification, multi-judge consensus, formal Lean proofs, or wave-based decomposition, use [rnd-framework](../rnd-framework/README.md) instead.

## Tests

```
cd plugins/tight-loop && bash tests/run-tests.sh
```

35 tests across `dismissal-gate.test.sh` (18) and `hooks.test.sh` (17 — covers `bash-gate`, `prereg-gate`, `format-on-save`, `permission-denied`, and `hooks.json` integrity).

## License

MIT. See [LICENSE](../../LICENSE).
