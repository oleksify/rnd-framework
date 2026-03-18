#!/usr/bin/env bun
// hooks/post-compact.ts — TypeScript port of hooks/post-compact (bash).
// Re-injects pipeline state after context compaction by reading compact-state.json
// and outputting it as hookSpecificOutput.additionalContext.
// Resilient: always exits 0, never fails.

import { resolveRndDir, advisory } from "./lib.ts";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

try {
  const rndDir = resolveRndDir();
  if (!rndDir || !rndDir.includes("/sessions/")) process.exit(0);

  const stateFile = join(rndDir, "compact-state.json");
  if (!existsSync(stateFile)) process.exit(0);

  const raw = readFileSync(stateFile, "utf-8");
  const state = JSON.parse(raw) as Record<string, unknown>;

  const plan = typeof state["planSummary"] === "string" ? state["planSummary"] : "";
  if (!plan) process.exit(0);

  const task = typeof state["currentTaskId"] === "string" ? state["currentTaskId"] : "unknown";
  const iter = state["iterationCount"] !== undefined ? String(state["iterationCount"]) : "0";
  const saved = typeof state["savedAt"] === "string" ? state["savedAt"] : "unknown";

  const msg = `Pipeline state restored after compaction:\n  Plan: ${plan}\n  Current task: ${task}\n  Iteration: ${iter}\n  State saved at: ${saved}`;
  console.log(JSON.stringify(advisory(msg)));
} catch {
  process.exit(0);
}
