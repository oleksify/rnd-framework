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

import { describe, expect, it } from "bun:test";
import { join } from "node:path";
import { runHook } from "./helpers";

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const HOOK_PATH = join(import.meta.dir, "..", "hooks", "chunk-gate");

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Build a Write hook input payload. */
function writeInput(filePath: string, content: string): unknown {
  return { tool_name: "Write", tool_input: { file_path: filePath, content } };
}

/** Build an Edit hook input payload. */
function editInput(filePath: string, newString: string): unknown {
  return {
    tool_name: "Edit",
    tool_input: { file_path: filePath, new_string: newString },
  };
}

/** Generate a string with exactly `n` lines (no trailing newline). */
function lines(n: number): string {
  return Array.from({ length: n }, (_, i) => `line ${i + 1}`).join("\n");
}

// ---------------------------------------------------------------------------
// SC1: Write with 31 lines to non-.rnd/ path → blocked
// ---------------------------------------------------------------------------

describe("SC1: Write with 31 lines to non-.rnd/ path is blocked", () => {
  it("returns exit 2", async () => {
    const result = await runHook(
      HOOK_PATH,
      writeInput("/project/src/file.ts", lines(31)),
    );
    expect(result.exitCode).toBe(2);
  });

  it("stderr contains BLOCKED", async () => {
    const result = await runHook(
      HOOK_PATH,
      writeInput("/project/src/file.ts", lines(31)),
    );
    expect(result.stderr).toContain("BLOCKED");
  });

  it("stdout is empty", async () => {
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
  it("returns exit 0", async () => {
    const result = await runHook(
      HOOK_PATH,
      writeInput("/project/src/file.ts", lines(30)),
    );
    expect(result.exitCode).toBe(0);
  });

  it("stdout is empty (no opinion)", async () => {
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
  it("returns exit 2", async () => {
    const result = await runHook(
      HOOK_PATH,
      editInput("/project/src/component.tsx", lines(31)),
    );
    expect(result.exitCode).toBe(2);
  });

  it("stderr contains BLOCKED", async () => {
    const result = await runHook(
      HOOK_PATH,
      editInput("/project/src/component.tsx", lines(31)),
    );
    expect(result.stderr).toContain("BLOCKED");
  });

  it("stdout is empty", async () => {
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
  it("returns exit 0", async () => {
    const result = await runHook(
      HOOK_PATH,
      editInput("/project/src/component.tsx", lines(30)),
    );
    expect(result.exitCode).toBe(0);
  });

  it("stdout is empty (no opinion)", async () => {
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
  it("Write to .rnd/ path with 50 lines returns exit 0", async () => {
    const result = await runHook(
      HOOK_PATH,
      writeInput("/home/user/.rnd/sessions/20260305/builds/T1-manifest.md", lines(50)),
    );
    expect(result.exitCode).toBe(0);
  });

  it("Write to .rnd/ path emits permissionDecision=allow", async () => {
    const result = await runHook(
      HOOK_PATH,
      writeInput("/home/user/.rnd/sessions/20260305/builds/T1-manifest.md", lines(50)),
    );
    const parsed = JSON.parse(result.stdout);
    expect(parsed.hookSpecificOutput.permissionDecision).toBe("allow");
  });

  it("Edit to .rnd/ path with 50 lines returns exit 0", async () => {
    const result = await runHook(
      HOOK_PATH,
      editInput("/home/user/.rnd/sessions/20260305/verifications/T1-verification.md", lines(50)),
    );
    expect(result.exitCode).toBe(0);
  });

  it("Edit to .rnd/ path emits permissionDecision=allow", async () => {
    const result = await runHook(
      HOOK_PATH,
      editInput("/home/user/.rnd/sessions/20260305/verifications/T1-verification.md", lines(50)),
    );
    const parsed = JSON.parse(result.stdout);
    expect(parsed.hookSpecificOutput.permissionDecision).toBe("allow");
  });
});
