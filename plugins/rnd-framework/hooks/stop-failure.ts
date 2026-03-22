#!/usr/bin/env bun
// hooks/stop-failure.ts — Logs StopFailure API errors to $RND_DIR/stop-failures.jsonl.
// Always exits 0. StopFailure events do not have tool_name/tool_input; read stdin directly.
import { appendFileSync } from "node:fs";
import { join } from "node:path";
import { readStdin, activeSessionDir, isoTimestamp, advisory } from "./lib.ts";

async function main(): Promise<void> {
  const text = await readStdin();
  let obj: Record<string, unknown> = {};
  try { obj = JSON.parse(text) as Record<string, unknown>; } catch { /* fall through */ }

  const errorType = typeof obj["error_type"] === "string" ? obj["error_type"] : "unknown";
  const message = typeof obj["message"] === "string" ? obj["message"] : "unknown";

  const rndDir = activeSessionDir();
  if (rndDir) {
    const entry = JSON.stringify({ ts: isoTimestamp(), errorType, message }) + "\n";
    appendFileSync(join(rndDir, "stop-failures.jsonl"), entry, "utf-8");
  }

  console.log(JSON.stringify(advisory(
    "API error encountered. Wait a moment before retrying, or adjust rate limits if errors persist.",
  )));
}

try { await main(); } catch { process.exit(0); }
