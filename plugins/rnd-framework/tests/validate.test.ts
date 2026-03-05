/**
 * Tests for lib/validate.sh
 *
 * Two test groups:
 *   A) Smoke tests — run validate.sh against the real plugin root
 *   B) Synthetic tests — inject defects into minimal plugin structures and
 *      assert validate.sh detects them
 *
 * Each synthetic test:
 *   1. Creates a fully-valid minimal plugin tree in a temp dir
 *   2. Copies the real validate.sh into <tmp>/lib/validate.sh
 *      (so PLUGIN_ROOT resolves to <tmp>)
 *   3. Injects exactly one defect
 *   4. Runs the copied script and asserts exit 1 + specific FAIL message
 */

import { describe, test, expect, beforeEach, afterEach } from "bun:test";
import { mkdtemp, mkdir, writeFile, rm, copyFile, chmod } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";

// ---------------------------------------------------------------------------
// Paths
// ---------------------------------------------------------------------------

const PLUGIN_ROOT = join(import.meta.dir, "..");
const REAL_VALIDATE_SH = join(PLUGIN_ROOT, "lib", "validate.sh");

// ---------------------------------------------------------------------------
// RunResult interface + runScript helper
// ---------------------------------------------------------------------------

interface RunResult {
  stdout: string;
  stderr: string;
  exitCode: number;
}

async function runScript(
  scriptPath: string,
  args: string[] = [],
): Promise<RunResult> {
  const proc = Bun.spawn([scriptPath, ...args], {
    stdin: "ignore",
    stdout: "pipe",
    stderr: "pipe",
  });

  const [stdoutBuf, stderrBuf] = await Promise.all([
    Bun.readableStreamToArrayBuffer(proc.stdout),
    Bun.readableStreamToArrayBuffer(proc.stderr),
    proc.exited,
  ]);

  const dec = new TextDecoder();
  return {
    stdout: dec.decode(stdoutBuf),
    stderr: dec.decode(stderrBuf),
    exitCode: proc.exitCode ?? 0,
  };
}

// ---------------------------------------------------------------------------
// createMinimalPlugin: sets up a fully-valid baseline plugin structure
// Returns the tmpDir path and the path to the copied validate.sh
// ---------------------------------------------------------------------------

async function createMinimalPlugin(tmpDir: string): Promise<string> {
  // .claude-plugin/plugin.json
  await mkdir(join(tmpDir, ".claude-plugin"), { recursive: true });
  await writeFile(
    join(tmpDir, ".claude-plugin", "plugin.json"),
    JSON.stringify({ name: "test-plugin", description: "A test plugin", version: "1.0.0" }),
  );

  // hooks/hooks.json referencing hooks/test-hook
  await mkdir(join(tmpDir, "hooks"), { recursive: true });
  await writeFile(
    join(tmpDir, "hooks", "hooks.json"),
    JSON.stringify({
      hooks: {
        PreToolUse: [
          {
            matcher: "Bash",
            hooks: [{ type: "command", command: "'${CLAUDE_PLUGIN_ROOT}/hooks/test-hook'" }],
          },
        ],
      },
    }),
  );
  // The referenced hook script — must be executable
  const hookScript = join(tmpDir, "hooks", "test-hook");
  await writeFile(hookScript, "#!/usr/bin/env bash\nexit 0\n");
  await chmod(hookScript, 0o755);

  // skills/my-skill/SKILL.md with valid frontmatter
  await mkdir(join(tmpDir, "skills", "my-skill"), { recursive: true });
  await writeFile(
    join(tmpDir, "skills", "my-skill", "SKILL.md"),
    "---\nname: my-skill\ndescription: A test skill\n---\n\n# My Skill\n",
  );

  // agents/my-agent.md with valid frontmatter
  await mkdir(join(tmpDir, "agents"), { recursive: true });
  await writeFile(
    join(tmpDir, "agents", "my-agent.md"),
    "---\nname: my-agent\ndescription: A test agent\ntools: Read, Write\nmodel: sonnet\n---\n\n# My Agent\n",
  );

  // commands/my-command.md with valid frontmatter (no $ARGUMENTS used)
  await mkdir(join(tmpDir, "commands"), { recursive: true });
  await writeFile(
    join(tmpDir, "commands", "my-command.md"),
    "---\ndescription: A test command\n---\n\n# My Command\n",
  );

  // output-styles/my-style.md with valid frontmatter
  await mkdir(join(tmpDir, "output-styles"), { recursive: true });
  await writeFile(
    join(tmpDir, "output-styles", "my-style.md"),
    "---\nname: My Style\ndescription: A test output style\n---\n\n# My Style\n",
  );

  // lib/rnd-dir.sh and lib/bump.sh — executable stubs
  await mkdir(join(tmpDir, "lib"), { recursive: true });
  for (const libScript of ["rnd-dir.sh", "bump.sh"]) {
    const p = join(tmpDir, "lib", libScript);
    await writeFile(p, "#!/usr/bin/env bash\nexit 0\n");
    await chmod(p, 0o755);
  }

  // Copy real validate.sh into <tmp>/lib/validate.sh
  const validateDest = join(tmpDir, "lib", "validate.sh");
  await copyFile(REAL_VALIDATE_SH, validateDest);
  await chmod(validateDest, 0o755);

  return validateDest;
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

let tmpDir: string;
let validateSh: string;  // path inside tmpDir — overwritten per test

beforeEach(async () => {
  tmpDir = await mkdtemp(join(tmpdir(), "validate-test-"));
  validateSh = await createMinimalPlugin(tmpDir);
});

afterEach(async () => {
  await rm(tmpDir, { recursive: true, force: true });
});

// ===========================================================================
// A) Smoke tests — run the REAL validate.sh against the REAL plugin root
// ===========================================================================

describe("Smoke: real plugin root", () => {
  test("exits 0 and stdout contains 'All' and 'passed'", async () => {
    const result = await runScript(REAL_VALIDATE_SH);
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toContain("All");
    expect(result.stdout).toContain("passed");
  });

  test("--quiet exits 0 and stdout does NOT contain 'PASS' per-check lines but DOES contain 'Summary'", async () => {
    const result = await runScript(REAL_VALIDATE_SH, ["--quiet"]);
    expect(result.exitCode).toBe(0);
    // Per-check PASS lines are suppressed in quiet mode
    expect(result.stdout).not.toMatch(/^\s+PASS\s/m);
    // Summary table is always emitted
    expect(result.stdout).toContain("Summary");
  });
});

// ===========================================================================
// B) Synthetic tests — inject defects and assert validate.sh catches them
// ===========================================================================

// ── Manifest category ───────────────────────────────────────────────────────

describe("Synthetic: Manifest — missing plugin.json", () => {
  test("exits 1 and output contains 'FAIL' and 'plugin.json'", async () => {
    // Remove the plugin.json
    await rm(join(tmpDir, ".claude-plugin", "plugin.json"));

    const result = await runScript(validateSh);
    expect(result.exitCode).toBe(1);
    expect(result.stdout).toContain("FAIL");
    expect(result.stdout).toContain("plugin.json");
  });
});

describe("Synthetic: Manifest — invalid JSON in plugin.json", () => {
  test("exits 1 and output contains 'FAIL' and 'not valid JSON'", async () => {
    await writeFile(
      join(tmpDir, ".claude-plugin", "plugin.json"),
      "{ this is not valid json ",
    );

    const result = await runScript(validateSh);
    expect(result.exitCode).toBe(1);
    expect(result.stdout).toContain("FAIL");
    expect(result.stdout).toContain("not valid JSON");
  });
});

describe("Synthetic: Manifest — plugin.json missing 'name' field", () => {
  test("exits 1 and output contains 'FAIL' and \"missing 'name'\"", async () => {
    await writeFile(
      join(tmpDir, ".claude-plugin", "plugin.json"),
      JSON.stringify({ description: "No name here", version: "1.0.0" }),
    );

    const result = await runScript(validateSh);
    expect(result.exitCode).toBe(1);
    expect(result.stdout).toContain("FAIL");
    expect(result.stdout).toContain("missing 'name'");
  });
});

describe("Synthetic: Manifest — plugin.json with non-semver version", () => {
  test("exits 1 and output contains 'FAIL' and 'not valid semver'", async () => {
    await writeFile(
      join(tmpDir, ".claude-plugin", "plugin.json"),
      JSON.stringify({ name: "test-plugin", description: "A test plugin", version: "v1.0" }),
    );

    const result = await runScript(validateSh);
    expect(result.exitCode).toBe(1);
    expect(result.stdout).toContain("FAIL");
    expect(result.stdout).toContain("not valid semver");
  });
});

// ── Hooks category ──────────────────────────────────────────────────────────

describe("Synthetic: Hooks — hooks.json references a script that does not exist", () => {
  test("exits 1 and output contains 'FAIL' and 'not found'", async () => {
    // Point to a non-existent hook script
    await writeFile(
      join(tmpDir, "hooks", "hooks.json"),
      JSON.stringify({
        hooks: {
          PreToolUse: [
            {
              matcher: "Bash",
              hooks: [{ type: "command", command: "'${CLAUDE_PLUGIN_ROOT}/hooks/ghost-hook'" }],
            },
          ],
        },
      }),
    );

    const result = await runScript(validateSh);
    expect(result.exitCode).toBe(1);
    expect(result.stdout).toContain("FAIL");
    expect(result.stdout).toContain("not found");
  });
});

describe("Synthetic: Hooks — hook script exists but is not executable", () => {
  test("exits 1 and output contains 'FAIL' and 'not executable'", async () => {
    // Create the hook file but without execute permission
    const hookScript = join(tmpDir, "hooks", "test-hook");
    await writeFile(hookScript, "#!/usr/bin/env bash\nexit 0\n");
    await chmod(hookScript, 0o644);  // not executable

    const result = await runScript(validateSh);
    expect(result.exitCode).toBe(1);
    expect(result.stdout).toContain("FAIL");
    expect(result.stdout).toContain("not executable");
  });
});

// ── Skills category ─────────────────────────────────────────────────────────

describe("Synthetic: Skills — skill directory missing SKILL.md", () => {
  test("exits 1 and output contains 'FAIL' and 'missing SKILL.md'", async () => {
    // Create a skill dir with no SKILL.md inside
    await mkdir(join(tmpDir, "skills", "broken-skill"), { recursive: true });

    const result = await runScript(validateSh);
    expect(result.exitCode).toBe(1);
    expect(result.stdout).toContain("FAIL");
    expect(result.stdout).toContain("missing SKILL.md");
  });
});

describe("Synthetic: Skills — SKILL.md with name not matching directory", () => {
  test("exits 1 and output contains 'FAIL' and 'mismatch'", async () => {
    await writeFile(
      join(tmpDir, "skills", "my-skill", "SKILL.md"),
      "---\nname: wrong-name\ndescription: A test skill\n---\n\n# My Skill\n",
    );

    const result = await runScript(validateSh);
    expect(result.exitCode).toBe(1);
    expect(result.stdout).toContain("FAIL");
    expect(result.stdout).toContain("mismatch");
  });
});

// ── Agents category ─────────────────────────────────────────────────────────

describe("Synthetic: Agents — agent .md missing frontmatter", () => {
  test("exits 1 and output contains 'FAIL' and 'missing frontmatter'", async () => {
    await writeFile(
      join(tmpDir, "agents", "my-agent.md"),
      "# My Agent\n\nNo frontmatter at all.\n",
    );

    const result = await runScript(validateSh);
    expect(result.exitCode).toBe(1);
    expect(result.stdout).toContain("FAIL");
    expect(result.stdout).toContain("missing frontmatter");
  });
});

describe("Synthetic: Agents — agent with unknown tool in tools field", () => {
  test("exits 1 and output contains 'FAIL' and 'unknown tool'", async () => {
    await writeFile(
      join(tmpDir, "agents", "my-agent.md"),
      "---\nname: my-agent\ndescription: A test agent\ntools: Read, FakeTool\nmodel: sonnet\n---\n\n# My Agent\n",
    );

    const result = await runScript(validateSh);
    expect(result.exitCode).toBe(1);
    expect(result.stdout).toContain("FAIL");
    expect(result.stdout).toContain("unknown tool");
  });
});

describe("Synthetic: Agents — agent with unknown model", () => {
  test("exits 1 and output contains 'FAIL' and 'unknown model'", async () => {
    await writeFile(
      join(tmpDir, "agents", "my-agent.md"),
      "---\nname: my-agent\ndescription: A test agent\ntools: Read, Write\nmodel: gpt-4o\n---\n\n# My Agent\n",
    );

    const result = await runScript(validateSh);
    expect(result.exitCode).toBe(1);
    expect(result.stdout).toContain("FAIL");
    expect(result.stdout).toContain("unknown model");
  });
});

// ── Commands category ────────────────────────────────────────────────────────

describe("Synthetic: Commands — command .md missing description in frontmatter", () => {
  test("exits 1 and output contains 'FAIL' and 'missing'", async () => {
    await writeFile(
      join(tmpDir, "commands", "my-command.md"),
      "---\nargument-hint: something\n---\n\n# My Command\n\n$ARGUMENTS\n",
    );

    const result = await runScript(validateSh);
    expect(result.exitCode).toBe(1);
    expect(result.stdout).toContain("FAIL");
    expect(result.stdout).toContain("missing");
  });
});

// ── Output Styles category ───────────────────────────────────────────────────

describe("Synthetic: Output Styles — output-style .md missing name in frontmatter", () => {
  test("exits 1 and output contains 'FAIL' and \"missing 'name'\"", async () => {
    await writeFile(
      join(tmpDir, "output-styles", "my-style.md"),
      "---\ndescription: A style without a name\n---\n\n# My Style\n",
    );

    const result = await runScript(validateSh);
    expect(result.exitCode).toBe(1);
    expect(result.stdout).toContain("FAIL");
    expect(result.stdout).toContain("missing 'name'");
  });
});

// ── Lib Scripts category ─────────────────────────────────────────────────────

describe("Synthetic: Lib Scripts — rnd-dir.sh is missing", () => {
  test("exits 1 and output contains 'FAIL' and 'not found'", async () => {
    // Remove the lib/rnd-dir.sh stub
    await rm(join(tmpDir, "lib", "rnd-dir.sh"));

    const result = await runScript(validateSh);
    expect(result.exitCode).toBe(1);
    expect(result.stdout).toContain("FAIL");
    expect(result.stdout).toContain("not found");
  });
});

// ── Summary table presence ───────────────────────────────────────────────────

describe("Summary table", () => {
  test("summary table appears when all checks pass (valid plugin)", async () => {
    const result = await runScript(validateSh);
    // The minimal plugin should be valid
    expect(result.stdout).toContain("Summary");
  });

  test("summary table appears when checks fail (defective plugin)", async () => {
    // Inject a defect
    await rm(join(tmpDir, ".claude-plugin", "plugin.json"));

    const result = await runScript(validateSh);
    expect(result.exitCode).toBe(1);
    expect(result.stdout).toContain("Summary");
  });
});

// ── Quiet flag ───────────────────────────────────────────────────────────────

describe("--quiet flag with failing plugin", () => {
  test("suppresses per-check FAIL lines but still shows summary", async () => {
    // Inject a defect
    await rm(join(tmpDir, ".claude-plugin", "plugin.json"));

    const result = await runScript(validateSh, ["--quiet"]);
    expect(result.exitCode).toBe(1);
    // Per-check FAIL lines should be suppressed
    expect(result.stdout).not.toMatch(/^\s+FAIL\s/m);
    // Summary must still appear
    expect(result.stdout).toContain("Summary");
  });
});
