#!/usr/bin/env bun
// PreToolUse hook for Read: enforces the information barrier and auto-allows .rnd/ and plugin cache reads.
//
// Three responsibilities:
//   1. Information barrier — blocks reads of self-assessment files to prevent the
//      Verifier from anchoring on Builder reasoning.
//   2. Auto-allow plugin cache — permits reads from plugins/cache/ paths without prompting.
//   3. Auto-allow .rnd/ — permits reads targeting .rnd/ paths without prompting.

import { parseInput, isRndPath, isPluginCachePath, allow, block } from "./lib.ts";

/** Decide what to do given a file path and agent type. Pure. */
export function decide(
  filePath: string,
  agentType: string,
): "block" | "allow" | "no-opinion" {
  if (filePath.toLowerCase().includes("self-assessment")) {
    const isKnownNonVerifier =
      agentType.length > 0 &&
      !agentType.toLowerCase().includes("verifier");
    if (!isKnownNonVerifier) return "block";
  }
  if (isPluginCachePath(filePath)) return "allow";
  if (isRndPath(filePath)) return "allow";
  return "no-opinion";
}

const input = await parseInput();
const filePath =
  typeof input?.tool_input?.["file_path"] === "string"
    ? (input.tool_input["file_path"] as string)
    : "";
const agentType = input?.agent_type ?? "";

const decision = decide(filePath, agentType);
if (decision === "block") {
  block(
    "INFORMATION BARRIER: self-assessment files are write-only records for the orchestrator. " +
    "Direct reading is blocked to maintain information barriers between Builder and Verifier.",
  );
} else if (decision === "allow") {
  console.log(JSON.stringify(allow()));
}
// no-opinion: exit 0, no stdout
