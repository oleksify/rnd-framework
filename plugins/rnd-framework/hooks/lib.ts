#!/usr/bin/env bun
// hooks/lib.ts — Shared TypeScript utilities for rnd-framework hooks.
// Import from any hook: import { parseInput, isRndPath, ... } from "./lib.ts"

import { existsSync } from "node:fs";
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

/** Counts logical lines in a string. Empty string is 0. Trailing newline does not add an extra line. Pure. */
export function countLines(content: string): number {
  if (content.length === 0) return 0;
  const parts = content.split("\n");
  return content.endsWith("\n") ? parts.length - 1 : parts.length;
}

/**
 * Shells out to lib/rnd-dir.sh and returns the resolved path.
 * Passes all provided flags (e.g. "-c", "--base") directly to the script.
 * Returns null if the script fails or returns empty output.
 * Uses Bun.spawnSync — no execSync.
 * Memoized: repeated calls with the same args return the cached result.
 */
const _resolveRndDirCache = new Map<string, string | null>();

export function resolveRndDir(...args: string[]): string | null {
  const key = args.join("\0");
  if (_resolveRndDirCache.has(key)) return _resolveRndDirCache.get(key)!;
  const scriptPath = resolve(import.meta.dir, "..", "lib", "rnd-dir.sh");
  const result = Bun.spawnSync([scriptPath, ...args], { stderr: "ignore" });
  if (result.exitCode !== 0) { _resolveRndDirCache.set(key, null); return null; }
  const out = new TextDecoder().decode(result.stdout).trim();
  const val = out.length > 0 ? out : null;
  _resolveRndDirCache.set(key, val);
  return val;
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

// ---------------------------------------------------------------------------
// Shared hook helpers
// ---------------------------------------------------------------------------

/**
 * Extracts the written content string from Write or Edit tool input.
 * Write → tool_input.content; Edit → tool_input.new_string.
 * Returns null for any other tool name or when the expected key is absent or not a string.
 * Pure.
 */
export function extractWriteEditContent(toolName: string, toolInput: Record<string, unknown>): string | null {
  if (toolName === "Write") {
    const c = toolInput["content"];
    return typeof c === "string" ? c : null;
  }
  if (toolName === "Edit") {
    const ns = toolInput["new_string"];
    return typeof ns === "string" ? ns : null;
  }
  return null;
}

/**
 * Extracts the file_path string from tool input.
 * Returns null when file_path is absent or not a string.
 * Pure.
 */
export function extractFilePath(toolInput: Record<string, unknown>): string | null {
  const fp = toolInput["file_path"];
  return typeof fp === "string" ? fp : null;
}

/**
 * Returns an ISO 8601 UTC timestamp string without milliseconds (e.g. "2025-03-22T09:10:11Z").
 * Pure (deterministic for a given wall-clock moment).
 */
export function isoTimestamp(): string {
  return new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
}

/** Generates a short random hex string for needle-in-the-haystack verification. Pure (given crypto source). */
export function generateNeedle(): string {
  const bytes = new Uint8Array(4);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

/**
 * Resolves the active RND session directory, validates it contains /sessions/ and exists on disk.
 * Returns the directory path if all conditions hold, null otherwise.
 * Uses existsSync for directory check — Bun.file().exists() only works for files, not directories.
 */
export function activeSessionDir(): string | null {
  const dir = resolveRndDir();
  if (dir === null || !dir.includes("/sessions/")) return null;
  if (!existsSync(dir)) return null;
  return dir;
}
