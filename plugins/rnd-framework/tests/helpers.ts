/**
 * Test helpers for rnd-framework hook/library script testing.
 *
 * Exports:
 *   runHook(scriptPath, stdinJson?, env?)    — run a hook script as a subprocess
 *   runHookRaw(scriptPath, rawStdin?, env?)  — run a hook script with raw string stdin
 *   createTempRndDir()                       — create an isolated .rnd/-like temp tree
 */

import { mkdtemp, mkdir, writeFile, rm } from "node:fs/promises";
import { existsSync } from "node:fs";
import { join, basename } from "node:path";
import { tmpdir } from "node:os";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface HookResult {
  /** Combined stdout of the subprocess as a UTF-8 string. */
  stdout: string;
  /** Combined stderr of the subprocess as a UTF-8 string. */
  stderr: string;
  /** Process exit code (0 = success). */
  exitCode: number;
}

/**
 * Environment produced by createTestEnv() for hook integration tests.
 * configDir is a temp dir that acts as CLAUDE_CONFIG_DIR; env is ready to
 * pass to runHook() as the env argument.
 */
export interface TestEnv {
  configDir: string;
  baseDir: string;
  sessionDir: string;
  env: Record<string, string>;
  cleanup: () => Promise<void>;
}

export interface TempRndDir {
  /** Root of the temporary project-level .rnd directory, e.g. /tmp/rnd-xxxx */
  baseDir: string;
  /**
   * Active session directory: baseDir/sessions/YYYYMMDD-HHMMSS-XXXX
   * Contains builds/, verifications/, integration/ subdirectories.
   */
  sessionDir: string;
  /**
   * Removes the entire baseDir tree. Safe to call multiple times.
   */
  cleanup: () => Promise<void>;
}

// ---------------------------------------------------------------------------
// computeSlug
// ---------------------------------------------------------------------------

/**
 * Computes the slug used by rnd-dir.sh for a given directory path.
 * Format: <basename(dir)>-<first-8-hex-chars-of-sha256(dir)>
 */
export async function computeSlug(dir: string): Promise<string> {
  const proc = Bun.spawn(
    ["bash", "-c", 'printf "%s" "$TARGET_DIR" | shasum -a 256 | cut -c1-8'],
    { stdout: "pipe", stderr: "pipe", env: { ...process.env, TARGET_DIR: dir } },
  );
  const bytes = await Bun.readableStreamToArrayBuffer(proc.stdout);
  await proc.exited;
  const hash = new TextDecoder().decode(bytes).trim();
  return `${basename(dir)}-${hash}`;
}

// ---------------------------------------------------------------------------
// runHook
// ---------------------------------------------------------------------------

/**
 * Runs a hook/library script as a subprocess, optionally passing a JSON
 * object on stdin and injecting extra environment variables.
 *
 * The subprocess inherits the current process environment. Extra env vars
 * provided via the `env` parameter are merged on top (they can override
 * inherited values if keys collide).
 *
 * @param scriptPath  Absolute path to the executable script.
 * @param stdinJson   Optional value to serialize as JSON and write to stdin.
 * @param env         Optional extra environment variables for the subprocess.
 * @returns           { stdout, stderr, exitCode }
 */
export async function runHook(
  scriptPath: string,
  stdinJson?: unknown,
  env?: Record<string, string>,
): Promise<HookResult> {
  const mergedEnv: Record<string, string> = {
    ...process.env as Record<string, string>,
    ...(env ?? {}),
  };

  const proc = Bun.spawn([scriptPath], {
    stdin: stdinJson !== undefined ? "pipe" : "ignore",
    stdout: "pipe",
    stderr: "pipe",
    env: mergedEnv,
  });

  // Write JSON to stdin then close the write end so the script gets EOF
  if (stdinJson !== undefined && proc.stdin) {
    const encoded = new TextEncoder().encode(JSON.stringify(stdinJson));
    await proc.stdin.write(encoded);
    proc.stdin.end();
  }

  // Collect stdout and stderr concurrently while waiting for exit
  const [stdoutBytes, stderrBytes] = await Promise.all([
    Bun.readableStreamToArrayBuffer(proc.stdout),
    Bun.readableStreamToArrayBuffer(proc.stderr),
    proc.exited,
  ]);

  const decoder = new TextDecoder();

  return {
    stdout: decoder.decode(stdoutBytes),
    stderr: decoder.decode(stderrBytes),
    exitCode: proc.exitCode ?? 0,
  };
}

// ---------------------------------------------------------------------------
// runHookRaw
// ---------------------------------------------------------------------------

/**
 * Runs a hook/library script as a subprocess, passing a raw string directly
 * on stdin without any JSON serialization. Use this when you need to send
 * malformed JSON or other non-JSON payloads (e.g. empty string, plain text).
 *
 * The subprocess inherits the current process environment. Extra env vars
 * provided via the `env` parameter are merged on top (they can override
 * inherited values if keys collide).
 *
 * @param scriptPath  Absolute path to the executable script.
 * @param rawStdin    Optional raw string to write directly to stdin.
 * @param env         Optional extra environment variables for the subprocess.
 * @returns           { stdout, stderr, exitCode }
 */
export async function runHookRaw(
  scriptPath: string,
  rawStdin?: string,
  env?: Record<string, string>,
): Promise<HookResult> {
  const mergedEnv: Record<string, string> = {
    ...process.env as Record<string, string>,
    ...(env ?? {}),
  };

  const proc = Bun.spawn([scriptPath], {
    stdin: rawStdin !== undefined ? "pipe" : "ignore",
    stdout: "pipe",
    stderr: "pipe",
    env: mergedEnv,
  });

  // Write raw bytes to stdin then close the write end so the script gets EOF
  if (rawStdin !== undefined && proc.stdin) {
    const encoded = new TextEncoder().encode(rawStdin);
    await proc.stdin.write(encoded);
    proc.stdin.end();
  }

  // Collect stdout and stderr concurrently while waiting for exit
  const [stdoutBytes, stderrBytes] = await Promise.all([
    Bun.readableStreamToArrayBuffer(proc.stdout),
    Bun.readableStreamToArrayBuffer(proc.stderr),
    proc.exited,
  ]);

  const decoder = new TextDecoder();

  return {
    stdout: decoder.decode(stdoutBytes),
    stderr: decoder.decode(stderrBytes),
    exitCode: proc.exitCode ?? 0,
  };
}

// ---------------------------------------------------------------------------
// createTestEnv
// ---------------------------------------------------------------------------

/**
 * Creates an isolated temp environment mimicking rnd-dir.sh output.
 * opts.withSession=true creates the session tree and .current-session file.
 */
export async function createTestEnv(
  opts: { withSession?: boolean } = {},
): Promise<TestEnv> {
  const configDir = await mkdtemp(join(tmpdir(), "rnd-test-env-"));
  const slug = await computeSlug(process.cwd());
  const baseDir = join(configDir, ".rnd", slug);
  await mkdir(baseDir, { recursive: true });
  const sessionId = "20260305-120000-abcd";
  const sessionDir = join(baseDir, "sessions", sessionId);
  if (opts.withSession) {
    await mkdir(sessionDir, { recursive: true });
    await writeFile(join(baseDir, ".current-session"), sessionId, "utf-8");
  }
  const cleanup = async () => {
    if (existsSync(configDir)) await rm(configDir, { recursive: true, force: true });
  };
  return { configDir, baseDir, sessionDir, env: { CLAUDE_CONFIG_DIR: configDir }, cleanup };
}

// ---------------------------------------------------------------------------
// createTempRndDir
// ---------------------------------------------------------------------------

/**
 * Generates a session ID string in the YYYYMMDD-HHMMSS-XXXX format used by
 * rnd-dir.sh.
 */
function generateSessionId(): string {
  const now = new Date();
  const pad = (n: number, len = 2) => String(n).padStart(len, "0");
  const date =
    `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}`;
  const time =
    `${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`;
  const rand = Math.random().toString(16).slice(2, 6).padEnd(4, "0");
  return `${date}-${time}-${rand}`;
}

/**
 * Creates an isolated temporary directory tree that mirrors the .rnd/ layout
 * produced by lib/rnd-dir.sh:
 *
 *   <tmpdir>/rnd-XXXX/                   ← baseDir
 *   ├── .current-session                 ← contains session ID
 *   └── sessions/
 *       └── YYYYMMDD-HHMMSS-XXXX/       ← sessionDir
 *           ├── builds/
 *           ├── verifications/
 *           └── integration/
 *
 * The returned `cleanup()` function removes the entire baseDir tree.
 * Calling cleanup() more than once is safe (subsequent calls are no-ops).
 */
export async function createTempRndDir(): Promise<TempRndDir> {
  const sessionId = generateSessionId();

  // Create root temp dir  e.g. /tmp/rnd-abc123
  const baseDir = await mkdtemp(join(tmpdir(), "rnd-"));

  const sessionsDir = join(baseDir, "sessions");
  const sessionDir = join(sessionsDir, sessionId);

  // Create directory tree
  await mkdir(sessionsDir);
  await mkdir(sessionDir);
  for (const subdir of ["builds", "verifications", "integration"]) {
    await mkdir(join(sessionDir, subdir));
  }

  // Write .current-session marker
  await writeFile(join(baseDir, ".current-session"), sessionId, "utf-8");

  let cleaned = false;

  async function cleanup(): Promise<void> {
    if (cleaned) return;
    cleaned = true;
    if (existsSync(baseDir)) {
      await rm(baseDir, { recursive: true, force: true });
    }
  }

  return { baseDir, sessionDir, cleanup };
}

// ---------------------------------------------------------------------------
// Input builders
// ---------------------------------------------------------------------------

/** Write hook input payload (chunk-gate, slop-gate). */
export function writeInput(filePath: string, content: string): unknown {
  return { tool_name: "Write", tool_input: { file_path: filePath, content } };
}

/** Edit hook input payload. */
export function editInput(filePath: string, newString: string): unknown {
  return { tool_name: "Edit", tool_input: { file_path: filePath, new_string: newString } };
}

/** Read hook input payload (read-gate). */
export function readInput(filePath: string): unknown {
  return { tool_input: { file_path: filePath } };
}

/** Bash hook input payload (prefer-tools). */
export function bashInput(command: string): unknown {
  return { tool_input: { command } };
}

/** Generic hook payload with tool_name + file_path. */
export function hookInput(toolName: string, filePath: string): unknown {
  return { tool_name: toolName, tool_input: { file_path: filePath } };
}
