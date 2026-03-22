/**
 * Tests for M2: SCAN re-anchoring in the builder skill.
 * Verifies the SCAN compliance statement step is present.
 */

import { describe, test, expect } from "bun:test";
import { readFile } from "node:fs/promises";
import { join } from "node:path";

const SKILL_PATH = join(import.meta.dir, "..", "skills", "rnd-building", "SKILL.md");

describe("SCAN re-anchoring", () => {
  test("building skill contains SCAN step", async () => {
    const content = await readFile(SKILL_PATH, "utf-8");
    expect(content).toContain("SCAN — Re-anchor before each criterion");
  });

  test("SCAN step is marked mandatory", async () => {
    const content = await readFile(SKILL_PATH, "utf-8");
    expect(content).toContain("(mandatory)");
  });

  test("SCAN step appears before RED step", async () => {
    const content = await readFile(SKILL_PATH, "utf-8");
    const scanIdx = content.indexOf("SCAN — Re-anchor");
    const redIdx = content.indexOf("RED — Write a failing test");
    expect(scanIdx).toBeGreaterThan(-1);
    expect(redIdx).toBeGreaterThan(-1);
    expect(scanIdx).toBeLessThan(redIdx);
  });

  test("SCAN step includes the compliance statement format", async () => {
    const content = await readFile(SKILL_PATH, "utf-8");
    expect(content).toContain("SCAN: Working on criterion");
  });

  test("SCAN step explains the attention decay mechanism", async () => {
    const content = await readFile(SKILL_PATH, "utf-8");
    expect(content).toContain("attention weight");
  });
});
