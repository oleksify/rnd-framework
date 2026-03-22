#!/usr/bin/env bun
// PreToolUse hook for Write and Edit: auto-allows .rnd/ path operations.
//
// Responsibility:
//   Auto-allow .rnd/ — permits writes/edits targeting .rnd/ paths without prompting,
//   so pipeline agents can create artifacts (plans, manifests, reports) without
//   triggering permission prompts.
//
// Output convention:
//   Auto-allow: exit 0 + hookSpecificOutput JSON with permissionDecision=allow
//   No opinion: exit 0 + no output (let Claude Code default permission prompt handle it)

import { parseInput, isRndPath, extractFilePath, allow } from "./lib.ts";

try {
  const input = await parseInput();
  const filePath = extractFilePath(input?.tool_input ?? {});
  if (filePath && isRndPath(filePath)) {
    console.log(JSON.stringify(allow()));
  }
  // No opinion for non-.rnd/ paths — exit 0, no stdout
} catch {
  process.exit(0);
}
