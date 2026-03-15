/**
 * Tests for T3: Verification Skill — Add Evidence Grounding Criterion
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

// Criterion 1: Step 3d contains "Evidence Gathered" check
describe('T3-C1: Step 3d "Code Inspection" contains Evidence Gathered check', () => {
  test('Step 3d contains "Evidence Gathered"', async () => {
    const s = section(await read(), "**d. Code Inspection**");
    expect(s).toContain("Evidence Gathered");
  });

  test("Step 3d check references the build manifest", async () => {
    const s = section(await read(), "**d. Code Inspection**");
    expect(s.toLowerCase()).toContain("manifest");
  });
});

// Criterion 2: Step 3.5 point 4 references "Evidence Gathered"
describe('T3-C2: Step 3.5 point 4 references "Evidence Gathered"', () => {
  test("Step 3.5 Cross-Criterion Sweep references Evidence Gathered", async () => {
    const s = section(await read(), "### 3.5.");
    expect(s).toContain("Evidence Gathered");
  });
});

// Criterion 3: Ungrounded decision = Correctness-tier failure
describe("T3-C3: ungrounded decision is a Correctness-tier failure", () => {
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

// Criterion 4: Existing Step 3d checks preserved
describe("T3-C4: existing Step 3d checks preserved (no regressions)", () => {
  test("Step 3d still checks for dead code or hardcoded values", async () => {
    const s = section(await read(), "**d. Code Inspection**");
    expect(s.toLowerCase()).toMatch(/dead code|hardcoded value/);
  });

  test("Step 3d still checks for shortcuts", async () => {
    const s = section(await read(), "**d. Code Inspection**");
    expect(s.toLowerCase()).toContain("shortcut");
  });

  test("Step 3d still checks for deviation from declared approach", async () => {
    const s = section(await read(), "**d. Code Inspection**");
    expect(s.toLowerCase()).toContain("deviation");
  });

  test("Step 3d still checks for hardcoded assumptions", async () => {
    const s = section(await read(), "**d. Code Inspection**");
    expect(s.toLowerCase()).toContain("hardcoded assumption");
  });
});
