#!/usr/bin/env bun
// hooks/post-tool-use.ts — Merged PostToolUse hook for Write and Edit.
//
// Combines three separate hooks into one to eliminate redundant process spawns:
//   1. Audit logging — appends JSONL entry to $RND_DIR/audit.jsonl (all files)
//   2. Slop analysis — detects LLM anti-patterns in code files, writes artifacts
//   3. Evidence scanning — detects SQL/API references in code files
//
// Output convention:
//   - Resilient: always exits 0
//   - Outputs combined advisory JSON when slop or evidence findings are present
//   - No stdout when there are no findings
//   - Audit logging always runs for any file type during an active session

import { appendFileSync } from "node:fs";
import { join } from "node:path";
import {
  parseInput,
  isCodeFile,
  isRndPath,
  extractFilePath,
  extractWriteEditContent,
  activeSessionDir,
  isoTimestamp,
  advisory,
  countLines,
} from "./lib.ts";
import {
  loadCatalog,
  analyzeContent,
  buildSlopAdvisory,
  writePipelineArtifacts,
} from "./slop-gate.ts";
import { scanSQL, scanAPI, buildEvidenceWarning } from "./evidence-warn.ts";

async function main(): Promise<void> {
  const input = await parseInput();
  if (input === null) return;

  const { tool_name: toolName, tool_input: toolInput } = input;

  const filePath = extractFilePath(toolInput);
  if (!filePath) return;

  // ---------------------------------------------------------------------------
  // Step 1: Audit logging — runs for ALL files during active session
  // ---------------------------------------------------------------------------

  const sessionDir = activeSessionDir();
  if (sessionDir !== null) {
    const ts = isoTimestamp();
    const entry = JSON.stringify({ ts, tool: toolName, file: filePath }) + "\n";
    try {
      appendFileSync(join(sessionDir, "audit.jsonl"), entry, "utf-8");
    } catch {
      // Resilient — never fail the hook
    }
  }

  // ---------------------------------------------------------------------------
  // Steps 2 & 3: Slop + Evidence — code files only
  // ---------------------------------------------------------------------------

  if (!isCodeFile(filePath)) return;

  const content = extractWriteEditContent(toolName, toolInput);
  if (content === null) return;

  const advisoryMessages: string[] = [];

  // Step 2: Slop analysis
  try {
    const catalog = await loadCatalog();
    if (catalog !== null) {
      const matches = analyzeContent(content, catalog.patterns);
      await writePipelineArtifacts(filePath, countLines(content), matches);
      const msg = buildSlopAdvisory(filePath, matches, catalog);
      if (msg !== null) advisoryMessages.push(msg);
    }
  } catch {
    // Slop analysis failure must not block evidence scanning
  }

  // Step 3: Evidence scanning — skip .rnd/ paths
  if (!isRndPath(filePath)) {
    try {
      const tables = scanSQL(content);
      const endpoints = scanAPI(content);
      const msg = buildEvidenceWarning(tables, endpoints);
      if (msg !== null) advisoryMessages.push(msg);
    } catch {
      // Evidence scanning failure must not propagate
    }
  }

  if (advisoryMessages.length > 0) {
    console.log(JSON.stringify(advisory(advisoryMessages.join("\n\n"))));
  }
}

try {
  await main();
} catch {
  // Resilient hook: never fail regardless of error
  process.exit(0);
}
