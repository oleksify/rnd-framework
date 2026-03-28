---
name: committing
description: Use when creating git commits — enforces commit message style, length limits, and user confirmation before committing
effort: low
---

# Committing

## Rules

1. **One line, imperative mood.** "Fix race condition in token refresh", not "Fixed" or "Fixes" or "Fixing".
2. **50 characters or fewer.** Hard limit. If you can't fit it, you're describing too much — split the commit or be more specific.
3. **Never mention AI, LLM, agent, Claude, or any tool authorship.** Write as a human developer would.
4. **Never add Co-Authored-By lines.**
5. **Say what and why, not how.** "Fix off-by-one in pagination cursor" — not "Change `i < len` to `i <= len`".
6. **Be specific.** "Fix login redirect on expired session" — not "Fix bug" or "Update auth".
7. **No filler words.** Drop "various", "some", "minor", "small". Every word must carry information.
8. **Don't explain framework internals.** Never reference skills, hooks, pipeline phases, or orchestration mechanics. Describe the user-visible change.
9. **Don't assume GitHub.** The remote could be GitLab, Gitea, Codeberg, Forgejo, Tangled, or any other host. Check `git remote get-url origin` before using platform-specific CLI tools (e.g., `gh` is GitHub-only). For PRs/MRs, ask the user or infer from the remote URL.

## Before Committing

**Always use `AskUserQuestion`/`AskUser`** to confirm the commit message before running `git commit`. Present 2-3 message options with the best one marked "(Recommended)".

Example:

```
AskUserQuestion:
  question: "Commit message?"
  options:
    - label: "Add Write tool to verifier agent (Recommended)"
      description: "Describes the functional change"
    - label: "Fix verifier using bash heredocs for file creation"
      description: "Describes the problem that was solved"
```

## Good Examples

```
Add rate limiting to public API endpoints
Fix duplicate webhook delivery on retry
Remove deprecated v1 auth endpoints
Extract PDF parser into standalone module
Update Stripe SDK to v15 for SCA compliance
```

## Bad Examples

```
Update files                          # vague
Fix bug                               # what bug?
Refactor code for better quality      # says nothing
Add AI-powered verification system    # leaks internals
Various improvements and fixes        # filler
Change line 42 in auth.ts             # describes how, not what
```
