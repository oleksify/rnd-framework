#!/usr/bin/env bun
// hooks/pre-compact.ts — PreCompact hook for rnd-framework plugin.
// Saves pipeline state to $RND_DIR/compact-state.json before context compaction.
//
// Fire-and-forget: exits 0 always, produces no stdout.
// Reads: plan.md, builds/T*-manifest.md, iteration-log.md

import { readFileSync, readdirSync, statSync, existsSync, writeFileSync } from "node:fs";
import { join, basename } from "node:path";
import { activeSessionDir, isoTimestamp } from "./lib.ts";

// ---------------------------------------------------------------------------
// Pure helpers
// ---------------------------------------------------------------------------

/** Returns first 5 lines of plan.md content, or "no plan" if absent. Pure. */
export function extractPlanSummary(rndDir: string): string {
  const planFile = join(rndDir, "plan.md");
  if (!existsSync(planFile)) return "no plan";
  try {
    const content = readFileSync(planFile, "utf-8");
    return content.split("\n").slice(0, 5).join("\n");
  } catch {
    return "no plan";
  }
}

/** Returns task ID from most recent T*-manifest.md, or null. Pure. */
export function extractCurrentTaskId(rndDir: string): string | null {
  const buildsDir = join(rndDir, "builds");
  if (!existsSync(buildsDir)) return null;
  try {
    const files = readdirSync(buildsDir).filter((f) => /^T\w+-manifest\.md$/.test(f));
    if (files.length === 0) return null;
    const sorted = files
      .map((f) => ({ name: f, mtime: statSync(join(buildsDir, f)).mtimeMs }))
      .sort((a, b) => b.mtime - a.mtime);
    return basename(sorted[0].name, "-manifest.md");
  } catch {
    return null;
  }
}

/** Returns line count of iteration-log.md, or 0 if absent. Pure. */
export function extractIterationCount(rndDir: string): number {
  const logFile = join(rndDir, "iteration-log.md");
  if (!existsSync(logFile)) return 0;
  try {
    const content = readFileSync(logFile, "utf-8");
    return content.split("\n").length;
  } catch {
    return 0;
  }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main(): Promise<void> {
  const rndDir = activeSessionDir();
  if (!rndDir) process.exit(0);

  const state = {
    planSummary: extractPlanSummary(rndDir),
    currentTaskId: extractCurrentTaskId(rndDir),
    iterationCount: extractIterationCount(rndDir),
    savedAt: isoTimestamp(),
  };

  try {
    writeFileSync(join(rndDir, "compact-state.json"), JSON.stringify(state, null, 2), "utf-8");
  } catch {
    // Fire-and-forget: never fail
  }
  process.exit(0);
}

try {
  await main();
} catch {
  process.exit(0);
}
