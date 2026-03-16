#!/usr/bin/env bun
// PostToolUse hook: wellbeing-check
//
// Checks elapsed time since last break suggestion.
// If >=45 minutes have passed (or no timestamp exists), writes current
// timestamp to $RND_DIR/.wellbeing-ts and emits an advisory break message.
// Resilient: always exits 0, never fails.

import { writeFileSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { resolveRndDir, advisory } from "./lib.ts";

const THRESHOLD_SECONDS = 2700; // 45 minutes

async function main(): Promise<void> {
  const rndDir = resolveRndDir();
  if (!rndDir || !rndDir.includes("/sessions/")) return;

  const tsFile = join(rndDir, ".wellbeing-ts");
  const now = Math.floor(Date.now() / 1000);

  try {
    const last = parseInt(readFileSync(tsFile, "utf-8"), 10);
    if (!isNaN(last) && now - last < THRESHOLD_SECONDS) return;
  } catch {
    // No file yet — proceed to write and advise
  }

  writeFileSync(tsFile, String(now), "utf-8");

  const msg =
    "You have been working for a while. Consider taking a 10-15 minute break" +
    " — step away from the screen, stretch, look at something far away." +
    " Your focus quality improves after rest.";
  console.log(JSON.stringify(advisory(msg)));
}

try {
  await main();
} catch {
  process.exit(0);
}
