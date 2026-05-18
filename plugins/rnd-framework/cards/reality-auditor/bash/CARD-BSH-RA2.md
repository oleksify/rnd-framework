---
id: BSH-RA2
role: reality-auditor
language: bash
tags: [anomaly, paths, side-effects]
applicable_task_types: [new-feature, infra, refactor]
scope: Flag hard-coded `/tmp/` paths in scripts and recommend `mktemp` or a session-scoped directory instead.
specializes: [P-EFFECTS-EDGE-01]
---

Specializes the effects-at-the-edge principle by surfacing where unscoped temp paths create races, name collisions, and residue that outlives the script's intent.

**Good audit output:**
> `scripts/build-report.sh:34` writes to `/tmp/report.json` unconditionally. If two CI jobs run concurrently they will clobber each other's file and produce corrupted output. The path also persists after the script exits — any sensitive data written there is readable by other processes until the OS clears `/tmp`. Flag: replace with `TMPFILE="$(mktemp)"` and `trap 'rm -f "$TMPFILE"' EXIT` so each invocation gets a unique path that is cleaned up automatically.

**Worse audit output:**
> The script uses `/tmp/report.json` as a temporary file. `/tmp` is the standard location for temporary files in Unix systems.

**Why good is better:** The worse output treats `/tmp` as a safe default without examining the concurrent-access and cleanup implications. Fixed names in a shared directory are a TOCTOU race in CI and a leak vector when the script handles credentials or intermediate build artifacts. The good output names the exact line, explains the two failure modes (collision + residue), and gives the concrete fix (`mktemp` + `trap`). Whenever you see a fixed `/tmp/<name>` path, flag it.
