import { test, expect } from "bun:test";
import { join } from "node:path";
import { CODE_EXTENSIONS, isCodeFile, isRndPath, allow, advisory } from "../hooks/lib.ts";

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

test("isRndPath returns true for path containing .rnd/", () =>
  expect(isRndPath("/foo/.rnd/bar")).toBe(true));
test("isRndPath returns false for path without .rnd/", () =>
  expect(isRndPath("/foo/bar")).toBe(false));
test("isRndPath returns false for .rnd with no trailing slash", () =>
  expect(isRndPath("/foo/.rnd")).toBe(false));

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
