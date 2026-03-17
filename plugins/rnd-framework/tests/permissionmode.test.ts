/**
 * T8: permissionMode in agent frontmatter + removal from commands
 *
 * Tests verify:
 * 1. 5 non-builder agents contain permissionMode: bypassPermissions
 * 2. rnd-builder.md does NOT contain permissionMode (chunk-gate must apply)
 * 3. No command .md contains mode: "bypassPermissions"
 * 4. start.md no longer contains the builder-specific bypass prose
 * 5. verify.md note about bypassPermissions is updated
 * 6. validate.ts passes
 */

import { describe, test, expect } from "bun:test";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

const PLUGIN_ROOT = join(import.meta.dir, "..");
const AGENTS_DIR = join(PLUGIN_ROOT, "agents");
const COMMANDS_DIR = join(PLUGIN_ROOT, "commands");

const NON_BUILDER_AGENTS = [
  "rnd-planner.md",
  "rnd-verifier.md",
  "rnd-integrator.md",
  "rnd-data-scientist.md",
  "rnd-proof-gate.md",
];

describe("T8: non-builder agents have permissionMode: bypassPermissions", () => {
  for (const agentFile of NON_BUILDER_AGENTS) {
    test(`${agentFile} contains permissionMode: bypassPermissions`, async () => {
      const content = await readFile(join(AGENTS_DIR, agentFile), "utf-8");
      expect(content).toContain("permissionMode: bypassPermissions");
    });
  }
});

describe("T8: rnd-builder does NOT have permissionMode (chunk-gate enforcement)", () => {
  test("rnd-builder.md does not contain permissionMode: bypassPermissions", async () => {
    const content = await readFile(join(AGENTS_DIR, "rnd-builder.md"), "utf-8");
    expect(content).not.toContain("permissionMode: bypassPermissions");
  });
  test("rnd-builder.md does not contain permissionMode at all", async () => {
    const content = await readFile(join(AGENTS_DIR, "rnd-builder.md"), "utf-8");
    expect(content).not.toContain("permissionMode");
  });
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

describe("T8: validate.ts still passes after changes", () => {
  test("validate.ts --quiet exits 0", () => {
    const VALIDATE_TS = join(PLUGIN_ROOT, "lib", "validate.ts");
    const result = spawnSync("bun", [VALIDATE_TS, "--quiet"], { encoding: "utf-8" });
    expect(result.status).toBe(0);
  });
});
