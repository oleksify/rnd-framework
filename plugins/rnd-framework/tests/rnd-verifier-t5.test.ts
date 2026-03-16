/**
 * Tests for agents/rnd-verifier.md
 *
 * Verifies the verifier agent definition after updating for Write access,
 * new skills, and the 6-step verification process.
 */

import { describe, test, expect } from "bun:test";
import { readFile } from "node:fs/promises";
import { join } from "node:path";

const PLUGIN_ROOT = join(import.meta.dir, "..");
const VERIFIER_PATH = join(PLUGIN_ROOT, "agents", "rnd-verifier.md");

let content: string;

const getContent = async (): Promise<string> => {
  if (!content) {
    content = await readFile(VERIFIER_PATH, "utf-8");
  }
  return content;
};

// Extract frontmatter block (between first --- and second ---)
const getFrontmatter = async (): Promise<string> => {
  const doc = await getContent();
  const match = doc.match(/^---\n([\s\S]*?)\n---/);
  return match ? match[1] : "";
};

const getFrontmatterLine = async (key: string): Promise<string> => {
  const fm = await getFrontmatter();
  return fm.split("\n").find((l) => l.startsWith(`${key}:`)) ?? "";
};

describe("SC1: disallowedTools contains only Edit", () => {
  test("disallowedTools does not include Write", async () => {
    const line = await getFrontmatterLine("disallowedTools");
    expect(line).not.toContain("Write");
  });

  test("disallowedTools includes Edit", async () => {
    const line = await getFrontmatterLine("disallowedTools");
    expect(line).toContain("Edit");
  });
});

describe("SC2: tools field includes Write", () => {
  test("tools field contains Write", async () => {
    const line = await getFrontmatterLine("tools");
    expect(line).toContain("Write");
  });
});

describe("SC3: skills field includes new skills", () => {
  test("skills includes rnd-experiments", async () => {
    const line = await getFrontmatterLine("skills");
    expect(line).toContain("rnd-experiments");
  });

  test("skills does not include rnd-calibration (orchestrator responsibility)", async () => {
    const line = await getFrontmatterLine("skills");
    expect(line).not.toContain("rnd-calibration");
  });

  test("skills retains rnd-verification", async () => {
    const line = await getFrontmatterLine("skills");
    expect(line).toContain("rnd-verification");
  });
});

describe("SC4: Process section has 6 numbered steps", () => {
  test("Process section contains step 6", async () => {
    const doc = await getContent();
    const processSection = doc.slice(doc.indexOf("## Process"));
    expect(processSection).toMatch(/^6\./m);
  });

  test("Process section does not have step 7", async () => {
    const doc = await getContent();
    const processSection = doc.slice(doc.indexOf("## Process"));
    expect(processSection).not.toMatch(/^7\./m);
  });
});

describe("SC5: Rules permits experiment writes to $RND_DIR", () => {
  test("Rules mentions writing experiment files to $RND_DIR", async () => {
    const doc = await getContent();
    const rulesSection = doc.slice(doc.indexOf("## Rules"));
    expect(rulesSection).toContain("$RND_DIR");
  });

  test("Rules still prohibits writing project files", async () => {
    const doc = await getContent();
    const rulesSection = doc.slice(doc.indexOf("## Rules"));
    expect(rulesSection.toLowerCase()).toMatch(/project files?/);
  });
});

describe("SC6: Required Skills lists rnd-experiments", () => {
  test("Required Skills section contains rnd-experiments", async () => {
    const doc = await getContent();
    const reqSection = doc.slice(doc.indexOf("## Required Skills"));
    expect(reqSection).toContain("rnd-experiments");
  });

  test("Required Skills section does not contain rnd-calibration", async () => {
    const doc = await getContent();
    const reqSection = doc.slice(doc.indexOf("## Required Skills"));
    expect(reqSection).not.toContain("rnd-calibration");
  });
});

describe("SC7: Information Barrier section unchanged", () => {
  test("Information Barrier section is present", async () => {
    const doc = await getContent();
    expect(doc).toContain("## CRITICAL: Information Barrier");
  });

  test("Information Barrier contains self-assessment prohibition", async () => {
    const doc = await getContent();
    const barrierSection = doc.slice(
      doc.indexOf("## CRITICAL: Information Barrier"),
      doc.indexOf("## Startup Self-Check")
    );
    expect(barrierSection).toContain("self-assessment");
  });
});

describe("SC8 & SC9: Startup Self-Check and Memory sections unchanged", () => {
  test("Startup Self-Check section is present", async () => {
    const doc = await getContent();
    expect(doc).toContain("## Startup Self-Check");
  });

  test("Memory section is present", async () => {
    const doc = await getContent();
    expect(doc).toContain("## Memory");
  });
});
