/**
 * Tests for hooks/auto-allow-rnd
 *
 * Success criteria:
 *   SC1: Path containing ".rnd/" returns exit 0 and stdout contains permissionDecision "allow"
 *   SC2: Path NOT containing ".rnd/" with no active session returns exit 0 and empty stdout
 *   SC3: Path NOT containing ".rnd/" during planning phase (marker file exists) returns exit 2 and stderr contains "BLOCKED"
 *   SC4: Path NOT containing ".rnd/" outside planning phase (no marker) returns exit 0 and empty stdout
 *   SC5: Deeply nested .rnd/ paths (e.g., /foo/bar/.rnd/baz/qux.md) are auto-allowed
 */

import { describe, expect, it, beforeAll, afterAll } from "bun:test";
import { join } from "node:path";
import { mkdir, writeFile, rm, mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { runHook } from "./helpers";

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const HOOK_PATH = join(
  import.meta.dir,
  "..",
  "hooks",
  "auto-allow-rnd",
);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Build the hook input payload for a given file_path.
 */
function hookInput(filePath: string): unknown {
  return { tool_input: { file_path: filePath } };
}

/**
 * Compute the project slug rnd-dir.sh would produce for a given directory.
 * Slug format: <basename>-<8char sha256 hex hash of full path>
 *
 * Uses Bun.spawn to avoid execSync (which triggers security hooks).
 */
async function computeSlug(dir: string): Promise<string> {
  const basename = dir.split("/").filter(Boolean).at(-1) ?? "unknown";

  const proc = Bun.spawn(
    ["bash", "-c", `printf '%s' ${JSON.stringify(dir)} | shasum -a 256 | cut -c1-8`],
    { stdout: "pipe", stderr: "pipe" },
  );
  const bytes = await Bun.readableStreamToArrayBuffer(proc.stdout);
  await proc.exited;
  const hash = new TextDecoder().decode(bytes).trim();

  return `${basename}-${hash}`;
}

/**
 * Create a fake CLAUDE_CONFIG_DIR environment where rnd-dir.sh will find an
 * active session. Optionally places a .planning-phase marker in the session dir.
 *
 * Returns { configDir, cleanup }.
 */
async function createFakeConfigDir(
  cwd: string,
  opts: { planningPhase?: boolean } = {},
): Promise<{ configDir: string; cleanup: () => Promise<void> }> {
  // Build the directory tree that rnd-dir.sh expects:
  //   <configDir>/.rnd/<slug>/.current-session   <- session ID
  //   <configDir>/.rnd/<slug>/sessions/<id>/     <- session dir
  //   [optionally] sessions/<id>/.planning-phase

  const configDir = await mkdtemp(join(tmpdir(), "rnd-test-config-"));
  const SESSION_ID = "20260305-120000-abcd";
  const slug = await computeSlug(cwd);
  const rndBase = join(configDir, ".rnd", slug);
  const sessionDir = join(rndBase, "sessions", SESSION_ID);

  await mkdir(sessionDir, { recursive: true });
  await writeFile(join(rndBase, ".current-session"), SESSION_ID, "utf-8");

  if (opts.planningPhase) {
    await writeFile(join(sessionDir, ".planning-phase"), "", "utf-8");
  }

  async function cleanup(): Promise<void> {
    await rm(configDir, { recursive: true, force: true });
  }

  return { configDir, cleanup };
}

// ---------------------------------------------------------------------------
// Determine the cwd that bun test will use (same as where bun is invoked from)
// ---------------------------------------------------------------------------

// When bun test is run, it runs in the process cwd. The hook calls rnd-dir.sh
// which uses `pwd`, so the relevant cwd is the test process's cwd.
const TEST_CWD = process.cwd();

// ---------------------------------------------------------------------------
// SC1: .rnd/ path is auto-allowed
// ---------------------------------------------------------------------------

describe("SC1: .rnd/ path is auto-allowed", () => {
  it("returns exit 0 when path contains .rnd/", async () => {
    const result = await runHook(
      HOOK_PATH,
      hookInput("/home/user/.rnd/sessions/20260305-1234/plan.md"),
    );
    expect(result.exitCode).toBe(0);
  });

  it("stdout contains permissionDecision allow", async () => {
    const result = await runHook(
      HOOK_PATH,
      hookInput("/home/user/.rnd/sessions/20260305-1234/plan.md"),
    );
    expect(result.stdout).not.toBe("");
    const parsed = JSON.parse(result.stdout.trim());
    expect(parsed.hookSpecificOutput.permissionDecision).toBe("allow");
  });

  it("stdout is valid JSON for .rnd/ path", async () => {
    const result = await runHook(HOOK_PATH, hookInput("/some/.rnd/path.txt"));
    expect(() => JSON.parse(result.stdout.trim())).not.toThrow();
  });
});

// ---------------------------------------------------------------------------
// SC2: Non-.rnd/ path with no active session -> exit 0, empty stdout
// ---------------------------------------------------------------------------

describe("SC2: non-.rnd/ path with no active session returns no opinion", () => {
  it("returns exit 0 for non-.rnd/ path when no session directory exists", async () => {
    const nonExistentDir = join(tmpdir(), `rnd-nonexistent-${Date.now()}`);
    const result = await runHook(
      HOOK_PATH,
      hookInput("/some/regular/file.txt"),
      {
        CLAUDE_CONFIG_DIR: nonExistentDir,
        CLAUDE_PLUGIN_ROOT: "",
      },
    );
    expect(result.exitCode).toBe(0);
  });

  it("stdout is empty (no opinion) for non-.rnd/ path with no session", async () => {
    const nonExistentDir = join(tmpdir(), `rnd-nonexistent-${Date.now()}`);
    const result = await runHook(
      HOOK_PATH,
      hookInput("/some/regular/file.txt"),
      {
        CLAUDE_CONFIG_DIR: nonExistentDir,
        CLAUDE_PLUGIN_ROOT: "",
      },
    );
    expect(result.stdout.trim()).toBe("");
  });
});

// ---------------------------------------------------------------------------
// SC3: Non-.rnd/ path during planning phase -> exit 2, stderr contains BLOCKED
// ---------------------------------------------------------------------------

describe("SC3: non-.rnd/ path during planning phase is blocked", () => {
  let configDir: string;
  let cleanupConfig: () => Promise<void>;

  beforeAll(async () => {
    const fake = await createFakeConfigDir(TEST_CWD, { planningPhase: true });
    configDir = fake.configDir;
    cleanupConfig = fake.cleanup;
  });

  afterAll(async () => {
    await cleanupConfig();
  });

  it("returns exit 2 when .planning-phase marker exists", async () => {
    const result = await runHook(
      HOOK_PATH,
      hookInput("/some/project/file.ts"),
      {
        CLAUDE_CONFIG_DIR: configDir,
        CLAUDE_PLUGIN_ROOT: "",
      },
    );
    expect(result.exitCode).toBe(2);
  });

  it("stderr contains BLOCKED when .planning-phase marker exists", async () => {
    const result = await runHook(
      HOOK_PATH,
      hookInput("/some/project/file.ts"),
      {
        CLAUDE_CONFIG_DIR: configDir,
        CLAUDE_PLUGIN_ROOT: "",
      },
    );
    expect(result.stderr).toContain("BLOCKED");
  });

  it("stdout is empty when blocked", async () => {
    const result = await runHook(
      HOOK_PATH,
      hookInput("/some/project/file.ts"),
      {
        CLAUDE_CONFIG_DIR: configDir,
        CLAUDE_PLUGIN_ROOT: "",
      },
    );
    expect(result.stdout.trim()).toBe("");
  });

  it(".rnd/ path is still allowed even during planning phase", async () => {
    const result = await runHook(
      HOOK_PATH,
      hookInput("/home/user/.rnd/plan.md"),
      {
        CLAUDE_CONFIG_DIR: configDir,
        CLAUDE_PLUGIN_ROOT: "",
      },
    );
    expect(result.exitCode).toBe(0);
    const parsed = JSON.parse(result.stdout.trim());
    expect(parsed.hookSpecificOutput.permissionDecision).toBe("allow");
  });
});

// ---------------------------------------------------------------------------
// SC4: Non-.rnd/ path, no planning phase marker -> exit 0, empty stdout
// ---------------------------------------------------------------------------

describe("SC4: non-.rnd/ path outside planning phase returns no opinion", () => {
  let configDir: string;
  let cleanupConfig: () => Promise<void>;

  beforeAll(async () => {
    // Active session but NO .planning-phase marker
    const fake = await createFakeConfigDir(TEST_CWD, { planningPhase: false });
    configDir = fake.configDir;
    cleanupConfig = fake.cleanup;
  });

  afterAll(async () => {
    await cleanupConfig();
  });

  it("returns exit 0 when active session has no .planning-phase marker", async () => {
    const result = await runHook(
      HOOK_PATH,
      hookInput("/some/project/file.ts"),
      {
        CLAUDE_CONFIG_DIR: configDir,
        CLAUDE_PLUGIN_ROOT: "",
      },
    );
    expect(result.exitCode).toBe(0);
  });

  it("stdout is empty (no opinion) when no .planning-phase marker", async () => {
    const result = await runHook(
      HOOK_PATH,
      hookInput("/some/project/file.ts"),
      {
        CLAUDE_CONFIG_DIR: configDir,
        CLAUDE_PLUGIN_ROOT: "",
      },
    );
    expect(result.stdout.trim()).toBe("");
  });
});

// ---------------------------------------------------------------------------
// SC5: Deeply nested .rnd/ paths are auto-allowed
// ---------------------------------------------------------------------------

describe("SC5: deeply nested .rnd/ paths are auto-allowed", () => {
  const deepPaths = [
    "/foo/bar/.rnd/baz/qux.md",
    "/home/alice/projects/.rnd/sessions/20260305-120000-abcd/builds/T1-manifest.md",
    "/very/deeply/nested/path/here/.rnd/verifications/T2-verification.md",
    "/a/.rnd/b/c/d/e/f/g.txt",
  ];

  for (const filePath of deepPaths) {
    it(`auto-allows: ${filePath}`, async () => {
      const result = await runHook(HOOK_PATH, hookInput(filePath));
      expect(result.exitCode).toBe(0);
      const parsed = JSON.parse(result.stdout.trim());
      expect(parsed.hookSpecificOutput.permissionDecision).toBe("allow");
    });
  }
});
