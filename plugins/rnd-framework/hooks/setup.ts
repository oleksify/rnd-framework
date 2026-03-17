#!/usr/bin/env bun
// hooks/setup.ts — TypeScript port of hooks/setup (bash).
// Reports plugin validation status and dependency availability.
// Always exits 0 — status reporter, not a gate.

import { resolve } from "node:path";

const PLUGIN_ROOT = resolve(import.meta.dir, "..");

function runValidate(): { status: "pass" | "fail"; passCount: number; failCount: number } {
  const scriptPath = resolve(PLUGIN_ROOT, "lib", "validate.ts");
  const result = Bun.spawnSync(["bun", scriptPath], { stderr: "pipe" });
  const out = new TextDecoder().decode(result.stdout) +
              new TextDecoder().decode(result.stderr);
  const status = result.exitCode === 0 ? "pass" : "fail";
  const passCount = (out.match(/  PASS  /g) ?? []).length;
  const failCount = (out.match(/  FAIL  /g) ?? []).length;
  return { status, passCount, failCount };
}

function checkTool(name: string, versionFlag: string): string {
  const which = Bun.spawnSync(["which", name], { stderr: "ignore" });
  if (which.exitCode !== 0) return "not found";
  const ver = Bun.spawnSync([name, versionFlag], { stderr: "pipe" });
  const raw = new TextDecoder().decode(ver.stdout).trim() ||
              new TextDecoder().decode(ver.stderr).trim();
  const version = raw.length > 0 ? raw : "unknown";
  return `available (${version})`;
}

const { status, passCount, failCount } = runValidate();
const bunStatus = checkTool("bun", "--version");
const jqStatus = checkTool("jq", "--version");

const ctx = [
  `rnd-framework setup:`,
  `  Validation: ${status} (${passCount} pass, ${failCount} fail)`,
  `  bun: ${bunStatus}`,
  `  jq: ${jqStatus}`,
].join("\n");

console.log(JSON.stringify({
  hookSpecificOutput: { hookEventName: "Setup", additionalContext: ctx },
}));

process.exit(0);
