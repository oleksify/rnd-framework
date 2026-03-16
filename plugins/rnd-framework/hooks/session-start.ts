#!/usr/bin/env bun
import { resolve } from "node:path";
import { resolveRndDir } from "./lib.ts";

const PLUGIN_ROOT = resolve(import.meta.dir, "..");

const skillPath = resolve(PLUGIN_ROOT, "skills", "using-rnd-framework", "SKILL.md");
let skillContent: string;
try {
  skillContent = await Bun.file(skillPath).text();
} catch {
  skillContent = "Error reading using-rnd-framework skill";
}

const rndDir = resolveRndDir("-c") ?? "";

// Version mismatch check — read cached plugin version first
const cachedPluginPath = resolve(PLUGIN_ROOT, ".claude-plugin", "plugin.json");
let versionWarning = "";
let cachedVersion = "";
try {
  const cachedJson = await Bun.file(cachedPluginPath).json() as Record<string, string>;
  cachedVersion = cachedJson["version"] ?? "";
} catch { /* no version if reading fails */ }

if (cachedVersion) {
  const gitResult = Bun.spawnSync(["git", "rev-parse", "--show-toplevel"], { stderr: "ignore" });
  const gitRoot = gitResult.exitCode === 0
    ? new TextDecoder().decode(gitResult.stdout).trim() : "";
  const candidates = [
    `${gitRoot}/plugins/rnd-framework/.claude-plugin/plugin.json`,
    `${gitRoot}/rnd-framework/.claude-plugin/plugin.json`,
    `${gitRoot}/.claude-plugin/plugin.json`,
  ];
  for (const candidate of candidates) {
    const f = Bun.file(candidate);
    if (!await f.exists()) continue;
    const srcJson = await f.json() as Record<string, string>;
    if (srcJson["name"] !== "rnd-framework") continue;
    const srcVersion = srcJson["version"] ?? "";
    if (srcVersion && srcVersion !== cachedVersion) {
      versionWarning = `\n\n⚠ **Plugin version mismatch:** cached v${cachedVersion}, source v${srcVersion}. Run \`/plugin update rnd-framework@rnd-framework-plugins\` to sync.`;
    }
    break;
  }
}

const rndLine = rndDir
  ? `\n\n**RND_DIR (pipeline artifact directory for this project):** \`${rndDir}\``
  : "";

const ctx =
  `<EXTREMELY_IMPORTANT>\nYou have rnd-framework.\n\n` +
  `**Below is the full content of your 'rnd-framework:using-rnd-framework' skill` +
  ` - your introduction to using the R&D framework. For all other skills, use the 'Skill' tool:**\n\n` +
  `${skillContent}${rndLine}${versionWarning}\n\n</EXTREMELY_IMPORTANT>`;

console.log(JSON.stringify({
  additional_context: ctx,
  hookSpecificOutput: { hookEventName: "SessionStart", additionalContext: ctx },
}));
