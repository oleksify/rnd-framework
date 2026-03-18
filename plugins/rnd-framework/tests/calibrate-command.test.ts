// Tests for T3: /rnd-framework:calibrate command
import { describe, test, expect } from "bun:test";
import { readFile } from "node:fs/promises";
import { join } from "node:path";

const COMMANDS_DIR = join(import.meta.dir, "..", "commands");

const readCmd = () => readFile(join(COMMANDS_DIR, "calibrate.md"), "utf-8");

const fm = (c: string) => c.match(/^---\n([\s\S]*?)\n---/)![1];

const body = (c: string) => c.replace(/^---\n[\s\S]*?\n---\n/, "");

describe("T3: calibrate.md body", () => {
  test("instructs reading verdict from verifications/ path", async () => {
    const b = body(await readCmd());
    expect(b).toMatch(/sessions\//);
    expect(b).toMatch(/verifications\//);
    expect(b).toMatch(/verification\.md/);
  });

  test("instructs appending to calibration.jsonl via BASE_DIR", async () => {
    const b = body(await readCmd());
    expect(b).toMatch(/calibration\.jsonl/);
    expect(b).toMatch(/BASE_DIR/);
  });

  test("references rnd-framework:rnd-calibration skill", async () => {
    expect(body(await readCmd())).toContain("rnd-framework:rnd-calibration");
  });

  test("uses rnd-dir.sh with --base flag", async () => {
    const b = body(await readCmd());
    expect(b).toContain("rnd-dir.sh");
    expect(b).toContain("--base");
  });
  test("references CLAUDE_PLUGIN_DATA as primary storage location", async () => {
    expect(body(await readCmd())).toContain("CLAUDE_PLUGIN_DATA");
  });
  test("includes fallback instructions mentioning BASE_DIR", async () => {
    expect(body(await readCmd())).toMatch(/\$BASE_DIR.*fall\s*back|fall\s*back.*\$BASE_DIR/is);
  });
});

describe("T3: calibrate.md frontmatter", () => {
  test("file exists", async () => {
    expect((await readCmd()).length).toBeGreaterThan(0);
  });

  test("has description", async () => {
    expect(fm(await readCmd())).toMatch(/^description:/m);
  });

  test("argument-hint has session-id, task-id, true-verdict", async () => {
    const hint = fm(await readCmd()).split("\n").find((l) => l.startsWith("argument-hint:")) ?? "";
    expect(hint).toMatch(/session-id/i);
    expect(hint).toMatch(/task-id/i);
    expect(hint).toMatch(/true-verdict/i);
  });
});
