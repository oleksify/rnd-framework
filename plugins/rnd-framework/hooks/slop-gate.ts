#!/usr/bin/env bun
// PostToolUse hook: slop-gate
//
// Reads the slop pattern catalog, analyzes code written by Write/Edit tools
// for structural anti-patterns, computes a scoring verdict, and outputs
// structured JSON feedback to stdout.
//
// Behavior:
//   - Write: analyzes tool_input.content (full file)
//   - Edit:  analyzes tool_input.new_string only (diff-aware)
//   - Non-code file extensions: exits 0, no output
//   - Malformed stdin, missing catalog, any error: exits 0, no output
//   - Always exits 0 (PostToolUse hooks are advisory)

import { resolve } from "node:path";
import { readFileSync, mkdirSync, writeFileSync } from "node:fs";
import { parseInput, isCodeFile, resolveRndDir } from "./lib.ts";

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

type Verdict = "PASS" | "WARN" | "FAIL";

interface HookOutput {
  verdict: Verdict;
  score: number;
  file_path: string;
  line_count: number;
  matches: Match[];
}

// ---------------------------------------------------------------------------
// Scoring thresholds
// ---------------------------------------------------------------------------

const WARN_THRESHOLD = 3;
const FAIL_THRESHOLD = 7;

function computeVerdict(score: number): Verdict {
  if (score > FAIL_THRESHOLD) return "FAIL";
  if (score >= WARN_THRESHOLD) return "WARN";
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

function writePipelineArtifacts(output: HookOutput): void {
  const sessionDir = resolveRndDir();
  if (sessionDir === null || !sessionDir.includes("/sessions/")) return;

  try {
    const reportsDir = resolve(sessionDir, "slop-reports");
    mkdirSync(reportsDir, { recursive: true });

    const report: SlopReport = {
      file_path: output.file_path, verdict: output.verdict, score: output.score,
      matches: output.matches, line_count: output.line_count,
      timestamp: new Date().toISOString(),
    };
    const reportPath = resolve(reportsDir, sanitizePathToFilename(output.file_path));
    writeFileSync(reportPath, JSON.stringify(report, null, 2), "utf-8");

    const cumulativePath = resolve(reportsDir, "cumulative-score.json");
    let cumulative: CumulativeScore;
    try {
      cumulative = JSON.parse(readFileSync(cumulativePath, "utf-8")) as CumulativeScore;
    } catch {
      cumulative = { total_score: 0, file_count: 0, average_score: 0, worst_file: "", worst_score: 0, per_file: {} };
    }
    if (!cumulative.per_file) cumulative.per_file = {};

    const prevScore = cumulative.per_file[output.file_path] ?? 0;
    cumulative.total_score += output.score - prevScore;
    if (!(output.file_path in cumulative.per_file)) cumulative.file_count += 1;
    cumulative.per_file[output.file_path] = output.score;
    cumulative.average_score = cumulative.file_count > 0 ? cumulative.total_score / cumulative.file_count : 0;
    cumulative.worst_score = 0;
    cumulative.worst_file = "";
    for (const [file, score] of Object.entries(cumulative.per_file)) {
      if (score > cumulative.worst_score) {
        cumulative.worst_score = score;
        cumulative.worst_file = file;
      }
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
  const lineCount = content.split("\n").length;
  const score = computeScore(matches, lineCount);
  const verdict = computeVerdict(score);

  const output: HookOutput = { verdict, score, file_path: filePath, line_count: lineCount, matches };

  writePipelineArtifacts(output);
  process.stdout.write(JSON.stringify(output) + "\n");
}

try {
  await main();
} catch {
  process.exit(0);
}
