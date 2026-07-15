---
description: "Generate a self-contained interactive HTML explainer for a diff — background, intuition, code walkthrough, and quiz."
argument-hint: "[ref or range, e.g. HEAD~3..HEAD | empty for merge-base diff against the default branch]"
effort: high
---

# R&D Framework: Explain Diff

Produces a single self-contained `.html` file that teaches a reader what a diff changes and why — background, intuition, a grouped code walkthrough, and a quiz. Use this after shipping a branch, or any time you want a shareable, offline-readable explanation of a set of changes. This command owns diff-target resolution and the output path; the actual HTML generation contract lives in the `rnd-framework:rnd-explain` skill.

## Task Input

If `$ARGUMENTS` is non-empty, treat it as an explicit ref or range (e.g. `HEAD~3..HEAD`, a commit SHA, a branch name) and use it verbatim as the diff target in Step 1 — skip default-branch/merge-base resolution entirely.

If `$ARGUMENTS` is empty, resolve the diff target automatically in Step 1.

## Step 0: Setup

```bash
RND_DIR=$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh" -c)
mkdir -p "$RND_DIR/explain"
```

## Step 1: Resolve the Diff Target

**If `$ARGUMENTS` is provided:** run `git diff $ARGUMENTS` and use its output as the diff. If that diff is empty, ERROR ("No changes for the given ref/range: `$ARGUMENTS`.") and STOP — write no `.html`. Otherwise skip to Step 2.

**If `$ARGUMENTS` is empty**, resolve the default target:

1. Resolve the current branch: `git symbolic-ref --short HEAD`. If this fails, HEAD is detached.
2. Resolve the default branch: `git symbolic-ref refs/remotes/origin/HEAD` and strip the `refs/remotes/origin/` prefix. If no remote-tracking `HEAD` exists, fall back to `main` if a local `main` branch exists, else `master`.
3. **Guard — on default branch.** If the current branch (step 1) equals the resolved default branch (step 2), ERROR: "You are on the default branch (`<branch>`) — there is nothing to explain relative to itself. Pass an explicit ref/range as an argument instead." STOP. Write no `.html`.
4. **Guard — detached HEAD.** If step 1 could not resolve a branch name, ERROR: "HEAD is detached — rnd-explain needs a branch to diff against the default branch. Pass an explicit ref/range via the command argument." STOP. Write no `.html`.
5. Compute the merge base: `git merge-base <default-branch> HEAD`. If this fails, ERROR: "No common ancestor found between `<default-branch>` and HEAD." STOP. Write no `.html`.
6. Compute the diff with a three-dot range against the merge base (not the tip of the default branch): `git diff <merge-base>...HEAD`.
7. **Guard — empty diff.** If the diff output is empty, ERROR: "No changes between `<default-branch>` and HEAD — nothing to explain." STOP. Write no `.html`.

Only after every applicable guard passes does this command proceed to Step 2.

## Step 2: Compute the Output Path

1. **Slug base.** Sanitize the branch name resolved in Step 1 (or a short label derived from `$ARGUMENTS` when it was used): lowercase, replace `/` and any run of non-`[a-z0-9-]` characters with `-`, trim leading/trailing `-`.
2. **Date prefix.** Today's local date as `YYYY-MM-DD`.
3. **Candidate path.** `$RND_DIR/explain/<date>-<slug>.html`.
4. **Collision guard.** If a file already exists at the candidate path:
   - First, append a short commit SHA (`git rev-parse --short HEAD`) to the slug and retry.
   - If that path is still taken (e.g. a second run against the same commit), append a numeric suffix (`-2`, `-3`, ...) and increment until an unused path is found.
   - Never overwrite an existing `.html` under `$RND_DIR/explain/`. Two branches whose sanitized names collide on the slug root must never clobber each other's output.

The final path from this step is the exact path the skill must write to in Step 3.

## Step 3: Generate the HTML

Invoke the `rnd-framework:rnd-explain` skill to produce the HTML content. Provide it:
- the resolved diff (from Step 1),
- `$RND_DIR`, so the skill can perform its additive session-artifact enrichment when session reports exist,
- the exact output path computed in Step 2.

The skill owns the full generation contract — section structure, self-containment rules, and its blocking pre-save scan. This command does not author HTML markup itself; it only resolves what to diff and where to write the result.

## Step 4: Surface the Result

Tell the user:
- The absolute file path of the generated `.html`.
- An open-in-browser hint (e.g. `open <path>` on macOS, or "open the path directly in your browser").

Do **not** print the HTML body into chat. The artifact is a full inline-styled, self-contained document meant to be opened in a browser, not read as a chat transcript — dumping its source defeats the point of producing a standalone file.

## Output Discipline

This command produces exactly one artifact: the generated `.html` under `$RND_DIR/explain/`. Surface the file path and the open-in-browser hint per the Report Surfacing Protocol in your active output style — but this artifact is explicitly excluded from verbatim body-dump: never print the HTML source into chat, only the path and the hint. If a guard in Step 1 stops the command (empty diff, detached HEAD, on-default-branch), surface that error message clearly and confirm no `.html` was written.
