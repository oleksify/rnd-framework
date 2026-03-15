/**
 * Tests for hooks/post-compact
 *
 * Covers all success criteria from T2 pre-registration:
 *   1. Hook exits 0 and produces valid JSON when compact-state.json present
 *   2. stdout JSON contains hookSpecificOutput.additionalContext with pipeline state
 *   3. No stdout when compact-state.json is absent
 *   4. No stdout (exits 0) when compact-state.json is malformed
 *   5. hooks.json contains a PostCompact entry
 */

import { describe, it, expect } from "bun:test";
import { mkdtemp, mkdir, writeFile, rm, readFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { join, basename } from "node:path";
import { tmpdir } from "node:os";
import { runHook, runHookRaw } from "./helpers";

const HOOK_PATH = join(import.meta.dir, "..", "hooks", "post-compact");
const PLUGIN_ROOT = join(import.meta.dir, "..");
const HOOKS_JSON = join(PLUGIN_ROOT, "hooks", "hooks.json");

async function computeSlug(dir: string): Promise<string> {
  const proc = Bun.spawn(
    ["bash", "-c", 'printf "%s" "$TARGET_DIR" | shasum -a 256 | cut -c1-8'],
    { stdout: "pipe", stderr: "pipe", env: { ...process.env, TARGET_DIR: dir } },
  );
  const bytes = await Bun.readableStreamToArrayBuffer(proc.stdout);
  await proc.exited;
  return `${basename(dir)}-${new TextDecoder().decode(bytes).trim()}`;
}

interface TestEnv { configDir: string; sessionDir: string; cleanup: () => Promise<void>; }

async function createTestEnv(): Promise<TestEnv> {
  const configDir = await mkdtemp(join(tmpdir(), "post-compact-test-"));
  const slug = await computeSlug(process.cwd());
  const baseDir = join(configDir, ".rnd", slug);
  const sessionId = "20260305-120000-abcd";
  const sessionDir = join(baseDir, "sessions", sessionId);
  await mkdir(sessionDir, { recursive: true });
  await writeFile(join(baseDir, ".current-session"), sessionId, "utf-8");
  return {
    configDir,
    sessionDir,
    cleanup: async () => {
      if (existsSync(configDir)) await rm(configDir, { recursive: true, force: true });
    },
  };
}

const SAMPLE_STATE = {
  planSummary: "# Test Plan\nTask T1",
  currentTaskId: "T1",
  iterationCount: 3,
  savedAt: "2026-03-05T12:00:00Z",
};

async function writeState(dir: string, state: unknown = SAMPLE_STATE): Promise<void> {
  await writeFile(join(dir, "compact-state.json"), JSON.stringify(state), "utf-8");
}

describe("post-compact: hooks.json registration", () => {
  it("hooks.json has a PostCompact key", async () => {
    const raw = await readFile(HOOKS_JSON, "utf-8");
    const parsed = JSON.parse(raw) as Record<string, unknown>;
    expect((parsed["hooks"] as Record<string, unknown>)).toHaveProperty("PostCompact");
  });

  it("PostCompact entry references the post-compact script", async () => {
    const raw = await readFile(HOOKS_JSON, "utf-8");
    expect(raw).toContain("post-compact");
  });
});

describe("post-compact: compact-state.json present — exits 0 with valid JSON", () => {
  it("exits 0 when compact-state.json exists", async () => {
    const env = await createTestEnv();
    try {
      await writeState(env.sessionDir);
      const r = await runHook(HOOK_PATH, {}, { CLAUDE_CONFIG_DIR: env.configDir });
      expect(r.exitCode).toBe(0);
    } finally { await env.cleanup(); }
  });

  it("stdout is valid JSON when compact-state.json exists", async () => {
    const env = await createTestEnv();
    try {
      await writeState(env.sessionDir);
      const r = await runHook(HOOK_PATH, {}, { CLAUDE_CONFIG_DIR: env.configDir });
      expect(() => JSON.parse(r.stdout)).not.toThrow();
    } finally { await env.cleanup(); }
  });
});

describe("post-compact: stdout JSON has hookSpecificOutput.additionalContext", () => {
  it("stdout JSON has hookSpecificOutput.additionalContext key", async () => {
    const env = await createTestEnv();
    try {
      await writeState(env.sessionDir);
      const r = await runHook(HOOK_PATH, {}, { CLAUDE_CONFIG_DIR: env.configDir });
      const out = JSON.parse(r.stdout);
      expect(out).toHaveProperty("hookSpecificOutput");
      expect(out.hookSpecificOutput).toHaveProperty("additionalContext");
    } finally { await env.cleanup(); }
  });

  it("additionalContext mentions planSummary", async () => {
    const env = await createTestEnv();
    try {
      await writeState(env.sessionDir);
      const r = await runHook(HOOK_PATH, {}, { CLAUDE_CONFIG_DIR: env.configDir });
      const out = JSON.parse(r.stdout);
      expect(out.hookSpecificOutput.additionalContext).toContain("# Test Plan");
    } finally { await env.cleanup(); }
  });

  it("additionalContext mentions currentTaskId", async () => {
    const env = await createTestEnv();
    try {
      await writeState(env.sessionDir);
      const r = await runHook(HOOK_PATH, {}, { CLAUDE_CONFIG_DIR: env.configDir });
      const out = JSON.parse(r.stdout);
      expect(out.hookSpecificOutput.additionalContext).toContain("T1");
    } finally { await env.cleanup(); }
  });

  it("additionalContext mentions iterationCount", async () => {
    const env = await createTestEnv();
    try {
      await writeState(env.sessionDir);
      const r = await runHook(HOOK_PATH, {}, { CLAUDE_CONFIG_DIR: env.configDir });
      const out = JSON.parse(r.stdout);
      expect(out.hookSpecificOutput.additionalContext).toContain("3");
    } finally { await env.cleanup(); }
  });

  it("additionalContext mentions savedAt", async () => {
    const env = await createTestEnv();
    try {
      await writeState(env.sessionDir);
      const r = await runHook(HOOK_PATH, {}, { CLAUDE_CONFIG_DIR: env.configDir });
      const out = JSON.parse(r.stdout);
      expect(out.hookSpecificOutput.additionalContext).toContain("2026-03-05T12:00:00Z");
    } finally { await env.cleanup(); }
  });
});

describe("post-compact: no compact-state.json — exits 0 with no stdout", () => {
  it("exits 0 when compact-state.json is absent", async () => {
    const env = await createTestEnv();
    try {
      const r = await runHook(HOOK_PATH, {}, { CLAUDE_CONFIG_DIR: env.configDir });
      expect(r.exitCode).toBe(0);
    } finally { await env.cleanup(); }
  });

  it("produces no stdout when compact-state.json is absent", async () => {
    const env = await createTestEnv();
    try {
      const r = await runHook(HOOK_PATH, {}, { CLAUDE_CONFIG_DIR: env.configDir });
      expect(r.stdout.trim()).toBe("");
    } finally { await env.cleanup(); }
  });
});

describe("post-compact: malformed compact-state.json — exits 0 with no stdout", () => {
  it("exits 0 when compact-state.json is malformed", async () => {
    const env = await createTestEnv();
    try {
      await writeFile(join(env.sessionDir, "compact-state.json"), "not json!!", "utf-8");
      const r = await runHook(HOOK_PATH, {}, { CLAUDE_CONFIG_DIR: env.configDir });
      expect(r.exitCode).toBe(0);
    } finally { await env.cleanup(); }
  });

  it("produces no stdout when compact-state.json is malformed", async () => {
    const env = await createTestEnv();
    try {
      await writeFile(join(env.sessionDir, "compact-state.json"), "not json!!", "utf-8");
      const r = await runHook(HOOK_PATH, {}, { CLAUDE_CONFIG_DIR: env.configDir });
      expect(r.stdout.trim()).toBe("");
    } finally { await env.cleanup(); }
  });
});
