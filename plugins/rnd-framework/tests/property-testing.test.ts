/**
 * Tests for M3: Property-based testing guidance in the builder skill.
 */

import { describe, test, expect } from "bun:test";
import { readFile } from "node:fs/promises";
import { join } from "node:path";

const SKILL_PATH = join(import.meta.dir, "..", "skills", "rnd-building", "SKILL.md");

describe("property-based testing guidance", () => {
  test("building skill contains property-based testing section", async () => {
    const content = await readFile(SKILL_PATH, "utf-8");
    expect(content).toContain("## Property-Based Testing");
  });

  test("section explains when to use property tests", async () => {
    const content = await readFile(SKILL_PATH, "utf-8");
    expect(content).toContain("When to use property-based tests");
  });

  test("section explains when specific-output tests are better", async () => {
    const content = await readFile(SKILL_PATH, "utf-8");
    expect(content).toContain("When specific-output tests are better");
  });

  test("section appears before Common Rationalizations", async () => {
    const content = await readFile(SKILL_PATH, "utf-8");
    const propIdx = content.indexOf("## Property-Based Testing");
    const rationalIdx = content.indexOf("## Common Rationalizations");
    expect(propIdx).toBeGreaterThan(-1);
    expect(rationalIdx).toBeGreaterThan(-1);
    expect(propIdx).toBeLessThan(rationalIdx);
  });
});
