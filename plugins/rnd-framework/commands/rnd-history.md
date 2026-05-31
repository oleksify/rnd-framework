---
description: "Browse past R&D pipeline sessions for this project. Shows session dates, task summaries, and SHIP/NO-SHIP verdicts."
effort: low
disallowed-tools: ["Edit", "Write"]
---

# R&D Framework: History

Get the project base directory:

```bash
BASE_DIR=$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh" --base)
SESSIONS_DIR="${BASE_DIR}/sessions"
CURRENT_SESSION_FILE="${BASE_DIR}/.current-session"
```

If `$SESSIONS_DIR` does not exist or contains no subdirectories, display:

> No sessions found. Start one with `/rnd-framework:rnd-start <task>`.

Then use `AskUserQuestion` with options:
- "Start new pipeline" — run `/rnd-framework:rnd-start`

Otherwise, list all directories under `$SESSIONS_DIR`. Each subdirectory is a session. For each session directory found:

1. **Extract the session ID** from the directory name (e.g., `20260301-143052-a7b3`).

2. **Extract the date** from the first part of the session ID: `YYYYMMDD-HHMMSS` → format as `YYYY-MM-DD`.

3. **Read the task name** from `<session>/protocol.md`: read the first line that starts with `# `, strip the `# ` prefix, and also strip a leading `RND Plan: ` prefix if present (e.g., `# RND Plan: Auth system` → `Auth system`). If `protocol.md` does not exist, use `—` as the task name.

4. **Determine the verdict** by checking `<session>/integration/` for any report files:
   - If any file in `integration/` contains `NO-SHIP`: verdict is `NO-SHIP ❌`
   - If any file in `integration/` contains `SHIP` (but not `NO-SHIP`): verdict is `SHIP ✅`
   - If `integration/` is empty or does not exist: verdict is `Incomplete`

5. **Mark the current session** by reading `$CURRENT_SESSION_FILE`. If the session ID matches the file's contents, append ` *` to the Session ID column.

Display the sessions as a table, sorted by session ID descending (most recent first):

```
Session ID               | Date       | Task                     | Verdict
-------------------------|------------|--------------------------|----------
20260301-143052-a7b3 *   | 2026-03-01 | Auth system              | SHIP ✅
20260301-120000-f2c1     | 2026-03-01 | Fix login bug            | NO-SHIP ❌
20260228-090000-1a2b     | 2026-02-28 | API refactor             | Incomplete
```

(`*` marks the currently active session.)

After displaying the table, use `AskUserQuestion` with options:
- "Start new pipeline" — run `/rnd-framework:rnd-start`
- "View session details" — ask the user to type a session ID, then display: `protocol.md` contents, a list of build manifests from `builds/`, verification reports from `verifications/`, and integration reports from `integration/`
- "Continue current session" — run `/rnd-framework:rnd-status` (only show this option if there is an active session marked with `*`)
