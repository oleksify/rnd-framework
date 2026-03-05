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
import { mkdtemp, mkdir, writeFile, rm, readFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { join, basename } from "node:path";
import { tmpdir } from "node:os";
import { runHook } from "./helpers";

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const HOOK_PATH =
  "/Users/oleksify/Developer/oleksify/claude/plugins/rnd-framework/hooks/audit-log";

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
