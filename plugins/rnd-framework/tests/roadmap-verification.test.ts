/**
 * Tests for: Roadmap mode must enforce verification for each milestone.
 *
 * Verifies that:
 * 1. roadmap.md command contains full pipeline requirement
 * 2. roadmap.md warns against re-invoking start recursively
 * 3. rnd-roadmapping skill mentions verification
 * 4. rnd-roadmapping skill warns against inline completion
 */

import { describe, test, expect } from "bun:test";
import { readFile } from "node:fs/promises";
import { join } from "node:path";

const PLUGIN_ROOT = join(import.meta.dir, "..");
const ROADMAP_CMD = join(PLUGIN_ROOT, "commands", "roadmap.md");
const ROADMAP_SKILL = join(PLUGIN_ROOT, "skills", "rnd-roadmapping", "SKILL.md");

describe("roadmap: verification enforcement", () => {
  test("roadmap command requires full pipeline for milestones", async () => {
    const content = await readFile(ROADMAP_CMD, "utf-8");
    expect(content).toContain("Plan → Build → Verify → Integrate");
  });

  test("roadmap command warns about recursive start invocation", async () => {
    const content = await readFile(ROADMAP_CMD, "utf-8");
    expect(content).toContain("do not attempt to recursively re-invoke");
  });

  test("roadmap command states verification is not optional", async () => {
    const content = await readFile(ROADMAP_CMD, "utf-8");
    expect(content).toContain("Verification is not optional");
  });
});

describe("rnd-roadmapping skill: verification guidance", () => {
  test("skill mentions verification", async () => {
    const content = await readFile(ROADMAP_SKILL, "utf-8");
    expect(content.toLowerCase()).toContain("verification");
  });

  test("skill has milestone execution section", async () => {
    const content = await readFile(ROADMAP_SKILL, "utf-8");
    expect(content).toContain("## Milestone Execution and Verification");
  });

  test("skill warns against inline completion anti-pattern", async () => {
    const content = await readFile(ROADMAP_SKILL, "utf-8");
    expect(content).toContain("Anti-pattern");
    expect(content).toContain("inline without spawning the pipeline");
  });

  test("skill requires full pipeline phases", async () => {
    const content = await readFile(ROADMAP_SKILL, "utf-8");
    expect(content).toContain("Plan → Build → Verify → Integrate");
  });
});
