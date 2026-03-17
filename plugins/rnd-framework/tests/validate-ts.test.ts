/**
 * Tests for lib/validate.ts
 *
 * Imports validate.ts directly to verify exported functions.
 */

import { describe, test, expect } from "bun:test";
import { join } from "node:path";
import { readFileSync, statSync } from "node:fs";
import {
  validate,
  frontmatterVal,
  VALID_TOOLS,
  VALID_MODELS,
  PARITY_TABLE,
  CategoryTracker,
} from "../lib/validate.ts";

const PLUGIN_ROOT = join(import.meta.dir, "..");
const VALIDATE_TS = join(PLUGIN_ROOT, "lib", "validate.ts");

// --- File attributes ---

describe("validate.ts: file attributes", () => {
  test("has #!/usr/bin/env bun shebang on first line", () => {
    const first = readFileSync(VALIDATE_TS, "utf8").split("\n")[0];
    expect(first).toBe("#!/usr/bin/env bun");
  });

  test("is executable (mode & 0o111 !== 0)", () => {
    expect(statSync(VALIDATE_TS).mode & 0o111).not.toBe(0);
  });
});

// --- Exported symbols ---

describe("validate.ts: exports", () => {
  test("validate is a function", () => { expect(typeof validate).toBe("function"); });
  test("frontmatterVal is a function", () => { expect(typeof frontmatterVal).toBe("function"); });
  test("VALID_TOOLS is a Set", () => { expect(VALID_TOOLS instanceof Set).toBe(true); });
  test("VALID_MODELS is a Set", () => { expect(VALID_MODELS instanceof Set).toBe(true); });
  test("PARITY_TABLE is an Array", () => { expect(Array.isArray(PARITY_TABLE)).toBe(true); });
  test("CategoryTracker is a class", () => { expect(typeof CategoryTracker).toBe("function"); });
});

// --- validate() against real plugin root ---

describe("validate.ts: smoke test — real plugin root", () => {
  const result = validate(PLUGIN_ROOT, false);

  test("errors is 0", () => { expect(result.errors).toBe(0); });
  test("passes >= 289", () => { expect(result.passes).toBeGreaterThanOrEqual(289); });
  test("output contains 'All' and 'passed'", () => {
    expect(result.output).toContain("All");
    expect(result.output).toContain("passed");
  });
  test("output contains all 10 category headers", () => {
    for (const cat of ["Manifest","Hooks","Skills","Agents","Commands",
                       "Output Styles","Proofs","Lib Scripts","Cross-References","Content Parity"]) {
      expect(result.output).toContain(`=== ${cat} ===`);
    }
  });
  test("output contains Summary header", () => {
    expect(result.output).toContain("=== Summary ===");
  });
});

// --- --quiet mode ---

describe("validate.ts: --quiet mode", () => {
  const result = validate(PLUGIN_ROOT, true);

  test("no PASS lines in quiet mode", () => {
    expect(result.output).not.toMatch(/^\s+PASS\s/m);
  });
  test("no FAIL lines in quiet mode", () => {
    expect(result.output).not.toMatch(/^\s+FAIL\s/m);
  });
  test("Summary is present in quiet mode", () => {
    expect(result.output).toContain("Summary");
  });
  test("errors is 0 in quiet mode", () => { expect(result.errors).toBe(0); });
});

// --- Summary table format ---

describe("validate.ts: summary table format", () => {
  test("header row has correct padding", () => {
    const r = validate(PLUGIN_ROOT, true);
    expect(r.output).toContain("  Category               Pass   Fail   Status");
  });
  test("data rows have correct printf-style alignment", () => {
    const r = validate(PLUGIN_ROOT, false);
    expect(r.output).toMatch(/  Manifest\s+\d+\s+\d+\s+ok/);
  });
});

// --- PARITY_TABLE ---

describe("validate.ts: PARITY_TABLE", () => {
  test("has exactly 41 entries", () => {
    expect(PARITY_TABLE.length).toBe(41);
  });
  test("every entry has 4 non-empty string fields", () => {
    for (const entry of PARITY_TABLE) {
      expect(entry.length).toBe(4);
      for (const field of entry) {
        expect(typeof field).toBe("string");
        expect(field.length).toBeGreaterThan(0);
      }
    }
  });
});

// --- VALID_TOOLS ---

describe("validate.ts: VALID_TOOLS", () => {
  test("has 32 tools", () => { expect(VALID_TOOLS.size).toBe(32); });
  for (const tool of ["TeamCreate","TeamDelete","LSP","CronCreate","CronDelete","CronList"]) {
    test(`includes ${tool}`, () => { expect(VALID_TOOLS.has(tool)).toBe(true); });
  }
  test("does not include FakeTool", () => { expect(VALID_TOOLS.has("FakeTool")).toBe(false); });
});

// --- VALID_MODELS ---

describe("validate.ts: VALID_MODELS", () => {
  test("contains opus", () => { expect(VALID_MODELS.has("opus")).toBe(true); });
  test("contains sonnet", () => { expect(VALID_MODELS.has("sonnet")).toBe(true); });
  test("contains haiku", () => { expect(VALID_MODELS.has("haiku")).toBe(true); });
  test("does not contain gpt-4o", () => { expect(VALID_MODELS.has("gpt-4o")).toBe(false); });
});

// --- frontmatterVal ---

describe("validate.ts: frontmatterVal edge cases", () => {
  test("returns empty string for nonexistent file", () => {
    expect(frontmatterVal("/nonexistent/file.md", "name")).toBe("");
  });

  test("extracts unquoted value", async () => {
    const tmp = `/tmp/fmtest-${Date.now()}.md`;
    await Bun.write(tmp, "---\nname: my-skill\ndescription: A skill\n---\n\n# Body\n");
    expect(frontmatterVal(tmp, "name")).toBe("my-skill");
  });

  test("strips double quotes from value", async () => {
    const tmp = `/tmp/fmtest-dq-${Date.now()}.md`;
    await Bun.write(tmp, '---\nname: "my-skill"\ndescription: A skill\n---\n\n# Body\n');
    expect(frontmatterVal(tmp, "name")).toBe("my-skill");
  });

  test("strips single quotes from value", async () => {
    const tmp = `/tmp/fmtest-sq-${Date.now()}.md`;
    await Bun.write(tmp, "---\nname: 'my-skill'\ndescription: A skill\n---\n\n# Body\n");
    expect(frontmatterVal(tmp, "name")).toBe("my-skill");
  });

  test("returns empty string for missing key", async () => {
    const tmp = `/tmp/fmtest-missing-${Date.now()}.md`;
    await Bun.write(tmp, "---\nname: my-skill\n---\n\n# Body\n");
    expect(frontmatterVal(tmp, "description")).toBe("");
  });

  test("handles multiline frontmatter (finds key anywhere in block)", async () => {
    const tmp = `/tmp/fmtest-multi-${Date.now()}.md`;
    await Bun.write(tmp, "---\nname: foo\ndescription: A thing\nmodel: opus\n---\n# Body\n");
    expect(frontmatterVal(tmp, "model")).toBe("opus");
  });
});

// --- No jq dependency ---

describe("validate.ts: no jq dependency", () => {
  test("source does not call jq (uses JSON.parse instead)", () => {
    const src = readFileSync(VALIDATE_TS, "utf8");
    expect(src).not.toContain('"jq"');
    expect(src).not.toContain("'jq'");
    expect(src).toContain("JSON.parse");
  });
});
