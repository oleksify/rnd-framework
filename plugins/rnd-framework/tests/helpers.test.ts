/**
 * Self-tests for tests/helpers.ts
 * Validates that runHook() and createTempRndDir() work as documented.
 */

import { describe, expect, test, beforeAll, afterAll } from "bun:test";
import { existsSync } from "node:fs";
import { join } from "node:path";
import {
  runHook,
  runHookRaw,
  createTempRndDir,
  computeSlug,
  createTestEnv,
  writeInput,
  editInput,
  readInput,
  bashInput,
  hookInput,
} from "./helpers";

// A tiny inline bash script that acts as a fake hook for testing
const ECHO_HOOK = `#!/usr/bin/env bash
# Reads stdin, echoes it back to stdout, exits 0
cat
`;

const STDERR_HOOK = `#!/usr/bin/env bash
# Writes a message to stderr and exits 2
echo "hook error message" >&2
exit 2
`;

const ENV_HOOK = `#!/usr/bin/env bash
# Echoes the TEST_VAR env variable to stdout
echo "$TEST_VAR"
`;

let echoHookPath: string;
let stderrHookPath: string;
let envHookPath: string;
let tmpScriptDir: string;

beforeAll(async () => {
  // Create temp scripts for testing
  const os = await import("node:os");
  const fs = await import("node:fs/promises");
  tmpScriptDir = await fs.mkdtemp(join(os.tmpdir(), "hook-test-scripts-"));

  echoHookPath = join(tmpScriptDir, "echo-hook");
  stderrHookPath = join(tmpScriptDir, "stderr-hook");
  envHookPath = join(tmpScriptDir, "env-hook");

  await fs.writeFile(echoHookPath, ECHO_HOOK, { mode: 0o755 });
  await fs.writeFile(stderrHookPath, STDERR_HOOK, { mode: 0o755 });
  await fs.writeFile(envHookPath, ENV_HOOK, { mode: 0o755 });
});

afterAll(async () => {
  const fs = await import("node:fs/promises");
  await fs.rm(tmpScriptDir, { recursive: true, force: true });
});

// ---------------------------------------------------------------------------
// runHook() — return shape
// ---------------------------------------------------------------------------

describe("runHook() return shape", () => {
  test("returns an object with stdout, stderr, and exitCode fields", async () => {
    const result = await runHook(echoHookPath);
    expect(result).toHaveProperty("stdout");
    expect(result).toHaveProperty("stderr");
    expect(result).toHaveProperty("exitCode");
    expect(typeof result.stdout).toBe("string");
    expect(typeof result.stderr).toBe("string");
    expect(typeof result.exitCode).toBe("number");
  });
});

// ---------------------------------------------------------------------------
// runHook() — stdin JSON passing
// ---------------------------------------------------------------------------

describe("runHook() stdin JSON passing", () => {
  test("passes stdinJson to subprocess via stdin", async () => {
    const payload = { tool: "Write", tool_input: { file_path: "/tmp/test.txt" } };
    const result = await runHook(echoHookPath, payload);
    expect(result.exitCode).toBe(0);
    // The echo hook reads stdin and writes it to stdout
    const parsed = JSON.parse(result.stdout);
    expect(parsed).toEqual(payload);
  });

  test("passes no stdin when stdinJson is omitted", async () => {
    const result = await runHook(echoHookPath);
    expect(result.exitCode).toBe(0);
    // No input → stdout should be empty or whitespace only
    expect(result.stdout.trim()).toBe("");
  });

  test("captures stderr and non-zero exit code", async () => {
    const result = await runHook(stderrHookPath);
    expect(result.exitCode).toBe(2);
    expect(result.stderr.trim()).toBe("hook error message");
    expect(result.stdout.trim()).toBe("");
  });
});

// ---------------------------------------------------------------------------
// runHook() — env parameter
// ---------------------------------------------------------------------------

describe("runHook() env parameter", () => {
  test("sets environment variables in the subprocess", async () => {
    const result = await runHook(envHookPath, undefined, { TEST_VAR: "hello-from-env" });
    expect(result.exitCode).toBe(0);
    expect(result.stdout.trim()).toBe("hello-from-env");
  });

  test("allows empty env object (no extra env vars)", async () => {
    const result = await runHook(envHookPath, undefined, {});
    expect(result.exitCode).toBe(0);
    // TEST_VAR not set → empty line
    expect(result.stdout.trim()).toBe("");
  });

  test("env vars are accessible alongside inherited process env", async () => {
    // PATH must still be inherited so bash can run
    const result = await runHook(echoHookPath, { ok: true }, { EXTRA: "yes" });
    expect(result.exitCode).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// runHookRaw() — return shape
// ---------------------------------------------------------------------------

describe("runHookRaw() return shape", () => {
  test("returns an object with stdout, stderr, and exitCode fields", async () => {
    const result = await runHookRaw(echoHookPath, "hello");
    expect(result).toHaveProperty("stdout");
    expect(result).toHaveProperty("stderr");
    expect(result).toHaveProperty("exitCode");
    expect(typeof result.stdout).toBe("string");
    expect(typeof result.stderr).toBe("string");
    expect(typeof result.exitCode).toBe("number");
  });
});

// ---------------------------------------------------------------------------
// runHookRaw() — raw stdin passing
// ---------------------------------------------------------------------------

describe("runHookRaw() raw stdin passing", () => {
  test("sends an empty string on stdin (not the JSON string \"\")", async () => {
    const result = await runHookRaw(echoHookPath, "");
    expect(result.exitCode).toBe(0);
    // An empty string written to stdin → cat echoes nothing
    expect(result.stdout).toBe("");
  });

  test("sends literal bytes 'not json' on stdin", async () => {
    const result = await runHookRaw(echoHookPath, "not json");
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("not json");
  });

  test("sends a valid JSON string exactly as-is on stdin", async () => {
    const raw = '{"tool_input":{}}';
    const result = await runHookRaw(echoHookPath, raw);
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe(raw);
  });

  test("passes no stdin when rawStdin is omitted", async () => {
    const result = await runHookRaw(echoHookPath);
    expect(result.exitCode).toBe(0);
    expect(result.stdout.trim()).toBe("");
  });

  test("captures stderr and non-zero exit code", async () => {
    const result = await runHookRaw(stderrHookPath, "anything");
    expect(result.exitCode).toBe(2);
    expect(result.stderr.trim()).toBe("hook error message");
  });

  test("supports env parameter like runHook", async () => {
    const result = await runHookRaw(envHookPath, "", { TEST_VAR: "raw-env-test" });
    expect(result.exitCode).toBe(0);
    expect(result.stdout.trim()).toBe("raw-env-test");
  });
});

// ---------------------------------------------------------------------------
// createTempRndDir() — directory structure
// ---------------------------------------------------------------------------

describe("createTempRndDir() directory structure", () => {
  test("returns { baseDir, sessionDir, cleanup }", async () => {
    const dirs = await createTempRndDir();
    try {
      expect(dirs).toHaveProperty("baseDir");
      expect(dirs).toHaveProperty("sessionDir");
      expect(dirs).toHaveProperty("cleanup");
      expect(typeof dirs.baseDir).toBe("string");
      expect(typeof dirs.sessionDir).toBe("string");
      expect(typeof dirs.cleanup).toBe("function");
    } finally {
      await dirs.cleanup();
    }
  });

  test("creates a sessions/ subdirectory inside baseDir", async () => {
    const dirs = await createTempRndDir();
    try {
      const sessionsDir = join(dirs.baseDir, "sessions");
      expect(existsSync(sessionsDir)).toBe(true);
    } finally {
      await dirs.cleanup();
    }
  });

  test("creates sessionDir inside baseDir/sessions/", async () => {
    const dirs = await createTempRndDir();
    try {
      expect(dirs.sessionDir.startsWith(join(dirs.baseDir, "sessions"))).toBe(true);
      expect(existsSync(dirs.sessionDir)).toBe(true);
    } finally {
      await dirs.cleanup();
    }
  });

  test("creates builds/, verifications/, integration/ subdirs inside sessionDir", async () => {
    const dirs = await createTempRndDir();
    try {
      for (const subdir of ["builds", "verifications", "integration"]) {
        expect(existsSync(join(dirs.sessionDir, subdir))).toBe(true);
      }
    } finally {
      await dirs.cleanup();
    }
  });

  test("creates a .current-session file in baseDir pointing to session ID", async () => {
    const dirs = await createTempRndDir();
    try {
      const markerPath = join(dirs.baseDir, ".current-session");
      expect(existsSync(markerPath)).toBe(true);
      const content = await Bun.file(markerPath).text();
      // The session ID is the basename of sessionDir
      const sessionId = dirs.sessionDir.split("/").at(-1)!;
      expect(content.trim()).toBe(sessionId);
    } finally {
      await dirs.cleanup();
    }
  });
});

// ---------------------------------------------------------------------------
// createTempRndDir() — cleanup
// ---------------------------------------------------------------------------

describe("createTempRndDir() cleanup", () => {
  test("cleanup() removes the entire baseDir tree", async () => {
    const dirs = await createTempRndDir();
    const { baseDir, cleanup } = dirs;
    expect(existsSync(baseDir)).toBe(true);
    await cleanup();
    expect(existsSync(baseDir)).toBe(false);
  });

  test("cleanup() is idempotent (calling twice does not throw)", async () => {
    const dirs = await createTempRndDir();
    await dirs.cleanup();
    // Second call should not throw
    await expect(dirs.cleanup()).resolves.toBeUndefined();
  });
});

// ---------------------------------------------------------------------------
// computeSlug() — hash-based slug
// ---------------------------------------------------------------------------

describe("computeSlug()", () => {
  test("returns a string in <basename>-<8char-hex> format", async () => {
    const slug = await computeSlug("/some/path/myproject");
    expect(slug).toMatch(/^myproject-[0-9a-f]{8}$/);
  });

  test("returns the same slug for the same input on repeated calls", async () => {
    const slug1 = await computeSlug("/test/dir");
    const slug2 = await computeSlug("/test/dir");
    expect(slug1).toBe(slug2);
  });

  test("returns different slugs for different dirs", async () => {
    const slug1 = await computeSlug("/dir/a");
    const slug2 = await computeSlug("/dir/b");
    expect(slug1).not.toBe(slug2);
  });
});

// ---------------------------------------------------------------------------
// createTestEnv() — test environment factory
// ---------------------------------------------------------------------------

describe("createTestEnv()", () => {
  test("has all required fields and CLAUDE_CONFIG_DIR in env", async () => {
    const env = await createTestEnv();
    try {
      for (const key of ["baseDir", "sessionDir", "configDir", "cleanup", "env"]) {
        expect(env).toHaveProperty(key);
      }
      expect(env.env.CLAUDE_CONFIG_DIR).toBe(env.configDir);
    } finally {
      await env.cleanup();
    }
  });
});

describe("createTestEnv() withSession", () => {
  test("withSession:true creates .current-session", async () => {
    const env = await createTestEnv({ withSession: true });
    try {
      expect(existsSync(join(env.baseDir, ".current-session"))).toBe(true);
    } finally { await env.cleanup(); }
  });

  test("default (no opts) omits .current-session", async () => {
    const env = await createTestEnv();
    try {
      expect(existsSync(join(env.baseDir, ".current-session"))).toBe(false);
    } finally { await env.cleanup(); }
  });
});

// ---------------------------------------------------------------------------
// Input builders
// ---------------------------------------------------------------------------

describe("writeInput() and editInput()", () => {
  test("writeInput returns Write payload with file_path and content", () => {
    const r = writeInput("/f.ts", "x") as Record<string, unknown>;
    expect(r.tool_name).toBe("Write");
    const ti = r.tool_input as Record<string, unknown>;
    expect(ti.file_path).toBe("/f.ts");
    expect(ti.content).toBe("x");
  });

  test("editInput returns Edit payload with file_path and new_string", () => {
    const r = editInput("/f.ts", "new") as Record<string, unknown>;
    expect(r.tool_name).toBe("Edit");
    const ti = r.tool_input as Record<string, unknown>;
    expect(ti.file_path).toBe("/f.ts");
    expect(ti.new_string).toBe("new");
  });
});

describe("readInput(), bashInput(), hookInput()", () => {
  test("readInput returns Read payload with file_path", () => {
    const r = readInput("/f.ts") as Record<string, unknown>;
    const ti = r.tool_input as Record<string, unknown>;
    expect(ti.file_path).toBe("/f.ts");
  });

  test("bashInput returns Bash payload with command", () => {
    const r = bashInput("ls") as Record<string, unknown>;
    const ti = r.tool_input as Record<string, unknown>;
    expect(ti.command).toBe("ls");
  });

  test("hookInput returns payload with tool_name and file_path", () => {
    const r = hookInput("Write", "/f.ts") as Record<string, unknown>;
    expect(r.tool_name).toBe("Write");
    const ti = r.tool_input as Record<string, unknown>;
    expect(ti.file_path).toBe("/f.ts");
  });
});
