#!/usr/bin/env bun
// hooks/chunk-gate.ts — PreToolUse hook for Write and Edit.
//   1. Auto-allows .rnd/ paths (framework artifacts are never size-limited).
//   2. Blocks non-.rnd/ writes during planning phase (.planning-phase marker).
//   3. Blocks writes/edits exceeding 30 lines on project files.
//
// Output convention:
//   Auto-allow: exit 0 + hookSpecificOutput JSON  (path is .rnd/)
//   No opinion: exit 0 + no output                (line count <= 30)
//   Block:      exit 2 + reason on stderr          (planning phase or >30 lines)

import { existsSync } from "node:fs";
import { join } from "node:path";
import { parseInput, isRndPath, allow, block, resolveRndDir, countLines } from "./lib.ts";

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main(): Promise<void> {
  const input = await parseInput();
  if (!input) process.exit(0);

  const filePath = (input.tool_input["file_path"] as string | undefined) ?? "";

  // Auto-allow .rnd/ paths — framework artifacts are never size-limited
  if (isRndPath(filePath)) {
    console.log(JSON.stringify(allow()));
    process.exit(0);
  }

  // Block writes/edits during planning phase
  const rndDir = resolveRndDir();
  if (rndDir !== null && existsSync(join(rndDir, ".planning-phase"))) {
    block(
      "BLOCKED: Write/Edit to paths outside .rnd/ is not allowed during the " +
        "planning phase. The Planner writes only to $RND_DIR/plan.md.",
    );
  }

  // Extract content based on tool type
  const toolName = input.tool_name;
  let content = "";
  if (toolName === "Write") {
    content = (input.tool_input["content"] as string | undefined) ?? "";
  } else if (toolName === "Edit") {
    content = (input.tool_input["new_string"] as string | undefined) ?? "";
  } else {
    process.exit(0);
  }

  const lineCount = countLines(content);
  if (lineCount > 30) {
    block(
      `BLOCKED: ${toolName} to '${filePath}' has ${lineCount} lines (limit: 30). ` +
        "Split into smaller chunks of 30 lines or fewer.",
    );
  }
}

try {
  await main();
} catch {
  process.exit(0);
}
