/**
 * Tests for lib/extract-patterns.ts — T1 success criteria.
 */

import { describe, it, expect } from "bun:test";
import { mkdtemp, mkdir, writeFile, rm } from "node:fs/promises";
import { existsSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";

const SCRIPT = join(import.meta.dir, "../lib/extract-patterns.ts");

interface SlopPattern {
  id: string; name: string; regex: string;
  severity: number; category: string;
  description: string; remediation: string;
  multiline?: boolean;
}

async function run(rndDir: string, cwd: string) {
  const proc = Bun.spawn(["bun", SCRIPT, rndDir], {
    cwd, stdout: "pipe", stderr: "pipe",
  });
  const [out, err] = await Promise.all([
    Bun.readableStreamToText(proc.stdout),
    Bun.readableStreamToText(proc.stderr),
    proc.exited,
  ]);
  return { exitCode: proc.exitCode ?? 0, stdout: out, stderr: err };
}

async function setup(claudeContent: string) {
  const cwd = await mkdtemp(join(tmpdir(), "ep-test-"));
  const rndDir = await mkdtemp(join(tmpdir(), "ep-rnd-"));
  await writeFile(join(cwd, "CLAUDE.md"), claudeContent, "utf-8");
  const cleanup = async () => {
    for (const d of [cwd, rndDir]) {
      if (existsSync(d)) await rm(d, { recursive: true, force: true });
    }
  };
  return { cwd, rndDir, cleanup };
}

function readPatterns(rndDir: string): SlopPattern[] {
  const { readFileSync } = require("node:fs");
  return JSON.parse(readFileSync(join(rndDir, "project-patterns.json"), "utf-8")).patterns;
}

describe("extract-patterns", () => {
  it("exits 0 and produces valid JSON when CLAUDE.md has prohibition rules", async () => {
    const { cwd, rndDir, cleanup } = await setup("- No early returns — use ternary chains\n");
    try {
      const { exitCode } = await run(rndDir, cwd);
      expect(exitCode).toBe(0);
      const patterns = readPatterns(rndDir);
      expect(Array.isArray(patterns)).toBe(true);
    } finally { await cleanup(); }
  });

  it("produces pattern with id containing 'early-return' for 'No early returns'", async () => {
    const { cwd, rndDir, cleanup } = await setup("- No early returns — use ternary chains\n");
    try {
      await run(rndDir, cwd);
      const patterns = readPatterns(rndDir);
      const match = patterns.find(p => p.id.includes("early-return"));
      expect(match).toBeDefined();
      expect(match!.category).toBe("project-standard");
    } finally { await cleanup(); }
  });

  it("severity 4 for NEVER patterns", async () => {
    const { cwd, rndDir, cleanup } = await setup("- NEVER use any\n");
    try {
      await run(rndDir, cwd);
      const patterns = readPatterns(rndDir);
      expect(patterns.length).toBeGreaterThan(0);
      expect(patterns[0].severity).toBe(4);
    } finally { await cleanup(); }
  });

  it("severity 3 for avoid patterns", async () => {
    const { cwd, rndDir, cleanup } = await setup("- avoid console.log\n");
    try {
      await run(rndDir, cwd);
      const patterns = readPatterns(rndDir);
      expect(patterns.length).toBeGreaterThan(0);
      expect(patterns[0].severity).toBe(3);
    } finally { await cleanup(); }
  });

  it("writes empty patterns array when no CLAUDE.md found", async () => {
    const cwd = await mkdtemp(join(tmpdir(), "ep-empty-"));
    const rndDir = await mkdtemp(join(tmpdir(), "ep-rnd-"));
    try {
      const { exitCode } = await run(rndDir, cwd);
      expect(exitCode).toBe(0);
      const patterns = readPatterns(rndDir);
      expect(patterns).toEqual([]);
    } finally {
      for (const d of [cwd, rndDir]) if (existsSync(d)) await rm(d, { recursive: true, force: true });
    }
  });

  it("pattern IDs are kebab-case and deterministic", async () => {
    const { cwd, rndDir, cleanup } = await setup("- No early returns\n");
    const rndDir2 = await mkdtemp(join(tmpdir(), "ep-rnd2-"));
    try {
      await run(rndDir, cwd);
      await run(rndDir2, cwd);
      const p1 = readPatterns(rndDir);
      const p2 = readPatterns(rndDir2);
      expect(p1[0].id).toBe(p2[0].id);
      expect(p1[0].id).toMatch(/^[a-z0-9]+(-[a-z0-9]+)*$/);
    } finally {
      await cleanup();
      if (existsSync(rndDir2)) await rm(rndDir2, { recursive: true, force: true });
    }
  });
});
