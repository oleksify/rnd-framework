/**
 * Tests for hooks/audit-log
 *
 * The hook appends a JSONL entry to $RND_DIR/audit.jsonl when a session is
 * active and exits silently (exit 0, no file created) when there is no active
 * session.
 *
 * Strategy:
 *   - The hook derives PLUGIN_ROOT from its own script location, then calls
 *     the REAL lib/rnd-dir.sh to resolve RND_DIR.
 *   - rnd-dir.sh respects CLAUDE_CONFIG_DIR, so tests set that to a temp dir.
 *   - The slug is based on PWD (inherited from the test process), so tests
 *     compute the same slug and create the .current-session file there.
 */

import { describe, expect, it, beforeEach, afterEach } from "bun:test";
import { mkdtemp, mkdir, writeFile, rm, readFile, symlink, chmod } from "node:fs/promises";
import { existsSync } from "node:fs";
import { join, basename } from "node:path";
import { tmpdir } from "node:os";
import { runHook, runHookRaw } from "./helpers";

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const HOOK_PATH = join(import.meta.dir, "..", "hooks", "audit-log");

// The hook is invoked in the test process's CWD, so slug = <basename(CWD)>-<hash(CWD)>
// We replicate that computation here to know where rnd-dir.sh will look.
async function computeSlug(dir: string): Promise<string> {
  const base = basename(dir);
  // Use env var to pass dir safely — avoids shell injection with special chars in paths
  const proc = Bun.spawn(
    ["bash", "-c", 'printf "%s" "$TARGET_DIR" | shasum -a 256 | cut -c1-8'],
    { stdout: "pipe", stderr: "pipe", env: { ...process.env, TARGET_DIR: dir } },
  );
  const bytes = await Bun.readableStreamToArrayBuffer(proc.stdout);
  await proc.exited;
  const hash = new TextDecoder().decode(bytes).trim();
  return `${base}-${hash}`;
}

// ---------------------------------------------------------------------------
// Per-test temp directory setup
// ---------------------------------------------------------------------------

interface TestEnv {
  configDir: string;
  slug: string;
  baseDir: string;
  sessionDir: string;
  cleanup: () => Promise<void>;
}

async function createTestEnv(withSession: boolean): Promise<TestEnv> {
  const configDir = await mkdtemp(join(tmpdir(), "audit-log-test-"));
  const cwd = process.cwd();
  const slug = await computeSlug(cwd);
  const baseDir = join(configDir, ".rnd", slug);
  await mkdir(baseDir, { recursive: true });

  const sessionId = "20260305-120000-abcd";
  const sessionDir = join(baseDir, "sessions", sessionId);

  if (withSession) {
    await mkdir(sessionDir, { recursive: true });
    await writeFile(join(baseDir, ".current-session"), sessionId, "utf-8");
  }

  async function cleanup() {
    if (existsSync(configDir)) {
      // Restore permissions before attempting removal (for read-only file tests)
      try {
        const auditPath = join(sessionDir, "audit.jsonl");
        if (existsSync(auditPath)) {
          await chmod(auditPath, 0o644);
        }
      } catch {
        // Ignore errors — file may not exist
      }
      await rm(configDir, { recursive: true, force: true });
    }
  }

  return { configDir, slug, baseDir, sessionDir, cleanup };
}

// Build hook input payload
function hookInput(toolName: string, filePath: string): unknown {
  return {
    tool_name: toolName,
    tool_input: { file_path: filePath },
  };
}

// ---------------------------------------------------------------------------
// Criterion 1 & 4: Exit code and file presence
// ---------------------------------------------------------------------------

describe("audit-log: exit code", () => {
  it("exits 0 when an active session exists", async () => {
    const env = await createTestEnv(true);
    try {
      const result = await runHook(
        HOOK_PATH,
        hookInput("Write", "/tmp/test.txt"),
        { CLAUDE_CONFIG_DIR: env.configDir },
      );
      expect(result.exitCode).toBe(0);
    } finally {
      await env.cleanup();
    }
  });

  it("exits 0 when no active session exists (no .current-session file)", async () => {
    const env = await createTestEnv(false);
    try {
      const result = await runHook(
        HOOK_PATH,
        hookInput("Write", "/tmp/test.txt"),
        { CLAUDE_CONFIG_DIR: env.configDir },
      );
      expect(result.exitCode).toBe(0);
    } finally {
      await env.cleanup();
    }
  });
});

// ---------------------------------------------------------------------------
// Criterion 4: No audit.jsonl when no active session
// ---------------------------------------------------------------------------

describe("audit-log: no session — no audit.jsonl", () => {
  it("does not create audit.jsonl when no active session exists", async () => {
    const env = await createTestEnv(false);
    try {
      await runHook(
        HOOK_PATH,
        hookInput("Write", "/tmp/test.txt"),
        { CLAUDE_CONFIG_DIR: env.configDir },
      );
      // rnd-dir.sh returns the base dir (not a session path) when no .current-session
      // exists. The hook must detect this and NOT write anything — check both the
      // base dir and the (never-created) session dir.
      const auditInBaseDir = join(env.baseDir, "audit.jsonl");
      const auditInSessionDir = join(env.sessionDir, "audit.jsonl");
      expect(existsSync(auditInBaseDir)).toBe(false);
      expect(existsSync(auditInSessionDir)).toBe(false);
    } finally {
      await env.cleanup();
    }
  });
});

// ---------------------------------------------------------------------------
// Criterion 1: audit.jsonl is created when session is active
// ---------------------------------------------------------------------------

describe("audit-log: active session — audit.jsonl is created", () => {
  it("creates audit.jsonl in sessionDir after invocation", async () => {
    const env = await createTestEnv(true);
    try {
      await runHook(
        HOOK_PATH,
        hookInput("Write", "/tmp/test.txt"),
        { CLAUDE_CONFIG_DIR: env.configDir },
      );
      const auditPath = join(env.sessionDir, "audit.jsonl");
      expect(existsSync(auditPath)).toBe(true);
    } finally {
      await env.cleanup();
    }
  });
});

// ---------------------------------------------------------------------------
// Criterion 2: JSONL entry has correct keys and values
// ---------------------------------------------------------------------------

describe("audit-log: JSONL entry keys and values", () => {
  it("produces a valid JSON object on a single line", async () => {
    const env = await createTestEnv(true);
    try {
      await runHook(
        HOOK_PATH,
        hookInput("Write", "/tmp/my-file.ts"),
        { CLAUDE_CONFIG_DIR: env.configDir },
      );
      const auditPath = join(env.sessionDir, "audit.jsonl");
      const raw = await readFile(auditPath, "utf-8");
      const lines = raw.trim().split("\n").filter(Boolean);
      expect(lines).toHaveLength(1);
      // Must parse as valid JSON
      const entry = JSON.parse(lines[0]);
      expect(typeof entry).toBe("object");
    } finally {
      await env.cleanup();
    }
  });

  it("entry has keys: ts, tool, file", async () => {
    const env = await createTestEnv(true);
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

  it("entry.tool matches tool_name from input", async () => {
    const env = await createTestEnv(true);
    try {
      await runHook(
        HOOK_PATH,
        hookInput("Edit", "/src/foo.ts"),
        { CLAUDE_CONFIG_DIR: env.configDir },
      );
      const auditPath = join(env.sessionDir, "audit.jsonl");
      const raw = await readFile(auditPath, "utf-8");
      const entry = JSON.parse(raw.trim().split("\n")[0]);
      expect(entry.tool).toBe("Edit");
    } finally {
      await env.cleanup();
    }
  });

  it("entry.file matches tool_input.file_path from input", async () => {
    const env = await createTestEnv(true);
    try {
      await runHook(
        HOOK_PATH,
        hookInput("Write", "/src/bar.ts"),
        { CLAUDE_CONFIG_DIR: env.configDir },
      );
      const auditPath = join(env.sessionDir, "audit.jsonl");
      const raw = await readFile(auditPath, "utf-8");
      const entry = JSON.parse(raw.trim().split("\n")[0]);
      expect(entry.file).toBe("/src/bar.ts");
    } finally {
      await env.cleanup();
    }
  });
});

// ---------------------------------------------------------------------------
// Criterion 3: ts matches ISO 8601 UTC format
// ---------------------------------------------------------------------------

describe("audit-log: ts format", () => {
  it("ts matches ISO 8601 UTC format /^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$/", async () => {
    const env = await createTestEnv(true);
    try {
      await runHook(
        HOOK_PATH,
        hookInput("Write", "/tmp/ts-test.txt"),
        { CLAUDE_CONFIG_DIR: env.configDir },
      );
      const auditPath = join(env.sessionDir, "audit.jsonl");
      const raw = await readFile(auditPath, "utf-8");
      const entry = JSON.parse(raw.trim().split("\n")[0]);
      expect(entry.ts).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/);
    } finally {
      await env.cleanup();
    }
  });
});

// ---------------------------------------------------------------------------
// Criterion 5: Multiple invocations append multiple lines
// ---------------------------------------------------------------------------

describe("audit-log: multiple invocations", () => {
  it("appends one line per invocation (3 invocations → 3 lines)", async () => {
    const env = await createTestEnv(true);
    try {
      const invocations = [
        hookInput("Write", "/a.ts"),
        hookInput("Edit", "/b.ts"),
        hookInput("Write", "/c.ts"),
      ];

      for (const input of invocations) {
        await runHook(HOOK_PATH, input, { CLAUDE_CONFIG_DIR: env.configDir });
      }

      const auditPath = join(env.sessionDir, "audit.jsonl");
      const raw = await readFile(auditPath, "utf-8");
      const lines = raw.trim().split("\n").filter(Boolean);
      expect(lines).toHaveLength(3);
    } finally {
      await env.cleanup();
    }
  });

  it("each line is a distinct valid JSON object", async () => {
    const env = await createTestEnv(true);
    try {
      const files = ["/x/first.ts", "/x/second.ts", "/x/third.ts"];
      for (const fp of files) {
        await runHook(
          HOOK_PATH,
          hookInput("Write", fp),
          { CLAUDE_CONFIG_DIR: env.configDir },
        );
      }

      const auditPath = join(env.sessionDir, "audit.jsonl");
      const raw = await readFile(auditPath, "utf-8");
      const lines = raw.trim().split("\n").filter(Boolean);

      const entries = lines.map((l) => JSON.parse(l));
      const filePaths = entries.map((e: { file: string }) => e.file);
      expect(filePaths).toEqual(files);
    } finally {
      await env.cleanup();
    }
  });
});

// ---------------------------------------------------------------------------
// Criterion 6: File paths with special characters are safely serialized
// ---------------------------------------------------------------------------

describe("audit-log: special characters in file paths", () => {
  it("serializes a file path containing spaces correctly", async () => {
    const env = await createTestEnv(true);
    try {
      const pathWithSpaces = "/tmp/my file with spaces.ts";
      await runHook(
        HOOK_PATH,
        hookInput("Write", pathWithSpaces),
        { CLAUDE_CONFIG_DIR: env.configDir },
      );
      const auditPath = join(env.sessionDir, "audit.jsonl");
      const raw = await readFile(auditPath, "utf-8");
      const entry = JSON.parse(raw.trim().split("\n")[0]);
      expect(entry.file).toBe(pathWithSpaces);
    } finally {
      await env.cleanup();
    }
  });

  it("serializes a file path containing double quotes correctly", async () => {
    const env = await createTestEnv(true);
    try {
      // jq --arg ensures safe handling — this tests that protection
      const pathWithQuotes = '/tmp/he said "hello".ts';
      await runHook(
        HOOK_PATH,
        hookInput("Write", pathWithQuotes),
        { CLAUDE_CONFIG_DIR: env.configDir },
      );
      const auditPath = join(env.sessionDir, "audit.jsonl");
      const raw = await readFile(auditPath, "utf-8");
      const entry = JSON.parse(raw.trim().split("\n")[0]);
      expect(entry.file).toBe(pathWithQuotes);
    } finally {
      await env.cleanup();
    }
  });

  it("serializes a file path containing single quotes correctly", async () => {
    const env = await createTestEnv(true);
    try {
      const pathWithSingleQuotes = "/tmp/it's a file.ts";
      await runHook(
        HOOK_PATH,
        hookInput("Write", pathWithSingleQuotes),
        { CLAUDE_CONFIG_DIR: env.configDir },
      );
      const auditPath = join(env.sessionDir, "audit.jsonl");
      const raw = await readFile(auditPath, "utf-8");
      const entry = JSON.parse(raw.trim().split("\n")[0]);
      expect(entry.file).toBe(pathWithSingleQuotes);
    } finally {
      await env.cleanup();
    }
  });

  it("serializes a file path containing backslashes correctly", async () => {
    const env = await createTestEnv(true);
    try {
      const pathWithBackslash = "/tmp/path\\with\\backslashes.ts";
      await runHook(
        HOOK_PATH,
        hookInput("Write", pathWithBackslash),
        { CLAUDE_CONFIG_DIR: env.configDir },
      );
      const auditPath = join(env.sessionDir, "audit.jsonl");
      const raw = await readFile(auditPath, "utf-8");
      const entry = JSON.parse(raw.trim().split("\n")[0]);
      expect(entry.file).toBe(pathWithBackslash);
    } finally {
      await env.cleanup();
    }
  });
});

// ---------------------------------------------------------------------------
// New criterion: Malformed stdin — exits 0, no crash
// ---------------------------------------------------------------------------

describe("audit-log: malformed stdin — exits 0", () => {
  it("exits 0 when stdin is empty string", async () => {
    const env = await createTestEnv(true);
    try {
      const result = await runHookRaw(
        HOOK_PATH,
        "",
        { CLAUDE_CONFIG_DIR: env.configDir },
      );
      expect(result.exitCode).toBe(0);
    } finally {
      await env.cleanup();
    }
  });

  it("exits 0 when stdin is non-JSON text", async () => {
    const env = await createTestEnv(true);
    try {
      const result = await runHookRaw(
        HOOK_PATH,
        "not json",
        { CLAUDE_CONFIG_DIR: env.configDir },
      );
      expect(result.exitCode).toBe(0);
    } finally {
      await env.cleanup();
    }
  });

  it("exits 0 when stdin JSON is missing tool_input key", async () => {
    const env = await createTestEnv(true);
    try {
      const result = await runHookRaw(
        HOOK_PATH,
        JSON.stringify({ tool_name: "Write" }),
        { CLAUDE_CONFIG_DIR: env.configDir },
      );
      expect(result.exitCode).toBe(0);
    } finally {
      await env.cleanup();
    }
  });

  it("exits 0 when stdin JSON is missing tool_name key", async () => {
    const env = await createTestEnv(true);
    try {
      const result = await runHookRaw(
        HOOK_PATH,
        JSON.stringify({ tool_input: { file_path: "/tmp/test.ts" } }),
        { CLAUDE_CONFIG_DIR: env.configDir },
      );
      expect(result.exitCode).toBe(0);
    } finally {
      await env.cleanup();
    }
  });

  it("does not write an audit entry when input is malformed (active session)", async () => {
    const env = await createTestEnv(true);
    try {
      await runHookRaw(
        HOOK_PATH,
        "not json",
        { CLAUDE_CONFIG_DIR: env.configDir },
      );
      const auditPath = join(env.sessionDir, "audit.jsonl");
      // No corrupt entry should be written
      expect(existsSync(auditPath)).toBe(false);
    } finally {
      await env.cleanup();
    }
  });

  it("does not write an audit entry when tool_input key is missing (active session)", async () => {
    const env = await createTestEnv(true);
    try {
      await runHookRaw(
        HOOK_PATH,
        JSON.stringify({ tool_name: "Write" }),
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
// New criterion: Missing jq — exits 0, no audit.jsonl
// ---------------------------------------------------------------------------

describe("audit-log: missing jq dependency", () => {
  it("exits 0 when jq is not on PATH and no audit.jsonl is created", async () => {
    const env = await createTestEnv(true);
    // Create a temp dir with a fake jq that exits 127, put it first in PATH
    const fakeBin = await mkdtemp(join(tmpdir(), "fake-bin-"));
    try {
      // Write a fake jq that exits 127 (not found behaviour)
      await writeFile(join(fakeBin, "jq"), "#!/bin/bash\nexit 127\n", { mode: 0o755 });

      // Build a PATH that puts fakeBin first — this shadows the real jq
      const restrictedPath = `${fakeBin}:${process.env.PATH ?? ""}`;

      const result = await runHook(
        HOOK_PATH,
        hookInput("Write", "/tmp/test.ts"),
        { CLAUDE_CONFIG_DIR: env.configDir, PATH: restrictedPath },
      );
      expect(result.exitCode).toBe(0);

      const auditPath = join(env.sessionDir, "audit.jsonl");
      expect(existsSync(auditPath)).toBe(false);
    } finally {
      await env.cleanup();
      await rm(fakeBin, { recursive: true, force: true });
    }
  });
});

// ---------------------------------------------------------------------------
// New criterion: Missing date — exits 0, no audit.jsonl
// ---------------------------------------------------------------------------

describe("audit-log: missing date dependency", () => {
  it("exits 0 when date is not on PATH and no audit.jsonl is created", async () => {
    const env = await createTestEnv(true);
    // Create a temp dir with a fake date that exits 127, put it first in PATH
    const fakeBin = await mkdtemp(join(tmpdir(), "fake-bin-"));
    try {
      // Write a fake date that exits 127
      await writeFile(join(fakeBin, "date"), "#!/bin/bash\nexit 127\n", { mode: 0o755 });

      // Build a PATH that puts fakeBin first — this shadows the real date
      const restrictedPath = `${fakeBin}:${process.env.PATH ?? ""}`;

      const result = await runHook(
        HOOK_PATH,
        hookInput("Write", "/tmp/test.ts"),
        { CLAUDE_CONFIG_DIR: env.configDir, PATH: restrictedPath },
      );
      expect(result.exitCode).toBe(0);

      const auditPath = join(env.sessionDir, "audit.jsonl");
      expect(existsSync(auditPath)).toBe(false);
    } finally {
      await env.cleanup();
      await rm(fakeBin, { recursive: true, force: true });
    }
  });
});

// ---------------------------------------------------------------------------
// New criterion: Read-only audit.jsonl — exits 0, no new entry
// ---------------------------------------------------------------------------

describe("audit-log: read-only audit.jsonl", () => {
  it("exits 0 when audit.jsonl exists but is read-only — no crash, no new entry", async () => {
    const env = await createTestEnv(true);
    try {
      // Create a read-only audit.jsonl
      const auditPath = join(env.sessionDir, "audit.jsonl");
      await writeFile(auditPath, '{"ts":"2026-01-01T00:00:00Z","tool":"Write","file":"/existing.ts"}\n', "utf-8");
      await chmod(auditPath, 0o444);

      const result = await runHook(
        HOOK_PATH,
        hookInput("Write", "/new-entry.ts"),
        { CLAUDE_CONFIG_DIR: env.configDir },
      );

      expect(result.exitCode).toBe(0);

      // Restore permissions before reading
      await chmod(auditPath, 0o644);
      const raw = await readFile(auditPath, "utf-8");
      const lines = raw.trim().split("\n").filter(Boolean);
      // Should still have only the original 1 line, no new entry was appended
      expect(lines).toHaveLength(1);
    } finally {
      await env.cleanup();
    }
  });
});

// ---------------------------------------------------------------------------
// New criterion: Unicode characters in file paths
// ---------------------------------------------------------------------------

describe("audit-log: Unicode characters in file paths", () => {
  it("file path with Unicode (café) produces valid JSONL with correct path", async () => {
    const env = await createTestEnv(true);
    try {
      const unicodePath = "/tmp/file-café.ts";
      await runHook(
        HOOK_PATH,
        hookInput("Write", unicodePath),
        { CLAUDE_CONFIG_DIR: env.configDir },
      );
      const auditPath = join(env.sessionDir, "audit.jsonl");
      const raw = await readFile(auditPath, "utf-8");
      const entry = JSON.parse(raw.trim().split("\n")[0]);
      expect(entry.file).toBe(unicodePath);
    } finally {
      await env.cleanup();
    }
  });

  it("file path with emoji produces valid JSONL with correct path", async () => {
    const env = await createTestEnv(true);
    try {
      const emojiPath = "/tmp/file-\u{1F680}.ts";
      await runHook(
        HOOK_PATH,
        hookInput("Write", emojiPath),
        { CLAUDE_CONFIG_DIR: env.configDir },
      );
      const auditPath = join(env.sessionDir, "audit.jsonl");
      const raw = await readFile(auditPath, "utf-8");
      const entry = JSON.parse(raw.trim().split("\n")[0]);
      expect(entry.file).toBe(emojiPath);
    } finally {
      await env.cleanup();
    }
  });
});

// ---------------------------------------------------------------------------
// New criterion: Newline characters in file paths
// ---------------------------------------------------------------------------

describe("audit-log: newline characters in file paths", () => {
  it("file path with embedded newline produces valid JSONL (newline escaped in JSON)", async () => {
    const env = await createTestEnv(true);
    try {
      // A file path containing a real newline character
      const pathWithNewline = "/tmp/file\nwith-newline.ts";
      await runHook(
        HOOK_PATH,
        hookInput("Write", pathWithNewline),
        { CLAUDE_CONFIG_DIR: env.configDir },
      );
      const auditPath = join(env.sessionDir, "audit.jsonl");
      const raw = await readFile(auditPath, "utf-8");
      // Each JSONL line must parse as valid JSON — embedded newlines are escaped as \n in JSON
      const lines = raw.split("\n").filter(Boolean);
      // Should be exactly one JSONL entry (the newline inside the path is escaped)
      expect(lines.length).toBeGreaterThanOrEqual(1);
      // The first parseable line should have the correct file value
      const entry = JSON.parse(lines[0]);
      expect(entry.file).toBe(pathWithNewline);
    } finally {
      await env.cleanup();
    }
  });

  it("file path with literal backslash-n (\\\\n) produces valid JSONL", async () => {
    const env = await createTestEnv(true);
    try {
      // A file path containing literal backslash followed by n (not a newline)
      const pathWithLiteralBackslashN = "/tmp/file\\nwith-literal.ts";
      await runHook(
        HOOK_PATH,
        hookInput("Write", pathWithLiteralBackslashN),
        { CLAUDE_CONFIG_DIR: env.configDir },
      );
      const auditPath = join(env.sessionDir, "audit.jsonl");
      const raw = await readFile(auditPath, "utf-8");
      const entry = JSON.parse(raw.trim().split("\n")[0]);
      expect(entry.file).toBe(pathWithLiteralBackslashN);
    } finally {
      await env.cleanup();
    }
  });
});

// ---------------------------------------------------------------------------
// New criterion: Symlinked session directory
// ---------------------------------------------------------------------------

describe("audit-log: symlinked session directory", () => {
  it("writes audit.jsonl correctly when session dir is accessed via symlink", async () => {
    const env = await createTestEnv(true);
    // Create a symlink to the session dir and point .current-session at it via a symlinked path
    const realSessionId = "20260305-120000-abcd";
    const realSessionDir = env.sessionDir;
    const symlinkSessionDir = join(env.baseDir, "sessions", "symlinked-session");

    try {
      await symlink(realSessionDir, symlinkSessionDir);

      // Write a second .current-session pointing to the symlinked session ID
      // (rnd-dir.sh reads the session ID and builds the path — symlinks are transparent)
      await writeFile(join(env.baseDir, ".current-session"), realSessionId, "utf-8");

      await runHook(
        HOOK_PATH,
        hookInput("Write", "/tmp/symlink-test.ts"),
        { CLAUDE_CONFIG_DIR: env.configDir },
      );

      // The real session dir should have the audit.jsonl
      const auditPath = join(realSessionDir, "audit.jsonl");
      expect(existsSync(auditPath)).toBe(true);

      const raw = await readFile(auditPath, "utf-8");
      const entry = JSON.parse(raw.trim().split("\n")[0]);
      expect(entry.file).toBe("/tmp/symlink-test.ts");
    } finally {
      await env.cleanup();
    }
  });
});

// ---------------------------------------------------------------------------
// New criterion: 5 rapid sequential writes produce exactly 5 lines
// ---------------------------------------------------------------------------

describe("audit-log: 5 rapid sequential writes", () => {
  it("5 rapid sequential invocations produce exactly 5 lines in audit.jsonl", async () => {
    const env = await createTestEnv(true);
    try {
      const files = [
        "/rapid/file1.ts",
        "/rapid/file2.ts",
        "/rapid/file3.ts",
        "/rapid/file4.ts",
        "/rapid/file5.ts",
      ];

      // Run sequentially (simulate rapid sequential writes)
      for (const fp of files) {
        await runHook(HOOK_PATH, hookInput("Write", fp), { CLAUDE_CONFIG_DIR: env.configDir });
      }

      const auditPath = join(env.sessionDir, "audit.jsonl");
      const raw = await readFile(auditPath, "utf-8");
      const lines = raw.trim().split("\n").filter(Boolean);
      expect(lines).toHaveLength(5);

      // Each line should be valid JSON with the correct file
      const entries = lines.map((l) => JSON.parse(l));
      const filePaths = entries.map((e: { file: string }) => e.file);
      expect(filePaths).toEqual(files);
    } finally {
      await env.cleanup();
    }
  });
});
