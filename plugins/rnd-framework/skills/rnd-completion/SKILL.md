---
name: rnd-completion
description: "Use after final SHIP verdict — guides branch management, PR creation, cleanup of .rnd/ artifacts, and development branch completion"
---

# R&D Completion

## Overview

After the final integration wave receives a SHIP verdict, guide the completion workflow: commit remaining changes, manage branches, create PRs, and clean up R&D artifacts.

**Core principle:** A SHIP verdict means the work is verified. Now package it for merge.

## When to Use

- After final `/rnd-framework:integrate final` returns SHIP
- When wrapping up a completed R&D pipeline run
- Before merging development work into main branch

## Process

### 1. Verify SHIP Status

Confirm the final integration report at `$RND_DIR/integration/` shows SHIP verdict. Do not proceed if NO-SHIP.

> **Note on RND_DIR:** If not already set in session context, compute it by running `"${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh"`. Artifacts are stored in a centralized directory outside the project (e.g., `~/.claude/.rnd/project-abc123`), not inside the project tree.
>
> **Session-scoped:** `$RND_DIR` points to a session subdirectory (`<base>/sessions/<YYYYMMDD-HHMMSS-XXXX>/`), not the project base. Previous sessions remain on disk and can be browsed with `/rnd-framework:history`.

### 2. Handle Session Completion

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

### 3. Clean Up R&D Artifacts

The "Clean up" option removes `$RND_DIR` (the current session directory). Only do this if the artifacts are no longer needed — verification reports and build manifests can be useful references after merging.

No `.gitignore` changes needed — pipeline artifacts are stored outside the project directory and are never at risk of being committed.

### 4. Create Final Commit

Stage all verified changes. Write a clear commit message summarizing the feature/fix.

Pipeline artifacts in `$RND_DIR` are outside the project tree and cannot be accidentally staged.

### 5. Branch Management

**Don't assume GitHub.** Check `git remote get-url origin` to determine the hosting platform. The remote could be GitLab, Gitea, Codeberg, Forgejo, Tangled, or any other host. Use the appropriate CLI or web workflow — `gh` is GitHub-only, `glab` is GitLab-only, etc. When in doubt, ask the user.

Options:
- **Merge to main** — If working on a feature branch, merge or rebase
- **Create PR/MR** — Push branch, create pull/merge request with summary from integration report
- **Keep branch** — If more work is planned on this branch

### 6. Report to User

Summarize:
- What was built and verified
- Iteration count and any escalations
- Final integration status
- Branch/PR status

**Use `AskUserQuestion` to present next steps as structured options** with a recommended choice. For example: "Create PR (Recommended)", "Commit without PR", "Review changes first". Never leave the user with open-ended text asking what to do.

## Related Skills

- `rnd-framework:rnd-integration` — Integration testing and SHIP verdicts
- `rnd-framework:rnd-orchestration` — Pipeline overview
- `/rnd-framework:history` — Browse artifacts from past sessions
