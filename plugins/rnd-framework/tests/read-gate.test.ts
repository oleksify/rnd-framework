/**
 * Tests for hooks/read-gate
 *
 * Covers all 5 success criteria from the T5 pre-registration:
 *   1. Path containing "self-assessment" → exit 2 + stderr "INFORMATION BARRIER"
 *   2. Path containing ".rnd/" but NOT "self-assessment" → exit 0 + permissionDecision "allow"
 *   3. Path containing both ".rnd/" and "self-assessment" → exit 2 (block takes priority)
 *   4. Path not containing ".rnd/" → exit 0 + empty stdout (no opinion)
 *   5. Filename "self-assessment.md" in a non-.rnd/ path → still blocked (substring match)
 */

import { describe, test, expect } from "bun:test";
import { join } from "node:path";
import { runHook } from "./helpers";

const HOOK = join(import.meta.dir, "..", "hooks", "read-gate");

/** Build the stdin JSON that read-gate expects */
function input(filePath: string): unknown {
  return { tool_input: { file_path: filePath } };
}

// ---------------------------------------------------------------------------
// Criterion 1: self-assessment path → INFORMATION BARRIER block
// ---------------------------------------------------------------------------
describe("read-gate: self-assessment paths are blocked", () => {
  test("plain self-assessment filename returns exit 2", async () => {
    const result = await runHook(HOOK, input("T1-self-assessment.md"));
    expect(result.exitCode).toBe(2);
  });

  test("stderr contains INFORMATION BARRIER for self-assessment path", async () => {
    const result = await runHook(HOOK, input("T1-self-assessment.md"));
    expect(result.stderr).toContain("INFORMATION BARRIER");
  });

  test("self-assessment inside a nested directory is blocked", async () => {
    const result = await runHook(
      HOOK,
      input("/home/user/project/builds/T3-self-assessment.md"),
    );
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("INFORMATION BARRIER");
  });
});

// ---------------------------------------------------------------------------
// Criterion 2: .rnd/ path (no self-assessment) → auto-allow
// ---------------------------------------------------------------------------
describe("read-gate: .rnd/ paths without self-assessment are auto-allowed", () => {
  test("plain .rnd/ path returns exit 0", async () => {
    const result = await runHook(
      HOOK,
      input("/home/user/.rnd/project-abc/sessions/20260305-120000-1a2b/plan.md"),
    );
    expect(result.exitCode).toBe(0);
  });

  test(".rnd/ path stdout contains permissionDecision allow", async () => {
    const result = await runHook(
      HOOK,
      input("/home/user/.rnd/project-abc/sessions/20260305-120000-1a2b/plan.md"),
    );
    const parsed = JSON.parse(result.stdout);
    expect(parsed.hookSpecificOutput.permissionDecision).toBe("allow");
  });

  test("deeply nested .rnd/ path is auto-allowed", async () => {
    const result = await runHook(
      HOOK,
      input("/foo/bar/.rnd/baz/qux/deep/file.md"),
    );
    expect(result.exitCode).toBe(0);
    const parsed = JSON.parse(result.stdout);
    expect(parsed.hookSpecificOutput.permissionDecision).toBe("allow");
  });

  test(".rnd/ build manifest is auto-allowed", async () => {
    const result = await runHook(
      HOOK,
      input("/Users/me/.rnd/myproject-abc12345/sessions/20260305-120000-1a2b/builds/T2-manifest.md"),
    );
    expect(result.exitCode).toBe(0);
    const parsed = JSON.parse(result.stdout);
    expect(parsed.hookSpecificOutput.permissionDecision).toBe("allow");
  });
});

// ---------------------------------------------------------------------------
// Criterion 3: path with both ".rnd/" and "self-assessment" → block (priority)
// ---------------------------------------------------------------------------
describe("read-gate: .rnd/ + self-assessment → block takes priority", () => {
  test("path with both .rnd/ and self-assessment returns exit 2", async () => {
    const result = await runHook(
      HOOK,
      input("/home/user/.rnd/project/sessions/20260305-120000-1a2b/builds/T1-self-assessment.md"),
    );
    expect(result.exitCode).toBe(2);
  });

  test("path with both .rnd/ and self-assessment has INFORMATION BARRIER on stderr", async () => {
    const result = await runHook(
      HOOK,
      input("/home/user/.rnd/project/sessions/20260305-120000-1a2b/builds/T1-self-assessment.md"),
    );
    expect(result.stderr).toContain("INFORMATION BARRIER");
  });

  test("path with both .rnd/ and self-assessment produces no allow output", async () => {
    const result = await runHook(
      HOOK,
      input("/home/user/.rnd/project/sessions/20260305-120000-1a2b/builds/T1-self-assessment.md"),
    );
    // stdout must NOT contain a permissionDecision allow
    expect(result.stdout).not.toContain("allow");
  });
});

// ---------------------------------------------------------------------------
// Criterion 4: non-.rnd/ path → no opinion (exit 0, empty stdout)
// ---------------------------------------------------------------------------
describe("read-gate: non-.rnd/ paths produce no opinion", () => {
  test("regular source file returns exit 0", async () => {
    const result = await runHook(
      HOOK,
      input("/Users/me/project/src/index.ts"),
    );
    expect(result.exitCode).toBe(0);
  });

  test("regular source file stdout is empty", async () => {
    const result = await runHook(
      HOOK,
      input("/Users/me/project/src/index.ts"),
    );
    expect(result.stdout.trim()).toBe("");
  });

  test("a README.md produces no opinion", async () => {
    const result = await runHook(HOOK, input("/home/user/project/README.md"));
    expect(result.exitCode).toBe(0);
    expect(result.stdout.trim()).toBe("");
  });

  test("home directory config file produces no opinion", async () => {
    const result = await runHook(HOOK, input("/home/user/.bashrc"));
    expect(result.exitCode).toBe(0);
    expect(result.stdout.trim()).toBe("");
  });
});

// ---------------------------------------------------------------------------
// Criterion 5: "self-assessment.md" in a non-.rnd/ path is still blocked
// ---------------------------------------------------------------------------
describe("read-gate: self-assessment substring match applies to full path", () => {
  test("self-assessment.md in project root is blocked even without .rnd/", async () => {
    const result = await runHook(
      HOOK,
      input("/Users/me/project/self-assessment.md"),
    );
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("INFORMATION BARRIER");
  });

  test("self-assessment in path segment is blocked even without .rnd/", async () => {
    const result = await runHook(
      HOOK,
      input("/Users/me/docs/self-assessment/notes.txt"),
    );
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("INFORMATION BARRIER");
  });

  test("self-assessment.md on its own (relative path) is blocked", async () => {
    const result = await runHook(HOOK, input("self-assessment.md"));
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("INFORMATION BARRIER");
  });
});
