/**
 * Tests for M1: Release automation in Phase 6 menu.
 *
 * Verifies that start.md, quick.md, and rnd-completion/SKILL.md
 * all include the version bump option.
 */

import { describe, test, expect } from "bun:test";
import { readFile } from "node:fs/promises";
import { join } from "node:path";

const PLUGIN_ROOT = join(import.meta.dir, "..");
const START_MD = join(PLUGIN_ROOT, "commands", "start.md");
const QUICK_MD = join(PLUGIN_ROOT, "commands", "quick.md");
const COMPLETION_SKILL = join(PLUGIN_ROOT, "skills", "rnd-completion", "SKILL.md");

describe("release automation: start.md", () => {
  test("Phase 6 menu includes bump option", async () => {
    const content = await readFile(START_MD, "utf-8");
    expect(content).toContain("Bump version, tag and push");
  });

  test("bump option references /rnd-framework:bump", async () => {
    const content = await readFile(START_MD, "utf-8");
    expect(content).toContain("/rnd-framework:bump");
  });

  test("bump option appears after commit option", async () => {
    const content = await readFile(START_MD, "utf-8");
    const commitIdx = content.indexOf('"Commit changes (Recommended)"');
    const bumpIdx = content.indexOf('"Bump version, tag and push"');
    expect(commitIdx).toBeGreaterThan(-1);
    expect(bumpIdx).toBeGreaterThan(-1);
    expect(bumpIdx).toBeGreaterThan(commitIdx);
  });
});

describe("release automation: quick.md", () => {
  test("PASS menu includes bump option", async () => {
    const content = await readFile(QUICK_MD, "utf-8");
    expect(content).toContain("Bump version, tag and push");
  });

  test("bump option references /rnd-framework:bump", async () => {
    const content = await readFile(QUICK_MD, "utf-8");
    expect(content).toContain("/rnd-framework:bump");
  });
});

describe("release automation: rnd-completion skill", () => {
  test("includes version bump step", async () => {
    const content = await readFile(COMPLETION_SKILL, "utf-8");
    expect(content).toContain("Version Bump");
  });

  test("version bump step references /rnd-framework:bump", async () => {
    const content = await readFile(COMPLETION_SKILL, "utf-8");
    expect(content).toContain("/rnd-framework:bump");
  });

  test("version bump step appears between commit and branch management", async () => {
    const content = await readFile(COMPLETION_SKILL, "utf-8");
    const commitIdx = content.indexOf("Create Final Commit");
    const bumpIdx = content.indexOf("Version Bump");
    const branchIdx = content.indexOf("Branch Management");
    expect(commitIdx).toBeGreaterThan(-1);
    expect(bumpIdx).toBeGreaterThan(-1);
    expect(branchIdx).toBeGreaterThan(-1);
    expect(bumpIdx).toBeGreaterThan(commitIdx);
    expect(bumpIdx).toBeLessThan(branchIdx);
  });

  test("version bump offers AskUserQuestion options", async () => {
    const content = await readFile(COMPLETION_SKILL, "utf-8");
    expect(content).toContain("Bump, tag and push");
    expect(content).toContain("Skip versioning");
  });
});
