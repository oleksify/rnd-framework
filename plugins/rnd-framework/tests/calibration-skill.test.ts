/**
 * Tests for rnd-calibration skill
 */

import { describe, test, expect } from "bun:test";
import { readFile } from "node:fs/promises";
import { join } from "node:path";

const SKILL_PATH = join(import.meta.dir, "..", "skills/rnd-calibration/SKILL.md");
const read = () => readFile(SKILL_PATH, "utf-8");

const frontmatter = (c: string) => c.match(/^---\n([\s\S]*?)\n---/)![1];

describe("rnd-calibration skill file", () => {
  test("file exists and is non-empty", async () => {
    expect((await read()).length).toBeGreaterThan(0);
  });
  test("frontmatter name is rnd-calibration", async () => {
    expect(frontmatter(await read())).toMatch(/^name:\s*rnd-calibration$/m);
  });
  test("frontmatter has description field", async () => {
    expect(frontmatter(await read())).toMatch(/^description:/m);
  });
});

describe("rnd-calibration JSONL schema fields", () => {
  const REQUIRED = ["taskId", "sessionId", "verdict", "criterionResults", "iterationCount", "timestamp"];
  for (const field of REQUIRED) {
    test(`contains ${field} field`, async () => {
      expect(await read()).toContain(field);
    });
  }
});

describe("rnd-calibration storage path", () => {
  test("specifies calibration.jsonl at project base level", async () => {
    expect(await read()).toContain("calibration.jsonl");
  });
});
