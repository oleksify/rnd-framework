/**
 * Tests for hooks/wellbeing-check
 *
 * The hook reads a .wellbeing-ts file in $RND_DIR. If it doesn't exist or
 * is >=45 minutes old, the hook creates/updates it and outputs a JSON break
 * suggestion. If the file is <45 minutes old, the hook exits silently (exit 0,
 * no stdout). Always exits 0.
 */
import { describe, expect, test } from "bun:test";
import { writeFile, readFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { join } from "node:path";
import { runHook, runHookRaw, createTestEnv } from "./helpers";

const HOOK_PATH = join(import.meta.dir, "..", "hooks", "wellbeing-check.ts");

// ---------------------------------------------------------------------------
// Criterion 1: no .wellbeing-ts → creates file + emits additionalContext
// ---------------------------------------------------------------------------

describe("wellbeing-check: no timestamp file", () => {
  test("creates .wellbeing-ts and emits additionalContext when no timestamp file exists", async () => {
    const env = await createTestEnv({ withSession: true });
    try {
      const result = await runHook(HOOK_PATH, {}, { CLAUDE_CONFIG_DIR: env.configDir });
      const tsFile = join(env.sessionDir, ".wellbeing-ts");
      expect(existsSync(tsFile)).toBe(true);
      expect(result.stdout.trim()).not.toBe("");
    } finally {
      await env.cleanup();
    }
  });
});

// ---------------------------------------------------------------------------
// Criterion 2: .wellbeing-ts <45min old → no stdout, exit 0
// ---------------------------------------------------------------------------

describe("wellbeing-check: recent timestamp", () => {
  test("emits no stdout when .wellbeing-ts is less than 45 minutes old", async () => {
    const env = await createTestEnv({ withSession: true });
    try {
      const nowEpoch = Math.floor(Date.now() / 1000);
      await writeFile(join(env.sessionDir, ".wellbeing-ts"), String(nowEpoch), "utf-8");
      const result = await runHook(HOOK_PATH, {}, { CLAUDE_CONFIG_DIR: env.configDir });
      expect(result.exitCode).toBe(0);
      expect(result.stdout.trim()).toBe("");
    } finally {
      await env.cleanup();
    }
  });
});

// Criterion 3: old timestamp → emits output + updates
describe("wellbeing-check: old timestamp", () => {
  test("emits additionalContext when .wellbeing-ts is >=45 min old", async () => {
    const env = await createTestEnv({ withSession: true });
    try {
      const oldEpoch = Math.floor(Date.now() / 1000) - 3600;
      const tsFile = join(env.sessionDir, ".wellbeing-ts");
      await writeFile(tsFile, String(oldEpoch), "utf-8");
      const result = await runHook(HOOK_PATH, {}, { CLAUDE_CONFIG_DIR: env.configDir });
      expect(result.exitCode).toBe(0);
      expect(result.stdout.trim()).not.toBe("");
      const newTs = parseInt(await readFile(tsFile, "utf-8"), 10);
      expect(newTs).toBeGreaterThan(oldEpoch);
    } finally {
      await env.cleanup();
    }
  });
});

// Criterion 4: no active session → exit 0, no output
describe("wellbeing-check: no active session", () => {
  test("exits 0 with no output when no session", async () => {
    const env = await createTestEnv({ withSession: false });
    try {
      const result = await runHook(HOOK_PATH, {}, { CLAUDE_CONFIG_DIR: env.configDir });
      expect(result.exitCode).toBe(0);
      expect(result.stdout.trim()).toBe("");
    } finally {
      await env.cleanup();
    }
  });
});

// Criterion 5: malformed stdin
describe("wellbeing-check: malformed stdin", () => {
  test("exits 0 on empty stdin", async () => {
    const env = await createTestEnv({ withSession: true });
    try {
      const r = await runHookRaw(HOOK_PATH, "", { CLAUDE_CONFIG_DIR: env.configDir });
      expect(r.exitCode).toBe(0);
    } finally { await env.cleanup(); }
  });
});

// Criterion 6: output format
describe("wellbeing-check: output format", () => {
  test("output is valid JSON with additionalContext", async () => {
    const env = await createTestEnv({ withSession: true });
    try {
      const r = await runHook(HOOK_PATH, {}, { CLAUDE_CONFIG_DIR: env.configDir });
      const p = JSON.parse(r.stdout.trim());
      expect(p.hookSpecificOutput).toHaveProperty("additionalContext");
    } finally { await env.cleanup(); }
  });
});
