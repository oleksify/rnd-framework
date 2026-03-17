/**
 * Tests for hooks/chunk-gate
 *
 * Success criteria:
 *   SC1: Write with 31 lines to non-.rnd/ path → exit 2, stderr contains "BLOCKED"
 *   SC2: Write with 30 lines to non-.rnd/ path → exit 0, empty stdout
 *   SC3: Edit with 31 lines to non-.rnd/ path → exit 2, stderr contains "BLOCKED"
 *   SC4: Edit with 30 lines to non-.rnd/ path → exit 0, empty stdout
 *   SC5: Write/Edit to .rnd/ path with 50 lines → exit 0 (bypass)
 */

import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { writeFile } from "node:fs/promises";
import { join } from "node:path";
import { createTestEnv, runHook, writeInput, editInput, type TestEnv } from "./helpers";

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const HOOK_PATH = join(import.meta.dir, "..", "hooks", "chunk-gate.ts");

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Generate a string with exactly `n` lines (no trailing newline). */
function lines(n: number): string {
  return Array.from({ length: n }, (_, i) => `line ${i + 1}`).join("\n");
}

// ---------------------------------------------------------------------------
// SC1: Write with 31 lines to non-.rnd/ path → blocked
// ---------------------------------------------------------------------------

describe("SC1: Write with 31 lines to non-.rnd/ path is blocked", () => {
  test("returns exit 2", async () => {
    const result = await runHook(
      HOOK_PATH,
      writeInput("/project/src/file.ts", lines(31)),
    );
    expect(result.exitCode).toBe(2);
  });

  test("stderr contains BLOCKED", async () => {
    const result = await runHook(
      HOOK_PATH,
      writeInput("/project/src/file.ts", lines(31)),
    );
    expect(result.stderr).toContain("BLOCKED");
  });

  test("stdout is empty", async () => {
    const result = await runHook(
      HOOK_PATH,
      writeInput("/project/src/file.ts", lines(31)),
    );
    expect(result.stdout.trim()).toBe("");
  });
});

// ---------------------------------------------------------------------------
// SC2: Write with 30 lines to non-.rnd/ path → allowed (no opinion)
// ---------------------------------------------------------------------------

describe("SC2: Write with 30 lines to non-.rnd/ path passes", () => {
  test("returns exit 0", async () => {
    const result = await runHook(
      HOOK_PATH,
      writeInput("/project/src/file.ts", lines(30)),
    );
    expect(result.exitCode).toBe(0);
  });

  test("stdout is empty (no opinion)", async () => {
    const result = await runHook(
      HOOK_PATH,
      writeInput("/project/src/file.ts", lines(30)),
    );
    expect(result.stdout.trim()).toBe("");
  });
});

// ---------------------------------------------------------------------------
// SC3: Edit with 31 lines to non-.rnd/ path → blocked
// ---------------------------------------------------------------------------

describe("SC3: Edit with 31 lines to non-.rnd/ path is blocked", () => {
  test("returns exit 2", async () => {
    const result = await runHook(
      HOOK_PATH,
      editInput("/project/src/component.tsx", lines(31)),
    );
    expect(result.exitCode).toBe(2);
  });

  test("stderr contains BLOCKED", async () => {
    const result = await runHook(
      HOOK_PATH,
      editInput("/project/src/component.tsx", lines(31)),
    );
    expect(result.stderr).toContain("BLOCKED");
  });

  test("stdout is empty", async () => {
    const result = await runHook(
      HOOK_PATH,
      editInput("/project/src/component.tsx", lines(31)),
    );
    expect(result.stdout.trim()).toBe("");
  });
});

// ---------------------------------------------------------------------------
// SC4: Edit with 30 lines to non-.rnd/ path → allowed (no opinion)
// ---------------------------------------------------------------------------

describe("SC4: Edit with 30 lines to non-.rnd/ path passes", () => {
  test("returns exit 0", async () => {
    const result = await runHook(
      HOOK_PATH,
      editInput("/project/src/component.tsx", lines(30)),
    );
    expect(result.exitCode).toBe(0);
  });

  test("stdout is empty (no opinion)", async () => {
    const result = await runHook(
      HOOK_PATH,
      editInput("/project/src/component.tsx", lines(30)),
    );
    expect(result.stdout.trim()).toBe("");
  });
});

// ---------------------------------------------------------------------------
// SC5: .rnd/ path bypasses line-count limit for both Write and Edit
// ---------------------------------------------------------------------------

describe("SC5: .rnd/ path bypasses chunk limit with explicit allow", () => {
  test("Write to .rnd/ path with 50 lines returns exit 0", async () => {
    const result = await runHook(
      HOOK_PATH,
      writeInput("/home/user/.claude/.rnd/sessions/20260305/builds/T1-manifest.md", lines(50)),
    );
    expect(result.exitCode).toBe(0);
  });

  test("Write to .rnd/ path emits permissionDecision=allow", async () => {
    const result = await runHook(
      HOOK_PATH,
      writeInput("/home/user/.claude/.rnd/sessions/20260305/builds/T1-manifest.md", lines(50)),
    );
    const parsed = JSON.parse(result.stdout);
    expect(parsed.hookSpecificOutput.permissionDecision).toBe("allow");
  });

  test("Edit to .rnd/ path with 50 lines returns exit 0", async () => {
    const result = await runHook(
      HOOK_PATH,
      editInput("/home/user/.claude/.rnd/sessions/20260305/verifications/T1-verification.md", lines(50)),
    );
    expect(result.exitCode).toBe(0);
  });

  test("Edit to .rnd/ path emits permissionDecision=allow", async () => {
    const result = await runHook(
      HOOK_PATH,
      editInput("/home/user/.claude/.rnd/sessions/20260305/verifications/T1-verification.md", lines(50)),
    );
    const parsed = JSON.parse(result.stdout);
    expect(parsed.hookSpecificOutput.permissionDecision).toBe("allow");
  });
});

// ---------------------------------------------------------------------------
// SC6: Non-.rnd/ path during planning phase → blocked with planning message
// ---------------------------------------------------------------------------

describe("SC6: Non-.rnd/ path during planning phase is blocked", () => {
  let env: TestEnv;

  beforeEach(async () => {
    env = await createTestEnv({ withSession: true });
    await writeFile(join(env.sessionDir, ".planning-phase"), "", "utf-8");
  });

  afterEach(async () => { await env.cleanup(); });

  test("returns exit 2", async () => {
    const result = await runHook(
      HOOK_PATH,
      writeInput("/project/src/file.ts", lines(5)),
      { ...env.env, CLAUDE_PLUGIN_ROOT: "" },
    );
    expect(result.exitCode).toBe(2);
  });

  test("stderr contains BLOCKED and planning phase", async () => {
    const result = await runHook(
      HOOK_PATH,
      writeInput("/project/src/file.ts", lines(5)),
      { ...env.env, CLAUDE_PLUGIN_ROOT: "" },
    );
    expect(result.stderr).toContain("BLOCKED");
    expect(result.stderr).toContain("planning phase");
  });
});
