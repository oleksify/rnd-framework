/**
 * Tests for hooks/observation-mask.ts — PostToolUse/Bash advisory for verbose output.
 */

import { describe, test, expect } from "bun:test";
import { join } from "node:path";
import { runHook, runHookRaw, createTestEnv } from "./helpers";

const HOOK_PATH = join(import.meta.dir, "..", "hooks", "observation-mask.ts");

// ---------------------------------------------------------------------------
// Pure function tests
// ---------------------------------------------------------------------------

describe("shouldAdvise", () => {
  test("returns false for short output", async () => {
    const { shouldAdvise } = await import("../hooks/observation-mask.ts");
    expect(shouldAdvise("line1\nline2\nline3\n")).toBe(false);
  });

  test("returns true for output exceeding threshold", async () => {
    const { shouldAdvise } = await import("../hooks/observation-mask.ts");
    const longOutput = Array.from({ length: 60 }, (_, i) => `line ${i}`).join("\n");
    expect(shouldAdvise(longOutput)).toBe(true);
  });

  test("returns false for exactly 50 lines", async () => {
    const { shouldAdvise } = await import("../hooks/observation-mask.ts");
    const exact = Array.from({ length: 50 }, (_, i) => `line ${i}`).join("\n");
    expect(shouldAdvise(exact)).toBe(false);
  });
});

describe("buildAdvice", () => {
  test("includes line count", async () => {
    const { buildAdvice } = await import("../hooks/observation-mask.ts");
    const msg = buildAdvice(200);
    expect(msg).toContain("200 lines");
  });

  test("includes threshold", async () => {
    const { buildAdvice } = await import("../hooks/observation-mask.ts");
    const msg = buildAdvice(100);
    expect(msg).toContain("threshold: 50");
  });
});

// ---------------------------------------------------------------------------
// Integration tests via runHook
// ---------------------------------------------------------------------------

describe("observation-mask: integration", () => {
  test("emits advisory for verbose output during active session", async () => {
    const env = await createTestEnv({ withSession: true });
    try {
      const longOutput = Array.from({ length: 60 }, (_, i) => `test line ${i}`).join("\n");
      const input = { tool_name: "Bash", stdout: longOutput };
      const result = await runHook(HOOK_PATH, input, env.env);
      expect(result.exitCode).toBe(0);
      expect(result.stdout).toContain("Observation mask");
      expect(result.stdout).toContain("60 lines");
    } finally {
      await env.cleanup();
    }
  });

  test("no output for short Bash output", async () => {
    const env = await createTestEnv({ withSession: true });
    try {
      const input = { tool_name: "Bash", stdout: "ok\n" };
      const result = await runHook(HOOK_PATH, input, env.env);
      expect(result.exitCode).toBe(0);
      expect(result.stdout.trim()).toBe("");
    } finally {
      await env.cleanup();
    }
  });

  test("no output when no active session", async () => {
    const env = await createTestEnv({ withSession: false });
    try {
      const input = { tool_name: "Bash", stdout: Array.from({ length: 100 }, (_, i) => `x${i}`).join("\n") };
      const result = await runHook(HOOK_PATH, input, env.env);
      expect(result.exitCode).toBe(0);
      expect(result.stdout.trim()).toBe("");
    } finally {
      await env.cleanup();
    }
  });

  test("no output for malformed stdin", async () => {
    const env = await createTestEnv({ withSession: true });
    try {
      const result = await runHookRaw(HOOK_PATH, "not json", env.env);
      expect(result.exitCode).toBe(0);
      expect(result.stdout.trim()).toBe("");
    } finally {
      await env.cleanup();
    }
  });
});
