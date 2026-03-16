/**
 * Tests for rnd-experiments skill
 */

import { describe, test, expect } from "bun:test";
import { readFile } from "node:fs/promises";
import { join } from "node:path";

const SKILL_PATH = join(import.meta.dir, "..", "skills/rnd-experiments/SKILL.md");
const read = () => readFile(SKILL_PATH, "utf-8");

const frontmatter = (c: string) => c.match(/^---\n([\s\S]*?)\n---/)![1];

describe("rnd-experiments skill file", () => {
  test("file exists and is non-empty", async () => {
    expect((await read()).length).toBeGreaterThan(0);
  });
  test("frontmatter name is rnd-experiments", async () => {
    expect(frontmatter(await read())).toMatch(/^name:\s*rnd-experiments$/m);
  });
  test("frontmatter has description field", async () => {
    expect(frontmatter(await read())).toMatch(/^description:/m);
  });
});

describe("rnd-experiments output directory", () => {
  test("specifies $RND_DIR/verifications/T<id>-experiments/", async () => {
    expect(await read()).toContain("$RND_DIR/verifications/T<id>-experiments/");
  });
});

describe("rnd-experiments mandatory language", () => {
  test("states experiments are mandatory for every criterion", async () => {
    const c = (await read()).toUpperCase();
    expect(
      c.includes("MANDATORY FOR EVERY CRITERION") ||
        c.includes("EXPERIMENTS ARE MANDATORY"),
    ).toBe(true);
  });
  test("states experiments are not on-demand or optional", async () => {
    expect(await read()).toMatch(/not on.demand|not optional/i);
  });
});
