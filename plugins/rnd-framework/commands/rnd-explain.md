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

**If `$ARGUMENTS` is provided:** run `git diff $ARGUMENTS` and use its output as the diff. If that diff is empty, this is a stop condition ("No changes for the given ref/range: `$ARGUMENTS`.") — route it through the **Guard Recovery** menu below rather than erroring in prose. Otherwise skip to Step 2.

**If `$ARGUMENTS` is empty**, resolve the default target:

1. Resolve the current branch: `git symbolic-ref --short HEAD`. If this fails, HEAD is detached.
2. Resolve the default branch: `git symbolic-ref refs/remotes/origin/HEAD` and strip the `refs/remotes/origin/` prefix. If no remote-tracking `HEAD` exists, fall back to `main` if a local `main` branch exists, else `master`.
3. **Guard — on default branch.** If the current branch (step 1) equals the resolved default branch (step 2), this is a stop condition: "You are on the default branch (`<branch>`) — there is nothing to explain relative to itself." Route it through **Guard Recovery**.
4. **Guard — detached HEAD.** If step 1 could not resolve a branch name, this is a stop condition: "HEAD is detached — rnd-explain needs a branch to diff against the default branch." Route it through **Guard Recovery**.
5. Compute the merge base: `git merge-base <default-branch> HEAD`. If this fails, this is a stop condition: "No common ancestor found between `<default-branch>` and HEAD." Route it through **Guard Recovery**.
6. Compute the diff with a three-dot range against the merge base (not the tip of the default branch): `git diff <merge-base>...HEAD`.
7. **Guard — empty diff.** If the diff output is empty, this is a stop condition: "No changes between `<default-branch>` and HEAD — nothing to explain." Route it through **Guard Recovery**.

Only after every applicable guard passes does this command proceed to Step 2.

### Guard Recovery (interactive)

When any guard above hits a stop condition, do **not** surface the recovery choices as plain prose. Instead present them through a single `AskUserQuestion` (one question, header `Diff target`), stating the stop reason in the question text and offering:

- **Explain the last 3 commits** — resolves to `HEAD~3..HEAD` *(list this first / Recommended)*.
- **Explain the last commit** — resolves to `HEAD~1..HEAD`.
- **Cancel** — write nothing and stop.

The user can always pick "Other" to type an explicit ref, range, SHA, or branch name. On any choice other than Cancel, adopt the chosen (or typed) value as `$ARGUMENTS` and re-enter Step 1's provided-argument path: run `git diff <value>`; if that too is empty, re-present the same menu with the new stop reason. On **Cancel**, stop immediately, confirm no `.html` was written, and do not proceed to Step 2.

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

Tell the user the absolute file path of the generated `.html`.

Do **not** print the HTML body into chat. The artifact is a full inline-styled, self-contained document meant to be opened in a browser, not read as a chat transcript — dumping its source defeats the point of producing a standalone file.

## Step 5: Offer to Open It

After the `.html` is written, ask the user what to do with it through a single `AskUserQuestion` (one question, header `Open`) — do not just leave a prose hint. Offer:

- **Open in default browser** *(list first / Recommended)* — run `open "<file>"` (macOS). On Linux use `xdg-open "<file>"`; on Windows use `start "" "<file>"`.
- **Open containing folder** — run `open "<dir>"` (macOS), `xdg-open "<dir>"` (Linux), or `explorer "<dir>"` (Windows), where `<dir>` is `$RND_DIR/explain/`.
- **Leave it** — do nothing further; the file path was already surfaced in Step 4.

Run the corresponding command only for the branch the user picks. If the platform's opener is unavailable or the command fails, fall back to reminding the user of the file path — never treat a failed opener as a pipeline failure.

## Output Discipline

This command produces exactly one artifact: the generated `.html` under `$RND_DIR/explain/`. Surface the file path (Step 4) and offer to open it via the Step 5 `AskUserQuestion` per the Report Surfacing Protocol in your active output style — but this artifact is explicitly excluded from verbatim body-dump: never print the HTML source into chat, only the path. If a guard in Step 1 stops the command (empty diff, detached HEAD, on-default-branch, no common ancestor), route the recovery choices through the **Guard Recovery** `AskUserQuestion` menu rather than prose; if the user cancels there, confirm no `.html` was written.
