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
 * Splits a shell command string into individual segments for tool discipline
 * checking. Handles:
 *   - Shell operators: &&, ||, ;, |
 *   - Subshells: (cmd)
 *   - Command substitution: $(cmd)
 *   - Backtick substitution: `cmd`
 *
 * Each segment is the first "word" context that could be a prohibited command.
 * This is intentionally a best-effort split — it does not parse quoted strings
 * or heredocs. The hook is advisory, not a security sandbox, so false negatives
 * in pathological edge cases are acceptable.
 *
 * Pure.
 */
export function splitShellSegments(command: string): string[] {
  const results: string[] = [];

  // Step 1: extract all $(...) and `...` contents as additional candidates
  // This handles `echo $(grep ...)` → also checks `grep ...`
  const dollarParenContents = command.match(/\$\(([^)]*)\)/g) ?? [];
  for (const match of dollarParenContents) {
    // Strip $( and )
    results.push(match.slice(2, -1).trim());
  }

  const backtickContents = command.match(/`([^`]*)`/g) ?? [];
  for (const match of backtickContents) {
    // Strip backticks
    results.push(match.slice(1, -1).trim());
  }

  // Step 2: split the full command on shell operators: &&, ||, ;, |
  // Also split backtick delimiters (odd-indexed entries are inside backticks)
  const parts = command.split(/&&|\|\||;|\|/);

  for (const part of parts) {
    const trimmed = part.trim();
    // Strip leading ( to expose commands inside subshells
    const desubshell = trimmed.replace(/^\(+/, "").trim();
    // Strip trailing ) if it was a subshell
    const cleaned = desubshell.replace(/\)+$/, "").trim();
    if (cleaned.length > 0) {
      results.push(cleaned);
    }
  }

  return results.filter((s) => s.length > 0);
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

  // git add .rnd and git push checks operate on the full command string (not split)
  if (/git\s+add.*\.rnd(\/|\s|$)/.test(command)) {
    block("BLOCKED: .rnd/ is a pipeline artifact directory and must never be committed.");
  }
  if (/git\s+push\s+.*\b(main|master|production)\b/.test(command)) {
    block("BLOCKED: Direct push to main/master/production. Use a feature branch and PR instead.");
  }

  // Tool discipline checks — split into segments and check each independently.
  // These checks apply BEFORE the .rnd/ auto-allow so that tool discipline
  // overrides the auto-allow (e.g. `cat /path/.rnd/file` is still blocked).
  const segments = splitShellSegments(command);
  let hasEchoSegment = false;

  for (const seg of segments) {
    const stripped = stripCdPrefixes(seg);

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
      // echo/printf without unsafe redirect — flag for allow after full scan
      hasEchoSegment = true;
    }
  }

  // If any segment contains echo/printf without a bad redirect, and no other
  // segment triggered a block above, emit an allow for the whole command.
  if (hasEchoSegment) {
    console.log(JSON.stringify(allow())); process.exit(0);
  }

  // Auto-allow remaining commands involving .rnd/ paths or rnd-dir.sh
  // (placed after tool discipline so cat/sed on .rnd/ paths is still blocked)
  if (command.includes(".rnd/") || command.includes("rnd-dir.sh")) {
    console.log(JSON.stringify(allow())); process.exit(0);
  }

  // No opinion — let Claude Code default permission prompt handle everything else
}

try {
  await main();
} catch {
  process.exit(0);
}
