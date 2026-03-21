/**
 * Tests for lib/rnd-dir.sh
 *
 * Covers all 12 success criteria from the pre-registration:
 *   1.  --base returns <config-dir>/.rnd/<basename>-<8char-hash> and never creates dirs
 *   2.  -c creates session directory tree and returns session path
 *   3.  -c on subsequent calls returns the same session path (session ID reuse)
 *   4.  No flags + active session → returns session path
 *   5.  No flags + no session → returns base dir
 *   6.  --finish removes .current-session; subsequent no-flag call returns base dir
 *   7.  --finish is idempotent (succeeds when no session exists)
 *   8.  Invalid session ID in .current-session → exit code 1 + stderr "invalid session ID"
 *   9.  Session ID format matches /^\d{8}-\d{6}-[0-9a-f]{4}$/
 *  10.  CLAUDE_PLUGIN_ROOT with /plugins/cache/ suffix stripped to derive config dir
 *  11.  CLAUDE_CONFIG_DIR used when CLAUDE_PLUGIN_ROOT is unset
 *  12.  Falls back to $HOME/.claude when neither env var is set
 */

import { describe, test, expect, beforeEach, afterEach } from "bun:test";
import { mkdtemp, mkdir, writeFile, rm, stat } from "node:fs/promises";
import { existsSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";

// ---------------------------------------------------------------------------
// Path to the script under test
// ---------------------------------------------------------------------------

const SCRIPT = join(
  import.meta.dir,
  "..",
  "lib",
  "rnd-dir.sh",
);

// ---------------------------------------------------------------------------
// Helper: run rnd-dir.sh as a subprocess
// ---------------------------------------------------------------------------

interface RunResult {
  stdout: string;
  stderr: string;
  exitCode: number;
}

async function runScript(
  args: string[],
  opts: {
    cwd?: string;
    env?: Record<string, string>;
  } = {},
): Promise<RunResult> {
  // Strip env vars that would interfere with tests, then overlay opts.env
  const baseEnv: Record<string, string> = {};
  for (const [k, v] of Object.entries(process.env)) {
    if (
      k !== "CLAUDE_PLUGIN_ROOT" &&
      k !== "CLAUDE_CONFIG_DIR" &&
      v !== undefined
    ) {
      baseEnv[k] = v;
    }
  }

  const mergedEnv: Record<string, string> = {
    ...baseEnv,
    ...(opts.env ?? {}),
  };

  const proc = Bun.spawn([SCRIPT, ...args], {
    cwd: opts.cwd,
    stdin: "ignore",
    stdout: "pipe",
    stderr: "pipe",
    env: mergedEnv,
  });

  const [stdoutBuf, stderrBuf] = await Promise.all([
    Bun.readableStreamToArrayBuffer(proc.stdout),
    Bun.readableStreamToArrayBuffer(proc.stderr),
    proc.exited,
  ]);

  const dec = new TextDecoder();
  return {
    stdout: dec.decode(stdoutBuf).trim(),
    stderr: dec.decode(stderrBuf).trim(),
    exitCode: proc.exitCode ?? 0,
  };
}

// ---------------------------------------------------------------------------
// Fixture: isolated temp dirs for each test
// ---------------------------------------------------------------------------

let configDir: string;       // acts as the value of CLAUDE_CONFIG_DIR
let projectDir: string;      // cwd for the script (determines project slug)
let cleanup: () => Promise<void>;

beforeEach(async () => {
  configDir = await mkdtemp(join(tmpdir(), "rnd-test-config-"));
  projectDir = await mkdtemp(join(tmpdir(), "rnd-test-project-"));
  cleanup = async () => {
    await rm(configDir, { recursive: true, force: true });
    await rm(projectDir, { recursive: true, force: true });
  };
});

afterEach(async () => {
  await cleanup();
});

// ---------------------------------------------------------------------------
// Convenience: compute expected base dir for the current projectDir
// ---------------------------------------------------------------------------

async function expectedBaseDir(): Promise<string> {
  const result = await runScript(["--base"], {
    cwd: projectDir,
    env: { CLAUDE_CONFIG_DIR: configDir },
  });
  expect(result.exitCode).toBe(0);
  return result.stdout;
}

// ---------------------------------------------------------------------------
// Criterion 1: --base returns <config-dir>/.rnd/<basename>-<8char-hash>
//              and never creates directories
// ---------------------------------------------------------------------------

describe("--base flag", () => {
  test("returns path with format <config-dir>/.rnd/<basename>-<8char-hash>", async () => {
    const result = await runScript(["--base"], {
      cwd: projectDir,
      env: { CLAUDE_CONFIG_DIR: configDir },
    });

    expect(result.exitCode).toBe(0);

    const baseName = projectDir.split("/").at(-1)!;
    // Path should be under configDir/.rnd/
    expect(result.stdout).toMatch(new RegExp(`^${configDir}/.rnd/${baseName}-[0-9a-f]{8}$`));
  });

  test("does not create any directory", async () => {
    await runScript(["--base"], {
      cwd: projectDir,
      env: { CLAUDE_CONFIG_DIR: configDir },
    });

    const rndPath = join(configDir, ".rnd");
    expect(existsSync(rndPath)).toBe(false);
  });

  test("hash is 8 hex characters", async () => {
    const result = await runScript(["--base"], {
      cwd: projectDir,
      env: { CLAUDE_CONFIG_DIR: configDir },
    });

    expect(result.exitCode).toBe(0);
    const parts = result.stdout.split("-");
    const hash = parts.at(-1)!;
    expect(hash).toMatch(/^[0-9a-f]{8}$/);
  });

  test("is deterministic: same cwd → same output", async () => {
    const r1 = await runScript(["--base"], {
      cwd: projectDir,
      env: { CLAUDE_CONFIG_DIR: configDir },
    });
    const r2 = await runScript(["--base"], {
      cwd: projectDir,
      env: { CLAUDE_CONFIG_DIR: configDir },
    });

    expect(r1.exitCode).toBe(0);
    expect(r1.stdout).toBe(r2.stdout);
  });
});

// ---------------------------------------------------------------------------
// Criterion 2: -c creates session directory tree and returns session path
// ---------------------------------------------------------------------------

describe("-c flag: create session", () => {
  test("returns a path under <base>/sessions/<session-id>", async () => {
    const base = await expectedBaseDir();
    const result = await runScript(["-c"], {
      cwd: projectDir,
      env: { CLAUDE_CONFIG_DIR: configDir },
    });

    expect(result.exitCode).toBe(0);
    expect(result.stdout.startsWith(`${base}/sessions/`)).toBe(true);
  });

  test("creates builds/, verifications/, integration/ inside session dir", async () => {
    const result = await runScript(["-c"], {
      cwd: projectDir,
      env: { CLAUDE_CONFIG_DIR: configDir },
    });

    expect(result.exitCode).toBe(0);
    const sessionDir = result.stdout;

    for (const subdir of ["builds", "verifications", "integration"]) {
      expect(existsSync(join(sessionDir, subdir))).toBe(true);
      const s = await stat(join(sessionDir, subdir));
      expect(s.isDirectory()).toBe(true);
    }
  });

  test("creates .current-session file in base dir", async () => {
    const base = await expectedBaseDir();
    const result = await runScript(["-c"], {
      cwd: projectDir,
      env: { CLAUDE_CONFIG_DIR: configDir },
    });

    expect(result.exitCode).toBe(0);
    expect(existsSync(join(base, ".current-session"))).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// Criterion 3: -c on subsequent calls returns the same session path
// ---------------------------------------------------------------------------

describe("-c flag: session ID reuse", () => {
  test("second -c call returns the same path as the first", async () => {
    const env = { CLAUDE_CONFIG_DIR: configDir };
    const r1 = await runScript(["-c"], { cwd: projectDir, env });
    const r2 = await runScript(["-c"], { cwd: projectDir, env });

    expect(r1.exitCode).toBe(0);
    expect(r2.exitCode).toBe(0);
    expect(r1.stdout).toBe(r2.stdout);
  });
});

// ---------------------------------------------------------------------------
// Criterion 4: No flags + active session → returns session path
// ---------------------------------------------------------------------------

describe("no flags with active session", () => {
  test("returns the active session path", async () => {
    const env = { CLAUDE_CONFIG_DIR: configDir };

    // Create the session first
    const createResult = await runScript(["-c"], { cwd: projectDir, env });
    expect(createResult.exitCode).toBe(0);

    // Now run without flags
    const noFlagResult = await runScript([], { cwd: projectDir, env });
    expect(noFlagResult.exitCode).toBe(0);
    expect(noFlagResult.stdout).toBe(createResult.stdout);
  });
});

// ---------------------------------------------------------------------------
// Criterion 5: No flags + no session → returns base dir
// ---------------------------------------------------------------------------

describe("no flags without active session", () => {
  test("returns the base dir when no .current-session exists", async () => {
    const base = await expectedBaseDir();
    const result = await runScript([], {
      cwd: projectDir,
      env: { CLAUDE_CONFIG_DIR: configDir },
    });

    // The base dir doesn't exist yet (no -c called), but the script just
    // prints the path — it doesn't require the dir to exist
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe(base);
  });
});

// ---------------------------------------------------------------------------
// Criterion 6: --finish removes .current-session; subsequent no-flag → base dir
// ---------------------------------------------------------------------------

describe("--finish flag", () => {
  test("removes .current-session", async () => {
    const env = { CLAUDE_CONFIG_DIR: configDir };
    const base = await expectedBaseDir();

    // Create session first
    await runScript(["-c"], { cwd: projectDir, env });
    expect(existsSync(join(base, ".current-session"))).toBe(true);

    const result = await runScript(["--finish"], { cwd: projectDir, env });
    expect(result.exitCode).toBe(0);
    expect(existsSync(join(base, ".current-session"))).toBe(false);
  });

  test("subsequent no-flag call returns base dir after --finish", async () => {
    const env = { CLAUDE_CONFIG_DIR: configDir };
    const base = await expectedBaseDir();

    // Create session then finish it
    await runScript(["-c"], { cwd: projectDir, env });
    await runScript(["--finish"], { cwd: projectDir, env });

    const result = await runScript([], { cwd: projectDir, env });
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe(base);
  });
});

// ---------------------------------------------------------------------------
// Criterion 7: --finish is idempotent
// ---------------------------------------------------------------------------

describe("--finish idempotency", () => {
  test("succeeds when no session exists", async () => {
    const result = await runScript(["--finish"], {
      cwd: projectDir,
      env: { CLAUDE_CONFIG_DIR: configDir },
    });

    expect(result.exitCode).toBe(0);
  });

  test("calling --finish twice does not error", async () => {
    const env = { CLAUDE_CONFIG_DIR: configDir };

    // Create and finish once
    await runScript(["-c"], { cwd: projectDir, env });
    const r1 = await runScript(["--finish"], { cwd: projectDir, env });
    expect(r1.exitCode).toBe(0);

    // Finish again
    const r2 = await runScript(["--finish"], { cwd: projectDir, env });
    expect(r2.exitCode).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// Criterion 8: Invalid session ID → exit 1 + stderr "invalid session ID"
// ---------------------------------------------------------------------------

describe("invalid session ID handling", () => {
  async function writeInvalidSessionId(invalidId: string): Promise<void> {
    const base = await expectedBaseDir();
    await mkdir(base, { recursive: true });
    await writeFile(join(base, ".current-session"), invalidId, "utf-8");
  }

  test("-c with invalid session ID exits 1 and prints to stderr", async () => {
    await writeInvalidSessionId("not-a-valid-id");

    const result = await runScript(["-c"], {
      cwd: projectDir,
      env: { CLAUDE_CONFIG_DIR: configDir },
    });

    expect(result.exitCode).toBe(1);
    expect(result.stderr.toLowerCase()).toContain("invalid session id");
  });

  test("no flags with invalid session ID exits 1 and prints to stderr", async () => {
    await writeInvalidSessionId("BADFORMAT-12345");

    const result = await runScript([], {
      cwd: projectDir,
      env: { CLAUDE_CONFIG_DIR: configDir },
    });

    expect(result.exitCode).toBe(1);
    expect(result.stderr.toLowerCase()).toContain("invalid session id");
  });

  test("stderr message includes the words 'invalid session ID' (case-insensitive)", async () => {
    await writeInvalidSessionId("bad");

    const result = await runScript(["-c"], {
      cwd: projectDir,
      env: { CLAUDE_CONFIG_DIR: configDir },
    });

    expect(result.stderr.toLowerCase()).toContain("invalid session id");
  });
});

// ---------------------------------------------------------------------------
// Criterion 9: Session ID format matches /^\d{8}-\d{6}-[0-9a-f]{4}$/
// ---------------------------------------------------------------------------

describe("session ID format", () => {
  test("generated session ID matches YYYYMMDD-HHMMSS-xxxx", async () => {
    const env = { CLAUDE_CONFIG_DIR: configDir };
    const base = await expectedBaseDir();

    await runScript(["-c"], { cwd: projectDir, env });

    const sessionFile = join(base, ".current-session");
    expect(existsSync(sessionFile)).toBe(true);

    const sessionId = (await Bun.file(sessionFile).text()).trim();
    expect(sessionId).toMatch(/^\d{8}-\d{6}-[0-9a-f]{4}$/);
  });

  test("session path returned by -c ends with the session ID", async () => {
    const env = { CLAUDE_CONFIG_DIR: configDir };
    const result = await runScript(["-c"], { cwd: projectDir, env });

    expect(result.exitCode).toBe(0);
    const sessionId = result.stdout.split("/").at(-1)!;
    expect(sessionId).toMatch(/^\d{8}-\d{6}-[0-9a-f]{4}$/);
  });
});

// ---------------------------------------------------------------------------
// Criterion 10: CLAUDE_PLUGIN_ROOT with /plugins/cache/ stripped
// ---------------------------------------------------------------------------

describe("CLAUDE_PLUGIN_ROOT config dir derivation", () => {
  test("strips /plugins/cache/... suffix to get config root", async () => {
    // configDir acts as the Claude config root; the plugin root would be
    // something like <configDir>/plugins/cache/rnd-framework@1.0.0
    const fakePluginRoot = join(configDir, "plugins", "cache", "rnd-framework@1.0.0");

    const result = await runScript(["--base"], {
      cwd: projectDir,
      env: { CLAUDE_PLUGIN_ROOT: fakePluginRoot },
    });

    expect(result.exitCode).toBe(0);
    // Should derive configDir as the base, so path starts with configDir/.rnd/
    expect(result.stdout.startsWith(`${configDir}/.rnd/`)).toBe(true);
  });

  test("falls back to CLAUDE_CONFIG_DIR when CLAUDE_PLUGIN_ROOT has no /plugins/cache/", async () => {
    // A PLUGIN_ROOT that doesn't contain /plugins/cache/ → stripping fails
    // so it should fall back to CLAUDE_CONFIG_DIR
    const weirdPluginRoot = join(configDir, "some-other-path");
    const fallbackConfig = await mkdtemp(join(tmpdir(), "rnd-fallback-"));

    try {
      const result = await runScript(["--base"], {
        cwd: projectDir,
        env: {
          CLAUDE_PLUGIN_ROOT: weirdPluginRoot,
          CLAUDE_CONFIG_DIR: fallbackConfig,
        },
      });

      expect(result.exitCode).toBe(0);
      expect(result.stdout.startsWith(`${fallbackConfig}/.rnd/`)).toBe(true);
    } finally {
      await rm(fallbackConfig, { recursive: true, force: true });
    }
  });
});

// ---------------------------------------------------------------------------
// Criterion 11: CLAUDE_CONFIG_DIR used when CLAUDE_PLUGIN_ROOT is unset
// ---------------------------------------------------------------------------

describe("CLAUDE_CONFIG_DIR env var", () => {
  test("uses CLAUDE_CONFIG_DIR as config root when CLAUDE_PLUGIN_ROOT is absent", async () => {
    const result = await runScript(["--base"], {
      cwd: projectDir,
      env: {
        CLAUDE_CONFIG_DIR: configDir,
        // CLAUDE_PLUGIN_ROOT deliberately excluded via runScript's strip logic
      },
    });

    expect(result.exitCode).toBe(0);
    expect(result.stdout.startsWith(`${configDir}/.rnd/`)).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// Criterion 12: Falls back to $HOME/.claude when neither env var is set
// ---------------------------------------------------------------------------

describe("HOME fallback", () => {
  test("uses $HOME/.claude when CLAUDE_PLUGIN_ROOT and CLAUDE_CONFIG_DIR are both unset", async () => {
    const fakeHome = await mkdtemp(join(tmpdir(), "rnd-home-"));

    try {
      const result = await runScript(["--base"], {
        cwd: projectDir,
        env: {
          HOME: fakeHome,
          // Both CLAUDE_PLUGIN_ROOT and CLAUDE_CONFIG_DIR are excluded by
          // runScript's strip logic. Explicitly unset them here too.
          CLAUDE_PLUGIN_ROOT: "",
          CLAUDE_CONFIG_DIR: "",
        },
      });

      expect(result.exitCode).toBe(0);
      expect(result.stdout.startsWith(`${fakeHome}/.claude/.rnd/`)).toBe(true);
    } finally {
      await rm(fakeHome, { recursive: true, force: true });
    }
  });
});

// ---------------------------------------------------------------------------
// Criterion 13: Worktree — main checkout and worktree produce identical --base
// ---------------------------------------------------------------------------

/**
 * Run a bash command as a subprocess and return stdout (trimmed).
 * Throws if exit code is non-zero.
 */
async function sh(cmd: string, cwd?: string): Promise<string> {
  const proc = Bun.spawn(["bash", "-c", cmd], {
    cwd,
    stdin: "ignore",
    stdout: "pipe",
    stderr: "pipe",
  });
  const [out, errBuf] = await Promise.all([
    Bun.readableStreamToArrayBuffer(proc.stdout),
    Bun.readableStreamToArrayBuffer(proc.stderr),
    proc.exited,
  ]);
  if (proc.exitCode !== 0) {
    const errText = new TextDecoder().decode(errBuf).trim();
    throw new Error(`Command failed (exit ${proc.exitCode}): ${cmd}\n${errText}`);
  }
  return new TextDecoder().decode(out).trim();
}

describe("git worktree support", () => {
  let repoDir: string;
  let worktreeDir: string;
  let worktreeCleanup: () => Promise<void>;

  beforeEach(async () => {
    // Create a temp git repo with at least one commit
    repoDir = await mkdtemp(join(tmpdir(), "rnd-git-main-"));
    await sh(`git init -b main "${repoDir}"`);
    await sh('git config user.email "test@test.com"', repoDir);
    await sh('git config user.name "Test"', repoDir);
    await sh("touch README && git add README && git commit -m init", repoDir);

    // Create a worktree alongside the main checkout
    worktreeDir = await mkdtemp(join(tmpdir(), "rnd-git-worktree-"));
    // Remove the empty temp dir first — git worktree add requires a non-existent path
    await rm(worktreeDir, { recursive: true, force: true });
    await sh(`git worktree add -b wt "${worktreeDir}"`, repoDir);

    worktreeCleanup = async () => {
      // Remove worktree from git tracking before deleting dir
      await sh(`git worktree remove --force "${worktreeDir}"`, repoDir).catch(() => {});
      await rm(repoDir, { recursive: true, force: true });
      await rm(worktreeDir, { recursive: true, force: true }).catch(() => {});
    };
  });

  afterEach(async () => {
    await worktreeCleanup();
  });

  test("main checkout and worktree produce the same --base output", async () => {
    const env = { CLAUDE_CONFIG_DIR: configDir };

    const fromMain = await runScript(["--base"], { cwd: repoDir, env });
    const fromWorktree = await runScript(["--base"], { cwd: worktreeDir, env });

    expect(fromMain.exitCode).toBe(0);
    expect(fromWorktree.exitCode).toBe(0);
    expect(fromMain.stdout).toBe(fromWorktree.stdout);
  });

  test("--base slug basename comes from repo name, not worktree dir name", async () => {
    const env = { CLAUDE_CONFIG_DIR: configDir };

    // repoDir name is something like "rnd-git-main-XXXX"
    // worktreeDir name is "rnd-git-worktree-YYYY" — different basename
    const repoBasename = repoDir.split("/").at(-1)!;

    const fromMain = await runScript(["--base"], { cwd: repoDir, env });
    const fromWorktree = await runScript(["--base"], { cwd: worktreeDir, env });

    expect(fromMain.exitCode).toBe(0);
    expect(fromWorktree.exitCode).toBe(0);

    // Both should use the repo's dirname, not the worktree's dirname
    const slug = fromMain.stdout.split("/.rnd/").at(-1)!;
    expect(slug.startsWith(repoBasename)).toBe(true);

    // The worktree path should also have the repo basename
    const worktreeSlug = fromWorktree.stdout.split("/.rnd/").at(-1)!;
    expect(worktreeSlug.startsWith(repoBasename)).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// Criterion 13b: Subdirectory of a git repo produces the same --base as root
// ---------------------------------------------------------------------------

describe("git subdirectory support", () => {
  let repoDir: string;
  let subDir: string;
  let subdirCleanup: () => Promise<void>;

  beforeEach(async () => {
    // Create a temp git repo with a subdirectory
    repoDir = await mkdtemp(join(tmpdir(), "rnd-git-subdir-"));
    await sh(`git init -b main "${repoDir}"`);
    await sh('git config user.email "test@test.com"', repoDir);
    await sh('git config user.name "Test"', repoDir);
    await sh("touch README && git add README && git commit -m init", repoDir);

    // Create a nested subdirectory
    subDir = join(repoDir, "src", "lib");
    await mkdir(subDir, { recursive: true });

    subdirCleanup = async () => {
      await rm(repoDir, { recursive: true, force: true });
    };
  });

  afterEach(async () => {
    await subdirCleanup();
  });

  test("--base from a subdirectory matches --base from repo root", async () => {
    const env = { CLAUDE_CONFIG_DIR: configDir };

    const fromRoot = await runScript(["--base"], { cwd: repoDir, env });
    const fromSubdir = await runScript(["--base"], { cwd: subDir, env });

    expect(fromRoot.exitCode).toBe(0);
    expect(fromSubdir.exitCode).toBe(0);
    expect(fromRoot.stdout).toBe(fromSubdir.stdout);
  });

  test("slug basename from subdirectory comes from repo name, not '..'", async () => {
    const env = { CLAUDE_CONFIG_DIR: configDir };

    const fromSubdir = await runScript(["--base"], { cwd: subDir, env });

    expect(fromSubdir.exitCode).toBe(0);

    const slug = fromSubdir.stdout.split("/.rnd/").at(-1)!;
    // basename must NOT be ".." (that was the bug)
    expect(slug.startsWith("..")).toBe(false);
    // basename should come from the repo dir name
    const repoBasename = repoDir.split("/").at(-1)!;
    expect(slug.startsWith(repoBasename)).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// Criterion 14: Non-git directory uses pwd for hashing (fallback)
// ---------------------------------------------------------------------------

describe("non-git directory fallback", () => {
  test("--base in a non-git directory uses pwd basename and hash", async () => {
    // projectDir from beforeEach is a plain temp dir (not a git repo)
    const env = { CLAUDE_CONFIG_DIR: configDir };
    const result = await runScript(["--base"], { cwd: projectDir, env });

    expect(result.exitCode).toBe(0);

    // The slug should use the basename of projectDir
    const projectBasename = projectDir.split("/").at(-1)!;
    const slugPart = result.stdout.split("/.rnd/").at(-1)!;
    expect(slugPart.startsWith(projectBasename)).toBe(true);
    // Hash should still be 8 hex chars at the end
    expect(slugPart).toMatch(/-[0-9a-f]{8}$/);
  });

  test("--base is deterministic for non-git directory", async () => {
    const env = { CLAUDE_CONFIG_DIR: configDir };

    const r1 = await runScript(["--base"], { cwd: projectDir, env });
    const r2 = await runScript(["--base"], { cwd: projectDir, env });

    expect(r1.exitCode).toBe(0);
    expect(r1.stdout).toBe(r2.stdout);
  });
});
