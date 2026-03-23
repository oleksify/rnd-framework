/**
 * Tests for T3: Pipeline Integration
 *
 * Verifies that:
 * - start.md contains Phase 2.5b Reality Audit section after Proof Gate
 * - Reality Audit spawns rnd-reality-auditor agents in parallel
 * - INVALID_FOUND blocks pipeline and routes to Phase 4
 * - VALIDATED_ALL, VALIDATED_PARTIAL, SKIPPED proceed to Phase 3
 * - Phase 3 includes reality report paths in judge prompts
 * - rnd-orchestration/SKILL.md has Reality Auditor in agent roles and phases
 * - using-rnd-framework/SKILL.md has rnd-reality-auditing in skills table
 */

import { describe, test, expect } from "bun:test";
import { readFile } from "node:fs/promises";
import { join } from "node:path";

const PLUGIN_ROOT = join(import.meta.dir, "..");
const COMMANDS = join(PLUGIN_ROOT, "commands");
const SKILLS = join(PLUGIN_ROOT, "skills");

async function readCommand(name: string): Promise<string> {
  return readFile(join(COMMANDS, `${name}.md`), "utf-8");
}

async function readSkill(name: string): Promise<string> {
  return readFile(join(SKILLS, name, "SKILL.md"), "utf-8");
}

// ---------------------------------------------------------------------------
// start.md — Phase 2.5b Reality Audit section
// ---------------------------------------------------------------------------

describe("start.md: Phase 2.5b Reality Audit section exists after Proof Gate", () => {
  test("start.md contains a 'Reality Audit' section header", async () => {
    const content = await readCommand("start");
    expect(content).toContain("Phase 2.5b: Reality Audit");
  });

  test("Reality Audit section appears after the Proof Gate section", async () => {
    const content = await readCommand("start");
    const proofGateIdx = content.indexOf("Phase 2.5: Proof Gate");
    const realityAuditIdx = content.indexOf("Phase 2.5b: Reality Audit");
    expect(proofGateIdx).toBeGreaterThan(-1);
    expect(realityAuditIdx).toBeGreaterThan(-1);
    expect(realityAuditIdx).toBeGreaterThan(proofGateIdx);
  });

  test("Reality Audit section appears before Phase 3", async () => {
    const content = await readCommand("start");
    const realityAuditIdx = content.indexOf("Phase 2.5b: Reality Audit");
    const phase3Idx = content.indexOf("## Phase 3: Verify");
    expect(realityAuditIdx).toBeGreaterThan(-1);
    expect(phase3Idx).toBeGreaterThan(-1);
    expect(realityAuditIdx).toBeLessThan(phase3Idx);
  });
});

describe("start.md: Reality Audit spawns rnd-reality-auditor agents in parallel", () => {
  test("Reality Audit section references subagent_type rnd-framework:rnd-reality-auditor", async () => {
    const content = await readCommand("start");
    expect(content).toContain("rnd-framework:rnd-reality-auditor");
  });

  test("Reality Audit section spawns agents in a single message (parallel)", async () => {
    const content = await readCommand("start");
    const realityAuditIdx = content.indexOf("Phase 2.5b: Reality Audit");
    const phase3Idx = content.indexOf("## Phase 3: Verify");
    const section = content.slice(realityAuditIdx, phase3Idx);
    expect(section).toContain("single message");
  });
});

describe("start.md: Reality Audit routing — INVALID_FOUND blocks pipeline", () => {
  test("INVALID_FOUND routes to Phase 4 iteration", async () => {
    const content = await readCommand("start");
    const realityAuditIdx = content.indexOf("Phase 2.5b: Reality Audit");
    const phase3Idx = content.indexOf("## Phase 3: Verify");
    const section = content.slice(realityAuditIdx, phase3Idx);
    expect(section).toContain("INVALID_FOUND");
    expect(section.toLowerCase()).toMatch(/block|iteration|phase 4/i);
  });

  test("INVALID_FOUND includes reality report path as feedback for builder", async () => {
    const content = await readCommand("start");
    const realityAuditIdx = content.indexOf("Phase 2.5b: Reality Audit");
    const phase3Idx = content.indexOf("## Phase 3: Verify");
    const section = content.slice(realityAuditIdx, phase3Idx);
    expect(section).toContain("$RND_DIR/reality/T<id>-reality-report.md");
  });
});

describe("start.md: Reality Audit routing — proceed statuses go to Phase 3", () => {
  test("VALIDATED_ALL proceeds to Phase 3", async () => {
    const content = await readCommand("start");
    const realityAuditIdx = content.indexOf("Phase 2.5b: Reality Audit");
    const phase3Idx = content.indexOf("## Phase 3: Verify");
    const section = content.slice(realityAuditIdx, phase3Idx);
    expect(section).toContain("VALIDATED_ALL");
  });

  test("VALIDATED_PARTIAL proceeds to Phase 3", async () => {
    const content = await readCommand("start");
    const realityAuditIdx = content.indexOf("Phase 2.5b: Reality Audit");
    const phase3Idx = content.indexOf("## Phase 3: Verify");
    const section = content.slice(realityAuditIdx, phase3Idx);
    expect(section).toContain("VALIDATED_PARTIAL");
  });

  test("SKIPPED proceeds to Phase 3", async () => {
    const content = await readCommand("start");
    const realityAuditIdx = content.indexOf("Phase 2.5b: Reality Audit");
    const phase3Idx = content.indexOf("## Phase 3: Verify");
    const section = content.slice(realityAuditIdx, phase3Idx);
    expect(section).toContain("SKIPPED");
  });

  test("proceed statuses route to Phase 3 (not Phase 4)", async () => {
    const content = await readCommand("start");
    const realityAuditIdx = content.indexOf("Phase 2.5b: Reality Audit");
    const phase3Idx = content.indexOf("## Phase 3: Verify");
    const section = content.slice(realityAuditIdx, phase3Idx);
    // VALIDATED_ALL, VALIDATED_PARTIAL, SKIPPED line should say "proceed to Phase 3"
    expect(section).toMatch(/VALIDATED_ALL.*VALIDATED_PARTIAL.*SKIPPED.*proceed to Phase 3|proceed to Phase 3.*VALIDATED/si);
  });
});

describe("start.md: Phase 3 includes reality report paths in judge prompts", () => {
  test("Phase 3 pre-flight mentions reality report path", async () => {
    const content = await readCommand("start");
    const phase3Idx = content.indexOf("## Phase 3: Verify");
    const phase4Idx = content.indexOf("## Phase 4: Iterate");
    const phase3Section = content.slice(phase3Idx, phase4Idx);
    expect(phase3Section).toContain("$RND_DIR/reality/T<id>-reality-report.md");
  });

  test("Phase 3 mentions Reality Audit as source of additional evidence", async () => {
    const content = await readCommand("start");
    const phase3Idx = content.indexOf("## Phase 3: Verify");
    const phase4Idx = content.indexOf("## Phase 4: Iterate");
    const phase3Section = content.slice(phase3Idx, phase4Idx);
    expect(phase3Section).toContain("Reality Audit");
  });
});

describe("start.md: Reality Audit section structure matches Proof Gate pattern", () => {
  test("Reality Audit section has numbered steps", async () => {
    const content = await readCommand("start");
    const realityAuditIdx = content.indexOf("Phase 2.5b: Reality Audit");
    const phase3Idx = content.indexOf("## Phase 3: Verify");
    const section = content.slice(realityAuditIdx, phase3Idx);
    // Should have at least steps 1, 2, 3, 4
    expect(section).toMatch(/^1\./m);
    expect(section).toMatch(/^2\./m);
    expect(section).toMatch(/^3\./m);
    expect(section).toMatch(/^4\./m);
  });

  test("Reality Audit section has a status table", async () => {
    const content = await readCommand("start");
    const realityAuditIdx = content.indexOf("Phase 2.5b: Reality Audit");
    const phase3Idx = content.indexOf("## Phase 3: Verify");
    const section = content.slice(realityAuditIdx, phase3Idx);
    // Table has header row with Status column
    expect(section).toContain("| Status |");
  });

  test("Reality Audit section has auto-continue behavior note", async () => {
    const content = await readCommand("start");
    const realityAuditIdx = content.indexOf("Phase 2.5b: Reality Audit");
    const phase3Idx = content.indexOf("## Phase 3: Verify");
    const section = content.slice(realityAuditIdx, phase3Idx);
    expect(section).toContain("No AskUserQuestion");
  });
});

// ---------------------------------------------------------------------------
// rnd-orchestration/SKILL.md — Agent Roles and Execution Phases
// ---------------------------------------------------------------------------

describe("rnd-orchestration/SKILL.md: Agent Roles includes Reality Auditor", () => {
  test("SKILL.md contains 'Reality Auditor' in agent roles section", async () => {
    const content = await readSkill("rnd-orchestration");
    expect(content).toContain("Reality Auditor");
  });

  test("Reality Auditor description mentions blocking nature", async () => {
    const content = await readSkill("rnd-orchestration");
    const agentRolesIdx = content.indexOf("## Agent Roles");
    const nextSectionIdx = content.indexOf("\n## ", agentRolesIdx + 1);
    const rolesSection = content.slice(agentRolesIdx, nextSectionIdx > -1 ? nextSectionIdx : undefined);
    expect(rolesSection).toContain("Reality Auditor");
    // Should convey blocking nature
    expect(rolesSection.toLowerCase()).toMatch(/block|invalid_found/i);
  });
});

describe("rnd-orchestration/SKILL.md: Execution Phases includes Reality Audit", () => {
  test("Execution Phases section contains Reality Audit", async () => {
    const content = await readSkill("rnd-orchestration");
    const phasesIdx = content.indexOf("## Execution Phases");
    const nextSectionIdx = content.indexOf("\n## ", phasesIdx + 1);
    const phasesSection = content.slice(phasesIdx, nextSectionIdx > -1 ? nextSectionIdx : undefined);
    expect(phasesSection).toContain("Reality Audit");
  });

  test("Reality Audit listed as blocking sub-phase of 3.5", async () => {
    const content = await readSkill("rnd-orchestration");
    const phasesIdx = content.indexOf("## Execution Phases");
    const nextSectionIdx = content.indexOf("\n## ", phasesIdx + 1);
    const phasesSection = content.slice(phasesIdx, nextSectionIdx > -1 ? nextSectionIdx : undefined);
    // Should have a 3.5b or similar sub-phase notation
    expect(phasesSection).toMatch(/3\.5b|Reality Audit.*blocking/i);
  });
});

// ---------------------------------------------------------------------------
// using-rnd-framework/SKILL.md — Available Skills table
// ---------------------------------------------------------------------------

describe("using-rnd-framework/SKILL.md: Available Skills table includes rnd-reality-auditing", () => {
  test("SKILL.md contains rnd-reality-auditing in skills table", async () => {
    const content = await readSkill("using-rnd-framework");
    expect(content).toContain("rnd-reality-auditing");
  });

  test("rnd-reality-auditing entry has a description", async () => {
    const content = await readSkill("using-rnd-framework");
    const idx = content.indexOf("rnd-reality-auditing");
    expect(idx).toBeGreaterThan(-1);
    // The table row should have pipe separators and a description
    const lineStart = content.lastIndexOf("\n", idx);
    const lineEnd = content.indexOf("\n", idx);
    const line = content.slice(lineStart, lineEnd);
    // Should be a table row with at least 2 pipe separators
    const pipes = line.split("|").length - 1;
    expect(pipes).toBeGreaterThanOrEqual(2);
  });
});
