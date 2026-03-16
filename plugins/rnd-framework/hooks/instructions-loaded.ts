#!/usr/bin/env bun
// hooks/instructions-loaded.ts — InstructionsLoaded hook for rnd-framework plugin.
// Reminds the orchestrator to run rnd-standards extraction when CLAUDE.md loads.

import { advisory } from "./lib.ts";

const msg = "Run /rnd-framework:rnd-standards to extract project coding rules before planning.";

process.stdout.write(JSON.stringify(advisory(msg)) + "\n");
process.exit(0);
