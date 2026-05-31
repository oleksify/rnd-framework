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

### 4. Stale Comments / TODOs / Dead Branches / Pipeline-Context Leaks

- Comments describing code removed or refactored by this build.
- TODO / FIXME / HACK comments resolved by this build but left in place.
- `if false`, `if 0`, permanently-dead feature flags introduced or made dead by this build.
- Comment-guarded dead code with no ticket or decision reference.
- **Pipeline-context leaks** — any reference anywhere in project code, documentation, or test scaffolding (comments, docstrings, test names, variable names, tree-diagram annotations, headings) to RND-internal concepts that will rot when the session ends. **Canonical project docs (`CLAUDE.md`, `README.md`, top-level `AGENTS.md`) and shared test infrastructure are in scope** whenever this task's build manifest touched them — leakage in those files is the most damaging because future readers have no session to anchor on.
  - **Narrative milestone tags as prefixes:** `# M6: PreToolUse hook`, `# M5: archive helper`, `# M4 outside-view injector`, `(M3)` parentheticals describing what a file or section does. Strip the prefix; keep the description.
  - **Test-comment trace tags:** `# M4.wiring.outside-view-section-exists` above a test block, `(M2.calib.verdict-record-lands-at-slug-roo)` parentheticals after a `# Test N:` line. These trace tests back to validation-contract assertion IDs from a specific session. Strip the tag; keep the natural-language description.
  - **Task / wave identifiers:** `T1`, `T01`, `T14`, `M2`, `wave-3`, `FM6`, `Phase 1` (when used as a session-phase pointer rather than a domain term).
  - **Planner phase or disposition labels:** `Q4 disposition`, "compatibility audit", "decided during planning".
  - **Session artifact paths or meta-references:** `research/*.md`, `protocol.md`, `T<id>-manifest.md`, "the R&D session", "the pipeline".
  - **Distinguish leakage from framework-own guidance.** ID FORMATS (`M<N>.<area>.<slug>`, `T<id>`, `wave-<N>`) documented in agent/skill specs are canonical schema, NOT leakage — leave them alone. Sample IDs inside test FIXTURE DATA (heredoc content creating validation-contract.md or features.json) are demonstrating the parser, NOT leakage — leave them alone. The leakage pattern is narrative session-tag prefixes and trace comments in surrounding prose.
  Rewrite the comment/heading to ground its rationale in the project's own concepts, or delete it if it doesn't help a future reader who never saw the pipeline run.

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

Run the project's test suite directly via Bash (read `$RND_DIR/protocol.md` "Testing Strategy" for the canonical command — e.g., `bash tests/run-tests.sh`, `bun test`, `python -m pytest`). On all-green, write a minimal `T<id>-cleanup-pass-receipt.json` to `$RND_DIR/verifications/` with `source: "cleanup-reverify"` and an ISO 8601 timestamp. Do NOT spawn a fresh `rnd-verifier` agent — the full Verifier already PASSed this task before cleanup ran; this step only confirms the cleanup mutations did not break the existing tests.

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
[PASS / NEEDS_ITERATION / FAIL / skipped (no findings)]

## Outcome
[cleanup applied | cleanup skipped (broke verification) | cleanup skipped (no findings)]

## Metrics
- lines_removed: <integer>
- Deletion ratio: <deleted_loc> / <total_touched_loc>
```

The cleanup report MUST include a `lines_removed: <integer>` field (a bullet line is acceptable). The cleanup-bloat-gate.sh hook reads this field (falling back to the existing `Deletion ratio:` line) and emits an advisory `gate_fired` audit event when the deletion ratio is below 15%. The advisory does NOT block.

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
