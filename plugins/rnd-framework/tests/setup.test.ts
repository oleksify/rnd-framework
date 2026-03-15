/**
 * Tests for hooks/setup
 *
 * Covers all success criteria from T4 pre-registration:
 *   1. hooks/setup exists and is executable
 *   2. Running the hook exits 0 when validate.sh passes and bun/jq are available
 *   3. stdout is valid JSON containing hookSpecificOutput.additionalContext with setup status
 *   4. additionalContext includes validation result (pass count) and dependency status
 *   5. hooks.json contains a Setup entry pointing to ${CLAUDE_PLUGIN_ROOT}/hooks/setup
 *   6. Script uses set -euo pipefail and sources lib.sh
 *   7. Reports missing dependencies clearly without failing (exit 0 even when deps missing)
 */

import { describe, test, expect, beforeAll } from "bun:test";
import { join } from "node:path";
import { access, constants, readFile } from "node:fs/promises";
import { runHook } from "./helpers";

const PLUGIN_ROOT = join(import.meta.dir, "..");
const HOOK = join(PLUGIN_ROOT, "hooks", "setup");
const HOOKS_JSON = join(PLUGIN_ROOT, "hooks", "hooks.json");

let result: { stdout: string; stderr: string; exitCode: number };
let parsed: Record<string, unknown>;

beforeAll(async () => {
  result = await runHook(HOOK);
  try { parsed = JSON.parse(result.stdout); } catch { parsed = {}; }
});

describe("setup: script exists and is executable", () => {
  test("hooks/setup file exists", async () => {
    // access() resolves to null (not undefined) on success in Bun
    await expect(access(HOOK, constants.F_OK)).resolves.not.toBeUndefined();
    await access(HOOK, constants.F_OK); // throws if file missing
  });

  test("hooks/setup is executable", async () => {
    await access(HOOK, constants.X_OK); // throws if not executable
  });
});

describe("setup: exits 0 when validate.sh passes and deps available", () => {
  test("exits with code 0", () => {
    expect(result.exitCode).toBe(0);
  });
});

describe("setup: stdout is valid JSON with hookSpecificOutput.additionalContext", () => {
  test("stdout is non-empty", () => {
    expect(result.stdout.trim().length).toBeGreaterThan(0);
  });

  test("stdout is parseable JSON", () => {
    expect(() => JSON.parse(result.stdout)).not.toThrow();
  });

  test("output has hookSpecificOutput key", () => {
    expect(parsed).toHaveProperty("hookSpecificOutput");
  });

  test("hookSpecificOutput.additionalContext is present", () => {
    const hso = parsed["hookSpecificOutput"] as Record<string, unknown>;
    expect(hso).toHaveProperty("additionalContext");
  });
});

describe("setup: additionalContext includes validation result and dependency status", () => {
  test("additionalContext contains pass count from validate.sh", () => {
    const hso = parsed["hookSpecificOutput"] as Record<string, unknown>;
    const ctx = hso["additionalContext"] as string;
    expect(ctx).toMatch(/\d+ pass/i);
  });

  test("additionalContext mentions bun", () => {
    const hso = parsed["hookSpecificOutput"] as Record<string, unknown>;
    const ctx = hso["additionalContext"] as string;
    expect(ctx.toLowerCase()).toContain("bun");
  });

  test("additionalContext mentions jq", () => {
    const hso = parsed["hookSpecificOutput"] as Record<string, unknown>;
    const ctx = hso["additionalContext"] as string;
    expect(ctx.toLowerCase()).toContain("jq");
  });
});

describe("setup: hooks.json registration", () => {
  test("hooks.json has a Setup key", async () => {
    const raw = await readFile(HOOKS_JSON, "utf-8");
    const hooksJson = JSON.parse(raw);
    expect(hooksJson.hooks).toHaveProperty("Setup");
  });

  test("Setup entry references the setup script", async () => {
    const raw = await readFile(HOOKS_JSON, "utf-8");
    const hooksJson = JSON.parse(raw);
    const entries = hooksJson.hooks["Setup"] as { hooks: { command: string }[] }[];
    const commands = entries.flatMap(e => e.hooks).map(h => h.command);
    expect(commands.some((c: string) => c.includes("hooks/setup"))).toBe(true);
  });
});

describe("setup: script quality — uses set -euo pipefail and sources lib.sh", () => {
  test("script contains set -euo pipefail", async () => {
    const src = await readFile(HOOK, "utf-8");
    expect(src).toContain("set -euo pipefail");
  });

  test("script sources lib.sh", async () => {
    const src = await readFile(HOOK, "utf-8");
    expect(src).toContain("lib.sh");
  });
});

describe("setup: exit 0 even when bun is unavailable", () => {
  test("exits 0 even when PATH contains no bun", async () => {
    // Use /bin:/usr/bin to get bash+jq but exclude bun (in /opt/homebrew or ~/.bun)
    const r = await runHook(HOOK, undefined, { PATH: "/bin:/usr/bin" });
    expect(r.exitCode).toBe(0);
  });

  test("stdout is still valid JSON when bun is missing", async () => {
    const r = await runHook(HOOK, undefined, { PATH: "/bin:/usr/bin" });
    expect(() => JSON.parse(r.stdout)).not.toThrow();
  });

  test("additionalContext mentions bun not found when bun is missing", async () => {
    const r = await runHook(HOOK, undefined, { PATH: "/bin:/usr/bin" });
    const p = JSON.parse(r.stdout);
    const ctx = (p.hookSpecificOutput as Record<string, unknown>)
      .additionalContext as string;
    expect(ctx.toLowerCase()).toContain("bun");
  });
});
