/**
 * Tests for rnd-verification skill — Evidence Grounding Criterion
 */

import { describe, test, expect } from "bun:test";
import { readFile } from "node:fs/promises";
import { join } from "node:path";

const PLUGIN_ROOT = join(import.meta.dir, "..");
const SKILL_PATH = join(PLUGIN_ROOT, "skills/rnd-verification/SKILL.md");

async function read(): Promise<string> {
  return readFile(SKILL_PATH, "utf-8");
}

function section(content: string, heading: string): string {
  const lines = content.split("\n");
  const start = lines.findIndex((l) => l.includes(heading));
  if (start === -1) return "";
  const end = lines.findIndex(
    (l, i) => i > start && /^#{1,4} /.test(l)
  );
  return lines.slice(start, end === -1 ? lines.length : end).join("\n");
}

// Step 5b contains "Evidence Gathered" check
describe('Step 5b "Code Inspection" contains Evidence Gathered check', () => {
  test('Step 5b contains "Evidence Gathered"', async () => {
    const s = section(await read(), "**b. Code Inspection**");
    expect(s).toContain("Evidence Gathered");
  });

  test("Step 5b check references the build manifest", async () => {
    const s = section(await read(), "**b. Code Inspection**");
    expect(s.toLowerCase()).toContain("manifest");
  });
});

// Step 5c cross-criterion sweep references "Evidence Gathered"
describe('Step 5c "Cross-Criterion Sweep" references "Evidence Gathered"', () => {
  test("Step 5c Cross-Criterion Sweep references Evidence Gathered", async () => {
    const s = section(await read(), "**c. Cross-Criterion Sweep**");
    expect(s).toContain("Evidence Gathered");
  });
});

// Ungrounded decision = Correctness-tier failure
describe("ungrounded decision is a Correctness-tier failure", () => {
  test('skill contains "ungrounded" and "Correctness" failure language', async () => {
    const content = await read();
    const lc = content.toLowerCase();
    expect(lc).toContain("ungrounded");
    const hasCorrectnessTier =
      lc.includes("correctness-tier") ||
      lc.includes("correctness tier") ||
      lc.includes("correctness failure");
    expect(hasCorrectnessTier).toBe(true);
  });
});

// 6-step structure: headings ### 1. through ### 6. must all exist
describe("6-step process structure", () => {
  test("has all 6 numbered step headings", async () => {
    const content = await read();
    for (let i = 1; i <= 6; i++) {
      expect(content).toContain(`### ${i}.`);
    }
  });

  test("does not have a 7th step", async () => {
    expect(await read()).not.toContain("### 7.");
  });
});

// Existing Step 5b checks preserved (no regressions from restructure)
describe("existing Step 5b checks preserved (no regressions)", () => {
  test("Step 5b still checks for dead code or hardcoded values", async () => {
    const s = section(await read(), "**b. Code Inspection**");
    expect(s.toLowerCase()).toMatch(/dead code|hardcoded value/);
  });

  test("Step 5b still checks for shortcuts", async () => {
    const s = section(await read(), "**b. Code Inspection**");
    expect(s.toLowerCase()).toContain("shortcut");
  });

  test("Step 5b still checks for deviation from declared approach", async () => {
    const s = section(await read(), "**b. Code Inspection**");
    expect(s.toLowerCase()).toContain("deviation");
  });

  test("Step 5b still checks for hardcoded assumptions", async () => {
    const s = section(await read(), "**b. Code Inspection**");
    expect(s.toLowerCase()).toContain("hardcoded assumption");
  });
});
