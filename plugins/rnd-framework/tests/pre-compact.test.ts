/**
 * Tests for hooks/pre-compact
 *
 * Covers all success criteria from T1 pre-registration:
 *   1. Hook exits 0 with active session, no stdout
 *   2. compact-state.json is created and is valid JSON
 *   3. compact-state.json contains required keys
 *   4. No compact-state.json when no active session
 */

import { describe, test, expect } from "bun:test";
import { writeFile, readFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { join } from "node:path";
import { runHook, createTestEnv } from "./helpers";

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const HOOK_PATH = join(import.meta.dir, "..", "hooks", "pre-compact.ts");

// Build minimal hook stdin JSON (PreCompact event has no tool_input)
function hookInput(): unknown {
  return { hook_event_name: "PreCompact" };
}

const PLUGIN_ROOT = join(import.meta.dir, "..");
const HOOKS_JSON = join(PLUGIN_ROOT, "hooks", "hooks.json");

// ---------------------------------------------------------------------------
// Criterion: hooks.json has a PreCompact entry
// ---------------------------------------------------------------------------

describe("pre-compact: hooks.json registration", () => {
  test("hooks.json has a PreCompact key", async () => {
    const raw = await readFile(HOOKS_JSON, "utf-8");
    const parsed = JSON.parse(raw) as Record<string, unknown>;
    expect((parsed["hooks"] as Record<string, unknown>)).toHaveProperty("PreCompact");
  });

  test("PreCompact entry references the pre-compact script", async () => {
    const raw = await readFile(HOOKS_JSON, "utf-8");
    expect(raw).toContain("pre-compact");
  });
});

// ---------------------------------------------------------------------------
// Criterion: exits 0 and produces no stdout with an active session
// ---------------------------------------------------------------------------

describe("pre-compact: active session — exits 0 with no stdout", () => {
  test("exits 0 when an active session exists", async () => {
    const env = await createTestEnv({ withSession: true });
    try {
      const result = await runHook(HOOK_PATH, {}, { CLAUDE_CONFIG_DIR: env.configDir });
      expect(result.exitCode).toBe(0);
    } finally {
      await env.cleanup();
    }
  });

  test("produces no stdout when an active session exists", async () => {
    const env = await createTestEnv({ withSession: true });
    try {
      const result = await runHook(HOOK_PATH, {}, { CLAUDE_CONFIG_DIR: env.configDir });
      expect(result.stdout.trim()).toBe("");
    } finally {
      await env.cleanup();
    }
  });
});

// ---------------------------------------------------------------------------
// Criterion: compact-state.json created and is valid JSON
// ---------------------------------------------------------------------------

describe("pre-compact: compact-state.json is created and valid JSON", () => {
  test("creates compact-state.json in sessionDir after invocation", async () => {
    const env = await createTestEnv({ withSession: true });
    try {
      await runHook(HOOK_PATH, hookInput(), { CLAUDE_CONFIG_DIR: env.configDir });
      const statePath = join(env.sessionDir, "compact-state.json");
      expect(existsSync(statePath)).toBe(true);
    } finally {
      await env.cleanup();
    }
  });

  test("compact-state.json is valid JSON", async () => {
    const env = await createTestEnv({ withSession: true });
    try {
      await runHook(HOOK_PATH, hookInput(), { CLAUDE_CONFIG_DIR: env.configDir });
      const statePath = join(env.sessionDir, "compact-state.json");
      const raw = await readFile(statePath, "utf-8");
      expect(() => JSON.parse(raw)).not.toThrow();
    } finally {
      await env.cleanup();
    }
  });
});

describe("pre-compact: compact-state.json has required keys", () => {
  test("contains planSummary, currentTaskId, iterationCount, savedAt", async () => {
    const env = await createTestEnv({ withSession: true });
    try {
      await runHook(HOOK_PATH, hookInput(), { CLAUDE_CONFIG_DIR: env.configDir });
      const state = JSON.parse(
        await readFile(join(env.sessionDir, "compact-state.json"), "utf-8"),
      );
      expect(state).toHaveProperty("planSummary");
      expect(state).toHaveProperty("currentTaskId");
      expect(state).toHaveProperty("iterationCount");
      expect(state).toHaveProperty("savedAt");
    } finally { await env.cleanup(); }
  });
});

describe("pre-compact: savedAt is ISO 8601 UTC", () => {
  test("savedAt matches /^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$/", async () => {
    const env = await createTestEnv({ withSession: true });
    try {
      await runHook(HOOK_PATH, hookInput(), { CLAUDE_CONFIG_DIR: env.configDir });
      const state = JSON.parse(
        await readFile(join(env.sessionDir, "compact-state.json"), "utf-8"),
      );
      expect(state.savedAt).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/);
    } finally { await env.cleanup(); }
  });
});

describe("pre-compact: planSummary reflects plan.md content", () => {
  test("planSummary is 'no plan' when plan.md is absent", async () => {
    const env = await createTestEnv({ withSession: true });
    try {
      await runHook(HOOK_PATH, hookInput(), { CLAUDE_CONFIG_DIR: env.configDir });
      const state = JSON.parse(
        await readFile(join(env.sessionDir, "compact-state.json"), "utf-8"),
      );
      expect(state.planSummary).toBe("no plan");
    } finally { await env.cleanup(); }
  });

  test("planSummary contains first-line content from plan.md", async () => {
    const env = await createTestEnv({ withSession: true });
    try {
      await writeFile(join(env.sessionDir, "plan.md"), "# Test Plan\nTask T1\n", "utf-8");
      await runHook(HOOK_PATH, hookInput(), { CLAUDE_CONFIG_DIR: env.configDir });
      const state = JSON.parse(
        await readFile(join(env.sessionDir, "compact-state.json"), "utf-8"),
      );
      expect(state.planSummary).toContain("# Test Plan");
    } finally { await env.cleanup(); }
  });
});

describe("pre-compact: currentTaskId is null when no builds exist", () => {
  test("currentTaskId is null when builds/ has no manifests", async () => {
    const env = await createTestEnv({ withSession: true });
    try {
      await runHook(HOOK_PATH, hookInput(), { CLAUDE_CONFIG_DIR: env.configDir });
      const state = JSON.parse(
        await readFile(join(env.sessionDir, "compact-state.json"), "utf-8"),
      );
      expect(state.currentTaskId).toBeNull();
    } finally { await env.cleanup(); }
  });
});

describe("pre-compact: no active session — exits 0 and no compact-state.json", () => {
  test("exits 0 when no active session exists", async () => {
    const env = await createTestEnv({ withSession: false });
    try {
      const result = await runHook(HOOK_PATH, hookInput(), { CLAUDE_CONFIG_DIR: env.configDir });
      expect(result.exitCode).toBe(0);
    } finally { await env.cleanup(); }
  });

  test("does not create compact-state.json when no active session", async () => {
    const env = await createTestEnv({ withSession: false });
    try {
      await runHook(HOOK_PATH, hookInput(), { CLAUDE_CONFIG_DIR: env.configDir });
      expect(existsSync(join(env.sessionDir, "compact-state.json"))).toBe(false);
      expect(existsSync(join(env.baseDir, "compact-state.json"))).toBe(false);
    } finally { await env.cleanup(); }
  });
});

