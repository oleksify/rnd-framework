#!/usr/bin/env bun
// hooks/post-compact.ts — TypeScript port of hooks/post-compact (bash).
// Re-injects pipeline state after context compaction by reading compact-state.json
// and outputting it as hookSpecificOutput.additionalContext.
// Resilient: always exits 0, never fails.

import { activeSessionDir, advisory } from "./lib.ts";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

try {
  const rndDir = activeSessionDir();
  if (!rndDir) process.exit(0);

  const stateFile = join(rndDir, "compact-state.json");
  if (!existsSync(stateFile)) process.exit(0);

  const raw = readFileSync(stateFile, "utf-8");
  const state = JSON.parse(raw) as Record<string, unknown>;

  const plan = typeof state["planSummary"] === "string" ? state["planSummary"] : "";
  if (!plan) process.exit(0);

  const task = typeof state["currentTaskId"] === "string" ? state["currentTaskId"] : "unknown";
  const iter = state["iterationCount"] !== undefined ? String(state["iterationCount"]) : "0";
  const saved = typeof state["savedAt"] === "string" ? state["savedAt"] : "unknown";
  const needle = typeof state["verificationNeedle"] === "string" ? state["verificationNeedle"] : "";

  let msg = `Pipeline state restored after compaction:\n  Plan: ${plan}\n  Current task: ${task}\n  Iteration: ${iter}\n  State saved at: ${saved}`;
  if (needle) {
    msg += `\n\nVERIFICATION CHECK: Confirm your context survived compaction by stating: (1) current task ID: ${task}, (2) iteration count: ${iter}, (3) needle: ${needle}. If you cannot answer these, re-read $RND_DIR/plan.md before continuing.`;
  }
  console.log(JSON.stringify(advisory(msg)));
} catch {
  process.exit(0);
}
