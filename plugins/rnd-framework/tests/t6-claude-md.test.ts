import { describe, test, expect } from "bun:test";
import { readFileSync } from "fs";
import { join } from "path";

const CLAUDE_MD_PATH = join(import.meta.dir, "../../../CLAUDE.md");
const content = readFileSync(CLAUDE_MD_PATH, "utf8");

describe("T6: CLAUDE.md Documentation Update", () => {
  describe("SC1: Architecture table includes rnd-reality-auditor row", () => {
    test("table row with rnd-reality-auditor exists", () => {
      expect(content).toContain("`rnd-reality-auditor`");
    });

    test("row specifies model sonnet", () => {
      const lines = content.split("\n");
      const row = lines.find((l) => l.includes("`rnd-reality-auditor`"));
      expect(row).toBeDefined();
      expect(row).toContain("sonnet");
    });

    test("row specifies color teal", () => {
      const lines = content.split("\n");
      const row = lines.find((l) => l.includes("`rnd-reality-auditor`"));
      expect(row).toBeDefined();
      expect(row).toContain("teal");
    });

    test("row has a purpose description", () => {
      const lines = content.split("\n");
      const row = lines.find((l) => l.includes("`rnd-reality-auditor`"));
      expect(row).toBeDefined();
      // A row has 4 pipe-delimited cells; description is the last non-empty one
      const cells = row!.split("|").map((c) => c.trim()).filter(Boolean);
      expect(cells.length).toBeGreaterThanOrEqual(4);
      expect(cells[3].length).toBeGreaterThan(0);
    });

    test("row is inside the Agent Roles and Models table (after header row)", () => {
      const tableHeader = "| Agent | Model | Color | Purpose |";
      const headerIdx = content.indexOf(tableHeader);
      expect(headerIdx).toBeGreaterThan(-1);
      const auditorIdx = content.indexOf("`rnd-reality-auditor`");
      expect(auditorIdx).toBeGreaterThan(headerIdx);
    });

    test("table formatting is consistent with other rows (pipe-delimited, backtick agent name)", () => {
      const lines = content.split("\n");
      const auditorRow = lines.find((l) => l.includes("`rnd-reality-auditor`"));
      expect(auditorRow).toMatch(/^\|.*`rnd-reality-auditor`.*\|.*\|.*\|.*\|/);
    });
  });

  describe("SC2: Repository Layout tree includes reality/ directory under sessions/", () => {
    test("reality/T*-reality-report.md entry exists", () => {
      expect(content).toContain("reality/T*-reality-report.md");
    });

    test("reality/T*-experiments/ entry exists", () => {
      expect(content).toContain("reality/T*-experiments/");
    });

    test("reality entries appear inside the sessions/ tree block", () => {
      const sessionsMarker = "sessions/<YYYYMMDD-HHMMSS-XXXX>/";
      const iterationMarker = "iteration-log.md";
      const sessionsIdx = content.indexOf(sessionsMarker);
      const iterationIdx = content.indexOf(iterationMarker);
      const realityIdx = content.indexOf("reality/T*-reality-report.md");

      expect(sessionsIdx).toBeGreaterThan(-1);
      expect(iterationIdx).toBeGreaterThan(-1);
      expect(realityIdx).toBeGreaterThan(sessionsIdx);
      expect(realityIdx).toBeLessThan(iterationIdx);
    });
  });

  describe("SC3: Execution Phases mentions Reality Audit as blocking sub-phase", () => {
    test("Execution Phases section heading exists", () => {
      expect(content).toContain("### Execution Phases");
    });

    test("Reality Audit is mentioned in the Execution Phases section", () => {
      const sectionStart = content.indexOf("### Execution Phases");
      const nextSection = content.indexOf("\n### ", sectionStart + 1);
      const section = content.slice(sectionStart, nextSection > -1 ? nextSection : undefined);
      expect(section).toContain("Reality Audit");
    });

    test("Reality Audit is described as blocking", () => {
      const sectionStart = content.indexOf("### Execution Phases");
      const nextSection = content.indexOf("\n### ", sectionStart + 1);
      const section = content.slice(sectionStart, nextSection > -1 ? nextSection : undefined);
      expect(section.toLowerCase()).toContain("blocking");
    });

    test("INVALID_FOUND status is mentioned as the pipeline-blocking verdict", () => {
      const sectionStart = content.indexOf("### Execution Phases");
      const nextSection = content.indexOf("\n### ", sectionStart + 1);
      const section = content.slice(sectionStart, nextSection > -1 ? nextSection : undefined);
      expect(section).toContain("INVALID_FOUND");
    });
  });

  describe("SC4: hooks section lists reality-warn.ts as a pure library module", () => {
    test("reality-warn.ts appears in the Repository Layout hooks/ tree", () => {
      expect(content).toContain("reality-warn.ts");
    });

    test("reality-warn.ts entry describes it as a pure library module", () => {
      const lines = content.split("\n");
      const line = lines.find((l) => l.includes("reality-warn.ts"));
      expect(line).toBeDefined();
      expect(line!.toLowerCase()).toContain("pure library module");
    });

    test("reality-warn.ts is listed after evidence-warn.ts (consistent ordering)", () => {
      const evidenceIdx = content.indexOf("evidence-warn.ts");
      const realityWarnIdx = content.indexOf("reality-warn.ts");
      expect(evidenceIdx).toBeGreaterThan(-1);
      expect(realityWarnIdx).toBeGreaterThan(evidenceIdx);
    });
  });

  describe("Quality: table formatting consistency", () => {
    test("all agent table rows follow the same pipe-delimited pattern", () => {
      const tableStart = content.indexOf("| Agent | Model | Color | Purpose |");
      const tableEnd = content.indexOf("\n\n", tableStart);
      const tableBlock = content.slice(tableStart, tableEnd > -1 ? tableEnd : undefined);
      const rows = tableBlock
        .split("\n")
        .filter((l) => l.startsWith("|") && !l.includes("---"));
      // All data rows (not the header) should have 4+ cells
      for (const row of rows.slice(1)) {
        const cells = row.split("|").filter(Boolean);
        expect(cells.length).toBeGreaterThanOrEqual(4);
      }
    });
  });
});
