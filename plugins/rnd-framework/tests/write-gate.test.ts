/**
 * Tests for hooks/write-gate.ts — PreToolUse hook for Write and Edit.
 * Auto-allows .rnd/ path operations, no opinion for other paths.
 */

import { describe, expect, test } from "bun:test";
import { join } from "node:path";
import { runHook, runHookRaw } from "./helpers";

const HOOK_PATH = join(import.meta.dir, "..", "hooks", "write-gate.ts");

function makeInput(toolName: string, filePath: string) {
  return { tool_name: toolName, tool_input: { file_path: filePath } };
}

// ---------------------------------------------------------------------------
// Auto-allow .rnd/ paths
// ---------------------------------------------------------------------------

describe("write-gate: auto-allow .rnd/ paths", () => {
  test("Write to .rnd/ path → auto-allow", async () => {
    const result = await runHook(HOOK_PATH, makeInput("Write", "/Users/me/.claude/.rnd/proj-abc/sessions/20260322-120000-abcd/plan.md"));
    expect(result.exitCode).toBe(0);
    const parsed = JSON.parse(result.stdout.trim());
    expect(parsed.hookSpecificOutput.permissionDecision).toBe("allow");
  });

  test("Edit to .rnd/ path → auto-allow", async () => {
    const result = await runHook(HOOK_PATH, makeInput("Edit", "/Users/me/.claude-personal/.rnd/proj-abc/sessions/20260322-120000-abcd/builds/T1-manifest.md"));
    expect(result.exitCode).toBe(0);
    const parsed = JSON.parse(result.stdout.trim());
    expect(parsed.hookSpecificOutput.permissionDecision).toBe("allow");
  });

  test("Write to .rnd/ with different .claude dir name → auto-allow", async () => {
    const result = await runHook(HOOK_PATH, makeInput("Write", "/home/user/.claude-personal/.rnd/proj-abc/sessions/20260322/audit.jsonl"));
    expect(result.exitCode).toBe(0);
    const parsed = JSON.parse(result.stdout.trim());
    expect(parsed.hookSpecificOutput.permissionDecision).toBe("allow");
  });
});

// ---------------------------------------------------------------------------
// No opinion for non-.rnd/ paths
// ---------------------------------------------------------------------------

describe("write-gate: no opinion for non-.rnd/ paths", () => {
  test("Write to project file → no opinion (empty stdout)", async () => {
    const result = await runHook(HOOK_PATH, makeInput("Write", "/Users/me/project/src/index.ts"));
    expect(result.exitCode).toBe(0);
    expect(result.stdout.trim()).toBe("");
  });

  test("Edit to project file → no opinion (empty stdout)", async () => {
    const result = await runHook(HOOK_PATH, makeInput("Edit", "/Users/me/project/lib/utils.ts"));
    expect(result.exitCode).toBe(0);
    expect(result.stdout.trim()).toBe("");
  });

  test("Write to path containing 'rnd' but not .rnd/ → no opinion", async () => {
    const result = await runHook(HOOK_PATH, makeInput("Write", "/Users/me/rnd-project/src/file.ts"));
    expect(result.exitCode).toBe(0);
    expect(result.stdout.trim()).toBe("");
  });
});

// ---------------------------------------------------------------------------
// Resilience
// ---------------------------------------------------------------------------

describe("write-gate: resilience", () => {
  test("malformed stdin → exit 0, no output", async () => {
    const result = await runHookRaw(HOOK_PATH, "not json");
    expect(result.exitCode).toBe(0);
    expect(result.stdout.trim()).toBe("");
  });

  test("empty stdin → exit 0, no output", async () => {
    const result = await runHookRaw(HOOK_PATH, "");
    expect(result.exitCode).toBe(0);
    expect(result.stdout.trim()).toBe("");
  });

  test("missing file_path → exit 0, no output", async () => {
    const result = await runHook(HOOK_PATH, { tool_name: "Write", tool_input: {} });
    expect(result.exitCode).toBe(0);
    expect(result.stdout.trim()).toBe("");
  });

  test("never blocks — always exit 0", async () => {
    const result = await runHook(HOOK_PATH, makeInput("Write", "/etc/passwd"));
    expect(result.exitCode).toBe(0);
    expect(result.stderr.trim()).toBe("");
  });
});
