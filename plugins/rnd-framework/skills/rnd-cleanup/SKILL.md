---
name: rnd-cleanup
description: "Use after a task passes verification — detect and remove dead code, orphan files, duplicate implementations, and stale comments introduced during the build, then re-verify and roll back if verification breaks"
user-invocable: false
effort: medium
---

# R&D Cleanup

Post-verification entropy reduction. Runs after a task has passed verification. Detects code rot introduced during the build, applies mutations, re-verifies, and rolls back on failure.

## The Iron Laws

```
1. NEVER MODIFY TEST FILES OR PRE-REGISTRATION DOCUMENTS
2. NEVER AUTO-COMMIT — CHANGES STAY IN THE WORKING TREE
3. ROLL BACK ALL TOUCHED FILES ON ANY NON-PASS VERDICT
4. EMPTY CANDIDATE LIST → SKIP IMMEDIATELY, NO NO-OP EDITS
```

## Four Detection Categories

Run all four on every task.

### 1. Dead Functions / Unused Exports

Use language-specific tooling when available; fall back to LLM diff review for unsupported languages.

| Language | Tool |
|----------|------|
| TypeScript / JS | `ts-prune`; or Grep for exported symbol with no inbound import |
| Python | `ruff check --select F401,F841` on changed files |
| Bash, Markdown, other | LLM diff review — reason about whether any function/variable introduced in this build is called from outside its own file |

A finding: symbol defined in the diff with zero references from project entry points.

### 2. Orphan Files

1. Extract changed files from `$RND_DIR/builds/T<id>-manifest.md`.
2. Grep for each new file's basename and exported identifiers across the project.
3. A file is an orphan if no other file imports or references it AND it is not itself an entry point (`main`, `index`, `__main__`, CLI script in `package.json`/`pyproject.toml`).

### 3. Duplicate / Parallel Implementations

LLM diff review only. Read the diff; identify whether an existing utility does the same job as a newly added one. Cross-reference with the `simplify` skill (preloaded). A finding: two implementations with substantially overlapping purpose, where the build added one without removing the other.

### 4. Stale Comments / TODOs / Dead Branches

- Comments describing code removed or refactored by this build.
- TODO / FIXME / HACK comments resolved by this build but left in place.
- `if false`, `if 0`, permanently-dead feature flags introduced or made dead by this build.
- Comment-guarded dead code with no ticket or decision reference.

## Workflow

### 1. Inspect the diff

```bash
git diff HEAD -- <files from build manifest>
```

### 2. Propose mutations

List every proposed mutation before applying anything. If the list is empty:
- Append `T<id>: cleanup skipped (no findings)` to `$RND_DIR/iteration-log.md` and stop.

### 3. Apply mutations

Use Edit or Bash. Record every file touched.

### 4. Re-verify

Spawn `rnd-verifier` via the Agent tool with the task ID and pre-registration. Wait for verdict.

### 5. Branch on verdict

**PASS:**
- Leave changes in working tree.
- Write report to `$RND_DIR/cleanup/T<id>-cleanup-report.md`.
- Append `T<id>: cleanup applied` to `$RND_DIR/iteration-log.md`.

**NEEDS ITERATION or FAIL:**
- Roll back all touched files:
  ```bash
  git restore -- <touched files>
  ```
  Fall back if needed:
  ```bash
  git checkout HEAD -- <touched files>
  ```
- Write report explaining what was attempted and why it was rolled back.
- Append `T<id>: cleanup skipped (broke verification)` to `$RND_DIR/iteration-log.md`.

## Report Format

`$RND_DIR/cleanup/T<id>-cleanup-report.md`:

```markdown
# Cleanup Report: T<id>

## Detection Results

### Dead Functions / Unused Exports
- [finding or "(none)"]

### Orphan Files
- [finding or "(none)"]

### Duplicate / Parallel Implementations
- [finding or "(none)"]

### Stale Comments / TODOs / Dead Branches
- [finding or "(none)"]

## Mutations Proposed
[list or "(none — cleanup skipped)"]

## Mutations Applied
[list or "(none)"]

## Verification Result
[PASS / NEEDS ITERATION / FAIL / skipped (no findings)]

## Outcome
[cleanup applied | cleanup skipped (broke verification) | cleanup skipped (no findings)]
```

## Iteration-Log Entries

Exactly one line appended per run to `$RND_DIR/iteration-log.md`:

- `T<id>: cleanup applied`
- `T<id>: cleanup skipped (broke verification)`
- `T<id>: cleanup skipped (no findings)`

## Common Pitfalls

| Pitfall | Correct behavior |
|---------|-----------------|
| Skipping a detection category because "it looks fine" | Run all four categories every time |
| Applying mutations without listing them first | Always propose before applying |
| Partial rollback when verification fails | Roll back ALL touched files |
| Modifying test files during cleanup | Test files are off-limits |
| Auto-committing after PASS | Never auto-commit; leave in working tree |
