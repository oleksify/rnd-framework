#!/usr/bin/env bun
// hooks/session-end.ts — Clears the active RND session on session close/switch.
// Calls rnd-dir.sh --finish to remove .current-session. Idempotent, always exits 0.
import { resolve } from "node:path";

function main(): void {
  const scriptPath = resolve(import.meta.dir, "..", "lib", "rnd-dir.sh");
  Bun.spawnSync([scriptPath, "--finish"], { stderr: "ignore" });
}

try { main(); } catch { /* always exit 0 */ }
