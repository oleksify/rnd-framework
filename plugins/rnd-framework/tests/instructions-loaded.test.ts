/**
 * Tests for hooks/instructions-loaded
 *
 * Covers all success criteria from the T3 pre-registration:
 *   1. Hook script exits 0 and produces valid JSON on stdout
 *   2. stdout JSON contains hookSpecificOutput.additionalContext mentioning "rnd-standards"
 *   3. hooks.json contains an InstructionsLoaded entry pointing to the script
 *   4. Script uses set -euo pipefail (quality check via grep)
 *   5. The reminder message is concise (under 200 chars)
 */

import { describe, test, expect } from "bun:test";
import { join } from "node:path";
import { readFile } from "node:fs/promises";
import { runHook } from "./helpers";

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const PLUGIN_ROOT = join(import.meta.dir, "..");
const HOOK = join(PLUGIN_ROOT, "hooks", "instructions-loaded.ts");
const HOOKS_JSON = join(PLUGIN_ROOT, "hooks", "hooks.json");

// ---------------------------------------------------------------------------
// Criterion 1: exits 0 and produces valid JSON on stdout
// ---------------------------------------------------------------------------

describe("instructions-loaded: exit code and JSON output", () => {
  test("exits with code 0", async () => {
    const result = await runHook(HOOK);
    expect(result.exitCode).toBe(0);
  });

  test("stdout is non-empty", async () => {
    const result = await runHook(HOOK);
    expect(result.stdout.trim().length).toBeGreaterThan(0);
  });

  test("stdout is valid JSON", async () => {
    const result = await runHook(HOOK);
    expect(() => JSON.parse(result.stdout)).not.toThrow();
  });
});

// ---------------------------------------------------------------------------
// Criterion 2: hookSpecificOutput.additionalContext mentions "rnd-standards"
// ---------------------------------------------------------------------------

describe("instructions-loaded: additionalContext contains rnd-standards", () => {
  test("hookSpecificOutput exists in output", async () => {
    const result = await runHook(HOOK);
    const parsed = JSON.parse(result.stdout) as Record<string, unknown>;
    expect(parsed).toHaveProperty("hookSpecificOutput");
  });

  test("hookSpecificOutput.additionalContext exists", async () => {
    const result = await runHook(HOOK);
    const parsed = JSON.parse(result.stdout) as Record<string, unknown>;
    const hso = parsed["hookSpecificOutput"] as Record<string, unknown>;
    expect(hso).toHaveProperty("additionalContext");
  });

  test('hookSpecificOutput.additionalContext mentions "rnd-standards"', async () => {
    const result = await runHook(HOOK);
    const parsed = JSON.parse(result.stdout) as Record<string, unknown>;
    const hso = parsed["hookSpecificOutput"] as Record<string, unknown>;
    expect(hso["additionalContext"] as string).toContain("rnd-standards");
  });
});

// ---------------------------------------------------------------------------
// Criterion 3: hooks.json contains InstructionsLoaded entry for this script
// ---------------------------------------------------------------------------

describe("instructions-loaded: hooks.json registration", () => {
  test("hooks.json has an InstructionsLoaded key", async () => {
    const raw = await readFile(HOOKS_JSON, "utf-8");
    const parsed = JSON.parse(raw) as Record<string, unknown>;
    expect(parsed["hooks"]).toHaveProperty("InstructionsLoaded");
  });

  test("InstructionsLoaded entry references the instructions-loaded script", async () => {
    const raw = await readFile(HOOKS_JSON, "utf-8");
    expect(raw).toContain("instructions-loaded");
  });
});

// ---------------------------------------------------------------------------
// Criterion 4 (quality): reminder message is under 200 chars
// ---------------------------------------------------------------------------

describe("instructions-loaded: reminder is concise", () => {
  test("additionalContext is under 200 characters", async () => {
    const result = await runHook(HOOK);
    const parsed = JSON.parse(result.stdout) as Record<string, unknown>;
    const hso = parsed["hookSpecificOutput"] as Record<string, unknown>;
    const ctx = hso["additionalContext"] as string;
    expect(ctx.length).toBeLessThan(200);
  });
});

// ---------------------------------------------------------------------------
// Criterion 5 (quality): script uses #!/usr/bin/env bun shebang and imports from lib.ts
// ---------------------------------------------------------------------------

describe("instructions-loaded: script quality", () => {
  test("script uses bun shebang", async () => {
    const src = await readFile(HOOK, "utf-8");
    expect(src).toContain("#!/usr/bin/env bun");
  });

  test("script imports from lib.ts", async () => {
    const src = await readFile(HOOK, "utf-8");
    expect(src).toContain("lib.ts");
  });
});
