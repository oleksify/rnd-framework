/**
 * Tests for hooks/session-start
 *
 * Covers all 9 success criteria from the T7 pre-registration:
 *   1. Exit code is 0
 *   2. stdout is valid JSON parseable by JSON.parse
 *   3. JSON output has "additional_context" key containing "rnd-framework" text
 *   4. JSON output has "hookSpecificOutput.hookEventName" equal to "SessionStart"
 *   5. JSON output has "hookSpecificOutput.additionalContext" matching "additional_context"
 *   6. The additionalContext includes the content of the SKILL.md file
 *   7. When RND_DIR can be computed, the additionalContext includes the RND_DIR path
 *   8. When source plugin.json version differs from cached, output contains "version mismatch" warning
 *   9. When versions match, no version mismatch warning appears in output
 */

import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { join } from "node:path";
import { mkdtemp, mkdir, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { runHook } from "./helpers";

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const PLUGIN_ROOT = join(import.meta.dir, "..");
const HOOK = join(PLUGIN_ROOT, "hooks", "session-start.ts");
const SKILL_PATH = join(PLUGIN_ROOT, "skills", "using-rnd-framework", "SKILL.md");

// A distinctive string from the SKILL.md that will always be present
const SKILL_MARKER = "rnd-framework:rnd-building";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Runs the session-start hook with an isolated CLAUDE_CONFIG_DIR so rnd-dir.sh
 * doesn't pollute the real ~/.claude/.rnd state. Optionally sets cwd for the
 * subprocess (needed for the version-mismatch test).
 */
async function runSessionStart(opts: {
  extraEnv?: Record<string, string>;
  cwd?: string;
} = {}): Promise<{ stdout: string; stderr: string; exitCode: number }> {
  const claudeConfigDir = await mkdtemp(join(tmpdir(), "session-start-test-config-"));
  try {
    const mergedEnv: Record<string, string> = {
      ...process.env as Record<string, string>,
      CLAUDE_CONFIG_DIR: claudeConfigDir,
      // Ensure CLAUDE_PLUGIN_ROOT is NOT set so CLAUDE_CONFIG_DIR is used by rnd-dir.sh
      ...(opts.extraEnv ?? {}),
    };
    // Remove CLAUDE_PLUGIN_ROOT so rnd-dir.sh uses CLAUDE_CONFIG_DIR instead
    delete mergedEnv["CLAUDE_PLUGIN_ROOT"];

    const spawnOpts: Parameters<typeof Bun.spawn>[1] = {
      stdin: "ignore",
      stdout: "pipe",
      stderr: "pipe",
      env: mergedEnv,
      ...(opts.cwd ? { cwd: opts.cwd } : {}),
    };

    const proc = Bun.spawn([HOOK], spawnOpts);

    const [stdoutBytes, stderrBytes] = await Promise.all([
      Bun.readableStreamToArrayBuffer(proc.stdout as ReadableStream),
      Bun.readableStreamToArrayBuffer(proc.stderr as ReadableStream),
      proc.exited,
    ]);

    const decoder = new TextDecoder();
    return {
      stdout: decoder.decode(stdoutBytes),
      stderr: decoder.decode(stderrBytes),
      exitCode: proc.exitCode ?? 0,
    };
  } finally {
    await rm(claudeConfigDir, { recursive: true, force: true });
  }
}

// ---------------------------------------------------------------------------
// Shared result (run the hook once for the "happy path" tests)
// ---------------------------------------------------------------------------

let result: { stdout: string; stderr: string; exitCode: number };
let parsed: Record<string, unknown>;

beforeAll(async () => {
  result = await runSessionStart();
  try {
    parsed = JSON.parse(result.stdout);
  } catch {
    parsed = {};
  }
});

// ---------------------------------------------------------------------------
// Criterion 1: Exit code is 0
// ---------------------------------------------------------------------------

describe("session-start: exit code", () => {
  test("exits with code 0", () => {
    expect(result.exitCode).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// Criterion 2: stdout is valid JSON parseable by JSON.parse
// ---------------------------------------------------------------------------

describe("session-start: JSON output", () => {
  test("stdout is non-empty", () => {
    expect(result.stdout.trim().length).toBeGreaterThan(0);
  });

  test("stdout is parseable JSON", () => {
    expect(() => JSON.parse(result.stdout)).not.toThrow();
  });

  test("parsed output is an object", () => {
    expect(typeof parsed).toBe("object");
    expect(parsed).not.toBeNull();
  });
});

// ---------------------------------------------------------------------------
// Criterion 3: JSON output has "additional_context" key containing "rnd-framework"
// ---------------------------------------------------------------------------

describe("session-start: additional_context field", () => {
  test("output has an additional_context key", () => {
    expect(parsed).toHaveProperty("additional_context");
  });

  test("additional_context is a string", () => {
    expect(typeof parsed["additional_context"]).toBe("string");
  });

  test('additional_context contains "rnd-framework"', () => {
    expect(parsed["additional_context"] as string).toContain("rnd-framework");
  });
});

// ---------------------------------------------------------------------------
// Criterion 4: JSON output has hookSpecificOutput.hookEventName === "SessionStart"
// ---------------------------------------------------------------------------

describe("session-start: hookSpecificOutput.hookEventName", () => {
  test("output has hookSpecificOutput key", () => {
    expect(parsed).toHaveProperty("hookSpecificOutput");
  });

  test("hookSpecificOutput.hookEventName equals SessionStart", () => {
    const hso = parsed["hookSpecificOutput"] as Record<string, unknown>;
    expect(hso["hookEventName"]).toBe("SessionStart");
  });
});

// ---------------------------------------------------------------------------
// Criterion 5: hookSpecificOutput.additionalContext matches additional_context
// ---------------------------------------------------------------------------

describe("session-start: hookSpecificOutput.additionalContext matches additional_context", () => {
  test("hookSpecificOutput has additionalContext key", () => {
    const hso = parsed["hookSpecificOutput"] as Record<string, unknown>;
    expect(hso).toHaveProperty("additionalContext");
  });

  test("hookSpecificOutput.additionalContext equals additional_context", () => {
    const hso = parsed["hookSpecificOutput"] as Record<string, unknown>;
    expect(hso["additionalContext"]).toBe(parsed["additional_context"]);
  });
});

// ---------------------------------------------------------------------------
// Criterion 6: additionalContext includes content of the SKILL.md file
// ---------------------------------------------------------------------------

describe("session-start: SKILL.md content in additionalContext", () => {
  test("additionalContext contains a known string from SKILL.md", () => {
    const ctx = parsed["additional_context"] as string;
    // SKILL_MARKER is a distinctive string present in the SKILL.md file
    expect(ctx).toContain(SKILL_MARKER);
  });

  test("additionalContext contains the SKILL.md EXTREMELY-IMPORTANT heading", () => {
    const ctx = parsed["additional_context"] as string;
    expect(ctx).toContain("EXTREMELY");
  });

  test("additionalContext contains skill table entries from SKILL.md", () => {
    const ctx = parsed["additional_context"] as string;
    // The Available Skills table header is present in SKILL.md
    expect(ctx).toContain("rnd-framework:rnd-verification");
  });
});

// ---------------------------------------------------------------------------
// Criterion 7: When RND_DIR can be computed, additionalContext includes RND_DIR path
// ---------------------------------------------------------------------------

describe("session-start: RND_DIR path in additionalContext", () => {
  test("additionalContext contains RND_DIR path when rnd-dir.sh succeeds", async () => {
    // Run hook with a dedicated temp CLAUDE_CONFIG_DIR and a real cwd
    const claudeConfigDir = await mkdtemp(join(tmpdir(), "rnd-dir-test-"));
    try {
      const testResult = await runSessionStart({ extraEnv: { CLAUDE_CONFIG_DIR: claudeConfigDir } });
      const testParsed = JSON.parse(testResult.stdout);
      const ctx = testParsed["additional_context"] as string;

      // rnd-dir.sh produces a path containing ".rnd/"
      expect(ctx).toContain(".rnd/");
    } finally {
      await rm(claudeConfigDir, { recursive: true, force: true });
    }
  });

  test("additionalContext RND_DIR section contains RND_DIR label", async () => {
    const claudeConfigDir = await mkdtemp(join(tmpdir(), "rnd-dir-label-test-"));
    try {
      const testResult = await runSessionStart({ extraEnv: { CLAUDE_CONFIG_DIR: claudeConfigDir } });
      const testParsed = JSON.parse(testResult.stdout);
      const ctx = testParsed["additional_context"] as string;
      // The hook emits a "RND_DIR (pipeline artifact directory..." label
      expect(ctx).toContain("RND_DIR");
    } finally {
      await rm(claudeConfigDir, { recursive: true, force: true });
    }
  });
});

// ---------------------------------------------------------------------------
// Criterion 8: When source plugin.json version differs, output contains "version mismatch" warning
// ---------------------------------------------------------------------------

describe("session-start: version mismatch warning", () => {
  let mismatchDir: string;

  beforeAll(async () => {
    // Create a temp git repo with a plugin.json whose version differs from the real one
    mismatchDir = await mkdtemp(join(tmpdir(), "version-mismatch-test-"));

    // Initialize as a git repo so git rev-parse works
    const gitInit = Bun.spawn(["git", "init"], {
      cwd: mismatchDir,
      stdout: "ignore",
      stderr: "ignore",
    });
    await gitInit.exited;

    // Place a plugin.json at plugins/rnd-framework/.claude-plugin/plugin.json
    // with a deliberately different version (9.9.9)
    const pluginDir = join(mismatchDir, "plugins", "rnd-framework", ".claude-plugin");
    await mkdir(pluginDir, { recursive: true });
    await writeFile(
      join(pluginDir, "plugin.json"),
      JSON.stringify({ name: "rnd-framework", version: "9.9.9", description: "test" }),
      "utf-8",
    );
  });

  afterAll(async () => {
    if (mismatchDir) {
      await rm(mismatchDir, { recursive: true, force: true });
    }
  });

  test("output contains 'version mismatch' when source version differs from cached", async () => {
    const testResult = await runSessionStart({ cwd: mismatchDir });
    expect(testResult.exitCode).toBe(0);
    const ctx = JSON.parse(testResult.stdout)["additional_context"] as string;
    expect(ctx.toLowerCase()).toContain("version mismatch");
  });

  test("version mismatch warning mentions the source version (9.9.9)", async () => {
    const testResult = await runSessionStart({ cwd: mismatchDir });
    const ctx = JSON.parse(testResult.stdout)["additional_context"] as string;
    expect(ctx).toContain("9.9.9");
  });

  test("version mismatch warning mentions the cached version", async () => {
    // Read the real cached version from plugin.json
    const pluginJson = await Bun.file(join(PLUGIN_ROOT, ".claude-plugin", "plugin.json")).json();
    const cachedVersion = pluginJson.version as string;

    const testResult = await runSessionStart({ cwd: mismatchDir });
    const ctx = JSON.parse(testResult.stdout)["additional_context"] as string;
    expect(ctx).toContain(cachedVersion);
  });
});

// ---------------------------------------------------------------------------
// Criterion 9: When versions match, no version mismatch warning in output
// ---------------------------------------------------------------------------

describe("session-start: no version mismatch warning when versions match", () => {
  test("output does not contain 'version mismatch' when run from the real source repo", async () => {
    // Running from the plugin source directory — versions will match since
    // the hook reads the same plugin.json via both the cached and git-root paths
    const repoRoot = join(PLUGIN_ROOT, "..", "..");
    const testResult = await runSessionStart({ cwd: repoRoot });
    expect(testResult.exitCode).toBe(0);
    const ctx = JSON.parse(testResult.stdout)["additional_context"] as string;
    expect(ctx.toLowerCase()).not.toContain("version mismatch");
  });
});

// ---------------------------------------------------------------------------
// Criterion 10: Cron instruction removed — output must NOT contain CronCreate
// ---------------------------------------------------------------------------

describe("session-start: no cron instruction in output", () => {
  test("additionalContext does NOT contain 'CronCreate'", () => {
    expect(parsed["additional_context"] as string).not.toContain("CronCreate");
  });
});
