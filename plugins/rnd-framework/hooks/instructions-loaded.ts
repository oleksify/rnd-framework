#!/usr/bin/env bun
// hooks/instructions-loaded.ts — InstructionsLoaded hook for rnd-framework plugin.
// Reminds the orchestrator to run rnd-standards extraction when CLAUDE.md loads.

import { advisory } from "./lib.ts";

try {
  const msg = "Run /rnd-framework:rnd-standards to extract project coding rules before planning.";
  console.log(JSON.stringify(advisory(msg)));
} catch {
  process.exit(0);
}
