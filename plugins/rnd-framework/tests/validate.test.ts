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

// ===========================================================================
// C) Synthetic tests — Content Parity
//
// Each test:
//   1. Creates both files in the parity pair with the marker present in the skill
//   2. Creates the agent file WITHOUT the marker (the defect)
//   3. Asserts exit 1, stdout contains "FAIL", stdout contains "parity"
// ===========================================================================

// ---------------------------------------------------------------------------
// Helpers for parity tests
// ---------------------------------------------------------------------------

/** Creates a valid skill SKILL.md with the given marker in the body. */
async function createSkillWithMarker(
  dir: string,
  skillDirName: string,
  marker: string,
): Promise<void> {
  await mkdir(join(dir, "skills", skillDirName), { recursive: true });
  await writeFile(
    join(dir, "skills", skillDirName, "SKILL.md"),
    `---\nname: ${skillDirName}\ndescription: A parity test skill\n---\n\n# Skill\n\n${marker}\n`,
  );
}

/** Creates a valid agent .md WITHOUT the marker (the defect). */
async function createAgentWithoutMarker(
  dir: string,
  agentFileName: string,
): Promise<void> {
  await mkdir(join(dir, "agents"), { recursive: true });
  await writeFile(
    join(dir, "agents", `${agentFileName}.md`),
    `---\nname: ${agentFileName}\ndescription: A parity test agent\ntools: Read, Write\nmodel: sonnet\n---\n\n# Agent\n\nNo marker here.\n`,
  );
}

/** Creates a valid command .md WITHOUT the marker (the defect). */
async function createCommandWithoutMarker(
  dir: string,
  commandFileName: string,
): Promise<void> {
  await mkdir(join(dir, "commands"), { recursive: true });
  await writeFile(
    join(dir, "commands", `${commandFileName}.md`),
    `---\ndescription: A parity test command\n---\n\n# Command\n\nNo marker here.\n`,
  );
}

/** Creates a valid skill SKILL.md WITHOUT the marker (the defect). */
async function createSkillWithoutMarker(
  dir: string,
  skillDirName: string,
): Promise<void> {
  await mkdir(join(dir, "skills", skillDirName), { recursive: true });
  await writeFile(
    join(dir, "skills", skillDirName, "SKILL.md"),
    `---\nname: ${skillDirName}\ndescription: A parity test skill\n---\n\n# Skill\n\nNo marker here.\n`,
  );
}

describe("Synthetic: Content Parity", () => {
  // ── 1. decomposition↔planner: "External dependencies" ───────────────────

  test("parity: 'External dependencies' missing in rnd-planner exits 1 with FAIL+parity", async () => {
    await createSkillWithMarker(tmpDir, "rnd-decomposition", "External dependencies");
    await createAgentWithoutMarker(tmpDir, "rnd-planner");

    const result = await runScript(validateSh);
    expect(result.exitCode).toBe(1);
    expect(result.stdout).toContain("FAIL");
    expect(result.stdout).toContain("parity");
  });

  // ── 2. building↔builder: "erify external dependencies" ──────────────────

  test("parity: 'erify external dependencies' missing in rnd-builder exits 1 with FAIL+parity", async () => {
    await createSkillWithMarker(tmpDir, "rnd-building", "erify external dependencies");
    await createAgentWithoutMarker(tmpDir, "rnd-builder");

    const result = await runScript(validateSh);
    expect(result.exitCode).toBe(1);
    expect(result.stdout).toContain("FAIL");
    expect(result.stdout).toContain("parity");
  });

  // ── 3. building↔builder: "Verified external assumptions" ────────────────

  test("parity: 'Verified external assumptions' missing in rnd-builder exits 1 with FAIL+parity", async () => {
    // Agent file must contain "erify external dependencies" to pass parity check #2,
    // but must NOT contain "Verified external assumptions" (marker for this check).
    // Create agent with first marker but missing this one.
    await createSkillWithMarker(tmpDir, "rnd-building", "Verified external assumptions");
    await mkdir(join(tmpDir, "agents"), { recursive: true });
    await writeFile(
      join(tmpDir, "agents", "rnd-builder.md"),
      `---\nname: rnd-builder\ndescription: A parity test agent\ntools: Read, Write\nmodel: sonnet\n---\n\n# Agent\n\nerify external dependencies\n`,
    );

    const result = await runScript(validateSh);
    expect(result.exitCode).toBe(1);
    expect(result.stdout).toContain("FAIL");
    expect(result.stdout).toContain("parity");
  });

  // ── 4. building↔builder: "Unverified external assumptions" ──────────────

  test("parity: 'Unverified external assumptions' missing in rnd-builder exits 1 with FAIL+parity", async () => {
    await createSkillWithMarker(tmpDir, "rnd-building", "Unverified external assumptions");
    await createAgentWithoutMarker(tmpDir, "rnd-builder");

    const result = await runScript(validateSh);
    expect(result.exitCode).toBe(1);
    expect(result.stdout).toContain("FAIL");
    expect(result.stdout).toContain("parity");
  });

  // ── 5. verification↔verifier: "External contract conformance" ───────────

  test("parity: 'External contract conformance' missing in rnd-verifier exits 1 with FAIL+parity", async () => {
    await createSkillWithMarker(tmpDir, "rnd-verification", "External contract conformance");
    await createAgentWithoutMarker(tmpDir, "rnd-verifier");

    const result = await runScript(validateSh);
    expect(result.exitCode).toBe(1);
    expect(result.stdout).toContain("FAIL");
    expect(result.stdout).toContain("parity");
  });

  // ── 6. verification↔verifier: "assumptions about external systems" ───────

  test("parity: 'assumptions about external systems' missing in rnd-verifier exits 1 with FAIL+parity", async () => {
    await createSkillWithMarker(tmpDir, "rnd-verification", "assumptions about external systems");
    await createAgentWithoutMarker(tmpDir, "rnd-verifier");

    const result = await runScript(validateSh);
    expect(result.exitCode).toBe(1);
    expect(result.stdout).toContain("FAIL");
    expect(result.stdout).toContain("parity");
  });

  // ── 7. verification↔verifier: "ulti-Judge" ──────────────────────────────

  test("parity: 'ulti-Judge' missing in rnd-verifier exits 1 with FAIL+parity", async () => {
    await createSkillWithMarker(tmpDir, "rnd-verification", "ulti-Judge");
    await createAgentWithoutMarker(tmpDir, "rnd-verifier");

    const result = await runScript(validateSh);
    expect(result.exitCode).toBe(1);
    expect(result.stdout).toContain("FAIL");
    expect(result.stdout).toContain("parity");
  });

  // ── 8. decomposition↔planner: "ocal expert" ─────────────────────────────

  test("parity: 'ocal expert' missing in rnd-planner exits 1 with FAIL+parity", async () => {
    await createSkillWithMarker(tmpDir, "rnd-decomposition", "ocal expert");
    await createAgentWithoutMarker(tmpDir, "rnd-planner");

    const result = await runScript(validateSh);
    expect(result.exitCode).toBe(1);
    expect(result.stdout).toContain("FAIL");
    expect(result.stdout).toContain("parity");
  });

  // ── 9. data-science↔data-scientist: "mcp__julia__julia_eval" ────────────

  test("parity: 'mcp__julia__julia_eval' missing in rnd-data-scientist exits 1 with FAIL+parity", async () => {
    await createSkillWithMarker(tmpDir, "rnd-data-science", "mcp__julia__julia_eval");
    await createAgentWithoutMarker(tmpDir, "rnd-data-scientist");

    const result = await runScript(validateSh);
    expect(result.exitCode).toBe(1);
    expect(result.stdout).toContain("FAIL");
    expect(result.stdout).toContain("parity");
  });

  // ── 10. data-science↔data-scientist: "Validate input data" ──────────────

  test("parity: 'Validate input data' missing in rnd-data-scientist exits 1 with FAIL+parity", async () => {
    await createSkillWithMarker(tmpDir, "rnd-data-science", "Validate input data");
    await createAgentWithoutMarker(tmpDir, "rnd-data-scientist");

    const result = await runScript(validateSh);
    expect(result.exitCode).toBe(1);
    expect(result.stdout).toContain("FAIL");
    expect(result.stdout).toContain("parity");
  });

  // ── 11. data-science↔data-scientist: "independent cross-check" ───────────

  test("parity: 'independent cross-check' missing in rnd-data-scientist exits 1 with FAIL+parity", async () => {
    await createSkillWithMarker(tmpDir, "rnd-data-science", "independent cross-check");
    await createAgentWithoutMarker(tmpDir, "rnd-data-scientist");

    const result = await runScript(validateSh);
    expect(result.exitCode).toBe(1);
    expect(result.stdout).toContain("FAIL");
    expect(result.stdout).toContain("parity");
  });

  // ── 12. data-science↔data-scientist: "never hardcode" ───────────────────

  test("parity: 'never hardcode' missing in rnd-data-scientist exits 1 with FAIL+parity", async () => {
    await createSkillWithMarker(tmpDir, "rnd-data-science", "never hardcode");
    await createAgentWithoutMarker(tmpDir, "rnd-data-scientist");

    const result = await runScript(validateSh);
    expect(result.exitCode).toBe(1);
    expect(result.stdout).toContain("FAIL");
    expect(result.stdout).toContain("parity");
  });

  // ── 13. data-science↔data-scientist: "read_csv" ─────────────────────────

  test("parity: 'read_csv' missing in rnd-data-scientist exits 1 with FAIL+parity", async () => {
    await createSkillWithMarker(tmpDir, "rnd-data-science", "read_csv");
    await createAgentWithoutMarker(tmpDir, "rnd-data-scientist");

    const result = await runScript(validateSh);
    expect(result.exitCode).toBe(1);
    expect(result.stdout).toContain("FAIL");
    expect(result.stdout).toContain("parity");
  });

  // ── 14. data-science↔data-scientist: "duckdb -c" ────────────────────────

  test("parity: 'duckdb -c' missing in rnd-data-scientist exits 1 with FAIL+parity", async () => {
    await createSkillWithMarker(tmpDir, "rnd-data-science", "duckdb -c");
    await createAgentWithoutMarker(tmpDir, "rnd-data-scientist");

    const result = await runScript(validateSh);
    expect(result.exitCode).toBe(1);
    expect(result.stdout).toContain("FAIL");
    expect(result.stdout).toContain("parity");
  });

  // ── 15. data-science↔data-scientist: "Tool Selection" ───────────────────

  test("parity: 'Tool Selection' missing in rnd-data-scientist exits 1 with FAIL+parity", async () => {
    await createSkillWithMarker(tmpDir, "rnd-data-science", "Tool Selection");
    await createAgentWithoutMarker(tmpDir, "rnd-data-scientist");

    const result = await runScript(validateSh);
    expect(result.exitCode).toBe(1);
    expect(result.stdout).toContain("FAIL");
    expect(result.stdout).toContain("parity");
  });

  // ── T1: multi-judge parity (skill ↔ command) ─────────────────────────────

  // ── 16. multi-judge↔verify: "judge-a.md" ────────────────────────────────

  test("parity: 'judge-a.md' missing in commands/verify.md exits 1 with FAIL+parity", async () => {
    await createSkillWithMarker(tmpDir, "rnd-multi-judge", "judge-a.md");
    await createCommandWithoutMarker(tmpDir, "verify");

    const result = await runScript(validateSh);
    expect(result.exitCode).toBe(1);
    expect(result.stdout).toContain("FAIL");
    expect(result.stdout).toContain("parity");
  });

  // ── 17. multi-judge↔verify: "judge-b.md" ────────────────────────────────

  test("parity: 'judge-b.md' missing in commands/verify.md exits 1 with FAIL+parity", async () => {
    await createSkillWithMarker(tmpDir, "rnd-multi-judge", "judge-b.md");
    await createCommandWithoutMarker(tmpDir, "verify");

    const result = await runScript(validateSh);
    expect(result.exitCode).toBe(1);
    expect(result.stdout).toContain("FAIL");
    expect(result.stdout).toContain("parity");
  });

  // ── 18. multi-judge↔verify: "tiebreaker.md" ─────────────────────────────

  test("parity: 'tiebreaker.md' missing in commands/verify.md exits 1 with FAIL+parity", async () => {
    await createSkillWithMarker(tmpDir, "rnd-multi-judge", "tiebreaker.md");
    await createCommandWithoutMarker(tmpDir, "verify");

    const result = await runScript(validateSh);
    expect(result.exitCode).toBe(1);
    expect(result.stdout).toContain("FAIL");
    expect(result.stdout).toContain("parity");
  });

  // ── 19. multi-judge↔start: "judge-a.md" ─────────────────────────────────

  test("parity: 'judge-a.md' missing in commands/start.md exits 1 with FAIL+parity", async () => {
    await createSkillWithMarker(tmpDir, "rnd-multi-judge", "judge-a.md");
    await createCommandWithoutMarker(tmpDir, "start");

    const result = await runScript(validateSh);
    expect(result.exitCode).toBe(1);
    expect(result.stdout).toContain("FAIL");
    expect(result.stdout).toContain("parity");
  });

  // ── 20. multi-judge↔start: "judge-b.md" ─────────────────────────────────

  test("parity: 'judge-b.md' missing in commands/start.md exits 1 with FAIL+parity", async () => {
    await createSkillWithMarker(tmpDir, "rnd-multi-judge", "judge-b.md");
    await createCommandWithoutMarker(tmpDir, "start");

    const result = await runScript(validateSh);
    expect(result.exitCode).toBe(1);
    expect(result.stdout).toContain("FAIL");
    expect(result.stdout).toContain("parity");
  });

  // ── 21. multi-judge↔start: "tiebreaker.md" ──────────────────────────────

  test("parity: 'tiebreaker.md' missing in commands/start.md exits 1 with FAIL+parity", async () => {
    await createSkillWithMarker(tmpDir, "rnd-multi-judge", "tiebreaker.md");
    await createCommandWithoutMarker(tmpDir, "start");

    const result = await runScript(validateSh);
    expect(result.exitCode).toBe(1);
    expect(result.stdout).toContain("FAIL");
    expect(result.stdout).toContain("parity");
  });

  // ── 22. multi-judge↔verify: "Consensus method" ──────────────────────────

  test("parity: 'Consensus method' missing in commands/verify.md exits 1 with FAIL+parity", async () => {
    await createSkillWithMarker(tmpDir, "rnd-multi-judge", "Consensus method");
    await createCommandWithoutMarker(tmpDir, "verify");

    const result = await runScript(validateSh);
    expect(result.exitCode).toBe(1);
    expect(result.stdout).toContain("FAIL");
    expect(result.stdout).toContain("parity");
  });

  // ── T2: local expert discovery parity (skill ↔ command) ──────────────────

  // ── 23. local-experts↔start: ".claude/agents/" ──────────────────────────

  test("parity: '.claude/agents/' missing in commands/start.md exits 1 with FAIL+parity", async () => {
    await createSkillWithMarker(tmpDir, "rnd-local-experts", ".claude/agents/");
    await createCommandWithoutMarker(tmpDir, "start");

    const result = await runScript(validateSh);
    expect(result.exitCode).toBe(1);
    expect(result.stdout).toContain("FAIL");
    expect(result.stdout).toContain("parity");
  });

  // ── 24. local-experts↔start: ".claude/skills/" ──────────────────────────

  test("parity: '.claude/skills/' missing in commands/start.md exits 1 with FAIL+parity", async () => {
    await createSkillWithMarker(tmpDir, "rnd-local-experts", ".claude/skills/");
    await createCommandWithoutMarker(tmpDir, "start");

    const result = await runScript(validateSh);
    expect(result.exitCode).toBe(1);
    expect(result.stdout).toContain("FAIL");
    expect(result.stdout).toContain("parity");
  });

  // ── 25. local-experts↔start: "Local Experts Discovered" ─────────────────

  test("parity: 'Local Experts Discovered' missing in commands/start.md exits 1 with FAIL+parity", async () => {
    await createSkillWithMarker(tmpDir, "rnd-local-experts", "Local Experts Discovered");
    await createCommandWithoutMarker(tmpDir, "start");

    const result = await runScript(validateSh);
    expect(result.exitCode).toBe(1);
    expect(result.stdout).toContain("FAIL");
    expect(result.stdout).toContain("parity");
  });

  // ── T3: local expert invocation parity ───────────────────────────────────

  // ── 26. local-experts↔planner: "Local Experts Discovered" ───────────────

  test("parity: 'Local Experts Discovered' missing in rnd-planner exits 1 with FAIL+parity", async () => {
    await createSkillWithMarker(tmpDir, "rnd-local-experts", "Local Experts Discovered");
    await createAgentWithoutMarker(tmpDir, "rnd-planner");

    const result = await runScript(validateSh);
    expect(result.exitCode).toBe(1);
    expect(result.stdout).toContain("FAIL");
    expect(result.stdout).toContain("parity");
  });

  // ── 27. local-experts↔rnd-decomposition: "ocal expert" (skill↔skill) ────

  test("parity: 'ocal expert' missing in skills/rnd-decomposition exits 1 with FAIL+parity", async () => {
    await createSkillWithMarker(tmpDir, "rnd-local-experts", "ocal expert");
    await createSkillWithoutMarker(tmpDir, "rnd-decomposition");

    const result = await runScript(validateSh);
    expect(result.exitCode).toBe(1);
    expect(result.stdout).toContain("FAIL");
    expect(result.stdout).toContain("parity");
  });
});
