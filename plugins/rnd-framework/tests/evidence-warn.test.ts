// Tests for hooks/evidence-warn
// The hook detects SQL/API patterns and emits advisory warnings. Always exits 0.

import { describe, expect, it } from "bun:test";
import { join } from "node:path";
import { runHook, runHookRaw } from "./helpers";

const HOOK_PATH = join(import.meta.dir, "..", "hooks", "evidence-warn");

function writeInput(filePath: string, content: string): unknown {
  return { tool_name: "Write", tool_input: { file_path: filePath, content } };
}

function editInput(filePath: string, oldString: string, newString: string): unknown {
  return {
    tool_name: "Edit",
    tool_input: { file_path: filePath, old_string: oldString, new_string: newString },
  };
}

interface EvidenceOutput {
  hookSpecificOutput: { additionalContext: string };
}

function parseOutput(stdout: string): EvidenceOutput {
  return JSON.parse(stdout.trim()) as EvidenceOutput;
}

// ---------------------------------------------------------------------------
// evidence-warn: exit code (resilience)
// ---------------------------------------------------------------------------

describe("evidence-warn: exit code", () => {
  it("exits 0 for a Write with SQL code", async () => {
    const result = await runHook(HOOK_PATH, writeInput("/src/db.ts", "SELECT * FROM users"));
    expect(result.exitCode).toBe(0);
  });

  it("exits 0 for malformed stdin (empty string)", async () => {
    const result = await runHookRaw(HOOK_PATH, "");
    expect(result.exitCode).toBe(0);
  });

  it("exits 0 for malformed stdin (non-JSON)", async () => {
    const result = await runHookRaw(HOOK_PATH, "not valid json");
    expect(result.exitCode).toBe(0);
  });

  it("exits 0 for non-code file (README.md)", async () => {
    const result = await runHook(HOOK_PATH, writeInput("/README.md", "SELECT * FROM users"));
    expect(result.exitCode).toBe(0);
  });

  it("exits 0 for .rnd/ path", async () => {
    const rndInput = writeInput("/.rnd/session/builds/T1.md", "SELECT * FROM users");
    const result = await runHook(HOOK_PATH, rndInput);
    expect(result.exitCode).toBe(0);
  });
});

describe("evidence-warn: SQL patterns", () => {
  it("SELECT * FROM users → mentions 'users'", async () => {
    const result = await runHook(HOOK_PATH, writeInput("/src/db.ts", "SELECT * FROM users"));
    expect(result.stdout.trim()).not.toBe("");
    const output = parseOutput(result.stdout);
    expect(output.hookSpecificOutput.additionalContext).toContain("users");
  });

  it("INSERT INTO orders → mentions 'orders'", async () => {
    const result = await runHook(HOOK_PATH, writeInput("/src/db.ts", "INSERT INTO orders (id) VALUES (1)"));
    const output = parseOutput(result.stdout);
    expect(output.hookSpecificOutput.additionalContext).toContain("orders");
  });

  it("CREATE TABLE products → mentions 'products'", async () => {
    const result = await runHook(HOOK_PATH, writeInput("/src/db.ts", "CREATE TABLE products (id INT)"));
    const output = parseOutput(result.stdout);
    expect(output.hookSpecificOutput.additionalContext).toContain("products");
  });

  it("SQL regexes are case-insensitive (select * from Users)", async () => {
    const result = await runHook(HOOK_PATH, writeInput("/src/db.ts", "select * from Users"));
    const output = parseOutput(result.stdout);
    expect(output.hookSpecificOutput.additionalContext).toContain("Users");
  });
});

describe("evidence-warn: API patterns", () => {
  it("fetch('/api/users') → mentions the endpoint", async () => {
    const result = await runHook(HOOK_PATH, writeInput("/src/api.ts", 'fetch("/api/users")'));
    const output = parseOutput(result.stdout);
    expect(output.hookSpecificOutput.additionalContext).toContain("/api/users");
  });
});

describe("evidence-warn: no output when no patterns", () => {
  it("no SQL/API patterns → empty stdout", async () => {
    const result = await runHook(HOOK_PATH, writeInput("/src/math.ts", "const x = 1 + 2;\nconsole.log(x);"));
    expect(result.stdout.trim()).toBe("");
  });

  it("non-code file (README.md) → empty stdout", async () => {
    const result = await runHook(HOOK_PATH, writeInput("/README.md", "SELECT * FROM users"));
    expect(result.stdout.trim()).toBe("");
  });

  it(".rnd/ path → empty stdout", async () => {
    const rndInput = writeInput("/.rnd/session/builds/T1.md", "SELECT * FROM users");
    const result = await runHook(HOOK_PATH, rndInput);
    expect(result.stdout.trim()).toBe("");
  });
});

describe("evidence-warn: Edit input handling", () => {
  it("Edit input: analyzes new_string, not old_string", async () => {
    const input = editInput(
      "/src/db.ts",
      "SELECT * FROM users",  // old_string — should be ignored
      "const x = 1;",         // new_string — no SQL patterns
    );
    const result = await runHook(HOOK_PATH, input);
    expect(result.stdout.trim()).toBe("");
  });

  it("Edit input: detects SQL in new_string", async () => {
    const input = editInput(
      "/src/db.ts",
      "const x = 1;",             // old_string — no patterns
      "INSERT INTO orders (id) VALUES (1)",  // new_string — has SQL
    );
    const result = await runHook(HOOK_PATH, input);
    const output = parseOutput(result.stdout);
    expect(output.hookSpecificOutput.additionalContext).toContain("orders");
  });
});
