/**
 * Tests for M4: Post-compact needle-in-the-haystack verification.
 *
 * Verifies that:
 * 1. pre-compact generates a verificationNeedle in compact-state.json
 * 2. The needle is an 8-character hex string
 * 3. post-compact includes VERIFICATION CHECK in advisory output
 * 4. post-compact includes the needle value in the verification prompt
 * 5. post-compact works gracefully when needle is absent (legacy state files)
 */

import { describe, test, expect } from "bun:test";
import { writeFile, readFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { join } from "node:path";
import { runHook, createTestEnv } from "./helpers";

const PRE_COMPACT = join(import.meta.dir, "..", "hooks", "pre-compact.ts");
const POST_COMPACT = join(import.meta.dir, "..", "hooks", "post-compact.ts");

// ---------------------------------------------------------------------------
// generateNeedle (pure function test via import)
// ---------------------------------------------------------------------------

describe("generateNeedle", () => {
  test("returns an 8-character hex string", async () => {
    const { generateNeedle } = await import("../hooks/lib.ts");
    const needle = generateNeedle();
    expect(needle).toMatch(/^[0-9a-f]{8}$/);
  });

  test("returns different values on successive calls", async () => {
    const { generateNeedle } = await import("../hooks/lib.ts");
    const a = generateNeedle();
    const b = generateNeedle();
    // Extremely unlikely to collide with 32 bits of randomness
    expect(a).not.toBe(b);
  });
});

// ---------------------------------------------------------------------------
// pre-compact: verificationNeedle in compact-state.json
// ---------------------------------------------------------------------------

describe("pre-compact: needle generation", () => {
  test("compact-state.json contains verificationNeedle field", async () => {
    const env = await createTestEnv({ withSession: true });
    try {
      await runHook(PRE_COMPACT, { hook_event_name: "PreCompact" }, env.env);
      const stateFile = join(env.sessionDir, "compact-state.json");
      expect(existsSync(stateFile)).toBe(true);
      const state = JSON.parse(await readFile(stateFile, "utf-8"));
      expect(state.verificationNeedle).toBeDefined();
      expect(typeof state.verificationNeedle).toBe("string");
      expect(state.verificationNeedle).toMatch(/^[0-9a-f]{8}$/);
    } finally {
      await env.cleanup();
    }
  });
});

// ---------------------------------------------------------------------------
// post-compact: verification challenge in advisory
// ---------------------------------------------------------------------------

describe("post-compact: verification challenge", () => {
  test("advisory includes VERIFICATION CHECK when needle is present", async () => {
    const env = await createTestEnv({ withSession: true });
    try {
      const state = {
        planSummary: "Test plan summary",
        currentTaskId: "T3",
        iterationCount: 2,
        savedAt: "2026-03-22T10:00:00Z",
        verificationNeedle: "abcd1234",
      };
      await writeFile(join(env.sessionDir, "compact-state.json"), JSON.stringify(state), "utf-8");

      const result = await runHook(POST_COMPACT, {}, env.env);
      expect(result.exitCode).toBe(0);
      expect(result.stdout).toContain("VERIFICATION CHECK");
      expect(result.stdout).toContain("abcd1234");
      expect(result.stdout).toContain("T3");
    } finally {
      await env.cleanup();
    }
  });

  test("advisory works without needle (legacy compact-state.json)", async () => {
    const env = await createTestEnv({ withSession: true });
    try {
      const state = {
        planSummary: "Legacy plan",
        currentTaskId: "T1",
        iterationCount: 0,
        savedAt: "2026-03-22T10:00:00Z",
      };
      await writeFile(join(env.sessionDir, "compact-state.json"), JSON.stringify(state), "utf-8");

      const result = await runHook(POST_COMPACT, {}, env.env);
      expect(result.exitCode).toBe(0);
      expect(result.stdout).toContain("Pipeline state restored");
      expect(result.stdout).not.toContain("VERIFICATION CHECK");
    } finally {
      await env.cleanup();
    }
  });
});
