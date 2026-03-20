#!/usr/bin/env bun
import { resolve } from "node:path";
import { readdir } from "node:fs/promises";
import { resolveRndDir } from "./lib.ts";

interface RateEntry { used_percentage: number; resets_at: string }
interface RateLimits { fiveHour?: RateEntry; sevenDay?: RateEntry }
interface StatuslineInput { rate_limits?: RateLimits }

const buf = await Bun.readableStreamToArrayBuffer(Bun.stdin.stream());
const raw = new TextDecoder().decode(buf);
let input: StatuslineInput = {};
try { input = JSON.parse(raw) as StatuslineInput; } catch { /* ignore */ }

const rl = input.rate_limits ?? {};

async function hasMd(dir: string): Promise<boolean> {
  const files = await readdir(dir).catch(() => []);
  return files.some((f) => f.endsWith(".md"));
}

async function detectPhase(rndDir: string): Promise<string> {
  if (await hasMd(resolve(rndDir, "integration"))) return "Integrating";
  if (await hasMd(resolve(rndDir, "verifications"))) return "Verifying";
  if (await hasMd(resolve(rndDir, "builds"))) return "Building";
  if (await Bun.file(resolve(rndDir, "plan.md")).exists()) return "Planning";
  return "Idle";
}

const rndDir = resolveRndDir();
const phase = rndDir ? await detectPhase(rndDir) : "Idle";
const parts: string[] = [];
if (rl.fiveHour) parts.push(`5h: ${Math.round(rl.fiveHour.used_percentage)}%`);
if (rl.sevenDay) parts.push(`7d: ${Math.round(rl.sevenDay.used_percentage)}%`);

const ratePart = parts.length > 0 ? ` | ${parts.join(" | ")}` : "";
const text = `\u{1F52C} ${phase}${ratePart}`;

console.log(JSON.stringify({ text }));
process.exit(0);
