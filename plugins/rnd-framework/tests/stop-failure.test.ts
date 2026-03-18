/**
 * Tests for hooks/stop-failure
 *
 * The hook logs API errors to $RND_DIR/stop-failures.jsonl when a session is
 * active, emits advisory context, and always exits 0.
 */

import { describe, expect, test } from "bun:test";
import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { runHook, runHookRaw, createTestEnv } from "./helpers";

const HOOK_PATH = join(import.meta.dir, "..", "hooks", "stop-failure.ts");

function stopFailureInput(errorType: string, message: string): unknown {
  return { error_type: errorType, message };
}

// ---------------------------------------------------------------------------
// Criterion: always exits 0
// ---------------------------------------------------------------------------

describe("stop-failure: always exits 0", () => {
  test("exits 0 with valid error payload and active session", async () => {
    const env = await createTestEnv({ withSession: true });
    try {
      const result = await runHook(
        HOOK_PATH,
        stopFailureInput("rate_limit_error", "Rate limit exceeded"),
        { CLAUDE_CONFIG_DIR: env.configDir },
      );
      expect(result.exitCode).toBe(0);
    } finally { await env.cleanup(); }
  });

  test("exits 0 with malformed stdin (empty string)", async () => {
    const env = await createTestEnv({ withSession: true });
    try {
      const result = await runHookRaw(HOOK_PATH, "", { CLAUDE_CONFIG_DIR: env.configDir });
      expect(result.exitCode).toBe(0);
    } finally { await env.cleanup(); }
  });

  test("exits 0 with non-JSON stdin", async () => {
    const env = await createTestEnv({ withSession: true });
    try {
      const result = await runHookRaw(HOOK_PATH, "not json", { CLAUDE_CONFIG_DIR: env.configDir });
      expect(result.exitCode).toBe(0);
    } finally { await env.cleanup(); }
  });
});

describe("stop-failure: no active session — no stop-failures.jsonl", () => {
  test("does not create stop-failures.jsonl when no active session exists", async () => {
    const env = await createTestEnv({ withSession: false });
    try {
      await runHook(
        HOOK_PATH,
        stopFailureInput("api_error", "Error"),
        { CLAUDE_CONFIG_DIR: env.configDir },
      );
      expect(existsSync(join(env.baseDir, "stop-failures.jsonl"))).toBe(false);
      expect(existsSync(join(env.sessionDir, "stop-failures.jsonl"))).toBe(false);
    } finally { await env.cleanup(); }
  });
});

describe("stop-failure: active session — JSONL entry written", () => {
  test("creates stop-failures.jsonl in sessionDir when session is active", async () => {
    const env = await createTestEnv({ withSession: true });
    try {
      await runHook(HOOK_PATH, stopFailureInput("rate_limit_error", "Too many requests"), { CLAUDE_CONFIG_DIR: env.configDir });
      expect(existsSync(join(env.sessionDir, "stop-failures.jsonl"))).toBe(true);
    } finally { await env.cleanup(); }
  });

  test("JSONL entry has keys: ts, errorType, message", async () => {
    const env = await createTestEnv({ withSession: true });
    try {
      await runHook(HOOK_PATH, stopFailureInput("overloaded_error", "Overloaded"), { CLAUDE_CONFIG_DIR: env.configDir });
      const raw = await readFile(join(env.sessionDir, "stop-failures.jsonl"), "utf-8");
      const entry = JSON.parse(raw.trim().split("\n")[0]);
      expect(entry).toHaveProperty("ts");
      expect(entry).toHaveProperty("errorType");
      expect(entry).toHaveProperty("message");
    } finally { await env.cleanup(); }
  });

  test("entry.errorType and entry.message match input", async () => {
    const env = await createTestEnv({ withSession: true });
    try {
      await runHook(HOOK_PATH, stopFailureInput("rate_limit_error", "Too many req"), { CLAUDE_CONFIG_DIR: env.configDir });
      const raw = await readFile(join(env.sessionDir, "stop-failures.jsonl"), "utf-8");
      const entry = JSON.parse(raw.trim().split("\n")[0]);
      expect(entry.errorType).toBe("rate_limit_error");
      expect(entry.message).toBe("Too many req");
    } finally { await env.cleanup(); }
  });

  test("falls back to 'unknown' for missing fields in malformed payload", async () => {
    const env = await createTestEnv({ withSession: true });
    try {
      await runHook(HOOK_PATH, { unexpected_key: "value" }, { CLAUDE_CONFIG_DIR: env.configDir });
      const raw = await readFile(join(env.sessionDir, "stop-failures.jsonl"), "utf-8");
      const entry = JSON.parse(raw.trim().split("\n")[0]);
      expect(entry.errorType).toBe("unknown");
      expect(entry.message).toBe("unknown");
    } finally { await env.cleanup(); }
  });
});

describe("stop-failure: advisory context output", () => {
  test("stdout contains hookSpecificOutput.additionalContext", async () => {
    const env = await createTestEnv({ withSession: true });
    try {
      const result = await runHook(
        HOOK_PATH,
        stopFailureInput("rate_limit_error", "Too many requests"),
        { CLAUDE_CONFIG_DIR: env.configDir },
      );
      const parsed = JSON.parse(result.stdout);
      expect(parsed).toHaveProperty("hookSpecificOutput");
      expect(parsed.hookSpecificOutput).toHaveProperty("additionalContext");
      expect(typeof parsed.hookSpecificOutput.additionalContext).toBe("string");
    } finally { await env.cleanup(); }
  });
});
