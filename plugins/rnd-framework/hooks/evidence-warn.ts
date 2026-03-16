#!/usr/bin/env bun
// PostToolUse hook: evidence-warn
//
// Detects SQL table references and API endpoint patterns in written code
// and emits an advisory warning via hookSpecificOutput.additionalContext.
// Always exits 0 — purely advisory, never blocks.

import { parseInput, isCodeFile } from "./lib.ts";

const SQL_PATTERNS: Array<RegExp> = [
  /SELECT\s+.*\s+FROM\s+(\w+)/gi,
  /INSERT\s+INTO\s+(\w+)/gi,
  /CREATE\s+TABLE\s+(\w+)/gi,
  /UPDATE\s+(\w+)\s+SET/gi,
  /DELETE\s+FROM\s+(\w+)/gi,
  /ALTER\s+TABLE\s+(\w+)/gi,
  /DROP\s+TABLE\s+(\w+)/gi,
];

const API_PATTERNS: Array<RegExp> = [
  /fetch\s*\(\s*["'](\/?[^"']+)/gi,
  /axios\.\w+\s*\(\s*["'](\/?[^"']+)/gi,
];

function scanSQL(content: string): string[] {
  const tables = new Set<string>();
  for (const pattern of SQL_PATTERNS) {
    pattern.lastIndex = 0;
    let match: RegExpExecArray | null;
    while ((match = pattern.exec(content)) !== null) {
      if (match[1]) tables.add(match[1]);
    }
  }
  return Array.from(tables);
}

function scanAPI(content: string): string[] {
  const endpoints = new Set<string>();
  for (const pattern of API_PATTERNS) {
    pattern.lastIndex = 0;
    let match: RegExpExecArray | null;
    while ((match = pattern.exec(content)) !== null) {
      if (match[1]) endpoints.add(match[1].split("?")[0]);
    }
  }
  return Array.from(endpoints);
}

async function main(): Promise<void> {
  const input = await parseInput();
  if (input === null) process.exit(0);

  const { tool_name: toolName, tool_input: ti } = input;

  const filePath = ti["file_path"];
  if (typeof filePath !== "string" || filePath.length === 0) process.exit(0);
  if (filePath.includes(".rnd/") || !isCodeFile(filePath)) process.exit(0);

  let content: string;
  if (toolName === "Write") {
    const c = ti["content"];
    if (typeof c !== "string") process.exit(0);
    content = c;
  } else if (toolName === "Edit") {
    const ns = ti["new_string"];
    if (typeof ns !== "string") process.exit(0);
    content = ns;
  } else {
    process.exit(0);
  }

  return mainScan(content);
}

async function mainScan(content: string): Promise<void> {
  const tables = scanSQL(content);
  const endpoints = scanAPI(content);

  if (tables.length === 0 && endpoints.length === 0) process.exit(0);

  const parts: string[] = [];
  if (tables.length > 0) parts.push(`tables [${tables.join(", ")}]`);
  if (endpoints.length > 0) parts.push(`endpoints [${endpoints.join(", ")}]`);

  const msg =
    `Evidence check: This code references ${parts.join(" and ")}. ` +
    `Verify you have read the relevant schema/migration files and API specifications before proceeding.`;

  console.log(
    JSON.stringify({ hookSpecificOutput: { additionalContext: msg } }),
  );
}

try {
  await main();
} catch {
  process.exit(0);
}
