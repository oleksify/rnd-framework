/**
 * Tests for hooks/statusline.ts
 *
 * The script reads JSON from stdin with a rate_limits field and outputs
 * {"text": "..."} for the Claude Code v2.1.80 status bar.
 */

import { describe, expect, test } from "bun:test";
import { join } from "node:path";
import { mkdir, writeFile } from "node:fs/promises";
import { runHook, runHookRaw, createTestEnv } from "./helpers";

const HOOK_PATH = join(import.meta.dir, "..", "hooks", "statusline.ts");

type RateEntry = { used_percentage: number; resets_at: string };

function rateLimitsInput(fiveHour?: RateEntry, sevenDay?: RateEntry): unknown {
  const rate_limits: Record<string, unknown> = {};
  if (fiveHour) rate_limits["fiveHour"] = fiveHour;
  if (sevenDay) rate_limits["sevenDay"] = sevenDay;
  return { rate_limits };
}

const RL5 = { used_percentage: 42, resets_at: "2026-03-20T12:00:00Z" };
const RL7 = { used_percentage: 18, resets_at: "2026-03-27T12:00:00Z" };

// ---------------------------------------------------------------------------
// Criterion: output includes 5h and 7d usage percentages
// ---------------------------------------------------------------------------

describe("statusline: includes 5h usage percentage", () => {
  test("text contains '5h: 42%' when fiveHour.used_percentage is 42", async () => {
    const env = await createTestEnv({ withSession: false });
    try {
      const result = await runHook(HOOK_PATH, rateLimitsInput(RL5), { CLAUDE_CONFIG_DIR: env.configDir });
      const parsed = JSON.parse(result.stdout);
      expect(parsed.text).toContain("5h: 42%");
    } finally { await env.cleanup(); }
  });
});

describe("statusline: includes 7d usage percentage", () => {
  test("text contains '7d: 18%' when sevenDay.used_percentage is 18", async () => {
    const env = await createTestEnv({ withSession: false });
    try {
      const result = await runHook(HOOK_PATH, rateLimitsInput(RL5, RL7), { CLAUDE_CONFIG_DIR: env.configDir });
      const parsed = JSON.parse(result.stdout);
      expect(parsed.text).toContain("7d: 18%");
    } finally { await env.cleanup(); }
  });
});

describe("statusline: pipeline phase — building/verifying", () => {
  test("text contains 'Building' when builds/ has a manifest file", async () => {
    const env = await createTestEnv({ withSession: true });
    try {
      await mkdir(join(env.sessionDir, "builds"), { recursive: true });
      await writeFile(join(env.sessionDir, "builds", "T1-manifest.md"), "# Build", "utf-8");
      const result = await runHook(HOOK_PATH, rateLimitsInput(RL5), { CLAUDE_CONFIG_DIR: env.configDir });
      const parsed = JSON.parse(result.stdout);
      expect(parsed.text).toContain("Building");
    } finally { await env.cleanup(); }
  });

  test("text contains 'Verifying' when verifications/ has a verification file", async () => {
    const env = await createTestEnv({ withSession: true });
    try {
      await mkdir(join(env.sessionDir, "verifications"), { recursive: true });
      await writeFile(join(env.sessionDir, "verifications", "T1-verification.md"), "# Verify", "utf-8");
      const result = await runHook(HOOK_PATH, rateLimitsInput(RL5), { CLAUDE_CONFIG_DIR: env.configDir });
      const parsed = JSON.parse(result.stdout);
      expect(parsed.text).toContain("Verifying");
    } finally { await env.cleanup(); }
  });
});

describe("statusline: pipeline phase — integrating", () => {
  test("text contains 'Integrating' when integration/ has a report file", async () => {
    const env = await createTestEnv({ withSession: true });
    try {
      await mkdir(join(env.sessionDir, "integration"), { recursive: true });
      await writeFile(join(env.sessionDir, "integration", "wave-1-report.md"), "# Wave", "utf-8");
      const result = await runHook(HOOK_PATH, rateLimitsInput(RL5), { CLAUDE_CONFIG_DIR: env.configDir });
      const parsed = JSON.parse(result.stdout);
      expect(parsed.text).toContain("Integrating");
    } finally { await env.cleanup(); }
  });
});

// ---------------------------------------------------------------------------
// Criterion: handles missing/empty rate_limits gracefully
// ---------------------------------------------------------------------------

describe("statusline: handles missing rate_limits gracefully", () => {
  test("exits 0 and outputs text when rate_limits is absent", async () => {
    const env = await createTestEnv({ withSession: false });
    try {
      const result = await runHook(HOOK_PATH, {}, { CLAUDE_CONFIG_DIR: env.configDir });
      expect(result.exitCode).toBe(0);
      const parsed = JSON.parse(result.stdout);
      expect(parsed).toHaveProperty("text");
    } finally { await env.cleanup(); }
  });

  test("exits 0 with malformed (non-JSON) stdin", async () => {
    const env = await createTestEnv({ withSession: false });
    try {
      const result = await runHookRaw(HOOK_PATH, "not json", { CLAUDE_CONFIG_DIR: env.configDir });
      expect(result.exitCode).toBe(0);
    } finally { await env.cleanup(); }
  });
});

describe("statusline: omits missing rate limit segments", () => {
  test("omits '5h:' segment when fiveHour is absent", async () => {
    const env = await createTestEnv({ withSession: false });
    try {
      const result = await runHook(HOOK_PATH, rateLimitsInput(undefined, RL7), { CLAUDE_CONFIG_DIR: env.configDir });
      const parsed = JSON.parse(result.stdout);
      expect(parsed.text).not.toContain("5h:");
    } finally { await env.cleanup(); }
  });

  test("omits '7d:' segment when sevenDay is absent", async () => {
    const env = await createTestEnv({ withSession: false });
    try {
      const result = await runHook(HOOK_PATH, rateLimitsInput(RL5), { CLAUDE_CONFIG_DIR: env.configDir });
      const parsed = JSON.parse(result.stdout);
      expect(parsed.text).not.toContain("7d:");
    } finally { await env.cleanup(); }
  });
});

// ---------------------------------------------------------------------------
// Criterion: exits 0 on success
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Criterion: includes pipeline phase
// ---------------------------------------------------------------------------

describe("statusline: pipeline phase detection", () => {
  test("text contains 'Idle' when no active session", async () => {
    const env = await createTestEnv({ withSession: false });
    try {
      const result = await runHook(HOOK_PATH, rateLimitsInput(RL5), { CLAUDE_CONFIG_DIR: env.configDir });
      const parsed = JSON.parse(result.stdout);
      expect(parsed.text).toContain("Idle");
    } finally { await env.cleanup(); }
  });

  test("text contains 'Planning' when plan.md exists but no builds", async () => {
    const env = await createTestEnv({ withSession: true });
    try {
      await writeFile(join(env.sessionDir, "plan.md"), "# Plan", "utf-8");
      const result = await runHook(HOOK_PATH, rateLimitsInput(RL5), { CLAUDE_CONFIG_DIR: env.configDir });
      const parsed = JSON.parse(result.stdout);
      expect(parsed.text).toContain("Planning");
    } finally { await env.cleanup(); }
  });
});

describe("statusline: exits 0 on success", () => {
  test("exits 0 with valid rate_limits input", async () => {
    const env = await createTestEnv({ withSession: false });
    try {
      const result = await runHook(
        HOOK_PATH,
        rateLimitsInput(RL5, RL7),
        { CLAUDE_CONFIG_DIR: env.configDir },
      );
      expect(result.exitCode).toBe(0);
    } finally { await env.cleanup(); }
  });
});
