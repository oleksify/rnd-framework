#!/usr/bin/env bun
/**
 * Deterministic pattern extraction from CLAUDE.md files.
 * Usage: bun extract-patterns.ts <RND_DIR>
 * Reads all CLAUDE.md files in CWD, extracts prohibition/requirement patterns,
 * writes $RND_DIR/project-patterns.json.
 */

import { readdirSync, readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { join, resolve } from "node:path";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface SlopPattern {
  id: string; name: string; regex: string;
  severity: number; category: string;
  description: string; remediation: string;
  multiline?: boolean;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Convert a phrase to kebab-case. Pure, deterministic. */
const toKebabCase = (s: string): string =>
  s.toLowerCase()
    .replace(/[`'"]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");

/** Extract backtick-wrapped code term from rule text, if present. */
const extractCodeTerm = (text: string): string | null => {
  const m = text.match(/`([^`]+)`/);
  return m ? m[1] : null;
};

// Rule prefix patterns: [prefix-regex, severity]
const RULE_MATCHERS: Array<[RegExp, number]> = [
  [/^NEVER\s+(?:use\s+)?/i, 4],
  [/^ALWAYS\s+(?:use\s+)?/i, 4],
  [/^No\s+/i, 3],
  [/^avoid\s+/i, 3],
  [/^do\s+not\s+(?:use\s+)?/i, 3],
];

/** Escape special regex chars for literal matching. */
const escapeRegex = (s: string): string =>
  s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

/**
 * Convert a matched rule clause (after stripping prefix) to a SlopPattern.
 */
const clauseToPattern = (clause: string, severity: number): SlopPattern => {
  const codeTerm = extractCodeTerm(clause);
  const cleanClause = clause.replace(/—.*$/, "").trim().replace(/`([^`]+)`/g, "$1");
  const id = toKebabCase(cleanClause);
  const name = cleanClause.trim();

  const regex = codeTerm
    ? `\\b${escapeRegex(codeTerm)}\\b`
    : (cleanClause.split(/\s+/).slice(0, 3).map(w => escapeRegex(w.toLowerCase())).join("\\s+"));

  return {
    id, name, regex, severity,
    category: "project-standard",
    description: `Rule extracted from CLAUDE.md: ${name}`,
    remediation: `Follow project standard: ${name}`,
  };
};

/** Parse a single line, returning a SlopPattern or null if no rule matched. */
const parseLine = (line: string): SlopPattern | null => {
  const stripped = line.replace(/^[\s\-*]+/, "");
  for (const [prefix, severity] of RULE_MATCHERS) {
    const m = stripped.match(prefix);
    if (m) {
      const clause = stripped.slice(m[0].length).trim();
      if (clause.length < 3) return null;
      return clauseToPattern(clause, severity);
    }
  }
  return null;
};

/** Recursively find all CLAUDE.md files under a directory. */
const findClaudeMds = (dir: string): string[] => {
  const results: string[] = [];
  try {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      if (entry.name.startsWith(".") || entry.name === "node_modules") continue;
      const full = join(dir, entry.name);
      if (entry.isDirectory()) results.push(...findClaudeMds(full));
      else if (entry.name === "CLAUDE.md") results.push(full);
    }
  } catch { /* skip unreadable dirs */ }
  return results;
};

/** Extract all patterns from a CLAUDE.md file content. */
const parseClaudeMd = (content: string): SlopPattern[] =>
  content.split("\n").map(parseLine).filter((p): p is SlopPattern => p !== null);

/** Main entry point. */
const main = (): void => {
  const rndDir = resolve(process.argv[2] ?? ".");
  const cwd = process.cwd();
  const files = findClaudeMds(cwd);
  const patterns = files.flatMap(f => parseClaudeMd(readFileSync(f, "utf-8")));
  mkdirSync(rndDir, { recursive: true });
  writeFileSync(join(rndDir, "project-patterns.json"), JSON.stringify({ patterns }, null, 2));
};

main();
