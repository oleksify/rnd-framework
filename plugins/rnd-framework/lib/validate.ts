#!/usr/bin/env bun
import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { join, basename, dirname } from "node:path";

export interface CategoryResult {
  name: string;
  pass: number;
  fail: number;
}

export interface ValidateResult {
  passes: number;
  errors: number;
  output: string;
}

export class CategoryTracker {
  categories: CategoryResult[] = [];
  passes = 0;
  errors = 0;
  lines: string[] = [];
  private quiet: boolean;

  constructor(quiet: boolean) { this.quiet = quiet; }

  beginCategory(name: string): void {
    if (this.categories.length > 0 && !this.quiet) this.lines.push("");
    this.categories.push({ name, pass: 0, fail: 0 });
    if (!this.quiet) this.lines.push(`=== ${name} ===`);
  }

  pass(msg: string): void {
    if (!this.quiet) this.lines.push(`  PASS  ${msg}`);
    this.passes++;
    this.categories[this.categories.length - 1].pass++;
  }

  fail(msg: string): void {
    if (!this.quiet) this.lines.push(`  FAIL  ${msg}`);
    this.errors++;
    this.categories[this.categories.length - 1].fail++;
  }
}

/**
 * Extract a frontmatter value by key.
 * Returns empty string if file missing, key absent, or not in frontmatter.
 */
export function frontmatterVal(filePath: string, key: string): string {
  if (!existsSync(filePath)) return "";
  const content = readFileSync(filePath, "utf8");
  const parts = content.split(/^---$/m);
  if (parts.length < 3) return "";
  const fm = parts[1];
  for (const line of fm.split("\n")) {
    const m = line.match(new RegExp(`^${key}:\\s*(.*)$`));
    if (m) {
      return m[1].trim().replace(/^["']|["']$/g, "");
    }
  }
  return "";
}

function isExecutable(path: string): boolean {
  return (statSync(path).mode & 0o111) !== 0;
}

function validateManifest(t: CategoryTracker, pluginRoot: string): void {
  t.beginCategory("Manifest");
  const pjson = join(pluginRoot, ".claude-plugin", "plugin.json");
  if (!existsSync(pjson)) { t.fail(`plugin.json not found at ${pjson}`); return; }
  let parsed: Record<string, string>;
  try {
    parsed = JSON.parse(readFileSync(pjson, "utf8"));
    t.pass("plugin.json is valid JSON");
  } catch {
    t.fail("plugin.json is not valid JSON"); return;
  }
  for (const field of ["name", "description", "version"]) {
    const val = parsed[field];
    if (val) t.pass(`plugin.json has '${field}': ${val}`);
    else t.fail(`plugin.json missing '${field}'`);
  }
  const ver = parsed["version"] ?? "";
  if (/^\d+\.\d+\.\d+$/.test(ver)) t.pass("plugin.json version is valid semver");
  else t.fail(`plugin.json version '${ver}' is not valid semver (expected X.Y.Z)`);
}

function validateHooks(t: CategoryTracker, pluginRoot: string): void {
  t.beginCategory("Hooks");
  const hjson = join(pluginRoot, "hooks", "hooks.json");
  if (!existsSync(hjson)) { t.fail(`hooks.json not found at ${hjson}`); return; }
  let raw: string;
  try { raw = readFileSync(hjson, "utf8"); JSON.parse(raw); t.pass("hooks.json is valid JSON"); }
  catch { t.fail("hooks.json is not valid JSON"); return; }
  const refs = new Set<string>();
  for (const m of raw.matchAll(/hooks\/[a-z_.-]+/g)) refs.add(m[0]);
  for (const ref of [...refs].sort()) {
    const scriptPath = join(pluginRoot, ref);
    const name = basename(ref);
    if (!existsSync(scriptPath)) { t.fail(`hook script '${name}' not found at ${scriptPath}`); continue; }
    t.pass(`hook script '${name}' exists`);
    if (isExecutable(scriptPath)) t.pass(`hook script '${name}' is executable`);
    else t.fail(`hook script '${name}' is not executable`);
  }
  const slopCatalog = join(pluginRoot, "slop-patterns.json");
  if (!existsSync(slopCatalog)) { t.fail(`slop-patterns.json not found at ${slopCatalog}`); return; }
  try { JSON.parse(readFileSync(slopCatalog, "utf8")); t.pass("slop-patterns.json exists and is valid JSON"); }
  catch { t.fail("slop-patterns.json is not valid JSON"); }
}

function validateSkills(t: CategoryTracker, pluginRoot: string): void {
  t.beginCategory("Skills");
  const skillsDir = join(pluginRoot, "skills");
  let count = 0;
  if (!existsSync(skillsDir)) { t.lines.push(`  (0 skills found)`); return; }
  for (const entry of readdirSync(skillsDir, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue;
    const dirName = entry.name;
    const skillFile = join(skillsDir, dirName, "SKILL.md");
    if (!existsSync(skillFile)) { t.fail(`skill '${dirName}' missing SKILL.md`); continue; }
    count++;
    const firstLine = readFileSync(skillFile, "utf8").split("\n")[0];
    if (firstLine !== "---") { t.fail(`skill '${dirName}' missing frontmatter (no opening ---)`); continue; }
    const nameVal = frontmatterVal(skillFile, "name");
    const descVal = frontmatterVal(skillFile, "description");
    if (!nameVal) t.fail(`skill '${dirName}' missing 'name' in frontmatter`);
    else if (nameVal === dirName) t.pass(`skill '${dirName}' name matches directory`);
    else t.fail(`skill '${dirName}' name mismatch: frontmatter says '${nameVal}'`);
    if (descVal) t.pass(`skill '${dirName}' has description`);
    else t.fail(`skill '${dirName}' missing 'description' in frontmatter`);
  }
  t.lines.push(`  (${count} skills found)`);
}

export const VALID_TOOLS = new Set([
  "Read","Write","Edit","Bash","Glob","Grep","NotebookRead","NotebookEdit",
  "WebFetch","WebSearch","Agent","TodoWrite","AskUserQuestion",
  "TaskCreate","TaskGet","TaskUpdate","TaskList","TaskOutput","TaskStop",
  "Skill","SendMessage","EnterPlanMode","ExitPlanMode","ToolSearch",
  "EnterWorktree","ExitWorktree","TeamCreate","TeamDelete","LSP",
  "CronCreate","CronDelete","CronList",
]);

export const VALID_MODELS = new Set(["opus", "sonnet", "haiku"]);

function checkTools(t: CategoryTracker, agentName: string, toolsVal: string): boolean {
  const tools = toolsVal.split(/[, ]+/).map(s => s.trim()).filter(Boolean);
  let allValid = true;
  for (const tool of tools) {
    if (!VALID_TOOLS.has(tool)) { t.fail(`agent '${agentName}' has unknown tool '${tool}'`); allValid = false; }
  }
  if (allValid) t.pass(`agent '${agentName}' tools are valid: ${toolsVal}`);
  return allValid;
}

function checkDisallowedTools(t: CategoryTracker, agentName: string, val: string): void {
  const tools = val.split(/[, ]+/).map(s => s.trim()).filter(Boolean);
  let allValid = true;
  for (const tool of tools) {
    if (!VALID_TOOLS.has(tool)) { t.fail(`agent '${agentName}' has unknown disallowed tool '${tool}'`); allValid = false; }
  }
  if (allValid) t.pass(`agent '${agentName}' disallowedTools are valid: ${val}`);
}

function checkAgentOptionalFields(t: CategoryTracker, filePath: string, agentName: string): void {
  const memoryVal = frontmatterVal(filePath, "memory");
  if (memoryVal) {
    if (["user", "project", "local"].includes(memoryVal))
      t.pass(`agent '${agentName}' memory scope is valid: ${memoryVal}`);
    else t.fail(`agent '${agentName}' has invalid memory scope '${memoryVal}'`);
  }
  const colorVal = frontmatterVal(filePath, "color");
  if (colorVal) t.pass(`agent '${agentName}' has color: ${colorVal}`);
  const skillsVal = frontmatterVal(filePath, "skills");
  if (skillsVal) t.pass(`agent '${agentName}' has skills: ${skillsVal}`);
  const disallowedVal = frontmatterVal(filePath, "disallowedTools");
  if (disallowedVal) checkDisallowedTools(t, agentName, disallowedVal);
  const permVal = frontmatterVal(filePath, "permissionMode");
  if (permVal) {
    if (permVal === "bypassPermissions") t.pass(`agent '${agentName}' permissionMode is valid: ${permVal}`);
    else t.fail(`agent '${agentName}' has invalid permissionMode '${permVal}'`);
  }
}

function validateOneAgent(t: CategoryTracker, filePath: string, agentName: string): void {
  const firstLine = readFileSync(filePath, "utf8").split("\n")[0];
  if (firstLine !== "---") { t.fail(`agent '${agentName}' missing frontmatter`); return; }
  const nameVal = frontmatterVal(filePath, "name");
  if (nameVal === agentName) t.pass(`agent '${agentName}' name matches filename`);
  else if (nameVal) t.fail(`agent '${agentName}' name mismatch: frontmatter says '${nameVal}'`);
  else t.fail(`agent '${agentName}' missing 'name'`);
  const descVal = frontmatterVal(filePath, "description");
  if (descVal) t.pass(`agent '${agentName}' has description`);
  else t.fail(`agent '${agentName}' missing 'description'`);
  const toolsVal = frontmatterVal(filePath, "tools");
  if (toolsVal) checkTools(t, agentName, toolsVal);
  else t.fail(`agent '${agentName}' missing 'tools'`);
  const modelVal = frontmatterVal(filePath, "model");
  if (modelVal && VALID_MODELS.has(modelVal)) t.pass(`agent '${agentName}' model is valid: ${modelVal}`);
  else if (modelVal) t.fail(`agent '${agentName}' has unknown model '${modelVal}'`);
  else t.fail(`agent '${agentName}' missing 'model'`);
  checkAgentOptionalFields(t, filePath, agentName);
}

function validateAgents(t: CategoryTracker, pluginRoot: string): void {
  t.beginCategory("Agents");
  const agentsDir = join(pluginRoot, "agents");
  let count = 0;
  if (!existsSync(agentsDir)) { t.lines.push(`  (0 agents found)`); return; }
  for (const entry of readdirSync(agentsDir).filter(f => f.endsWith(".md"))) {
    count++;
    validateOneAgent(t, join(agentsDir, entry), entry.replace(/\.md$/, ""));
  }
  t.lines.push(`  (${count} agents found)`);
}

function validateCommands(t: CategoryTracker, pluginRoot: string): void {
  t.beginCategory("Commands");
  const cmdsDir = join(pluginRoot, "commands");
  let count = 0;
  if (!existsSync(cmdsDir)) { t.lines.push(`  (0 commands found)`); return; }
  for (const entry of readdirSync(cmdsDir).filter(f => f.endsWith(".md"))) {
    count++;
    const filePath = join(cmdsDir, entry);
    const cmdName = entry.replace(/\.md$/, "");
    const firstLine = readFileSync(filePath, "utf8").split("\n")[0];
    if (firstLine !== "---") { t.fail(`command '${cmdName}' missing frontmatter`); continue; }
    const descVal = frontmatterVal(filePath, "description");
    if (descVal) t.pass(`command '${cmdName}' has description`);
    else t.fail(`command '${cmdName}' missing 'description'`);
    const content = readFileSync(filePath, "utf8");
    const usesArgs = content.includes("$ARGUMENTS");
    const hintVal = frontmatterVal(filePath, "argument-hint");
    if (usesArgs && !hintVal) t.fail(`command '${cmdName}' uses $ARGUMENTS but missing 'argument-hint'`);
    else if (!usesArgs && hintVal) t.fail(`command '${cmdName}' has 'argument-hint' but never uses $ARGUMENTS`);
    else if (usesArgs && hintVal) t.pass(`command '${cmdName}' has argument-hint`);
    const modelVal = frontmatterVal(filePath, "model");
    if (modelVal && VALID_MODELS.has(modelVal)) t.pass(`command '${cmdName}' model is valid: ${modelVal}`);
    else if (modelVal) t.fail(`command '${cmdName}' has invalid model '${modelVal}'`);
  }
  t.lines.push(`  (${count} commands found)`);
}

function validateOutputStyles(t: CategoryTracker, pluginRoot: string): void {
  t.beginCategory("Output Styles");
  const stylesDir = join(pluginRoot, "output-styles");
  let count = 0;
  if (!existsSync(stylesDir)) { t.lines.push(`  (0 output styles found)`); return; }
  for (const entry of readdirSync(stylesDir).filter(f => f.endsWith(".md"))) {
    count++;
    const filePath = join(stylesDir, entry);
    const styleName = entry.replace(/\.md$/, "");
    const firstLine = readFileSync(filePath, "utf8").split("\n")[0];
    if (firstLine !== "---") { t.fail(`output-style '${styleName}' missing frontmatter`); continue; }
    const nameVal = frontmatterVal(filePath, "name");
    if (nameVal) t.pass(`output-style '${styleName}' has name: ${nameVal}`);
    else t.fail(`output-style '${styleName}' missing 'name'`);
    const descVal = frontmatterVal(filePath, "description");
    if (descVal) t.pass(`output-style '${styleName}' has description`);
    else t.fail(`output-style '${styleName}' missing 'description'`);
  }
  t.lines.push(`  (${count} output styles found)`);
}

function validateProofs(t: CategoryTracker, pluginRoot: string): void {
  t.beginCategory("Proofs");
  const proofsDir = join(pluginRoot, "proofs");
  if (!existsSync(proofsDir)) { t.pass("no proofs/ directory (skipped)"); return; }
  const leanAvail = Bun.spawnSync(["which", "lean"]).exitCode === 0;
  const lakeAvail = Bun.spawnSync(["which", "lake"]).exitCode === 0;
  if (!leanAvail || !lakeAvail) { t.pass("proofs/ exists (skipped — lean not available)"); return; }
  const result = Bun.spawnSync(["lake", "build"], { cwd: proofsDir });
  if (result.exitCode === 0) t.pass("lake build exits 0 (all proofs compile)");
  else t.fail("lake build failed in proofs/");
}

function validateLibScripts(t: CategoryTracker, pluginRoot: string): void {
  t.beginCategory("Lib Scripts");
  for (const libScript of ["rnd-dir.sh", "bump.sh"]) {
    const scriptPath = join(pluginRoot, "lib", libScript);
    if (!existsSync(scriptPath)) { t.fail(`lib/${libScript} not found`); continue; }
    t.pass(`lib/${libScript} exists`);
    if (isExecutable(scriptPath)) t.pass(`lib/${libScript} is executable`);
    else t.fail(`lib/${libScript} is not executable`);
  }
}

function getValidSkills(pluginRoot: string): Set<string> {
  const skillsDir = join(pluginRoot, "skills");
  const result = new Set<string>();
  if (!existsSync(skillsDir)) return result;
  for (const entry of readdirSync(skillsDir, { withFileTypes: true }))
    if (entry.isDirectory()) result.add(entry.name);
  return result;
}

// Check backtick-wrapped skill refs: `rnd-framework:name`
function checkUrfmSkillRefs(t: CategoryTracker, filePath: string, validSkills: Set<string>): number {
  if (!existsSync(filePath)) return 0;
  const content = readFileSync(filePath, "utf8");
  const refs = new Set<string>();
  for (const m of content.matchAll(/`rnd-framework:([a-z-]+)`/g)) refs.add(m[1]);
  let count = 0;
  for (const refName of [...refs].sort()) {
    count++;
    const fullRef = `rnd-framework:${refName}`;
    if (validSkills.has(refName)) t.pass(`using-rnd-framework skill ref '${fullRef}' resolves`);
    else t.fail(`using-rnd-framework skill ref '${fullRef}' — skill '${refName}' not found`);
  }
  return count;
}

// Check skill refs in agent files: rnd-framework:[a-z-]+
function checkAgentSkillRefs(t: CategoryTracker, filePath: string, agentName: string, validSkills: Set<string>): number {
  if (!existsSync(filePath)) return 0;
  const content = readFileSync(filePath, "utf8");
  const refs = new Set<string>();
  for (const m of content.matchAll(/(?<!\/)rnd-framework:([a-z-]+)/g)) refs.add(m[1]);
  let count = 0;
  for (const refName of [...refs].sort()) {
    count++;
    const fullRef = `rnd-framework:${refName}`;
    if (validSkills.has(refName)) t.pass(`agent '${agentName}' skill ref '${fullRef}' resolves`);
    else t.fail(`agent '${agentName}' skill ref '${fullRef}' — skill '${refName}' not found`);
  }
  return count;
}

// Check rnd-framework:rnd-* refs in command files against agents + skills
function checkCommandRefs(t: CategoryTracker, filePath: string, cmdName: string, validAgents: Set<string>, validSkillRefs: Set<string>): number {
  if (!existsSync(filePath)) return 0;
  const content = readFileSync(filePath, "utf8");
  const refs = new Set<string>();
  for (const m of content.matchAll(/rnd-framework:rnd-([a-z-]+)/g)) refs.add(`rnd-framework:rnd-${m[1]}`);
  let count = 0;
  for (const fullRef of [...refs].sort()) {
    count++;
    if (validAgents.has(fullRef)) t.pass(`command '${cmdName}' agent ref '${fullRef}' resolves`);
    else if (validSkillRefs.has(fullRef)) t.pass(`command '${cmdName}' skill ref '${fullRef}' resolves`);
    else t.fail(`command '${cmdName}' agent ref '${fullRef}' — agent not found`);
  }
  return count;
}

function validateCrossRefs(t: CategoryTracker, pluginRoot: string): void {
  t.beginCategory("Cross-References");
  const validSkills = getValidSkills(pluginRoot);
  const validAgents = new Set<string>();
  const validSkillRefs = new Set<string>();
  const agentsDir = join(pluginRoot, "agents");
  if (existsSync(agentsDir))
    for (const f of readdirSync(agentsDir).filter(f => f.endsWith(".md")))
      validAgents.add(`rnd-framework:${f.replace(/\.md$/, "")}`);
  for (const s of validSkills) validSkillRefs.add(`rnd-framework:${s}`);
  let xrefCount = 0;
  const urfm = join(pluginRoot, "skills", "using-rnd-framework", "SKILL.md");
  xrefCount += checkUrfmSkillRefs(t, urfm, validSkills);
  if (existsSync(agentsDir))
    for (const f of readdirSync(agentsDir).filter(f => f.endsWith(".md")))
      xrefCount += checkAgentSkillRefs(t, join(agentsDir, f), f.replace(/\.md$/, ""), validSkills);
  const cmdsDir = join(pluginRoot, "commands");
  if (existsSync(cmdsDir))
    for (const f of readdirSync(cmdsDir).filter(f => f.endsWith(".md")))
      xrefCount += checkCommandRefs(t, join(cmdsDir, f), f.replace(/\.md$/, ""), validAgents, validSkillRefs);
  t.lines.push(`  (${xrefCount} cross-references checked)`);
}

export const PARITY_TABLE: [string, string, string, string][] = [
  ["skills/rnd-decomposition/SKILL.md","agents/rnd-planner.md","External dependencies","pre-registration field"],
  ["skills/rnd-building/SKILL.md","agents/rnd-builder.md","erify external dependencies","step 2.5"],
  ["skills/rnd-building/SKILL.md","agents/rnd-builder.md","Verified external assumptions","self-assessment sub-section"],
  ["skills/rnd-building/SKILL.md","agents/rnd-builder.md","Unverified external assumptions","self-assessment sub-section"],
  ["skills/rnd-verification/SKILL.md","agents/rnd-verifier.md","External contract conformance","failure mode analysis"],
  ["skills/rnd-verification/SKILL.md","agents/rnd-verifier.md","assumptions about external systems","code inspection"],
  ["skills/rnd-verification/SKILL.md","agents/rnd-verifier.md","ulti-Judge","multi-judge consensus protocol"],
  ["skills/rnd-decomposition/SKILL.md","agents/rnd-planner.md","ocal expert","local expert field parity"],
  ["skills/rnd-data-science/SKILL.md","agents/rnd-data-scientist.md","mcp__julia__julia_eval","Julia MCP tool reference"],
  ["skills/rnd-data-science/SKILL.md","agents/rnd-data-scientist.md","Validate input data","data validation requirement"],
  ["skills/rnd-data-science/SKILL.md","agents/rnd-data-scientist.md","independent cross-check","numerical verification approach"],
  ["skills/rnd-data-science/SKILL.md","agents/rnd-data-scientist.md","never hardcode","no intermediate value hardcoding rule"],
  ["skills/rnd-data-science/SKILL.md","agents/rnd-data-scientist.md","read_csv","DuckDB CSV function reference"],
  ["skills/rnd-data-science/SKILL.md","agents/rnd-data-scientist.md","duckdb -c","DuckDB CLI invocation pattern"],
  ["skills/rnd-data-science/SKILL.md","agents/rnd-data-scientist.md","Tool Selection","DuckDB vs Julia decision table"],
  ["skills/rnd-multi-judge/SKILL.md","commands/verify.md","judge-a.md","multi-judge judge-a file naming"],
  ["skills/rnd-multi-judge/SKILL.md","commands/verify.md","judge-b.md","multi-judge judge-b file naming"],
  ["skills/rnd-multi-judge/SKILL.md","commands/verify.md","tiebreaker.md","multi-judge tiebreaker file naming"],
  ["skills/rnd-multi-judge/SKILL.md","commands/start.md","judge-a.md","multi-judge judge-a file naming in start"],
  ["skills/rnd-multi-judge/SKILL.md","commands/start.md","judge-b.md","multi-judge judge-b file naming in start"],
  ["skills/rnd-multi-judge/SKILL.md","commands/start.md","tiebreaker.md","multi-judge tiebreaker file naming in start"],
  ["skills/rnd-multi-judge/SKILL.md","commands/verify.md","Consensus method","multi-judge consensus method field"],
  ["skills/rnd-local-experts/SKILL.md","commands/start.md",".claude/agents/","local expert agents discovery path"],
  ["skills/rnd-local-experts/SKILL.md","commands/start.md",".claude/skills/","local expert skills discovery path"],
  ["skills/rnd-local-experts/SKILL.md","commands/start.md","Local Experts Discovered","local expert discovery summary field"],
  ["skills/rnd-local-experts/SKILL.md","agents/rnd-planner.md","Local Experts Discovered","local expert discovery field in planner"],
  ["skills/rnd-local-experts/SKILL.md","skills/rnd-decomposition/SKILL.md","ocal expert","local expert field in decomposition skill"],
  ["skills/rnd-failure-modes/SKILL.md","agents/rnd-verifier.md","failure modes","failure modes catalog reference in verifier"],
  ["skills/rnd-failure-modes/SKILL.md","skills/rnd-verification/SKILL.md","failure modes","failure modes catalog reference in verification skill"],
  ["skills/rnd-building/SKILL.md","agents/rnd-builder.md","DONE_WITH_CONCERNS","builder status code DONE_WITH_CONCERNS parity"],
  ["skills/rnd-building/SKILL.md","agents/rnd-builder.md","NEEDS_CONTEXT","builder status code NEEDS_CONTEXT parity"],
  ["skills/rnd-decomposition/SKILL.md","agents/rnd-planner.md","Correctness:","tiered criteria Correctness marker in planner"],
  ["skills/rnd-slop-detection/SKILL.md","slop-patterns.json","over-commenting","slop skill and catalog share over-commenting category"],
  ["skills/rnd-slop-detection/SKILL.md","slop-patterns.json","error-handling","slop skill and catalog share error-handling category"],
  ["skills/rnd-slop-detection/SKILL.md","slop-patterns.json","hygiene","slop skill and catalog share hygiene category"],
  ["hooks/slop-gate.ts","slop-patterns.json","severity","slop-gate hook and catalog share severity field schema"],
  ["skills/rnd-slop-detection/SKILL.md","hooks/slop-gate.ts","PASS","slop skill and hook share PASS verdict"],
  ["skills/rnd-slop-detection/SKILL.md","hooks/slop-gate.ts","WARN","slop skill and hook share WARN verdict"],
  ["skills/rnd-slop-detection/SKILL.md","hooks/slop-gate.ts","FAIL","slop skill and hook share FAIL verdict"],
  ["skills/rnd-building/SKILL.md","agents/rnd-builder.md","Evidence Gathered","evidence gathering manifest section parity"],
  ["skills/rnd-verification/SKILL.md","agents/rnd-verifier.md","Evidence Gathered","evidence grounding verification parity"],
];

function validateContentParity(t: CategoryTracker, pluginRoot: string): void {
  t.beginCategory("Content Parity");
  for (const [skillRel, agentRel, marker, desc] of PARITY_TABLE) {
    const skillFile = join(pluginRoot, skillRel);
    const agentFile = join(pluginRoot, agentRel);
    const skillName = basename(dirname(skillRel));
    const agentName = basename(agentRel, ".md");
    const markerLow = marker.toLowerCase();
    const skillHas = existsSync(skillFile) &&
      readFileSync(skillFile, "utf8").toLowerCase().includes(markerLow);
    const agentHas = existsSync(agentFile) &&
      readFileSync(agentFile, "utf8").toLowerCase().includes(markerLow);
    if (skillHas && agentHas)
      t.pass(`parity: '${marker}' in ${skillName} and ${agentName} (${desc})`);
    else if (skillHas && !agentHas)
      t.fail(`parity: '${marker}' in ${skillName} but missing in ${agentName}`);
    else if (!skillHas && agentHas)
      t.fail(`parity: '${marker}' in ${agentName} but missing in ${skillName}`);
    else
      t.fail(`parity: '${marker}' missing in both ${skillName} and ${agentName}`);
  }
}

function buildSummary(t: CategoryTracker): string[] {
  const lines: string[] = ["", "=== Summary ===", ""];
  const fmt = (cat: string, p: string | number, f: string | number, s: string) =>
    `  ${cat.padEnd(20)} ${String(p).padStart(6)} ${String(f).padStart(6)}   ${s}`;
  lines.push(fmt("Category", "Pass", "Fail", "Status"));
  lines.push(fmt("────────────────────", "──────", "──────", "──────"));
  for (const cat of t.categories)
    lines.push(fmt(cat.name, cat.pass, cat.fail, cat.fail > 0 ? "FAIL" : "ok"));
  lines.push(`  ${"────────────────────".padEnd(20)} ${"──────".padStart(6)} ${"──────".padStart(6)}`);
  lines.push(`  ${"Total".padEnd(20)} ${String(t.passes).padStart(6)} ${String(t.errors).padStart(6)}`);
  lines.push("");
  if (t.errors > 0) lines.push(`  ${t.errors} check(s) failed.`);
  else lines.push(`  All ${t.passes} checks passed.`);
  return lines;
}

export function validate(pluginRoot: string, quiet: boolean): ValidateResult {
  const t = new CategoryTracker(quiet);
  validateManifest(t, pluginRoot);
  validateHooks(t, pluginRoot);
  validateSkills(t, pluginRoot);
  validateAgents(t, pluginRoot);
  validateCommands(t, pluginRoot);
  validateOutputStyles(t, pluginRoot);
  validateProofs(t, pluginRoot);
  validateLibScripts(t, pluginRoot);
  validateCrossRefs(t, pluginRoot);
  validateContentParity(t, pluginRoot);
  const summary = buildSummary(t);
  const allLines = [...t.lines, ...summary];
  return { passes: t.passes, errors: t.errors, output: allLines.join("\n") };
}

if (import.meta.main) {
  const quiet = process.argv.includes("--quiet");
  const scriptDir = new URL(".", import.meta.url).pathname.replace(/\/$/, "");
  const pluginRoot = scriptDir.replace(/\/lib$/, "");
  const result = validate(pluginRoot, quiet);
  process.stdout.write(result.output + "\n");
  process.exit(result.errors > 0 ? 1 : 0);
}
