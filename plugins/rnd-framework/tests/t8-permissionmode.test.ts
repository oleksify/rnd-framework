/**
 * T8: permissionMode in agent frontmatter + removal from commands
 *
 * Tests verify:
 * 1. All 5 agent .md files contain permissionMode: bypassPermissions
 * 2. No command .md contains mode: "bypassPermissions"
 * 3. start.md no longer contains the builder-specific bypass prose
 * 4. verify.md note about bypassPermissions is updated
 * 5. validate.sh passes
 */

import { describe, test, expect } from "bun:test";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

const PLUGIN_ROOT = join(import.meta.dir, "..");
const AGENTS_DIR = join(PLUGIN_ROOT, "agents");
const COMMANDS_DIR = join(PLUGIN_ROOT, "commands");

const AGENT_FILES = [
  "rnd-planner.md",
  "rnd-builder.md",
  "rnd-verifier.md",
  "rnd-integrator.md",
  "rnd-data-scientist.md",
];

describe("T8: agents have permissionMode: bypassPermissions", () => {
  for (const agentFile of AGENT_FILES) {
    test(`${agentFile} contains permissionMode: bypassPermissions`, async () => {
      const content = await readFile(join(AGENTS_DIR, agentFile), "utf-8");
      expect(content).toContain("permissionMode: bypassPermissions");
    });
  }
});

describe("T8: no command file uses mode: bypassPermissions", () => {
  const COMMAND_GLOB = join(COMMANDS_DIR, "*.md");
  test("grep for mode: bypassPermissions in commands returns no matches", async () => {
    const { readdirSync, readFileSync } = await import("node:fs");
    const files = readdirSync(COMMANDS_DIR).filter((f) => f.endsWith(".md"));
    const matches: string[] = [];
    for (const f of files) {
      const text = readFileSync(join(COMMANDS_DIR, f), "utf-8");
      if (text.includes(`mode: "bypassPermissions"`)) matches.push(f);
    }
    expect(matches).toEqual([]);
  });
});

describe("T8: start.md builder bypass prose removed", () => {
  test("start.md does not contain the old builder bypass prose", async () => {
    const content = await readFile(join(COMMANDS_DIR, "start.md"), "utf-8");
    expect(content).not.toContain(
      `Do NOT use \`mode: "bypassPermissions"\` for Builders`,
    );
  });
});

describe("T8: verify.md bypassPermissions note updated", () => {
  test("verify.md does not reference mode: bypassPermissions in note", async () => {
    const content = await readFile(join(COMMANDS_DIR, "verify.md"), "utf-8");
    expect(content).not.toContain(`mode: "bypassPermissions"`);
  });
});

describe("T8: validate.sh still passes after changes", () => {
  test("validate.sh --quiet exits 0", () => {
    const VALIDATE_SH = join(PLUGIN_ROOT, "lib", "validate.sh");
    const result = spawnSync("bash", [VALIDATE_SH, "--quiet"], { encoding: "utf-8" });
    expect(result.status).toBe(0);
  });
});
