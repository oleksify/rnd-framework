// Tests for T15: model field in command frontmatter (quick.md + verify.md)
import { describe, test, expect } from "bun:test";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { readdirSync } from "node:fs";

const COMMANDS_DIR = join(import.meta.dir, "..", "commands");

function frontmatter(content: string): string {
  const match = content.match(/^---\n([\s\S]*?)\n---/);
  return match ? match[1] : "";
}

async function readCommand(name: string): Promise<string> {
  return readFile(join(COMMANDS_DIR, `${name}.md`), "utf-8");
}

describe("T15: commands/quick.md frontmatter contains model: sonnet", () => {
  test("quick.md frontmatter has 'model: sonnet'", async () => {
    const fm = frontmatter(await readCommand("quick"));
    expect(fm).toContain("model: sonnet");
  });
});

describe("T15: commands/verify.md frontmatter contains model: opus", () => {
  test("verify.md frontmatter has 'model: opus'", async () => {
    const fm = frontmatter(await readCommand("verify"));
    expect(fm).toContain("model: opus");
  });
});

describe("T15: no other command .md file has a model field", () => {
  test("only quick.md and verify.md have model in frontmatter", async () => {
    const files = readdirSync(COMMANDS_DIR).filter((f) => f.endsWith(".md"));
    const withModel: string[] = [];
    for (const file of files) {
      const content = await readFile(join(COMMANDS_DIR, file), "utf-8");
      if (frontmatter(content).includes("model:")) withModel.push(file);
    }
    withModel.sort();
    expect(withModel).toEqual(["quick.md", "verify.md"]);
  });
});
