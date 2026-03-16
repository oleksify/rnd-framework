/**
 * T4: Tests for doc-polish enforcement language in start.md and quick.md
 *
 * Criteria:
 * 1. start.md contains "MANDATORY" and "DO NOT SKIP" in the doc-polish section
 * 2. start.md contains "You MUST invoke rnd-framework:rnd-doc-polish BEFORE presenting the commit options"
 * 3. quick.md contains the same enforcement language
 * 4. In both files, the MANDATORY line appears BEFORE AskUserQuestion in Phase 6 / PASS path
 */

import { describe, test, expect } from "bun:test";
import { readFile } from "node:fs/promises";
import { join } from "node:path";

const PLUGIN_ROOT = join(import.meta.dir, "..");
const START_MD = join(PLUGIN_ROOT, "commands", "start.md");
const QUICK_MD = join(PLUGIN_ROOT, "commands", "quick.md");
