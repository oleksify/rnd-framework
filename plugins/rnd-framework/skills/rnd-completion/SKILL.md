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

> **Note on RND_DIR:** If not already set in session context, compute it by running `"${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh"`. Artifacts are stored in a centralized directory outside the project (e.g., `~/.claude-personal/.rnd/project-abc123`), not inside the project tree.

### 2. Clean Up R&D Artifacts

Decide whether to keep or remove the `$RND_DIR` directory:
- **Keep** if the team wants audit trails of verification
- **Remove** if the artifacts are no longer needed: `rm -rf "$RND_DIR"`

No `.gitignore` changes needed — pipeline artifacts are stored outside the project directory and are never at risk of being committed.

### 3. Create Final Commit

Stage all verified changes. Write a clear commit message summarizing the feature/fix.

Pipeline artifacts in `$RND_DIR` are outside the project tree and cannot be accidentally staged.

### 4. Branch Management

**Don't assume GitHub.** Check `git remote get-url origin` to determine the hosting platform. The remote could be GitLab, Gitea, Codeberg, Forgejo, Tangled, or any other host. Use the appropriate CLI or web workflow — `gh` is GitHub-only, `glab` is GitLab-only, etc. When in doubt, ask the user.

Options:
- **Merge to main** — If working on a feature branch, merge or rebase
- **Create PR/MR** — Push branch, create pull/merge request with summary from integration report
- **Keep branch** — If more work is planned on this branch

### 5. Report to User

Summarize:
- What was built and verified
- Iteration count and any escalations
- Final integration status
- Branch/PR status

**Use `AskUserQuestion` to present next steps as structured options** with a recommended choice. For example: "Create PR (Recommended)", "Commit without PR", "Review changes first". Never leave the user with open-ended text asking what to do.

## Related Skills

- `rnd-framework:rnd-integration` — Integration testing and SHIP verdicts
- `rnd-framework:rnd-orchestration` — Pipeline overview
