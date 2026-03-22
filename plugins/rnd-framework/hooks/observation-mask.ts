#!/usr/bin/env bun
// PostToolUse hook for Bash: advises on verbose output.
//
// When Bash output exceeds a threshold (default 50 lines), emits an advisory
// reminding the agent to summarize rather than process raw output.
//
// Always exits 0 — purely advisory, never blocks.
// Skips when no active pipeline session.

import { readStdin, activeSessionDir, advisory, countLines } from "./lib.ts";

const LINE_THRESHOLD = 50;

export function shouldAdvise(output: string): boolean {
  return countLines(output) > LINE_THRESHOLD;
}

export function buildAdvice(lineCount: number): string {
  return (
    `Observation mask: Bash output was ${lineCount} lines (threshold: ${LINE_THRESHOLD}). ` +
    `Summarize the key signal (pass/fail, errors, counts) in 5-10 lines rather than processing raw output. ` +
    `Verbose observations fill context without proportional value.`
  );
}

async function main(): Promise<void> {
  if (!activeSessionDir()) return;

  const text = await readStdin();
  let obj: Record<string, unknown> = {};
  try { obj = JSON.parse(text) as Record<string, unknown>; } catch { return; }

  const output = typeof obj["stdout"] === "string" ? obj["stdout"] : "";
  if (!output || !shouldAdvise(output)) return;

  const lineCount = countLines(output);
  console.log(JSON.stringify(advisory(buildAdvice(lineCount))));
}

try {
  await main();
} catch {
  process.exit(0);
}
