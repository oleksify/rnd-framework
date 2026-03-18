#!/usr/bin/env bun
// hooks/lib.ts — Shared TypeScript utilities for rnd-framework hooks.
// Import from any hook: import { parseInput, isRndPath, ... } from "./lib.ts"

import { resolve } from "node:path";

// ---------------------------------------------------------------------------
// Code file extension allowlist
// ---------------------------------------------------------------------------

export const CODE_EXTENSIONS = new Set([
  ".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs",
  ".py", ".rb", ".go", ".rs", ".java",
  ".c", ".cpp", ".h", ".hpp", ".cs",
  ".swift", ".kt", ".scala",
  ".sh", ".bash", ".zsh", ".fish",
  ".lua", ".php", ".vue", ".svelte",
  ".ex", ".exs",
]);

/** Returns true if the file has a recognised source-code extension. Pure. */
export function isCodeFile(filePath: string): boolean {
  const lastDot = filePath.lastIndexOf(".");
  if (lastDot === -1) return false;
  const ext = filePath.slice(lastDot).toLowerCase();
  return CODE_EXTENSIONS.has(ext);
}

// ---------------------------------------------------------------------------
// Path utilities
// ---------------------------------------------------------------------------

/** Returns true if path contains .rnd/ under a .claude config directory. Pure. */
export function isRndPath(path: string): boolean {
  return /\.claude[^/]*\/.*\.rnd\//.test(path);
}

/** Returns true if path contains plugins/cache/ under a .claude config directory. Pure. */
export function isPluginCachePath(path: string): boolean {
  return /\.claude[^/]*\/.*plugins\/cache\//.test(path);
}

/**
 * Shells out to lib/rnd-dir.sh and returns the resolved path.
 * Passes all provided flags (e.g. "-c", "--base") directly to the script.
 * Returns null if the script fails or returns empty output.
 * Uses Bun.spawnSync — no execSync.
 */
export function resolveRndDir(...args: string[]): string | null {
  const scriptPath = resolve(import.meta.dir, "..", "lib", "rnd-dir.sh");
  const result = Bun.spawnSync([scriptPath, ...args], { stderr: "ignore" });
  if (result.exitCode !== 0) return null;
  const out = new TextDecoder().decode(result.stdout).trim();
  return out.length > 0 ? out : null;
}

// ---------------------------------------------------------------------------
// Hook response constructors
// ---------------------------------------------------------------------------

/** Returns the allow JSON object for a PreToolUse hook. Pure. */
export function allow(): { hookSpecificOutput: { hookEventName: string; permissionDecision: string } } {
  return { hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: "allow" } };
}

/** Returns an advisory JSON object for PostToolUse hooks. Pure. */
export function advisory(msg: string): { hookSpecificOutput: { additionalContext: string } } {
  return { hookSpecificOutput: { additionalContext: msg } };
}

/**
 * Writes msg to stderr and exits with code 2.
 * Used to block a tool operation from a PreToolUse hook.
 * Side-effectful — not pure.
 */
export function block(msg: string): never {
  process.stderr.write(msg + "\n");
  process.exit(2);
}

// ---------------------------------------------------------------------------
// Stdin reading + input parsing
// ---------------------------------------------------------------------------

/** Typed shape of the JSON Claude Code sends to every hook on stdin. */
export interface HookInput {
  tool_name: string;
  tool_input: Record<string, unknown>;
  agent_type: string;
}

/**
 * Reads all bytes from Bun.stdin and returns them as a UTF-8 string.
 * I/O function — not pure.
 */
export async function readStdin(): Promise<string> {
  const buf = await Bun.readableStreamToArrayBuffer(Bun.stdin.stream());
  return new TextDecoder().decode(buf);
}

/**
 * Reads stdin and parses it as a HookInput JSON object.
 * Returns null if stdin is empty, malformed, or missing required fields.
 * I/O function — not pure.
 */
export async function parseInput(): Promise<HookInput | null> {
  const text = await readStdin();
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    return null;
  }
  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
    return null;
  }
  const obj = parsed as Record<string, unknown>;
  return {
    tool_name: typeof obj["tool_name"] === "string" ? obj["tool_name"] : "",
    tool_input: (typeof obj["tool_input"] === "object" && obj["tool_input"] !== null && !Array.isArray(obj["tool_input"]))
      ? obj["tool_input"] as Record<string, unknown>
      : {},
    agent_type: typeof obj["agent_type"] === "string" ? obj["agent_type"] : "",
  };
}
