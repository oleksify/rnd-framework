#!/usr/bin/env bun
// PostToolUse hook: slop-gate
//
// Reads the slop pattern catalog, analyzes code written by Write/Edit tools
// for structural anti-patterns, and outputs an advisory context message when
// findings are detected so agents see them inline.
//
// Behavior:
//   - Write: analyzes tool_input.content (full file)
//   - Edit:  analyzes tool_input.new_string only (diff-aware)
//   - Findings: outputs advisory JSON {hookSpecificOutput: {additionalContext}}
//   - No findings: exits 0 silently
//   - Non-code file extensions: exits 0, no output
//   - Malformed stdin, missing catalog, any error: exits 0, no output
//   - Always exits 0 (PostToolUse hooks are advisory)

import { resolve } from "node:path";
import { readFileSync, mkdirSync, writeFileSync } from "node:fs";
import { advisory, parseInput, isCodeFile, resolveRndDir, countLines } from "./lib.ts";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface SlopPattern {
  id: string;
  name: string;
  regex: string;
  severity: number;
  category: string;
  description: string;
  remediation: string;
}

interface PatternCatalog {
  patterns: SlopPattern[];
}

interface Match {
  pattern_id: string;
  line: number;
  snippet: string;
  severity: number;
}

// ---------------------------------------------------------------------------
// Artifact-only types (not exposed in agent-facing output)
// ---------------------------------------------------------------------------

type Verdict = "PASS" | "WARN" | "FAIL";

function computeVerdict(score: number): Verdict {
  if (score > 7) return "FAIL";
  if (score >= 3) return "WARN";
  return "PASS";
}

// ---------------------------------------------------------------------------
// Pattern analysis
// ---------------------------------------------------------------------------

function analyzeContent(content: string, patterns: SlopPattern[]): Match[] {
  const lines = content.split("\n");
  const matches: Match[] = [];

  for (const pattern of patterns) {
    let regex: RegExp;
    try {
      regex = new RegExp(pattern.regex);
    } catch {
      // Skip invalid regex patterns
      continue;
    }
    for (let i = 0; i < lines.length; i++) {
      if (regex.test(lines[i])) {
        matches.push({ pattern_id: pattern.id, line: i + 1, snippet: lines[i].trim().slice(0, 120), severity: pattern.severity });
      }
    }
  }
  return matches;
}

// ---------------------------------------------------------------------------
// Score computation
// ---------------------------------------------------------------------------

function computeScore(matches: Match[], lineCount: number): number {
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
function sanitizePathToFilename(filePath: string): string {
  const stripped = filePath.replace(/^\/+/, "").replace(/\//g, "-");
  return `${stripped}.json`;
}

// ---------------------------------------------------------------------------
// Artifact writing
// ---------------------------------------------------------------------------

function writePipelineArtifacts(filePath: string, lineCount: number, matches: Match[]): void {
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
    writeFileSync(reportPath, JSON.stringify(report, null, 2), "utf-8");

    const cumulativePath = resolve(reportsDir, "cumulative-score.json");
    let cumulative: CumulativeScore;
    try {
      cumulative = JSON.parse(readFileSync(cumulativePath, "utf-8")) as CumulativeScore;
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
    writeFileSync(cumulativePath, JSON.stringify(cumulative, null, 2), "utf-8");
  } catch {
    // Swallow all errors — artifact writing must never fail the hook
  }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main(): Promise<void> {
  const input = await parseInput();
  if (input === null) process.exit(0);

  const toolName = input.tool_name;
  const toolInputObj = input.tool_input;

  if (!toolName) process.exit(0);

  const filePath = toolInputObj["file_path"];
  if (typeof filePath !== "string" || filePath.length === 0) process.exit(0);

  if (!isCodeFile(filePath)) process.exit(0);

  let content: string;
  if (toolName === "Write") {
    const c = toolInputObj["content"];
    if (typeof c !== "string") process.exit(0);
    content = c;
  } else if (toolName === "Edit") {
    const ns = toolInputObj["new_string"];
    if (typeof ns !== "string") process.exit(0);
    content = ns;
  } else {
    process.exit(0);
  }

  const catalogPath = resolve(import.meta.dir, "..", "slop-patterns.json");
  let catalog: PatternCatalog;
  try {
    const raw = readFileSync(catalogPath, "utf-8");
    const parsed = JSON.parse(raw);
    if (typeof parsed !== "object" || parsed === null || !Array.isArray(parsed.patterns)) process.exit(0);
    catalog = parsed as PatternCatalog;
  } catch {
    process.exit(0);
  }

  const sessionDir = resolveRndDir();
  if (sessionDir !== null && sessionDir.includes("/sessions/")) {
    try {
      const raw = readFileSync(resolve(sessionDir, "project-patterns.json"), "utf-8");
      const parsed = JSON.parse(raw);
      if (typeof parsed === "object" && parsed !== null && Array.isArray(parsed.patterns)) {
        catalog = { patterns: catalog.patterns.concat(parsed.patterns as SlopPattern[]) };
      }
    } catch {
      // Missing or malformed project-patterns.json — silently continue
    }
  }

  const matches = analyzeContent(content, catalog.patterns);
  const lineCount = countLines(content);

  writePipelineArtifacts(filePath, lineCount, matches);

  if (matches.length === 0) process.exit(0);

  const patternMap = new Map(catalog.patterns.map((p) => [p.id, p]));
  const lines = [`Slop gate: ${matches.length} finding${matches.length === 1 ? "" : "s"} in ${filePath}`];
  for (const m of matches) {
    const p = patternMap.get(m.pattern_id);
    const name = p ? p.name : m.pattern_id;
    const remediation = p ? p.remediation : "";
    lines.push(`  L${m.line}: ${name} — "${m.snippet}" — ${remediation}`);
  }
  console.log(JSON.stringify(advisory(lines.join("\n"))));
}

try {
  await main();
} catch {
  process.exit(0);
}
