/**
 * Tests for T5: maxTurns in all agent frontmatter
 *
 * Verifies each agent file contains the correct maxTurns value in its YAML
 * frontmatter block (between --- delimiters), and that the frontmatter
 * structure remains valid.
 */

import { describe, test, expect } from "bun:test";
import { readFile } from "node:fs/promises";
import { join } from "node:path";

const AGENTS = join(import.meta.dir, "..", "agents");

async function getFrontmatter(agentFile: string): Promise<string> {
  const content = await readFile(join(AGENTS, agentFile), "utf-8");
  // parts[0] is empty (before first ---), parts[1] is the frontmatter block
  const parts = content.split("---");
  return parts.length >= 2 ? parts[1] : "";
}

async function getContent(agentFile: string): Promise<string> {
  return readFile(join(AGENTS, agentFile), "utf-8");
}

async function assertDelimitersIntact(file: string): Promise<void> {
  const content = await getContent(file);
  const lines = content.split("\n");
  expect(lines[0]).toBe("---");
  const closingIdx = lines.indexOf("---", 1);
  expect(closingIdx).toBeGreaterThan(1);
}

// ---------------------------------------------------------------------------
// SC1: rnd-planner maxTurns: 250
// ---------------------------------------------------------------------------

describe("SC1: rnd-planner.md maxTurns", () => {
  test("frontmatter contains maxTurns: 250", async () => {
    const fm = await getFrontmatter("rnd-planner.md");
    expect(fm).toContain("maxTurns: 250");
  });

  test("YAML delimiters remain intact", async () => {
    await assertDelimitersIntact("rnd-planner.md");
  });
});

// ---------------------------------------------------------------------------
// SC2: rnd-builder maxTurns: 200
// ---------------------------------------------------------------------------

describe("SC2: rnd-builder.md maxTurns", () => {
  test("frontmatter contains maxTurns: 200", async () => {
    const fm = await getFrontmatter("rnd-builder.md");
    expect(fm).toContain("maxTurns: 200");
  });

  test("YAML delimiters remain intact", async () => {
    await assertDelimitersIntact("rnd-builder.md");
  });
});

// ---------------------------------------------------------------------------
// SC3: rnd-verifier maxTurns: 100
// ---------------------------------------------------------------------------

describe("SC3: rnd-verifier.md maxTurns", () => {
  test("frontmatter contains maxTurns: 100", async () => {
    const fm = await getFrontmatter("rnd-verifier.md");
    expect(fm).toContain("maxTurns: 100");
  });

  test("YAML delimiters remain intact", async () => {
    await assertDelimitersIntact("rnd-verifier.md");
  });
});

// ---------------------------------------------------------------------------
// SC4: rnd-integrator maxTurns: 150
// ---------------------------------------------------------------------------

describe("SC4: rnd-integrator.md maxTurns", () => {
  test("frontmatter contains maxTurns: 150", async () => {
    const fm = await getFrontmatter("rnd-integrator.md");
    expect(fm).toContain("maxTurns: 150");
  });

  test("YAML delimiters remain intact", async () => {
    await assertDelimitersIntact("rnd-integrator.md");
  });
});

// ---------------------------------------------------------------------------
// SC5: rnd-data-scientist maxTurns: 150
// ---------------------------------------------------------------------------

describe("SC5: rnd-data-scientist.md maxTurns", () => {
  test("frontmatter contains maxTurns: 150", async () => {
    const fm = await getFrontmatter("rnd-data-scientist.md");
    expect(fm).toContain("maxTurns: 150");
  });

  test("YAML delimiters remain intact", async () => {
    await assertDelimitersIntact("rnd-data-scientist.md");
  });
});

// ---------------------------------------------------------------------------
// SC6: rnd-proof-gate maxTurns: 100
// ---------------------------------------------------------------------------

describe("SC6: rnd-proof-gate.md maxTurns", () => {
  test("frontmatter contains maxTurns: 100", async () => {
    const fm = await getFrontmatter("rnd-proof-gate.md");
    expect(fm).toContain("maxTurns: 100");
  });

  test("YAML delimiters remain intact", async () => {
    await assertDelimitersIntact("rnd-proof-gate.md");
  });
});

// ---------------------------------------------------------------------------
// SC7: maxTurns appears in frontmatter (not body) for all agents
// ---------------------------------------------------------------------------

describe("SC7: maxTurns placement in frontmatter", () => {
  const agents = [
    "rnd-planner.md",
    "rnd-builder.md",
    "rnd-verifier.md",
    "rnd-integrator.md",
    "rnd-data-scientist.md",
    "rnd-proof-gate.md",
  ];

  for (const agent of agents) {
    test(`${agent}: maxTurns appears in frontmatter block`, async () => {
      const fm = await getFrontmatter(agent);
      expect(fm).toMatch(/maxTurns:\s*\d+/);
    });
  }
});
