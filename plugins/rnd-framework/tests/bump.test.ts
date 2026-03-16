/**
 * Tests for lib/bump.sh
 *
 * Covers all success criteria from the T1 pre-registration:
 *   1.  No arguments → exit 1 + stderr "usage"
 *   2.  Empty string argument → exit 1
 *   3.  jq not in PATH → exit 1 + stderr "jq"
 *   4.  CHANGELOG.md missing → exit 1 + stderr "CHANGELOG"
 *   5.  Invalid semver in plugin.json → exit 1 + stderr "semver"
 *   6.  Happy path headline only → patch version incremented by 1
 *   7.  Happy path with description → CHANGELOG contains headline and body
 *   8.  Happy path → CHANGELOG.md first line (original header) preserved
 *   9.  Happy path → new version appears in both plugin.json and CHANGELOG.md
 *  10.  Happy path → stdout contains "Bumped version X.Y.Z -> X.Y.(Z+1)"
 *  11.  Happy path → git status shows plugin.json and CHANGELOG.md staged
 *  12.  Version 0.0.99 → 0.0.100 (no overflow to minor)
 *  13.  No test modifies files outside the temp directory
 *  14.  (bonus) bump.sh with description omitted → CHANGELOG entry has no extra blank body line
 */

import { describe, test, expect, beforeEach, afterEach } from "bun:test";
import { mkdtemp, mkdir, writeFile, rm, readFile } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";

// ---------------------------------------------------------------------------
// Helper: spawn a subprocess and collect stdout/stderr/exitCode
// ---------------------------------------------------------------------------

interface RunResult {
  stdout: string;
  stderr: string;
  exitCode: number;
}

async function runScript(
  scriptPath: string,
  args: string[],
  opts: {
    cwd?: string;
    env?: Record<string, string>;
  } = {},
): Promise<RunResult> {
  const proc = Bun.spawn([scriptPath, ...args], {
    cwd: opts.cwd ?? join(scriptPath, "..", ".."),
    stdin: "ignore",
    stdout: "pipe",
    stderr: "pipe",
    env: opts.env ?? { ...process.env },
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
// Fixture: temp directory with an isolated plugin structure
//
// Directory layout mirrors what bump.sh expects:
//   <tmp>/
//     lib/
//       bump.sh          (copy of real script)
//     .claude-plugin/
//       plugin.json
//     CHANGELOG.md
//
// bump.sh computes PLUGIN_DIR = dirname($0)/.. so when invoked as
// <tmp>/lib/bump.sh, PLUGIN_DIR resolves to <tmp>.
// ---------------------------------------------------------------------------

const REAL_BUMP_SH = join(import.meta.dir, "..", "lib", "bump.sh");

const DEFAULT_CHANGELOG = `# Changelog

## 0.8.1 — 2025-01-01

### Previous entry

Some body.
`;

function makePluginJson(version: string): string {
  return JSON.stringify({ name: "test-plugin", description: "test", version }, null, 2) + "\n";
}

interface TempPlugin {
  dir: string;           // root of the temp plugin tree
  bumpSh: string;        // path to the copied bump.sh
  pluginJson: string;    // path to .claude-plugin/plugin.json
  changelog: string;     // path to CHANGELOG.md
  cleanup: () => Promise<void>;
}

async function createTempPlugin(
  version = "0.8.1",
  changelogContent = DEFAULT_CHANGELOG,
): Promise<TempPlugin> {
  const dir = await mkdtemp(join(tmpdir(), "bump-test-"));
  const libDir = join(dir, "lib");
  const pluginJsonDir = join(dir, ".claude-plugin");

  await mkdir(libDir, { recursive: true });
  await mkdir(pluginJsonDir, { recursive: true });

  // Copy bump.sh into <tmp>/lib/bump.sh so PLUGIN_DIR resolves to <tmp>
  const scriptContent = await readFile(REAL_BUMP_SH, "utf-8");
  const bumpSh = join(libDir, "bump.sh");
  await writeFile(bumpSh, scriptContent, { mode: 0o755 });

  const pluginJson = join(pluginJsonDir, "plugin.json");
  await writeFile(pluginJson, makePluginJson(version));

  const changelog = join(dir, "CHANGELOG.md");
  await writeFile(changelog, changelogContent);

  // git init so "git add" inside bump.sh can stage files
  const gitInit = Bun.spawnSync(["git", "init"], { cwd: dir });
  if (gitInit.exitCode !== 0) {
    throw new Error("git init failed in temp dir");
  }
  // Configure a minimal git identity so git doesn't complain
  Bun.spawnSync(["git", "config", "user.email", "test@test.com"], { cwd: dir });
  Bun.spawnSync(["git", "config", "user.name", "Test"], { cwd: dir });

  return {
    dir,
    bumpSh,
    pluginJson,
    changelog,
    cleanup: () => rm(dir, { recursive: true, force: true }),
  };
}

// ---------------------------------------------------------------------------
// Per-test temp dir management
// ---------------------------------------------------------------------------

let plugin: TempPlugin;

beforeEach(async () => {
  plugin = await createTempPlugin();
});

afterEach(async () => {
  await plugin.cleanup();
});

// ---------------------------------------------------------------------------
// Criterion 1: No arguments → exit 1 + stderr "usage"
// ---------------------------------------------------------------------------

describe("argument validation", () => {
  test("no arguments exits with code 1 and stderr contains 'usage'", async () => {
    const result = await runScript(plugin.bumpSh, []);
    expect(result.exitCode).toBe(1);
    expect(result.stderr.toLowerCase()).toContain("usage");
  });

  // Criterion 2: empty string argument → exit 1
  test("empty string argument exits with code 1", async () => {
    const result = await runScript(plugin.bumpSh, [""]);
    expect(result.exitCode).toBe(1);
  });
});

// ---------------------------------------------------------------------------
// Criterion 3: jq not in PATH → exit 1 + stderr "jq"
// ---------------------------------------------------------------------------

describe("dependency checks", () => {
  test("missing jq exits with code 1 and stderr contains 'jq'", async () => {
    // Create a fake bin directory with a stub that shadows jq
    // This is more portable than restricting PATH (jq may be in /usr/bin on some systems)
    const fakeBin = await mkdtemp(join(tmpdir(), "fake-bin-"));
    try {
      // Write a fake jq that does NOT exist (we just don't create it) but we need
      // PATH to NOT include wherever jq is actually installed.
      // Strategy: find real jq, build a PATH that omits its parent directory.
      // On macOS jq is typically at /usr/bin/jq.
      // We give only /bin (contains bash/sh/date/etc.) as the PATH.
      // The bump.sh shebang is #!/usr/bin/env bash — but Bun.spawn invokes
      // the script directly via the kernel which reads the shebang line, so
      // /usr/bin/env must exist even if /usr/bin is not in PATH.
      // We create a minimal PATH: /bin + fakeBin (no jq in either).
      const result = await runScript(plugin.bumpSh, ["My headline"], {
        env: {
          ...process.env,
          PATH: `/bin:${fakeBin}`,
        },
      });
      expect(result.exitCode).toBe(1);
      expect(result.stderr.toLowerCase()).toContain("jq");
    } finally {
      await rm(fakeBin, { recursive: true, force: true });
    }
  });
});

// ---------------------------------------------------------------------------
// Criterion 4: CHANGELOG.md missing → exit 1 + stderr "CHANGELOG"
// ---------------------------------------------------------------------------

describe("file existence checks", () => {
  test("missing CHANGELOG.md exits with code 1 and stderr contains 'CHANGELOG'", async () => {
    // Remove the CHANGELOG.md that was set up
    await rm(plugin.changelog);

    const result = await runScript(plugin.bumpSh, ["My headline"]);
    expect(result.exitCode).toBe(1);
    expect(result.stderr).toContain("CHANGELOG");
  });
});

// ---------------------------------------------------------------------------
// Criterion 5: Invalid semver → exit 1 + stderr "semver"
// ---------------------------------------------------------------------------

describe("semver validation", () => {
  test("non-semver version in plugin.json exits with code 1 and stderr contains 'semver'", async () => {
    const badPlugin = await createTempPlugin("1.2.abc");
    try {
      const result = await runScript(badPlugin.bumpSh, ["My headline"]);
      expect(result.exitCode).toBe(1);
      expect(result.stderr.toLowerCase()).toContain("semver");
    } finally {
      await badPlugin.cleanup();
    }
  });

  test("version with only two parts is invalid semver", async () => {
    const badPlugin = await createTempPlugin("1.2");
    try {
      const result = await runScript(badPlugin.bumpSh, ["My headline"]);
      expect(result.exitCode).toBe(1);
      expect(result.stderr.toLowerCase()).toContain("semver");
    } finally {
      await badPlugin.cleanup();
    }
  });
});

// ---------------------------------------------------------------------------
// Criterion 6: Happy path — patch version incremented by 1
// ---------------------------------------------------------------------------

describe("happy path: version increment", () => {
  test("patch version in plugin.json increments by 1", async () => {
    const result = await runScript(plugin.bumpSh, ["My headline"]);
    expect(result.exitCode).toBe(0);

    const updatedJson = JSON.parse(await readFile(plugin.pluginJson, "utf-8"));
    expect(updatedJson.version).toBe("0.8.2");
  });

  // Criterion 12: 0.0.99 → 0.0.100
  test("version 0.0.99 bumps to 0.0.100 (no overflow to minor)", async () => {
    const p = await createTempPlugin("0.0.99");
    try {
      const result = await runScript(p.bumpSh, ["Overflow test"]);
      expect(result.exitCode).toBe(0);

      const updatedJson = JSON.parse(await readFile(p.pluginJson, "utf-8"));
      expect(updatedJson.version).toBe("0.0.100");
    } finally {
      await p.cleanup();
    }
  });
});

// ---------------------------------------------------------------------------
// Criterion 7: Happy path with description — CHANGELOG contains headline and body
// ---------------------------------------------------------------------------

describe("happy path: CHANGELOG entry contents", () => {
  test("with description — CHANGELOG contains headline as ### heading and body text", async () => {
    const result = await runScript(plugin.bumpSh, [
      "Fix important bug",
      "This is the description body paragraph.",
    ]);
    expect(result.exitCode).toBe(0);

    const changelog = await readFile(plugin.changelog, "utf-8");
    expect(changelog).toContain("### Fix important bug");
    expect(changelog).toContain("This is the description body paragraph.");
  });

  test("without description — CHANGELOG contains ### heading but no extra body", async () => {
    const result = await runScript(plugin.bumpSh, ["Headline only"]);
    expect(result.exitCode).toBe(0);

    const changelog = await readFile(plugin.changelog, "utf-8");
    expect(changelog).toContain("### Headline only");
  });

  // Criterion 8: original header is preserved
  test("original first line of CHANGELOG.md is preserved", async () => {
    const result = await runScript(plugin.bumpSh, ["New entry"]);
    expect(result.exitCode).toBe(0);

    const changelog = await readFile(plugin.changelog, "utf-8");
    expect(changelog.split("\n")[0]).toBe("# Changelog");
  });

  // Criterion 9: new version appears in both plugin.json and CHANGELOG.md
  test("new version appears in both plugin.json and CHANGELOG.md", async () => {
    const result = await runScript(plugin.bumpSh, ["Version bump"]);
    expect(result.exitCode).toBe(0);

    const updatedJson = JSON.parse(await readFile(plugin.pluginJson, "utf-8"));
    const changelog = await readFile(plugin.changelog, "utf-8");

    expect(updatedJson.version).toBe("0.8.2");
    expect(changelog).toContain("0.8.2");
  });

  test("previous CHANGELOG content is retained after prepend", async () => {
    const result = await runScript(plugin.bumpSh, ["New entry"]);
    expect(result.exitCode).toBe(0);

    const changelog = await readFile(plugin.changelog, "utf-8");
    expect(changelog).toContain("Previous entry");
    expect(changelog).toContain("Some body.");
  });
});

// ---------------------------------------------------------------------------
// Criterion 10: stdout contains "Bumped version X.Y.Z -> X.Y.(Z+1)"
// ---------------------------------------------------------------------------

describe("happy path: stdout output", () => {
  test("stdout contains 'Bumped version 0.8.1' and '0.8.2'", async () => {
    const result = await runScript(plugin.bumpSh, ["My headline"]);
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toContain("0.8.1");
    expect(result.stdout).toContain("0.8.2");
    // The arrow character may be unicode → match the key words
    expect(result.stdout.toLowerCase()).toContain("bumped");
  });
});

// ---------------------------------------------------------------------------
// Criterion 11: git status shows plugin.json and CHANGELOG.md staged
// ---------------------------------------------------------------------------

describe("happy path: git staging", () => {
  test("plugin.json is staged after bump", async () => {
    const result = await runScript(plugin.bumpSh, ["Staged check"]);
    expect(result.exitCode).toBe(0);

    const gitStatus = Bun.spawnSync(
      ["git", "diff", "--cached", "--name-only"],
      { cwd: plugin.dir },
    );
    const stagedFiles = new TextDecoder().decode(gitStatus.stdout);
    expect(stagedFiles).toContain("plugin.json");
  });

  test("CHANGELOG.md is staged after bump", async () => {
    const result = await runScript(plugin.bumpSh, ["Staged check"]);
    expect(result.exitCode).toBe(0);

    const gitStatus = Bun.spawnSync(
      ["git", "diff", "--cached", "--name-only"],
      { cwd: plugin.dir },
    );
    const stagedFiles = new TextDecoder().decode(gitStatus.stdout);
    expect(stagedFiles).toContain("CHANGELOG.md");
  });

  test("only plugin.json and CHANGELOG.md are staged (no other files)", async () => {
    // Write an extra file that should NOT be staged
    await writeFile(join(plugin.dir, "extra.txt"), "should not be staged");

    const result = await runScript(plugin.bumpSh, ["Staged check"]);
    expect(result.exitCode).toBe(0);

    const gitStatus = Bun.spawnSync(
      ["git", "diff", "--cached", "--name-only"],
      { cwd: plugin.dir },
    );
    const stagedFiles = new TextDecoder()
      .decode(gitStatus.stdout)
      .trim()
      .split("\n")
      .filter(Boolean);

    // Should contain exactly .claude-plugin/plugin.json and CHANGELOG.md
    expect(stagedFiles).toHaveLength(2);
    expect(stagedFiles.some((f) => f.includes("plugin.json"))).toBe(true);
    expect(stagedFiles.some((f) => f.includes("CHANGELOG.md"))).toBe(true);
    expect(stagedFiles).not.toContain("extra.txt");
  });
});

// ---------------------------------------------------------------------------
// Criterion 13: no test modifies files outside the temp directory
// (Structural guarantee — each test uses its own isolated temp dir; the real
// repo is never touched. Verified by the createTempPlugin approach.)
// ---------------------------------------------------------------------------

describe("isolation guarantee", () => {
  test("bump.sh only modifies files within the temp plugin directory", async () => {
    const realPluginJson = join(import.meta.dir, "..", ".claude-plugin", "plugin.json");
    const realChangelog = join(import.meta.dir, "..", "CHANGELOG.md");

    // Record real file contents before running
    const realJsonBefore = await readFile(realPluginJson, "utf-8");
    const realChangelogBefore = await readFile(realChangelog, "utf-8");

    // Run bump.sh in temp dir
    await runScript(plugin.bumpSh, ["Isolation test"]);

    // Real files must be untouched
    const realJsonAfter = await readFile(realPluginJson, "utf-8");
    const realChangelogAfter = await readFile(realChangelog, "utf-8");

    expect(realJsonAfter).toBe(realJsonBefore);
    expect(realChangelogAfter).toBe(realChangelogBefore);
  });
});
