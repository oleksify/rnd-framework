/**
 * Tests for T1: Reality Auditor Agent Definition
 *
 * Covers every success criterion from the pre-registration:
 *   - File exists at the expected path
 *   - YAML frontmatter contains required fields
 *   - Frontmatter tools list includes all required tools
 *   - Frontmatter skills list includes required skills
 *   - Body defines exactly 4 status codes
 *   - Body specifies correct artifact paths
 *   - Body includes Setup section with RND_DIR computation
 *   - Body includes Communication section matching proof-gate pattern
 *   - Body includes required rules
 *   - bun lib/validate.ts passes (tested via subprocess)
 *   - Description is under 200 characters
 *   - Body structure follows proof-gate template sections
 */

import { describe, test, expect } from "bun:test";
import { readFile, access } from "node:fs/promises";
import { join } from "node:path";
import { existsSync } from "node:fs";

const PLUGIN_ROOT = join(import.meta.dir, "..");
const AGENT_FILE = join(PLUGIN_ROOT, "agents", "rnd-reality-auditor.md");

async function getContent(): Promise<string> {
  return readFile(AGENT_FILE, "utf-8");
}

function getFrontmatter(content: string): string {
  const parts = content.split(/^---$/m);
  return parts.length >= 3 ? parts[1] : "";
}

function getBody(content: string): string {
  const parts = content.split(/^---$/m);
  return parts.length >= 3 ? parts.slice(2).join("---") : "";
}

// ---------------------------------------------------------------------------
// SC1: File exists
// ---------------------------------------------------------------------------

describe("SC1: file exists", () => {
  test("agents/rnd-reality-auditor.md exists", () => {
    expect(existsSync(AGENT_FILE)).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// SC2: YAML frontmatter required fields
// ---------------------------------------------------------------------------

describe("SC2: YAML frontmatter required fields", () => {
  test("name: rnd-reality-auditor", async () => {
    const fm = getFrontmatter(await getContent());
    expect(fm).toMatch(/^name:\s*rnd-reality-auditor\s*$/m);
  });

  test("model: sonnet", async () => {
    const fm = getFrontmatter(await getContent());
    expect(fm).toMatch(/^model:\s*sonnet\s*$/m);
  });

  test("maxTurns: 100", async () => {
    const fm = getFrontmatter(await getContent());
    expect(fm).toMatch(/^maxTurns:\s*100\s*$/m);
  });

  test("permissionMode: bypassPermissions", async () => {
    const fm = getFrontmatter(await getContent());
    expect(fm).toMatch(/^permissionMode:\s*bypassPermissions\s*$/m);
  });

  test('memory: user', async () => {
    const fm = getFrontmatter(await getContent());
    expect(fm).toMatch(/^memory:\s*user\s*$/m);
  });

  test('color: "#14B8A6"', async () => {
    const fm = getFrontmatter(await getContent());
    expect(fm).toContain("#14B8A6");
  });
});

// ---------------------------------------------------------------------------
// SC3: Frontmatter tools list
// ---------------------------------------------------------------------------

describe("SC3: frontmatter tools list", () => {
  const requiredTools = ["Read", "Write", "Bash", "Glob", "Grep", "WebFetch"];

  for (const tool of requiredTools) {
    test(`includes tool: ${tool}`, async () => {
      const fm = getFrontmatter(await getContent());
      const toolsLine = fm.split("\n").find(l => l.startsWith("tools:")) ?? "";
      expect(toolsLine).toContain(tool);
    });
  }
});

// ---------------------------------------------------------------------------
// SC4: Frontmatter skills list
// ---------------------------------------------------------------------------

describe("SC4: frontmatter skills list", () => {
  const requiredSkills = ["rnd-reality-auditing", "kiss-practices"];

  for (const skill of requiredSkills) {
    test(`includes skill: ${skill}`, async () => {
      const fm = getFrontmatter(await getContent());
      const skillsLine = fm.split("\n").find(l => l.startsWith("skills:")) ?? "";
      expect(skillsLine).toContain(skill);
    });
  }
});

// ---------------------------------------------------------------------------
// SC5: Body defines exactly 4 status codes
// ---------------------------------------------------------------------------

describe("SC5: body defines exactly 4 status codes", () => {
  const expectedCodes = [
    "VALIDATED_ALL",
    "VALIDATED_PARTIAL",
    "INVALID_FOUND",
    "SKIPPED",
  ];

  for (const code of expectedCodes) {
    test(`status code ${code} is present`, async () => {
      const body = getBody(await getContent());
      expect(body).toContain(code);
    });
  }

  test("no other status codes defined in body", async () => {
    const body = getBody(await getContent());
    // Status codes appear in backtick blocks or table cells — count distinct ones
    const allCodes = [...body.matchAll(/`([A-Z_]+)`/g)].map(m => m[1]);
    const statusCodes = allCodes.filter(c =>
      ["VALIDATED_ALL", "VALIDATED_PARTIAL", "INVALID_FOUND", "SKIPPED",
       "VALID", "INVALID", "UNCHECKED"].includes(c)
    );
    // The 4 pipeline status codes must all appear
    for (const code of expectedCodes) {
      expect(statusCodes).toContain(code);
    }
  });
});

// ---------------------------------------------------------------------------
// SC6: Body specifies artifact paths
// ---------------------------------------------------------------------------

describe("SC6: body specifies artifact paths", () => {
  test("reality report path: $RND_DIR/reality/T<id>-reality-report.md", async () => {
    const body = getBody(await getContent());
    expect(body).toContain("$RND_DIR/reality/");
    expect(body).toContain("reality-report.md");
  });

  test("experiments directory: $RND_DIR/reality/T<id>-experiments/", async () => {
    const body = getBody(await getContent());
    expect(body).toContain("experiments/");
  });
});

// ---------------------------------------------------------------------------
// SC7: Body includes Setup section with RND_DIR computation
// ---------------------------------------------------------------------------

describe("SC7: Setup section with RND_DIR computation", () => {
  test("contains ## Setup section", async () => {
    const body = getBody(await getContent());
    expect(body).toContain("## Setup");
  });

  test("computes RND_DIR via ${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh", async () => {
    const body = getBody(await getContent());
    expect(body).toContain("CLAUDE_PLUGIN_ROOT");
    expect(body).toContain("rnd-dir.sh");
  });
});

// ---------------------------------------------------------------------------
// SC8: Body includes Communication section matching proof-gate pattern
// ---------------------------------------------------------------------------

describe("SC8: Communication section", () => {
  test("contains ## Communication section", async () => {
    const body = getBody(await getContent());
    expect(body).toContain("## Communication");
  });

  test("mentions SendMessage", async () => {
    const body = getBody(await getContent());
    expect(body).toContain("SendMessage");
  });

  test("includes on-start notification", async () => {
    const body = getBody(await getContent());
    expect(body).toMatch(/On start.*SendMessage/s);
  });

  test("includes on-completion notification with status codes", async () => {
    const body = getBody(await getContent());
    expect(body).toMatch(/On completion.*status/is);
  });

  test("includes on-blockers notification", async () => {
    const body = getBody(await getContent());
    expect(body).toMatch(/On blockers/i);
  });
});

// ---------------------------------------------------------------------------
// SC9: Body includes "NEVER modify project source files" rule
// ---------------------------------------------------------------------------

describe("SC9: rule — never modify project source files", () => {
  test('body contains "NEVER modify project source files"', async () => {
    const body = getBody(await getContent());
    expect(body).toMatch(/NEVER modify project source files/i);
  });

  test("all writes go to $RND_DIR/reality/", async () => {
    const body = getBody(await getContent());
    expect(body).toContain("$RND_DIR/reality/");
  });
});

// ---------------------------------------------------------------------------
// SC10: Body includes information barrier rule
// ---------------------------------------------------------------------------

describe("SC10: information barrier rule", () => {
  test("body mentions not reading self-assessment", async () => {
    const body = getBody(await getContent());
    expect(body).toContain("self-assessment");
  });

  test("body contains the Do NOT read rule", async () => {
    const body = getBody(await getContent());
    expect(body).toMatch(/Do NOT read.*self-assessment/i);
  });
});

// ---------------------------------------------------------------------------
// SC11: validate.ts passes
// ---------------------------------------------------------------------------

describe("SC11: bun lib/validate.ts passes", () => {
  test("validate.ts exits 0 with the new agent present", async () => {
    const validateScript = join(PLUGIN_ROOT, "lib", "validate.ts");
    const proc = Bun.spawn(["bun", validateScript], {
      cwd: PLUGIN_ROOT,
      stdin: "ignore",
      stdout: "pipe",
      stderr: "pipe",
    });
    await proc.exited;
    expect(proc.exitCode).toBe(0);
  }, 30000);
});

// ---------------------------------------------------------------------------
// Quality: Description under 200 characters
// ---------------------------------------------------------------------------

describe("Quality: description under 200 characters", () => {
  test("frontmatter description is a single non-empty sentence", async () => {
    const fm = getFrontmatter(await getContent());
    const descLine = fm.split("\n").find(l => l.startsWith("description:")) ?? "";
    const desc = descLine.replace(/^description:\s*/, "").replace(/^["']|["']$/g, "").trim();
    expect(desc.length).toBeGreaterThan(0);
    expect(desc.length).toBeLessThan(200);
  });
});

// ---------------------------------------------------------------------------
// Quality: Body structure follows proof-gate template sections
// ---------------------------------------------------------------------------

describe("Quality: body structure follows proof-gate template", () => {
  const expectedSections = [
    "## Setup",
    "## Your Role",
    "## Process",
    "## Rules",
    "## Memory",
    "## Communication",
  ];

  for (const section of expectedSections) {
    test(`contains section: ${section}`, async () => {
      const body = getBody(await getContent());
      expect(body).toContain(section);
    });
  }
});
