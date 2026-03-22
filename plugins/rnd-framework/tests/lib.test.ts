import { test, expect } from "bun:test";
import { join } from "node:path";
import { CODE_EXTENSIONS, isCodeFile, isRndPath, isPluginCachePath, allow, advisory, countLines } from "../hooks/lib.ts";

const PLUGIN_ROOT = join(import.meta.dir, "..");
const LIB_SCRIPT = join(PLUGIN_ROOT, "hooks", "lib.ts");

// ---------------------------------------------------------------------------
// CODE_EXTENSIONS
// ---------------------------------------------------------------------------

test("CODE_EXTENSIONS is a Set containing .ts", () => {
  expect(CODE_EXTENSIONS).toBeInstanceOf(Set);
  expect(CODE_EXTENSIONS.has(".ts")).toBe(true);
});

// ---------------------------------------------------------------------------
// isCodeFile
// ---------------------------------------------------------------------------

test("isCodeFile returns true for .ts", () => expect(isCodeFile("foo.ts")).toBe(true));
test("isCodeFile returns true for .py", () => expect(isCodeFile("foo.py")).toBe(true));
test("isCodeFile returns false for .md", () => expect(isCodeFile("foo.md")).toBe(false));
test("isCodeFile returns false for no extension", () => expect(isCodeFile("foobar")).toBe(false));
test("isCodeFile is case-insensitive", () => expect(isCodeFile("foo.TS")).toBe(true));

// ---------------------------------------------------------------------------
// isRndPath
// ---------------------------------------------------------------------------

test("isRndPath returns true for .claude/.rnd/ path", () =>
  expect(isRndPath("/Users/me/.claude/.rnd/project/sessions/abc/plan.md")).toBe(true));
test("isRndPath returns true for .claude-personal/.rnd/ path", () =>
  expect(isRndPath("/Users/me/.claude-personal/.rnd/project/sessions/abc/plan.md")).toBe(true));
test("isRndPath returns false for .rnd/ without .claude prefix", () =>
  expect(isRndPath("/tmp/attacker/.rnd/fake/plan.md")).toBe(false));
test("isRndPath returns false for path without .rnd/", () =>
  expect(isRndPath("/foo/bar")).toBe(false));
test("isRndPath returns false for .rnd with no trailing slash", () =>
  expect(isRndPath("/Users/me/.claude/.rnd")).toBe(false));

// ---------------------------------------------------------------------------
// isPluginCachePath
// ---------------------------------------------------------------------------

test("isPluginCachePath returns true for .claude-personal plugin cache path", () =>
  expect(isPluginCachePath("/Users/me/.claude-personal/plugins/cache/rnd-framework-plugins/rnd-framework/0.10.9/skills/foo/SKILL.md")).toBe(true));
test("isPluginCachePath returns true for .claude plugin cache path", () =>
  expect(isPluginCachePath("/Users/me/.claude/plugins/cache/something/file.md")).toBe(true));
test("isPluginCachePath returns false for unrelated absolute path", () =>
  expect(isPluginCachePath("/Users/me/project/src/index.ts")).toBe(false));
test("isPluginCachePath returns false for plugins/cache/ without .claude prefix", () =>
  expect(isPluginCachePath("/tmp/malicious/plugins/cache/data.json")).toBe(false));
test("isPluginCachePath returns false for relative path with plugins/cache/", () =>
  expect(isPluginCachePath("plugins/cache/something")).toBe(false));
test("isPluginCachePath returns false when cache has no trailing slash", () =>
  expect(isPluginCachePath("/Users/me/.claude-personal/plugins/cachebreaker/foo")).toBe(false));

// ---------------------------------------------------------------------------
// allow
// ---------------------------------------------------------------------------

test("allow returns correct PreToolUse allow object", () => {
  expect(allow()).toEqual({
    hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: "allow" },
  });
});

// ---------------------------------------------------------------------------
// advisory
// ---------------------------------------------------------------------------

test("advisory returns additionalContext object", () => {
  expect(advisory("hello")).toEqual({ hookSpecificOutput: { additionalContext: "hello" } });
});

// ---------------------------------------------------------------------------
// block — subprocess (has side effects: stderr write + process.exit(2))
// ---------------------------------------------------------------------------

test("block writes msg to stderr and exits 2", async () => {
  const script = `
import { block } from ${JSON.stringify(LIB_SCRIPT)};
block("BLOCKED: test message");
`;
  const proc = Bun.spawn(["bun", "--eval", script], {
    stdout: "pipe", stderr: "pipe",
  });
  const [stderrBytes] = await Promise.all([
    Bun.readableStreamToArrayBuffer(proc.stderr),
    Bun.readableStreamToArrayBuffer(proc.stdout),
    proc.exited,
  ]);
  const stderr = new TextDecoder().decode(stderrBytes);
  expect(proc.exitCode).toBe(2);
  expect(stderr).toContain("BLOCKED: test message");
});

// ---------------------------------------------------------------------------
// parseInput — subprocess (reads Bun.stdin)
// ---------------------------------------------------------------------------

test("parseInput returns parsed HookInput from stdin JSON", async () => {
  const script = `
import { parseInput } from ${JSON.stringify(LIB_SCRIPT)};
const r = await parseInput();
process.stdout.write(JSON.stringify(r));
`;
  const payload = { tool_name: "Write", tool_input: { file_path: "x.ts" }, agent_type: "builder" };
  const proc = Bun.spawn(["bun", "--eval", script], { stdin: "pipe", stdout: "pipe", stderr: "pipe" });
  proc.stdin!.write(new TextEncoder().encode(JSON.stringify(payload)));
  proc.stdin!.end();
  const [out] = await Promise.all([Bun.readableStreamToArrayBuffer(proc.stdout), proc.exited]);
  const parsed = JSON.parse(new TextDecoder().decode(out));
  expect(parsed.tool_name).toBe("Write");
  expect(parsed.agent_type).toBe("builder");
});

// ---------------------------------------------------------------------------
// countLines
// ---------------------------------------------------------------------------

test("countLines returns 0 for empty string", () => expect(countLines("")).toBe(0));
test("countLines returns 1 for single char no newline", () => expect(countLines("a")).toBe(1));
test("countLines returns 1 for single char with trailing newline", () => expect(countLines("a\n")).toBe(1));
test("countLines returns 2 for two lines with trailing newline", () => expect(countLines("a\nb\n")).toBe(2));
test("countLines returns 2 for two lines without trailing newline", () => expect(countLines("a\nb")).toBe(2));

// ---------------------------------------------------------------------------
// resolveRndDir — shells out to rnd-dir.sh
// ---------------------------------------------------------------------------

test("resolveRndDir returns string or null without throwing", async () => {
  const { resolveRndDir } = await import("../hooks/lib.ts");
  const result = resolveRndDir();
  expect(result === null || typeof result === "string").toBe(true);
});

test("resolveRndDir script path resolves relative to hooks dir", async () => {
  const { resolveRndDir } = await import("../hooks/lib.ts");
  // With --base flag, rnd-dir.sh returns the base dir regardless of session state
  const result = resolveRndDir("--base");
  // --base may return null if not in a project, but must not throw
  expect(result === null || typeof result === "string").toBe(true);
});

test("resolveRndDir memoizes: second call returns same value without re-spawning", async () => {
  const { resolveRndDir } = await import("../hooks/lib.ts");
  const first = resolveRndDir("--base");
  const spawnCount = { n: 0 };
  const original = Bun.spawnSync;
  Bun.spawnSync = (...a: Parameters<typeof Bun.spawnSync>) => { spawnCount.n++; return original(...a); };
  const second = resolveRndDir("--base");
  Bun.spawnSync = original;
  expect(second).toBe(first);
  expect(spawnCount.n).toBe(0);
});

// ---------------------------------------------------------------------------
// extractWriteEditContent
// ---------------------------------------------------------------------------

test("extractWriteEditContent returns content for Write tool", async () => {
  const { extractWriteEditContent } = await import("../hooks/lib.ts");
  expect(extractWriteEditContent("Write", { content: "x" })).toBe("x");
});

test("extractWriteEditContent returns new_string for Edit tool", async () => {
  const { extractWriteEditContent } = await import("../hooks/lib.ts");
  expect(extractWriteEditContent("Edit", { new_string: "y" })).toBe("y");
});

test("extractWriteEditContent returns null for non-Write/Edit tool", async () => {
  const { extractWriteEditContent } = await import("../hooks/lib.ts");
  expect(extractWriteEditContent("Read", {})).toBe(null);
});

test("extractWriteEditContent returns null for Write with missing content key", async () => {
  const { extractWriteEditContent } = await import("../hooks/lib.ts");
  expect(extractWriteEditContent("Write", {})).toBe(null);
});

// ---------------------------------------------------------------------------
// extractFilePath
// ---------------------------------------------------------------------------

test("extractFilePath returns file_path string", async () => {
  const { extractFilePath } = await import("../hooks/lib.ts");
  expect(extractFilePath({ file_path: "/foo.ts" })).toBe("/foo.ts");
});

test("extractFilePath returns null for missing file_path key", async () => {
  const { extractFilePath } = await import("../hooks/lib.ts");
  expect(extractFilePath({})).toBe(null);
});

test("extractFilePath returns null when file_path is not a string", async () => {
  const { extractFilePath } = await import("../hooks/lib.ts");
  expect(extractFilePath({ file_path: 42 })).toBe(null);
});

// ---------------------------------------------------------------------------
// isoTimestamp
// ---------------------------------------------------------------------------

test("isoTimestamp returns ISO 8601 UTC string without milliseconds", async () => {
  const { isoTimestamp } = await import("../hooks/lib.ts");
  const ts = isoTimestamp();
  expect(ts).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/);
});

// ---------------------------------------------------------------------------
// activeSessionDir
// ---------------------------------------------------------------------------

test("activeSessionDir returns null when resolveRndDir returns null", async () => {
  const script = `
import { resolve } from "node:path";
const LIB = resolve(${JSON.stringify(join(PLUGIN_ROOT, "hooks", "lib.ts"))});
// Patch Bun.spawnSync before importing lib so resolveRndDir gets null
const origSpawnSync = Bun.spawnSync;
Bun.spawnSync = () => ({ exitCode: 1, stdout: new Uint8Array(), stderr: new Uint8Array(), success: false });
const { activeSessionDir } = await import(LIB);
const result = activeSessionDir();
process.stdout.write(JSON.stringify({ result }));
`;
  const proc = Bun.spawn(["bun", "--eval", script], { stdout: "pipe", stderr: "pipe" });
  const [out] = await Promise.all([Bun.readableStreamToArrayBuffer(proc.stdout), proc.exited]);
  const parsed = JSON.parse(new TextDecoder().decode(out));
  expect(parsed.result).toBe(null);
});

test("activeSessionDir returns null when resolveRndDir returns path without /sessions/", async () => {
  const script = `
import { existsSync } from "node:fs";
import { resolve } from "node:path";
const LIB = resolve(${JSON.stringify(join(PLUGIN_ROOT, "hooks", "lib.ts"))});
// Patch Bun.spawnSync before importing lib so resolveRndDir returns /tmp/no-sessions
const origSpawnSync = Bun.spawnSync;
Bun.spawnSync = () => ({
  exitCode: 0,
  stdout: new TextEncoder().encode("/tmp/no-sessions\\n"),
  stderr: new Uint8Array(),
  success: true,
});
const { activeSessionDir } = await import(LIB);
const result = activeSessionDir();
process.stdout.write(JSON.stringify({ result }));
`;
  const proc = Bun.spawn(["bun", "--eval", script], { stdout: "pipe", stderr: "pipe" });
  const [out] = await Promise.all([Bun.readableStreamToArrayBuffer(proc.stdout), proc.exited]);
  const parsed = JSON.parse(new TextDecoder().decode(out));
  expect(parsed.result).toBe(null);
});
