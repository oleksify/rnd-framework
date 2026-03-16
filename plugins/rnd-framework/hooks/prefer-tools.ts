#!/usr/bin/env bun
// hooks/prefer-tools.ts — PreToolUse hook for Bash: blocks sed/grep/cat/find/etc when
// dedicated Claude Code tools (Edit, Grep, Read, Glob) should be used instead.
//
// Output convention (hookSpecificOutput format):
//   Auto-allow: exit 0 + hookSpecificOutput JSON with permissionDecision=allow
//   Block:      exit 2 + reason on stderr
//   No opinion: exit 0 + no output

import { parseInput, allow, block } from "./lib.ts";

/**
 * Strips all leading "cd <path> && " or "cd <path> ;" or "cd <path>;;" prefixes.
 * Handles chained cd commands. Pure.
 */
export function stripCdPrefixes(command: string): string {
  const CD_PREFIX = /^cd\s+[^&;]+(&&|;;?)\s*/;
  let stripped = command;
  let prev: string;
  do {
    prev = stripped;
    stripped = stripped.replace(CD_PREFIX, "");
  } while (stripped !== prev);
  return stripped;
}

/**
 * Checks whether an echo/printf command contains an unsafe file redirect.
 * Strips safe redirects (> /dev/... and > .../.rnd/...) first, then checks
 * if any > remains. Pure.
 */
export function checkEchoRedirect(stripped: string): "block" | "allow" {
  const withoutSafe = stripped
    .replace(/>\s*\/dev\/\S+\s*/g, "")
    .replace(/>\s*\S*\.rnd\/\S*\s*/g, "");
  return withoutSafe.includes(">") ? "block" : "allow";
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main(): Promise<void> {
  const input = await parseInput();
  if (!input) { process.exit(0); }

  const command = (input.tool_input["command"] as string | undefined) ?? "";
  if (!command) { console.log(JSON.stringify(allow())); process.exit(0); }

  // Auto-allow commands involving .rnd/ paths or rnd-dir.sh (not git add)
  const isGitAdd = /^git\s+add\b/.test(command);
  if (!isGitAdd && (command.includes(".rnd/") || command.includes("rnd-dir.sh"))) {
    console.log(JSON.stringify(allow())); process.exit(0);
  }

  const stripped = stripCdPrefixes(command);

  if (/^(sed|awk)\b/.test(stripped)) {
    block("Use the Edit tool instead of sed/awk. Edit is reviewable, diffable, and handles indentation correctly.");
  }
  if (/^(cat|head|tail)\b/.test(stripped)) {
    block("Use the Read tool instead of cat/head/tail. Read supports line offsets and limits natively.");
  }
  if (/^(grep|rg)\b/.test(stripped)) {
    block("Use the Grep tool instead of grep/rg. Grep supports regex, file globs, and output modes.");
  }
  if (/^find\b/.test(stripped)) {
    block("Use the Glob tool instead of find. Glob supports patterns like **/*.ts.");
  }
  if (/^(echo|printf)\b/.test(stripped)) {
    if (checkEchoRedirect(stripped) === "block") {
      block("Use the Write tool instead of echo/printf with file redirects. Write is reviewable and creates proper diffs.");
    }
    console.log(JSON.stringify(allow())); process.exit(0);
  }
  if (/git\s+add.*\.rnd(\/|\s|$)/.test(command)) {
    block("BLOCKED: .rnd/ is a pipeline artifact directory and must never be committed.");
  }
  console.log(JSON.stringify(allow()));
}

main();
