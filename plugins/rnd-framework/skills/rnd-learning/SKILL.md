---
name: rnd-learning
description: "Use when extracting or reading pipeline-discovered gotchas — defines when/how to capture learnings from iteration cycles and inject them into builder prompts"
user-invocable: false
effort: low
---

# R&D Learning

## Overview

RND agents discover non-obvious gotchas during iteration cycles. This skill defines how to capture them via the user's existing Learning Library and how to inject them into future builder prompts — so the same class of mistake is not repeated across tasks or sessions.

## When to Extract

Only after a successful iteration cycle:

```
Build → Verify → NEEDS_ITERATION → Builder fixes → Re-verify → PASS
```

**NOT** on first-pass PASS (nothing was learned).
**NOT** on FAIL without eventual resolution (nothing was fixed).

## What to Extract

From the completed iteration cycle:
- **Gotcha:** what failed — from the Verifier's feedback
- **Fix:** what the Builder changed — from the iteration diff
- **Combined learning:** what went wrong + how to avoid it next time

Keep it terse. If you need a sentence to explain the fix, two bullets suffice.

## Format

Match the existing Learning Library exactly:

```markdown
## Topic Name
- Bullet describing the gotcha and its fix. Terse, factual, no prose.
- Optional second bullet for context or edge cases.
```

## Extension → Language File Mapping

| Extensions | Learnings File |
|---|---|
| `.ts`, `.js`, `.jsx`, `.tsx`, `.mjs`, `.cjs` | `javascript.md` |
| `.rs` | `rust.md` |
| `.jl` | `julia.md` |
| `.ex`, `.exs` | `elixir.md` |
| `.gleam` | `gleam.md` |
| `.sql` | `sql.md` |
| `.css`, `.scss` | `css.md` |
| `.sh`, `.bash` | `devops.md` |
| `.md` (non-doc) | `devops.md` |
| (fallback) | `devops.md` |

## Where to Write

Target path: `$CLAUDE_CONFIG_DIR/learnings/{language}.md`

If the file does not exist, create it with a `# {Language} Learnings` heading, then add a link in `$CLAUDE_CONFIG_DIR/learnings/INDEX.md`.

## Reading Protocol

Before writing builder prompts for a new task:

1. Detect languages from the task's expected output file extensions
2. Read matching learnings files from `$CLAUDE_CONFIG_DIR/learnings/`
3. Include as **"Known gotchas for {language}"** context in the builder prompt
4. If no file exists for a language, skip silently — do not error or warn

## Related Skills

- `rnd-framework:rnd-iteration` — iteration cycle that triggers extraction
- `rnd-framework:rnd-building` — builder prompt injection point
