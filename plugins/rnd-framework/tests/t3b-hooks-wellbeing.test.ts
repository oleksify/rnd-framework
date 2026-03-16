/** Tests for T3b: wellbeing-check registered in hooks.json PostToolUse */
import { describe, test, expect } from "bun:test";
import { readFile } from "node:fs/promises";
import { join } from "node:path";

const PLUGIN_ROOT = join(import.meta.dir, "..");
const HOOKS_JSON_PATH = join(PLUGIN_ROOT, "hooks", "hooks.json");
const WELLBEING_CMD = "'${CLAUDE_PLUGIN_ROOT}/hooks/wellbeing-check'";
const EVIDENCE_WARN_CMD = "'${CLAUDE_PLUGIN_ROOT}/hooks/evidence-warn'";

async function loadHooks() {
  const content = await readFile(HOOKS_JSON_PATH, "utf-8");
  return JSON.parse(content);
}

describe("T3b: hooks.json is valid JSON", () => {
  test("file parses without throwing", async () => {
    const content = await readFile(HOOKS_JSON_PATH, "utf-8");
    expect(() => JSON.parse(content)).not.toThrow();
  });
});

describe("T3b: PostToolUse Write array contains wellbeing-check", () => {
  test("Write hooks include wellbeing-check command entry", async () => {
    const hooks = await loadHooks();
    const writeBlock = hooks.hooks.PostToolUse.find(
      (b: { matcher?: string }) => b.matcher === "Write",
    );
    const commands = writeBlock.hooks.map((h: { command: string }) => h.command);
    expect(commands).toContain(WELLBEING_CMD);
  });

  test("wellbeing-check appears after evidence-warn in Write array", async () => {
    const hooks = await loadHooks();
    const writeBlock = hooks.hooks.PostToolUse.find(
      (b: { matcher?: string }) => b.matcher === "Write",
    );
    const commands = writeBlock.hooks.map((h: { command: string }) => h.command);
    expect(commands.indexOf(WELLBEING_CMD)).toBeGreaterThan(
      commands.indexOf(EVIDENCE_WARN_CMD),
    );
  });
});

describe("T3b: PostToolUse Edit array contains wellbeing-check", () => {
  test("Edit hooks include wellbeing-check command entry", async () => {
    const hooks = await loadHooks();
    const editBlock = hooks.hooks.PostToolUse.find(
      (b: { matcher?: string }) => b.matcher === "Edit",
    );
    const commands = editBlock.hooks.map((h: { command: string }) => h.command);
    expect(commands).toContain(WELLBEING_CMD);
  });

  test("wellbeing-check appears after evidence-warn in Edit array", async () => {
    const hooks = await loadHooks();
    const editBlock = hooks.hooks.PostToolUse.find(
      (b: { matcher?: string }) => b.matcher === "Edit",
    );
    const commands = editBlock.hooks.map((h: { command: string }) => h.command);
    expect(commands.indexOf(WELLBEING_CMD)).toBeGreaterThan(
      commands.indexOf(EVIDENCE_WARN_CMD),
    );
  });
});
