/**
 * Tests for M6: Criticality-based verification scaling.
 * Verifies the scaling skill contains criticality tiers.
 */

import { describe, test, expect } from "bun:test";
import { readFile } from "node:fs/promises";
import { join } from "node:path";

const SCALING_SKILL = join(import.meta.dir, "..", "skills", "rnd-scaling", "SKILL.md");

describe("criticality-based verification scaling", () => {
  test("scaling skill contains verification depth section", async () => {
    const content = await readFile(SCALING_SKILL, "utf-8");
    expect(content).toContain("## Verification Depth by Criticality");
  });

  test("defines LOW criticality tier", async () => {
    const content = await readFile(SCALING_SKILL, "utf-8");
    expect(content).toContain("### LOW criticality");
    expect(content).toContain("Single-judge verification");
  });

  test("defines MEDIUM criticality tier as default", async () => {
    const content = await readFile(SCALING_SKILL, "utf-8");
    expect(content).toContain("### MEDIUM criticality (default)");
    expect(content).toContain("2-judge consensus");
  });

  test("defines HIGH criticality tier", async () => {
    const content = await readFile(SCALING_SKILL, "utf-8");
    expect(content).toContain("### HIGH criticality");
    expect(content).toContain("Extended iteration budget");
  });

  test("explains how the Planner annotates criticality", async () => {
    const content = await readFile(SCALING_SKILL, "utf-8");
    expect(content).toContain("Criticality:");
    expect(content).toContain("orchestrator defaults to MEDIUM");
  });

  test("includes orchestrator application table", async () => {
    const content = await readFile(SCALING_SKILL, "utf-8");
    expect(content).toContain("| Criticality | Judges | Iteration budget | Proof gate |");
  });
});
