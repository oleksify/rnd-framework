#!/usr/bin/env bun
// hooks/audit-log.ts — PostToolUse hook for Write and Edit.
//   Appends a JSONL audit entry to $RND_DIR/audit.jsonl for every
//   file write/edit during an active pipeline session.
//
// Output convention:
//   Resilient: always exit 0, never fail.

import { appendFileSync, existsSync } from "node:fs";
import { join } from "node:path";
import { parseInput, resolveRndDir } from "./lib.ts";

async function main(): Promise<void> {
  const input = await parseInput();
  if (input === null) return;

  const file = typeof input.tool_input["file_path"] === "string"
    ? input.tool_input["file_path"]
    : "";
  const tool = input.tool_name;

  if (!file || !tool) return;

  const rndDir = resolveRndDir();
  if (!rndDir || !rndDir.includes("/sessions/")) return;
  if (!existsSync(rndDir)) return;

  const ts = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
  const entry = JSON.stringify({ ts, tool, file }) + "\n";
  appendFileSync(join(rndDir, "audit.jsonl"), entry, "utf-8");
}

try {
  await main();
} catch {
  // Resilient hook: never fail regardless of error
  process.exit(0);
}
