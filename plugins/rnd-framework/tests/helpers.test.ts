/**
 * Self-tests for tests/helpers.ts
 * Validates that runHook() and createTempRndDir() work as documented.
 */

import { describe, expect, it, beforeAll, afterAll } from "bun:test";
import { existsSync } from "node:fs";
import { join } from "node:path";
import { runHook, createTempRndDir } from "./helpers";

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
  it("returns an object with stdout, stderr, and exitCode fields", async () => {
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
  it("passes stdinJson to subprocess via stdin", async () => {
    const payload = { tool: "Write", tool_input: { file_path: "/tmp/test.txt" } };
    const result = await runHook(echoHookPath, payload);
    expect(result.exitCode).toBe(0);
    // The echo hook reads stdin and writes it to stdout
    const parsed = JSON.parse(result.stdout);
    expect(parsed).toEqual(payload);
  });

  it("passes no stdin when stdinJson is omitted", async () => {
    const result = await runHook(echoHookPath);
    expect(result.exitCode).toBe(0);
    // No input → stdout should be empty or whitespace only
    expect(result.stdout.trim()).toBe("");
  });

  it("captures stderr and non-zero exit code", async () => {
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
  it("sets environment variables in the subprocess", async () => {
    const result = await runHook(envHookPath, undefined, { TEST_VAR: "hello-from-env" });
    expect(result.exitCode).toBe(0);
    expect(result.stdout.trim()).toBe("hello-from-env");
  });

  it("allows empty env object (no extra env vars)", async () => {
    const result = await runHook(envHookPath, undefined, {});
    expect(result.exitCode).toBe(0);
    // TEST_VAR not set → empty line
    expect(result.stdout.trim()).toBe("");
  });

  it("env vars are accessible alongside inherited process env", async () => {
    // PATH must still be inherited so bash can run
    const result = await runHook(echoHookPath, { ok: true }, { EXTRA: "yes" });
    expect(result.exitCode).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// createTempRndDir() — directory structure
// ---------------------------------------------------------------------------

describe("createTempRndDir() directory structure", () => {
  it("returns { baseDir, sessionDir, cleanup }", async () => {
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

  it("creates a sessions/ subdirectory inside baseDir", async () => {
    const dirs = await createTempRndDir();
    try {
      const sessionsDir = join(dirs.baseDir, "sessions");
      expect(existsSync(sessionsDir)).toBe(true);
    } finally {
      await dirs.cleanup();
    }
  });

  it("creates sessionDir inside baseDir/sessions/", async () => {
    const dirs = await createTempRndDir();
    try {
      expect(dirs.sessionDir.startsWith(join(dirs.baseDir, "sessions"))).toBe(true);
      expect(existsSync(dirs.sessionDir)).toBe(true);
    } finally {
      await dirs.cleanup();
    }
  });

  it("creates builds/, verifications/, integration/ subdirs inside sessionDir", async () => {
    const dirs = await createTempRndDir();
    try {
      for (const subdir of ["builds", "verifications", "integration"]) {
        expect(existsSync(join(dirs.sessionDir, subdir))).toBe(true);
      }
    } finally {
      await dirs.cleanup();
    }
  });

  it("creates a .current-session file in baseDir pointing to session ID", async () => {
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
  it("cleanup() removes the entire baseDir tree", async () => {
    const dirs = await createTempRndDir();
    const { baseDir, cleanup } = dirs;
    expect(existsSync(baseDir)).toBe(true);
    await cleanup();
    expect(existsSync(baseDir)).toBe(false);
  });

  it("cleanup() is idempotent (calling twice does not throw)", async () => {
    const dirs = await createTempRndDir();
    await dirs.cleanup();
    // Second call should not throw
    await expect(dirs.cleanup()).resolves.toBeUndefined();
  });
});
