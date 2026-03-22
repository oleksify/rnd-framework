// hooks/slop-gate.ts — Pure library module for slop pattern analysis.
//
// Exported functions: loadCatalog, analyzeContent, computeScore,
// computeVerdict, sanitizePathToFilename, writePipelineArtifacts, buildSlopAdvisory
//
// This module has no main(), no shebang, no stdin reading.
// The executable entry point is hooks/post-tool-use.ts.

import { resolve } from "node:path";
import { mkdirSync } from "node:fs";
import { resolveRndDir } from "./lib.ts";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface SlopPattern {
  id: string;
  name: string;
  regex: string;
  severity: number;
  category: string;
  description: string;
  remediation: string;
  multiline?: boolean;
}

export interface PatternCatalog {
  patterns: SlopPattern[];
}

export interface Match {
  pattern_id: string;
  line: number;
  snippet: string;
  severity: number;
}

// ---------------------------------------------------------------------------
// Artifact-only types (not exposed in agent-facing output)
// ---------------------------------------------------------------------------

export type Verdict = "PASS" | "WARN" | "FAIL";

export function computeVerdict(score: number): Verdict {
  if (score > 7) return "FAIL";
  if (score >= 3) return "WARN";
  return "PASS";
}

// ---------------------------------------------------------------------------
// Pattern analysis
// ---------------------------------------------------------------------------

export function analyzeContent(content: string, patterns: SlopPattern[]): Match[] {
  const lines = content.split("\n");
  const matches: Match[] = [];

  for (const pattern of patterns.filter((p) => !p.multiline)) {
    let regex: RegExp;
    try { regex = new RegExp(pattern.regex); } catch { continue; }
    for (let i = 0; i < lines.length; i++) {
      if (regex.test(lines[i])) {
        matches.push({ pattern_id: pattern.id, line: i + 1, snippet: lines[i].trim().slice(0, 120), severity: pattern.severity });
      }
    }
  }
  for (const pattern of patterns.filter((p) => p.multiline)) {
    let regex: RegExp;
    try { regex = new RegExp(pattern.regex, "s"); } catch { continue; }
    const hit = regex.exec(content);
    if (hit) {
      matches.push({ pattern_id: pattern.id, line: 0, snippet: hit[0].trim().slice(0, 120), severity: pattern.severity });
    }
  }
  return matches;
}

// ---------------------------------------------------------------------------
// Score computation
// ---------------------------------------------------------------------------

export function computeScore(matches: Match[], lineCount: number): number {
  if (lineCount === 0) return 0;
  return matches.reduce((sum, m) => sum + m.severity, 0) / lineCount;
}

// ---------------------------------------------------------------------------
// Pipeline artifact types
// ---------------------------------------------------------------------------

interface SlopReport {
  file_path: string; verdict: Verdict; score: number;
  matches: Match[]; line_count: number; timestamp: string;
}

interface CumulativeScore {
  total_score: number; file_count: number; average_score: number;
  worst_file: string; worst_score: number; per_file: Record<string, number>;
}

// ---------------------------------------------------------------------------
// Filename sanitization
// ---------------------------------------------------------------------------

/**
 * Sanitizes a file path into a safe filename.
 * /src/utils/foo.ts => src-utils-foo.ts.json
 */
export function sanitizePathToFilename(filePath: string): string {
  const stripped = filePath.replace(/^\/+/, "").replace(/\//g, "-");
  return `${stripped}.json`;
}

// ---------------------------------------------------------------------------
// Artifact writing
// ---------------------------------------------------------------------------

export async function writePipelineArtifacts(filePath: string, lineCount: number, matches: Match[]): Promise<void> {
  const sessionDir = resolveRndDir();
  if (sessionDir === null || !sessionDir.includes("/sessions/")) return;

  try {
    const reportsDir = resolve(sessionDir, "slop-reports");
    mkdirSync(reportsDir, { recursive: true });

    const score = computeScore(matches, lineCount);
    const verdict = computeVerdict(score);
    const report: SlopReport = {
      file_path: filePath, verdict, score,
      matches, line_count: lineCount,
      timestamp: new Date().toISOString(),
    };
    const reportPath = resolve(reportsDir, sanitizePathToFilename(filePath));
    await Bun.write(reportPath, JSON.stringify(report, null, 2));

    const cumulativePath = resolve(reportsDir, "cumulative-score.json");
    let cumulative: CumulativeScore;
    try {
      cumulative = await Bun.file(cumulativePath).json() as CumulativeScore;
    } catch {
      cumulative = { total_score: 0, file_count: 0, average_score: 0, worst_file: "", worst_score: 0, per_file: {} };
    }
    if (!cumulative.per_file) cumulative.per_file = {};

    const prevScore = cumulative.per_file[filePath] ?? 0;
    cumulative.total_score += score - prevScore;
    if (!(filePath in cumulative.per_file)) cumulative.file_count += 1;
    cumulative.per_file[filePath] = score;
    cumulative.average_score = cumulative.file_count > 0 ? cumulative.total_score / cumulative.file_count : 0;
    cumulative.worst_score = 0;
    cumulative.worst_file = "";
    for (const [file, s] of Object.entries(cumulative.per_file)) {
      if (s > cumulative.worst_score) { cumulative.worst_score = s; cumulative.worst_file = file; }
    }
    await Bun.write(cumulativePath, JSON.stringify(cumulative, null, 2));
  } catch {
    // Swallow all errors — artifact writing must never fail the hook
  }
}

// ---------------------------------------------------------------------------
// Catalog loading
// ---------------------------------------------------------------------------

/**
 * Loads slop-patterns.json (always) and project-patterns.json from the active
 * session dir (if available). Returns combined PatternCatalog, or null if the
 * base catalog cannot be loaded.
 * IO function — reads files from disk.
 */
export async function loadCatalog(): Promise<PatternCatalog | null> {
  const catalogPath = resolve(import.meta.dir, "..", "slop-patterns.json");
  let catalog: PatternCatalog;
  try {
    const parsed = await Bun.file(catalogPath).json();
    if (typeof parsed !== "object" || parsed === null || !Array.isArray(parsed.patterns)) return null;
    catalog = parsed as PatternCatalog;
  } catch {
    return null;
  }

  const sessionDir = resolveRndDir();
  if (sessionDir !== null && sessionDir.includes("/sessions/")) {
    try {
      const parsed = await Bun.file(resolve(sessionDir, "project-patterns.json")).json();
      if (typeof parsed === "object" && parsed !== null && Array.isArray(parsed.patterns)) {
        catalog = { patterns: catalog.patterns.concat(parsed.patterns as SlopPattern[]) };
      }
    } catch {
      // Missing or malformed project-patterns.json — silently continue
    }
  }

  return catalog;
}

// ---------------------------------------------------------------------------
// Advisory formatting
// ---------------------------------------------------------------------------

/**
 * Formats slop matches and the source catalog into an advisory string.
 * Returns null if there are no matches.
 * Pure.
 */
export function buildSlopAdvisory(filePath: string, matches: Match[], catalog: PatternCatalog): string | null {
  if (matches.length === 0) return null;
  const patternMap = new Map(catalog.patterns.map((p) => [p.id, p]));
  const lines = [`Slop gate: ${matches.length} finding${matches.length === 1 ? "" : "s"} in ${filePath}`];
  for (const m of matches) {
    const p = patternMap.get(m.pattern_id);
    const name = p ? p.name : m.pattern_id;
    const remediation = p ? p.remediation : "";
    lines.push(`  L${m.line}: ${name} — "${m.snippet}" — ${remediation}`);
  }
  return lines.join("\n");
}
