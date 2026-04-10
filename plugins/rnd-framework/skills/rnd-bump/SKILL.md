---
name: rnd-bump
description: "Bump the plugin version (patch/minor/major) and add a CHANGELOG entry. Stages plugin.json and CHANGELOG.md, then offers to commit and optionally tag."
user-invocable: false
effort: low
---

# R&D Framework: Bump Version

Increment the rnd-framework plugin version and record a CHANGELOG entry.

## Step 1: Determine Version Bump Type

Analyze the changes since the last version tag to determine the appropriate bump type. Check `git log` from the last `v*` tag to HEAD.

Use `AskUserQuestion` to ask:

> "What type of version bump?"

Present three options. Mark exactly one as `(Recommended)` based on these rules:
- **Major** — breaking changes: removed commands/skills, renamed public APIs, changed hook output schemas, incompatible config changes
- **Minor** — new features or non-trivial improvements: new commands/skills, new hook events, significant behavior changes
- **Patch** — bug fixes, documentation updates, internal refactors with no user-facing behavior change

Format the options showing what the next version would be (read current version from plugin.json):
- `"Patch (X.Y.Z+1)"` or `"Patch (X.Y.Z+1) (Recommended)"`
- `"Minor (X.Y+1.0)"` or `"Minor (X.Y+1.0) (Recommended)"`
- `"Major (X+1.0.0)"` or `"Major (X+1.0.0) (Recommended)"`

If the user provides an explicit version type in `$ARGUMENTS` (e.g., "minor", "patch"), skip this step and use that type directly.

## Step 2: Get the Changelog Headline

Parse `$ARGUMENTS` to extract the headline and optional description:

- **If `$ARGUMENTS` contains a headline**, split on ` --- ` (space-dash-dash-dash-space) or a bare newline:
  - Everything before the separator is the **headline**
  - Everything after (if present) is the **description**
- **If no headline in `$ARGUMENTS`**, use `AskUserQuestion` to ask:
  > "What should the CHANGELOG headline be for this release?"

  Ask for a short imperative title (e.g., "Add bump command"). If the user wants to include a description body, they can provide it as a second line or after ` --- `.

## Step 3: Run bump.sh

Call `bump.sh` via the Bash tool. The script auto-detects the source repo from the git working tree, so it works correctly even when invoked from the plugin cache path:

```bash
"${CLAUDE_PLUGIN_ROOT}/lib/bump.sh" --<type> "<headline>" "<description>"
```

- Pass `--patch`, `--minor`, or `--major` as the first argument based on the chosen bump type.
- Pass `<headline>` as the next argument (always required).
- Pass `<description>` as the last argument only if non-empty; omit it otherwise.
- Capture and display the output (e.g., `Bumped version 3.0.18 → 3.1.0`).

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
