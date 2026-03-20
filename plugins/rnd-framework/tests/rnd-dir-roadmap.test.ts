/**
 * Tests for --roadmap flag in lib/rnd-dir.sh
 *
 * Criterion: Running rnd-dir.sh --roadmap outputs an absolute path ending in
 * /roadmap.md at the project base level, without creating any files or dirs.
 */

import { describe, test, expect, beforeEach, afterEach } from "bun:test";
import { mkdtemp, rm } from "node:fs/promises";
import { existsSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";

const SCRIPT = join(import.meta.dir, "..", "lib", "rnd-dir.sh");

interface RunResult { stdout: string; stderr: string; exitCode: number; }

async function runScript(
  args: string[],
  opts: { cwd?: string; env?: Record<string, string> } = {},
): Promise<RunResult> {
  const baseEnv: Record<string, string> = {};
  for (const [k, v] of Object.entries(process.env)) {
    if (k !== "CLAUDE_PLUGIN_ROOT" && k !== "CLAUDE_CONFIG_DIR" && v !== undefined) {
      baseEnv[k] = v;
    }
  }
  const proc = Bun.spawn([SCRIPT, ...args], {
    cwd: opts.cwd,
    stdin: "ignore",
    stdout: "pipe",
    stderr: "pipe",
    env: { ...baseEnv, ...(opts.env ?? {}) },
  });
  const [outBuf, errBuf] = await Promise.all([
    Bun.readableStreamToArrayBuffer(proc.stdout),
    Bun.readableStreamToArrayBuffer(proc.stderr),
    proc.exited,
  ]);
  const dec = new TextDecoder();
  return { stdout: dec.decode(outBuf).trim(), stderr: dec.decode(errBuf).trim(), exitCode: proc.exitCode ?? 0 };
}

let configDir: string;
let projectDir: string;

beforeEach(async () => {
  configDir = await mkdtemp(join(tmpdir(), "rnd-test-config-"));
  projectDir = await mkdtemp(join(tmpdir(), "rnd-test-project-"));
});

afterEach(async () => {
  await rm(configDir, { recursive: true, force: true });
  await rm(projectDir, { recursive: true, force: true });
});

describe("--roadmap flag", () => {
  const env = () => ({ CLAUDE_CONFIG_DIR: configDir });

  test("exits 0 and outputs a path ending in /roadmap.md", async () => {
    const result = await runScript(["--roadmap"], { cwd: projectDir, env: env() });
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toMatch(/\/roadmap\.md$/);
  });

  test("output is at the project base level (<base>/roadmap.md)", async () => {
    const baseResult = await runScript(["--base"], { cwd: projectDir, env: env() });
    const result = await runScript(["--roadmap"], { cwd: projectDir, env: env() });
    expect(result.stdout).toBe(`${baseResult.stdout}/roadmap.md`);
  });

  test("output is an absolute path", async () => {
    const result = await runScript(["--roadmap"], { cwd: projectDir, env: env() });
    expect(result.stdout).toMatch(/^\//);
  });

  test("does not create the roadmap.md file", async () => {
    const baseResult = await runScript(["--base"], { cwd: projectDir, env: env() });
    await runScript(["--roadmap"], { cwd: projectDir, env: env() });
    expect(existsSync(`${baseResult.stdout}/roadmap.md`)).toBe(false);
  });

  test("does not create any directories", async () => {
    await runScript(["--roadmap"], { cwd: projectDir, env: env() });
    expect(existsSync(join(configDir, ".rnd"))).toBe(false);
  });
});
