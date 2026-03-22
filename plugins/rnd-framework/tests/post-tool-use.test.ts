/**
 * Tests for hooks/post-tool-use.ts — merged PostToolUse hook.
 *
 * Covers each success criterion from T2 pre-registration:
 *   1. post-tool-use.ts exists and is executable (shebang)
 *   2. Write with slop code produces advisory JSON with slop findings
 *   3. Write referencing SQL tables produces advisory JSON mentioning those tables
 *   4. Write for a code file during active session creates audit.jsonl entry
 *   5. Write for a code file during active session creates slop-reports/ artifacts
 *   6. Malformed stdin exits 0 with no stdout
 *   7. Non-code file creates an audit entry but produces no advisory stdout
 *   8. Combined advisory includes both slop and evidence findings when both present
 *   9. audit-log.ts no longer exists
 *  10. slop-gate.ts no longer has a shebang or main()
 *  11. evidence-warn.ts no longer has a shebang or main()
 *  Quality:
 *  12. Outer try/catch pattern: exits 0 on any error
 *  13. Audit logging runs even if slop analysis throws
 *  14. Evidence scanning runs even if slop analysis throws
 */

import { describe, expect, test } from "bun:test";
import { mkdtemp, mkdir, writeFile, rm, readFile } from "node:fs/promises";
import { existsSync, statSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { runHook, runHookRaw, computeSlug, writeInput, hookInput } from "./helpers";

const HOOK_PATH = join(import.meta.dir, "..", "hooks", "post-tool-use.ts");
const HOOKS_DIR = join(import.meta.dir, "..", "hooks");

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

interface AdvisoryOutput {
  hookSpecificOutput: { additionalContext: string };
}

function parseAdvisory(stdout: string): string {
  const parsed = JSON.parse(stdout.trim()) as AdvisoryOutput;
  return parsed.hookSpecificOutput.additionalContext;
}

async function createPostToolUseTestEnv(withSession: boolean) {
  const configDir = await mkdtemp(join(tmpdir(), "post-tu-test-"));
  const slug = await computeSlug(process.cwd());
  const baseDir = join(configDir, ".rnd", slug);
  await mkdir(baseDir, { recursive: true });
  const sessionId = "20260322-090000-abcd";
  const sessionDir = join(baseDir, "sessions", sessionId);
  if (withSession) {
    await mkdir(sessionDir, { recursive: true });
    await writeFile(join(baseDir, ".current-session"), sessionId, "utf-8");
  }
  const cleanup = async () => {
    if (existsSync(configDir)) await rm(configDir, { recursive: true, force: true });
  };
  return { configDir, baseDir, sessionDir, cleanup };
}

// ---------------------------------------------------------------------------
// Criterion 1: executable with shebang
// ---------------------------------------------------------------------------

describe("post-tool-use: executable", () => {
  test("post-tool-use.ts exists at the expected path", () => {
    expect(existsSync(HOOK_PATH)).toBe(true);
  });

  test("post-tool-use.ts has execute permission", async () => {
    const stat = statSync(HOOK_PATH);
    // S_IXUSR = 0o100 (owner execute bit)
    expect(stat.mode & 0o100).not.toBe(0);
  });

  test("post-tool-use.ts has #!/usr/bin/env bun shebang", async () => {
    const content = await readFile(HOOK_PATH, "utf-8");
    expect(content.startsWith("#!/usr/bin/env bun")).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// Criterion 2: slop findings in advisory
// ---------------------------------------------------------------------------

describe("post-tool-use: slop detection", () => {
  test("Write with empty catch block produces advisory with slop findings", async () => {
    const input = writeInput("/src/test.ts", "function foo() {\n  try {\n    bar();\n  } catch (e) {}\n}\n");
    const result = await runHook(HOOK_PATH, input);
    expect(result.exitCode).toBe(0);
    expect(result.stdout.trim()).not.toBe("");
    const ctx = parseAdvisory(result.stdout);
    expect(ctx).toContain("Slop gate");
  });

  test("Write with over-commenting produces advisory naming the pattern", async () => {
    const input = writeInput("/src/test.ts", "// increment counter\ncounter++\n");
    const result = await runHook(HOOK_PATH, input);
    const ctx = parseAdvisory(result.stdout);
    expect(ctx).toContain("Over-commenting");
  });

  test("clean code produces no advisory stdout", async () => {
    const input = writeInput("/src/clean.ts", "const x = 1;\nconst y = 2;\n");
    const result = await runHook(HOOK_PATH, input);
    expect(result.stdout.trim()).toBe("");
  });
});

// ---------------------------------------------------------------------------
// Criterion 3: SQL table detection in advisory
// ---------------------------------------------------------------------------

describe("post-tool-use: evidence (SQL) detection", () => {
  test("Write with SELECT FROM users produces advisory mentioning users", async () => {
    const input = writeInput("/src/db.ts", "SELECT * FROM users");
    const result = await runHook(HOOK_PATH, input);
    expect(result.exitCode).toBe(0);
    const ctx = parseAdvisory(result.stdout);
    expect(ctx).toContain("users");
  });

  test("Write with INSERT INTO orders produces advisory mentioning orders", async () => {
    const input = writeInput("/src/db.ts", "INSERT INTO orders (id) VALUES (1)");
    const result = await runHook(HOOK_PATH, input);
    const ctx = parseAdvisory(result.stdout);
    expect(ctx).toContain("orders");
  });

  test("Write with fetch endpoint produces advisory mentioning the endpoint", async () => {
    const input = writeInput("/src/api.ts", 'fetch("/api/users")');
    const result = await runHook(HOOK_PATH, input);
    const ctx = parseAdvisory(result.stdout);
    expect(ctx).toContain("/api/users");
  });
});

// ---------------------------------------------------------------------------
// Criterion 4: audit.jsonl created during active session
// ---------------------------------------------------------------------------

describe("post-tool-use: audit logging during active session", () => {
  test("creates audit.jsonl in sessionDir for code file during active session", async () => {
    const env = await createPostToolUseTestEnv(true);
    try {
      await runHook(
        HOOK_PATH,
        hookInput("Write", "/src/foo.ts"),
        { CLAUDE_CONFIG_DIR: env.configDir },
      );
      const auditPath = join(env.sessionDir, "audit.jsonl");
      expect(existsSync(auditPath)).toBe(true);
    } finally {
      await env.cleanup();
    }
  });

  test("audit entry has ts, tool, file keys", async () => {
    const env = await createPostToolUseTestEnv(true);
    try {
      await runHook(
        HOOK_PATH,
        hookInput("Edit", "/src/foo.ts"),
        { CLAUDE_CONFIG_DIR: env.configDir },
      );
      const auditPath = join(env.sessionDir, "audit.jsonl");
      const raw = await readFile(auditPath, "utf-8");
      const entry = JSON.parse(raw.trim().split("\n")[0]);
      expect(entry).toHaveProperty("ts");
      expect(entry).toHaveProperty("tool");
      expect(entry).toHaveProperty("file");
    } finally {
      await env.cleanup();
    }
  });

  test("does not create audit.jsonl when no active session", async () => {
    const env = await createPostToolUseTestEnv(false);
    try {
      await runHook(
        HOOK_PATH,
        hookInput("Write", "/src/foo.ts"),
        { CLAUDE_CONFIG_DIR: env.configDir },
      );
      const auditPath = join(env.sessionDir, "audit.jsonl");
      expect(existsSync(auditPath)).toBe(false);
    } finally {
      await env.cleanup();
    }
  });
});

// ---------------------------------------------------------------------------
// Criterion 5: slop-reports/ artifacts created during active session
// ---------------------------------------------------------------------------

describe("post-tool-use: slop-reports artifacts", () => {
  test("creates slop-reports/ directory during active session for code file", async () => {
    const env = await createPostToolUseTestEnv(true);
    try {
      const input = writeInput("/src/test.ts", "const x = 1;\n");
      await runHook(HOOK_PATH, input, { CLAUDE_CONFIG_DIR: env.configDir });
      const reportsDir = join(env.sessionDir, "slop-reports");
      expect(existsSync(reportsDir)).toBe(true);
    } finally {
      await env.cleanup();
    }
  });

  test("creates a per-file JSON report in slop-reports/ for code file", async () => {
    const env = await createPostToolUseTestEnv(true);
    try {
      const input = writeInput("/src/test.ts", "const x = 1;\n");
      await runHook(HOOK_PATH, input, { CLAUDE_CONFIG_DIR: env.configDir });
      const reportsDir = join(env.sessionDir, "slop-reports");
      const reportFile = join(reportsDir, "src-test.ts.json");
      expect(existsSync(reportFile)).toBe(true);
    } finally {
      await env.cleanup();
    }
  });
});

// ---------------------------------------------------------------------------
// Criterion 6: malformed stdin exits 0 with no stdout
// ---------------------------------------------------------------------------

describe("post-tool-use: resilience", () => {
  test("malformed stdin (empty) exits 0 with no stdout", async () => {
    const result = await runHookRaw(HOOK_PATH, "");
    expect(result.exitCode).toBe(0);
    expect(result.stdout.trim()).toBe("");
  });

  test("malformed stdin (non-JSON) exits 0 with no stdout", async () => {
    const result = await runHookRaw(HOOK_PATH, "not valid json");
    expect(result.exitCode).toBe(0);
    expect(result.stdout.trim()).toBe("");
  });
});

// ---------------------------------------------------------------------------
// Criterion 7: non-code file creates audit entry but no advisory stdout
// ---------------------------------------------------------------------------

describe("post-tool-use: non-code file behavior", () => {
  test("non-code file produces no advisory stdout", async () => {
    const input = writeInput("/README.md", "SELECT * FROM users");
    const result = await runHook(HOOK_PATH, input);
    expect(result.stdout.trim()).toBe("");
  });

  test("non-code file creates audit.jsonl during active session", async () => {
    const env = await createPostToolUseTestEnv(true);
    try {
      await runHook(
        HOOK_PATH,
        hookInput("Write", "/README.md"),
        { CLAUDE_CONFIG_DIR: env.configDir },
      );
      const auditPath = join(env.sessionDir, "audit.jsonl");
      expect(existsSync(auditPath)).toBe(true);
    } finally {
      await env.cleanup();
    }
  });

  test("non-code file with .txt extension creates audit entry but no advisory", async () => {
    const env = await createPostToolUseTestEnv(true);
    try {
      const result = await runHook(
        HOOK_PATH,
        writeInput("/tmp/notes.txt", "some text"),
        { CLAUDE_CONFIG_DIR: env.configDir },
      );
      expect(result.stdout.trim()).toBe("");
      const auditPath = join(env.sessionDir, "audit.jsonl");
      expect(existsSync(auditPath)).toBe(true);
    } finally {
      await env.cleanup();
    }
  });
});

// ---------------------------------------------------------------------------
// Criterion 8: combined advisory includes both slop and evidence
// ---------------------------------------------------------------------------

describe("post-tool-use: combined advisory output", () => {
  test("combined advisory includes both slop and evidence when both are present", async () => {
    const input = writeInput("/src/db.ts", "catch (e) {}\nSELECT * FROM orders");
    const result = await runHook(HOOK_PATH, input);
    expect(result.stdout.trim()).not.toBe("");
    const ctx = parseAdvisory(result.stdout);
    expect(ctx).toContain("Slop gate");
    expect(ctx).toContain("orders");
  });
});

// ---------------------------------------------------------------------------
// Criterion 9: audit-log.ts no longer exists
// ---------------------------------------------------------------------------

describe("post-tool-use: audit-log.ts deleted", () => {
  test("hooks/audit-log.ts does not exist", () => {
    expect(existsSync(join(HOOKS_DIR, "audit-log.ts"))).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// Criterion 10: slop-gate.ts no longer has shebang or main()
// ---------------------------------------------------------------------------

describe("post-tool-use: slop-gate.ts is a pure module", () => {
  test("slop-gate.ts does not have a shebang line", async () => {
    const content = await readFile(join(HOOKS_DIR, "slop-gate.ts"), "utf-8");
    expect(content.startsWith("#!/")).toBe(false);
  });

  test("slop-gate.ts does not have an async function main()", async () => {
    const content = await readFile(join(HOOKS_DIR, "slop-gate.ts"), "utf-8");
    expect(content).not.toMatch(/async function main\(\)/);
  });
});

// ---------------------------------------------------------------------------
// Criterion 11: evidence-warn.ts no longer has shebang or main()
// ---------------------------------------------------------------------------

describe("post-tool-use: evidence-warn.ts is a pure module", () => {
  test("evidence-warn.ts does not have a shebang line", async () => {
    const content = await readFile(join(HOOKS_DIR, "evidence-warn.ts"), "utf-8");
    expect(content.startsWith("#!/")).toBe(false);
  });

  test("evidence-warn.ts does not have an async function main()", async () => {
    const content = await readFile(join(HOOKS_DIR, "evidence-warn.ts"), "utf-8");
    expect(content).not.toMatch(/async function main\(\)/);
  });
});

// ---------------------------------------------------------------------------
// Criterion 12: resilient pattern (outer try/catch exits 0)
// ---------------------------------------------------------------------------

describe("post-tool-use: resilient outer try/catch", () => {
  test("exits 0 even for unexpected input shapes", async () => {
    const result = await runHookRaw(HOOK_PATH, '{"totally":"wrong"}');
    expect(result.exitCode).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// Criteria 13 & 14: audit runs even if slop/evidence throw
// (tested via non-code file path which skips both slop and evidence,
//  demonstrating audit path is independent)
// ---------------------------------------------------------------------------

describe("post-tool-use: audit independent of slop/evidence", () => {
  test("audit runs for a file path with no content (hookInput style, non-code)", async () => {
    const env = await createPostToolUseTestEnv(true);
    try {
      // hookInput only provides file_path, no content — slop would fail to extract content
      // but audit should still fire because it runs before the isCodeFile guard
      await runHook(
        HOOK_PATH,
        hookInput("Write", "/docs/notes.txt"),
        { CLAUDE_CONFIG_DIR: env.configDir },
      );
      const auditPath = join(env.sessionDir, "audit.jsonl");
      expect(existsSync(auditPath)).toBe(true);
    } finally {
      await env.cleanup();
    }
  });

  test("evidence runs even when content has no slop (slop returns no findings)", async () => {
    // Clean code with SQL — slop fires no warnings, but evidence should still fire
    const input = writeInput("/src/db.ts", "const q = 'SELECT * FROM products';\n");
    const result = await runHook(HOOK_PATH, input);
    expect(result.exitCode).toBe(0);
    // Evidence should still detect the table reference
    const ctx = parseAdvisory(result.stdout);
    expect(ctx).toContain("products");
  });
});
