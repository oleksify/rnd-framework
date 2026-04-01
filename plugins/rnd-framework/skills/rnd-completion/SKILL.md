---
name: rnd-completion
description: "Use after final SHIP verdict — guides branch management, PR creation, cleanup of .rnd/ artifacts, and development branch completion"
user-invocable: false
effort: low
---

# R&D Completion

## Overview

After the final integration wave receives a SHIP verdict, guide the completion workflow: commit remaining changes, manage branches, create PRs, and clean up R&D artifacts.

**Core principle:** A SHIP verdict means the work is verified. Now package it for merge.

## When to Use

- After final `/rnd-framework:rnd-integrate final` returns SHIP
- When wrapping up a completed R&D pipeline run
- Before merging development work into main branch

## Process

### 1. Verify SHIP Status

Confirm the final integration report at `$RND_DIR/integration/` shows SHIP verdict. Do not proceed if NO-SHIP.

> **Note on RND_DIR:** If not already set in session context, compute it by running `"${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh"`. Artifacts are stored in a centralized directory outside the project (e.g., `~/.claude/.rnd/project-abc123`), not inside the project tree.
>
> **Session-scoped:** `$RND_DIR` points to a session subdirectory (`<base>/sessions/<YYYYMMDD-HHMMSS-XXXX>/`), not the project base. Previous sessions remain on disk and can be browsed with `/rnd-framework:rnd-history`.

### 2. Update Roadmap (if linked)

If a roadmap milestone is linked to this session, mark it complete:

```bash
ROADMAP="$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh" --roadmap)"
```

- If `$ROADMAP` points to an existing `roadmap.md` with an `IN_PROGRESS` milestone:
  - Change its status to `DONE`, record the session ID and a brief summary of deliverables, and update the "Last updated" date
  - Show the updated roadmap progress to the user
  - Use `AskUserQuestion` to offer: "Start next milestone (Recommended)", "Finish session", "Review roadmap"
- If no roadmap exists or no `IN_PROGRESS` milestone: skip silently

### 3. Handle Session Completion

After a SHIP verdict, offer the user these distinct options:

**Finish session** — Clears the session ID so the next pipeline run starts a new session, but **preserves all artifacts on disk** for historical reference:
```bash
"${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh" --finish
```

**Clean up** — Removes the current session's artifacts entirely (no recovery):
```bash
rm -rf "$RND_DIR"
```

**Both** — Finish the session and delete its artifacts.

**Neither** — Leave everything as-is (session ID remains active; pipeline commands will continue operating in this session).

> Finishing a session and cleaning up are independent. Most users will want to finish the session (to start fresh next time) but keep artifacts for audit trails. Use `AskUserQuestion` to present these as explicit choices.

### 4. Clean Up R&D Artifacts

The "Clean up" option removes `$RND_DIR` (the current session directory). Only do this if the artifacts are no longer needed — verification reports and build manifests can be useful references after merging.

No `.gitignore` changes needed — pipeline artifacts are stored outside the project directory and are never at risk of being committed.

### 4.5. Agent Cleanup

If the pipeline spawned agents (multi-agent mode via `/rnd-framework:rnd-start`), ensure all spawned agent processes have terminated. Agents should self-terminate after completing their work, but verify no orphaned agent sessions remain:

- Check that all Builder, Verifier, and Integrator agents have returned their final reports
- Confirm no background agent processes are still running
- Agent artifacts (build manifests, verification reports, experiment results) are already stored in `$RND_DIR` and will be cleaned up with the session directory if the user chooses cleanup

### 5. Create Final Commit

Stage all verified changes. Write a clear commit message summarizing the feature/fix.

Pipeline artifacts in `$RND_DIR` are outside the project tree and cannot be accidentally staged.

### 5.5. Version Bump (if applicable)

After committing, use `AskUserQuestion` to offer a version bump for versioned projects (plugins, libraries, packages):

> "Bump version and tag this release?"

Options:
- "Bump, tag and push (Recommended)" — run `/rnd-framework:rnd-bump` to add a CHANGELOG entry, increment the patch version, commit the bump, create an annotated git tag, and push both to the remote
- "Bump and tag only" — run `/rnd-framework:rnd-bump`, create a tag, but don't push
- "Skip versioning" — no bump, continue to branch management

**Skip this step silently** if the project has no `plugin.json`, `package.json`, or other version manifest — it's not a versioned project.

### 6. Branch Management

**Don't assume GitHub.** Check `git remote get-url origin` to determine the hosting platform. The remote could be GitLab, Gitea, Codeberg, Forgejo, Tangled, or any other host. Use the appropriate CLI or web workflow — `gh` is GitHub-only, `glab` is GitLab-only, etc. When in doubt, ask the user.

Options:
- **Merge to main** — If working on a feature branch, merge or rebase
- **Create PR/MR** — Push branch, create pull/merge request with summary from integration report
- **Keep branch** — If more work is planned on this branch

**PR creation rules:**
- **Never chain commands.** Each git/gh command must be a separate Bash tool call. Never `git push && gh pr create` — combined commands hang on hidden permission prompts.
- **Separate steps:** (1) `git push -u origin <branch>` in one call, (2) `gh pr create ...` in a separate call.
- **Long PR bodies:** Write the body to a temp file in `$RND_DIR` first, then pass `--body-file <path>`. Long `--body` inline arguments can cause the permission dialog to hang.

### 7. Report to User

Summarize:
- What was built and verified
- Iteration count and any escalations
- Final integration status
- Branch/PR status

**Use `AskUserQuestion` to present next steps as structured options** with a recommended choice. For example: "Create PR (Recommended)", "Commit without PR", "Review changes first". Never leave the user with open-ended text asking what to do.

## Related Skills

- `rnd-framework:rnd-integration` — Integration testing and SHIP verdicts
- `rnd-framework:rnd-orchestration` — Pipeline overview

## Related Commands

- `/rnd-framework:rnd-history` — Browse artifacts from past sessions
