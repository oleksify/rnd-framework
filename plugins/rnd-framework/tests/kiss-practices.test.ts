/**
 * Tests for T10: ${CLAUDE_SKILL_DIR} in kiss-practices/SKILL.md
 */
import { describe, test, expect } from "bun:test";
import { readFile } from "node:fs/promises";
import { join } from "node:path";

const PLUGIN_ROOT = join(import.meta.dir, "..");
const SKILL_MD = join(PLUGIN_ROOT, "skills", "kiss-practices", "SKILL.md");
const content = await readFile(SKILL_MD, "utf-8");

const LANG_FILES = [
  "bash.md", "duckdb.md", "elixir.md",
  "javascript.md", "markdown.md", "postgresql.md", "svelte.md",
];

describe("T10: kiss-practices uses ${CLAUDE_SKILL_DIR}", () => {
  test("at least one ${CLAUDE_SKILL_DIR} reference exists", () => {
    expect(content).toContain("${CLAUDE_SKILL_DIR}");
  });

  test("How to Use references a lang file via ${CLAUDE_SKILL_DIR}", () => {
    expect(content).toMatch(/\$\{CLAUDE_SKILL_DIR\}\/\w+\.md/);
  });

  test("description does not say 'from this skill's directory'", () => {
    const fm = content.split("---")[1] ?? "";
    expect(fm).not.toContain("from this skill's directory");
  });

  for (const lang of LANG_FILES) {
    const base = lang.replace(".md", "");
    test(`detection table references ${lang} via \${CLAUDE_SKILL_DIR}`, () => {
      expect(content).toContain(`\${CLAUDE_SKILL_DIR}/${lang}`);
    });
  }
});
