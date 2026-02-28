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

Confirm the final integration report at `.rnd/integration/` shows SHIP verdict. Do not proceed if NO-SHIP.

### 2. Clean Up R&D Artifacts

Decide whether to keep or remove `.rnd/` directory:
- **Keep** if the project wants audit trails of verification
- **Remove** if `.rnd/` is gitignored and ephemeral
- Add `.rnd/` to `.gitignore` if not already present

### 3. Create Final Commit

Stage all verified changes. Write a clear commit message summarizing the feature/fix.

**Never commit `.rnd/` contents.** The `.rnd/` directory is for pipeline artifacts only. Ensure `.rnd/` is in `.gitignore` before staging.

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
