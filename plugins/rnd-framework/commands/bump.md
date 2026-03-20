---
description: "Bump the plugin patch version and add a CHANGELOG entry. Stages plugin.json and CHANGELOG.md, then offers to commit and optionally tag."
argument-hint: "<changelog headline> [--- <optional description>]"
effort: low
---

# R&D Framework: Bump Version

Increment the patch version of the rnd-framework plugin and record a CHANGELOG entry.

## Step 1: Get the Changelog Headline

Parse `$ARGUMENTS` to extract the headline and optional description:

- **If `$ARGUMENTS` is non-empty**, split on ` --- ` (space-dash-dash-dash-space) or a bare newline:
  - Everything before the separator is the **headline**
  - Everything after (if present) is the **description**
- **If `$ARGUMENTS` is empty**, use `AskUserQuestion` to ask:
  > "What should the CHANGELOG headline be for this release?"

  Ask for a short imperative title (e.g., "Add bump command"). If the user wants to include a description body, they can provide it as a second line or after ` --- `.

## Step 2: Run bump.sh

Call `bump.sh` via the Bash tool. The script auto-detects the source repo from the git working tree, so it works correctly even when invoked from the plugin cache path:

```bash
"${CLAUDE_PLUGIN_ROOT}/lib/bump.sh" "<headline>" "<description>"
```

- Pass `<headline>` as the first argument (always required).
- Pass `<description>` as the second argument only if non-empty; omit it otherwise.
- Capture and display the output (e.g., `Bumped version 0.7.20 → 0.7.21`).

If the script exits non-zero, show the error and stop.

## Step 3: Show What Changed

After `bump.sh` succeeds:

1. Find the source `plugin.json` — look for `.claude-plugin/plugin.json` relative to the git root (e.g., `<git-root>/plugins/rnd-framework/.claude-plugin/plugin.json`). Read the new version from it.
2. Show the user a brief summary:
   - New version number
   - CHANGELOG headline (and description if provided)
   - Files staged: `rnd-framework/.claude-plugin/plugin.json`, `rnd-framework/CHANGELOG.md`

## Step 4: Commit Confirmation

Use `AskUserQuestion` to ask:

> "Version bumped to X.Y.Z. Ready to commit?"

Options:
- "Commit (Recommended)" — commit the staged files
- "Review changes first" — show `git diff --staged` output, then re-ask
- "Skip commit" — leave files staged, do nothing further

**If "Commit (Recommended)"** is chosen, run:

```bash
git commit -m "Bump version to X.Y.Z"
```

where `X.Y.Z` is the new version read from `plugin.json`.

**If "Review changes first"** is chosen, run `git diff --staged` (scoped to the plugin directory) and display the output, then use `AskUserQuestion` again with the same options.

**If "Skip commit"** is chosen, confirm to the user that files are staged and ready for manual commit.

## Step 5: Tag Offer

After a successful commit, use `AskUserQuestion` to ask:

> "Create an annotated git tag `vX.Y.Z`?"

Options:
- "Tag and push" — create the tag and push it to the remote
- "Tag only" — create the tag locally, don't push
- "Skip tagging (Recommended)" — no tag, done

**If "Tag and push"** or **"Tag only"** is chosen, run:

```bash
git tag -a vX.Y.Z -m "<headline>"
```

where `<headline>` is the CHANGELOG headline from Step 1. If "Tag and push", also run `git push origin vX.Y.Z`.

**If "Skip tagging"** is chosen, done — no further action.

## Commit Message Convention

Use the exact format: `Bump version to X.Y.Z`

- Imperative, one sentence
- No "Co-Authored-By" line
- No mention of Claude
