/**
 * Tests for agents/rnd-planner.md — T6: Planner agent update
 *
 * Verifies the structural success criteria from the T6 pre-registration:
 *   SC1: Process includes writing exploration findings to $RND_DIR/exploration/
 *   SC2: Exploration output format is defined (Files Examined, Key Patterns, Relevant Dependencies, Notes for Builders)
 *   SC3: Process states the Planner creates the $RND_DIR/exploration/ directory (mkdir)
 *   SC4: Existing process steps are preserved (decomposition, pre-registration, dependency matrix)
 *   SC5: Exploration step appears before decomposition (so findings inform task breakdown)
 */

import { describe, test, expect } from "bun:test";
import { readFile } from "node:fs/promises";
import { join } from "node:path";

const PLUGIN_ROOT = join(import.meta.dir, "..");
const PLANNER_PATH = join(PLUGIN_ROOT, "agents", "rnd-planner.md");

let content: string;

// Load once — all tests share this read
const getContent = async (): Promise<string> => {
  if (!content) {
    content = await readFile(PLANNER_PATH, "utf-8");
  }
  return content;
};

// ---------------------------------------------------------------------------
// SC1: Process includes writing exploration findings to $RND_DIR/exploration/
// ---------------------------------------------------------------------------

describe("SC1: Exploration cache output path", () => {
  test("document references $RND_DIR/exploration/ as the output directory", async () => {
    const doc = await getContent();
    expect(doc).toContain("$RND_DIR/exploration/");
  });

  test("document instructs writing findings to exploration cache", async () => {
    const doc = await getContent();
    // Should mention writing/writing structured findings
    expect(doc.toLowerCase()).toContain("exploration");
    // The exploration directory path must appear in the process section
    const processSection = doc.slice(doc.indexOf("## Process"));
    expect(processSection).toContain("$RND_DIR/exploration/");
  });
});

// ---------------------------------------------------------------------------
// SC2: Exploration output format is defined
// ---------------------------------------------------------------------------

describe("SC2: Exploration output format", () => {
  test("document defines a 'Files Examined' section in the exploration format", async () => {
    const doc = await getContent();
    expect(doc).toContain("Files Examined");
  });

  test("document defines a 'Key Patterns' section in the exploration format", async () => {
    const doc = await getContent();
    expect(doc).toContain("Key Patterns");
  });

  test("document defines a 'Relevant Dependencies' section in the exploration format", async () => {
    const doc = await getContent();
    expect(doc).toContain("Relevant Dependencies");
  });

  test("document defines a 'Notes for Builders' section in the exploration format", async () => {
    const doc = await getContent();
    expect(doc).toContain("Notes for Builders");
  });
});

// ---------------------------------------------------------------------------
// SC3: Process states the Planner creates the exploration/ directory
// ---------------------------------------------------------------------------

describe("SC3: Directory creation via mkdir", () => {
  test("document includes mkdir command for creating the exploration directory", async () => {
    const doc = await getContent();
    expect(doc).toContain("mkdir");
    expect(doc).toContain("exploration");
  });

  test("mkdir command targets the $RND_DIR/exploration path", async () => {
    const doc = await getContent();
    // The mkdir line should reference $RND_DIR/exploration
    expect(doc).toMatch(/mkdir.*\$RND_DIR\/exploration/);
  });
});

// ---------------------------------------------------------------------------
// SC4: Existing process steps are preserved
// ---------------------------------------------------------------------------

describe("SC4: Existing process steps preserved", () => {
  test("decomposition step is present", async () => {
    const doc = await getContent();
    expect(doc).toContain("Decompose");
    // Both hierarchical levels and the step itself
    expect(doc).toContain("System level");
    expect(doc).toContain("Module level");
    expect(doc).toContain("Unit level");
  });

  test("pre-registration document template is present", async () => {
    const doc = await getContent();
    expect(doc).toContain("Task ID:");
    expect(doc).toContain("Success criteria:");
    expect(doc).toContain("Verification level:");
  });

  test("dependency matrix step is present", async () => {
    const doc = await getContent();
    expect(doc).toContain("dependency matrix");
  });

  test("execution waves step is present", async () => {
    const doc = await getContent();
    expect(doc).toContain("execution wave");
  });
});

// ---------------------------------------------------------------------------
// SC5: Exploration step appears before decomposition
// ---------------------------------------------------------------------------

describe("SC5: Exploration step appears before decomposition", () => {
  test("exploration cache section appears before the Decompose step in the document", async () => {
    const doc = await getContent();
    const explorationPos = doc.indexOf("$RND_DIR/exploration/");
    // Use the numbered step "2. **Decompose" to avoid matching earlier occurrences in the description/role sections
    const decomposePos = doc.indexOf("2. **Decompose");
    expect(explorationPos).toBeGreaterThan(-1);
    expect(decomposePos).toBeGreaterThan(-1);
    expect(explorationPos).toBeLessThan(decomposePos);
  });

  test("exploration step is numbered between step 1 and step 2", async () => {
    const doc = await getContent();
    const step1Pos = doc.indexOf("1. **Understand the task");
    const explorationStepPos = doc.indexOf("Write exploration cache");
    const step2Pos = doc.indexOf("2. **Decompose");
    expect(step1Pos).toBeGreaterThan(-1);
    expect(explorationStepPos).toBeGreaterThan(-1);
    expect(step2Pos).toBeGreaterThan(-1);
    expect(step1Pos).toBeLessThan(explorationStepPos);
    expect(explorationStepPos).toBeLessThan(step2Pos);
  });
});
