/**
 * Tests for T11, T12, T13: Skill frontmatter updates
 *
 * T11: ${CLAUDE_SESSION_ID} appears in at least one skill
 * T12: context: fork in rnd-local-experts and rnd-design
 * T13: allowed-tools: [Read, Bash, Grep, Glob] in rnd-verification, no Write/Edit
 */

import { describe, test, expect } from "bun:test";
import { readFile } from "node:fs/promises";
import { join } from "node:path";

const PLUGIN_ROOT = join(import.meta.dir, "..");
const SKILLS = join(PLUGIN_ROOT, "skills");

async function readSkill(name: string): Promise<string> {
  return readFile(join(SKILLS, name, "SKILL.md"), "utf-8");
}

function frontmatter(content: string): string {
  const parts = content.split("---");
  return parts.length >= 3 ? parts[1] : "";
}

// ---------------------------------------------------------------------------
// T11: ${CLAUDE_SESSION_ID} in at least one skill
// ---------------------------------------------------------------------------

const T11_SKILLS = [
  "rnd-building", "rnd-verification", "rnd-orchestration",
  "rnd-completion", "rnd-integration", "rnd-iteration",
];

describe("T11: at least one scanned skill uses ${CLAUDE_SESSION_ID}", () => {
  test("at least one SKILL.md body contains ${CLAUDE_SESSION_ID}", async () => {
    const contents = await Promise.all(T11_SKILLS.map(readSkill));
    const any = contents.some((c) => c.includes("${CLAUDE_SESSION_ID}"));
    expect(any).toBe(true);
  });
});

describe("T11: no skill removes the rnd-dir.sh setup instruction", () => {
  for (const skill of T11_SKILLS) {
    test(`${skill} still references rnd-dir.sh`, async () => {
      const content = await readSkill(skill);
      expect(content).toContain("rnd-dir.sh");
    });
  }
});

// ---------------------------------------------------------------------------
// T12: context: fork in rnd-local-experts and rnd-design
// ---------------------------------------------------------------------------

describe("T12: rnd-local-experts has context: fork in frontmatter", () => {
  test("frontmatter contains 'context: fork'", async () => {
    const fm = frontmatter(await readSkill("rnd-local-experts"));
    expect(fm).toContain("context: fork");
  });
});

describe("T12: rnd-design has context: fork in frontmatter", () => {
  test("frontmatter contains 'context: fork'", async () => {
    const fm = frontmatter(await readSkill("rnd-design"));
    expect(fm).toContain("context: fork");
  });
});

// ---------------------------------------------------------------------------
// T13: allowed-tools in rnd-verification
// ---------------------------------------------------------------------------

describe("T13: rnd-verification has allowed-tools with Read, Bash, Grep, Glob", () => {
  test("frontmatter contains allowed-tools with all 4 tools", async () => {
    const fm = frontmatter(await readSkill("rnd-verification"));
    expect(fm).toContain("allowed-tools");
    expect(fm).toContain("Read");
    expect(fm).toContain("Bash");
    expect(fm).toContain("Grep");
    expect(fm).toContain("Glob");
  });
});

describe("T13: rnd-verification allowed-tools does NOT include Write or Edit", () => {
  test("frontmatter allowed-tools line does not contain Write or Edit", async () => {
    const fm = frontmatter(await readSkill("rnd-verification"));
    const toolsLine = fm.split("\n").find((l) => l.includes("allowed-tools")) ?? "";
    expect(toolsLine).not.toContain("Write");
    expect(toolsLine).not.toContain("Edit");
  });
});
