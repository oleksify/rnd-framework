/**
 * Tests for hooks/post-compact
 *
 * Covers all success criteria from T2 pre-registration:
 *   1. Hook exits 0 and produces valid JSON when compact-state.json present
 *   2. stdout JSON contains hookSpecificOutput.additionalContext with pipeline state
 *   3. No stdout when compact-state.json is absent
 *   4. No stdout (exits 0) when compact-state.json is malformed
 *   5. hooks.json contains a PostCompact entry
 */

import { describe, test, expect } from "bun:test";
import { writeFile, readFile } from "node:fs/promises";
import { join } from "node:path";
import { runHook, runHookRaw, createTestEnv } from "./helpers";

const HOOK_PATH = join(import.meta.dir, "..", "hooks", "post-compact.ts");
const PLUGIN_ROOT = join(import.meta.dir, "..");
const HOOKS_JSON = join(PLUGIN_ROOT, "hooks", "hooks.json");

const SAMPLE_STATE = {
  planSummary: "# Test Plan\nTask T1",
  currentTaskId: "T1",
  iterationCount: 3,
  savedAt: "2026-03-05T12:00:00Z",
};

async function writeState(dir: string, state: unknown = SAMPLE_STATE): Promise<void> {
  await writeFile(join(dir, "compact-state.json"), JSON.stringify(state), "utf-8");
}

describe("post-compact: hooks.json registration", () => {
  test("hooks.json has a PostCompact key", async () => {
    const raw = await readFile(HOOKS_JSON, "utf-8");
    const parsed = JSON.parse(raw) as Record<string, unknown>;
    expect((parsed["hooks"] as Record<string, unknown>)).toHaveProperty("PostCompact");
  });

  test("PostCompact entry references the post-compact script", async () => {
    const raw = await readFile(HOOKS_JSON, "utf-8");
    expect(raw).toContain("post-compact");
  });
});

describe("post-compact: compact-state.json present — exits 0 with valid JSON", () => {
  test("exits 0 when compact-state.json exists", async () => {
    const env = await createTestEnv({ withSession: true });
    try {
      await writeState(env.sessionDir);
      const r = await runHook(HOOK_PATH, {}, { CLAUDE_CONFIG_DIR: env.configDir });
      expect(r.exitCode).toBe(0);
    } finally { await env.cleanup(); }
  });

  test("stdout is valid JSON when compact-state.json exists", async () => {
    const env = await createTestEnv({ withSession: true });
    try {
      await writeState(env.sessionDir);
      const r = await runHook(HOOK_PATH, {}, { CLAUDE_CONFIG_DIR: env.configDir });
      expect(() => JSON.parse(r.stdout)).not.toThrow();
    } finally { await env.cleanup(); }
  });
});

describe("post-compact: stdout JSON has hookSpecificOutput.additionalContext", () => {
  test("stdout JSON has hookSpecificOutput.additionalContext key", async () => {
    const env = await createTestEnv({ withSession: true });
    try {
      await writeState(env.sessionDir);
      const r = await runHook(HOOK_PATH, {}, { CLAUDE_CONFIG_DIR: env.configDir });
      const out = JSON.parse(r.stdout);
      expect(out).toHaveProperty("hookSpecificOutput");
      expect(out.hookSpecificOutput).toHaveProperty("additionalContext");
    } finally { await env.cleanup(); }
  });

  test("additionalContext mentions planSummary", async () => {
    const env = await createTestEnv({ withSession: true });
    try {
      await writeState(env.sessionDir);
      const r = await runHook(HOOK_PATH, {}, { CLAUDE_CONFIG_DIR: env.configDir });
      const out = JSON.parse(r.stdout);
      expect(out.hookSpecificOutput.additionalContext).toContain("# Test Plan");
    } finally { await env.cleanup(); }
  });

  test("additionalContext mentions currentTaskId", async () => {
    const env = await createTestEnv({ withSession: true });
    try {
      await writeState(env.sessionDir);
      const r = await runHook(HOOK_PATH, {}, { CLAUDE_CONFIG_DIR: env.configDir });
      const out = JSON.parse(r.stdout);
      expect(out.hookSpecificOutput.additionalContext).toContain("T1");
    } finally { await env.cleanup(); }
  });

  test("additionalContext mentions iterationCount", async () => {
    const env = await createTestEnv({ withSession: true });
    try {
      await writeState(env.sessionDir);
      const r = await runHook(HOOK_PATH, {}, { CLAUDE_CONFIG_DIR: env.configDir });
      const out = JSON.parse(r.stdout);
      expect(out.hookSpecificOutput.additionalContext).toContain("3");
    } finally { await env.cleanup(); }
  });

  test("additionalContext mentions savedAt", async () => {
    const env = await createTestEnv({ withSession: true });
    try {
      await writeState(env.sessionDir);
      const r = await runHook(HOOK_PATH, {}, { CLAUDE_CONFIG_DIR: env.configDir });
      const out = JSON.parse(r.stdout);
      expect(out.hookSpecificOutput.additionalContext).toContain("2026-03-05T12:00:00Z");
    } finally { await env.cleanup(); }
  });
});

describe("post-compact: no compact-state.json — exits 0 with no stdout", () => {
  test("exits 0 when compact-state.json is absent", async () => {
    const env = await createTestEnv({ withSession: true });
    try {
      const r = await runHook(HOOK_PATH, {}, { CLAUDE_CONFIG_DIR: env.configDir });
      expect(r.exitCode).toBe(0);
    } finally { await env.cleanup(); }
  });

  test("produces no stdout when compact-state.json is absent", async () => {
    const env = await createTestEnv({ withSession: true });
    try {
      const r = await runHook(HOOK_PATH, {}, { CLAUDE_CONFIG_DIR: env.configDir });
      expect(r.stdout.trim()).toBe("");
    } finally { await env.cleanup(); }
  });
});

describe("post-compact: malformed compact-state.json — exits 0 with no stdout", () => {
  test("exits 0 when compact-state.json is malformed", async () => {
    const env = await createTestEnv({ withSession: true });
    try {
      await writeFile(join(env.sessionDir, "compact-state.json"), "not json!!", "utf-8");
      const r = await runHook(HOOK_PATH, {}, { CLAUDE_CONFIG_DIR: env.configDir });
      expect(r.exitCode).toBe(0);
    } finally { await env.cleanup(); }
  });

  test("produces no stdout when compact-state.json is malformed", async () => {
    const env = await createTestEnv({ withSession: true });
    try {
      await writeFile(join(env.sessionDir, "compact-state.json"), "not json!!", "utf-8");
      const r = await runHook(HOOK_PATH, {}, { CLAUDE_CONFIG_DIR: env.configDir });
      expect(r.stdout.trim()).toBe("");
    } finally { await env.cleanup(); }
  });
});
