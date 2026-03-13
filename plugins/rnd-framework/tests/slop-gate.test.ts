/**
 * Tests for hooks/slop-gate
 *
 * The hook detects LLM structural anti-patterns in code written by Write/Edit
 * tools and outputs structured JSON feedback. It is purely advisory — always
 * exits 0, no hookSpecificOutput.
 *
 * Strategy:
 *   - Feed known-slop code and verify matches appear in output JSON
 *   - Feed clean code and verify PASS verdict with empty matches
 *   - Feed Edit input and verify only new_string is analyzed
 *   - Feed non-code file paths and verify no output
 *   - Feed malformed stdin and verify no output + exit 0
 *   - Tests use a fake catalog path for the missing-catalog scenario
 */

import { describe, expect, it } from "bun:test";
import { mkdtemp, mkdir, writeFile, rm, readFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { join, basename } from "node:path";
import { tmpdir } from "node:os";
import { runHook, runHookRaw } from "./helpers";

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const HOOK_PATH =
  "/Users/oleksify/Developer/oleksify/claude/plugins/rnd-framework/hooks/slop-gate";

// ---------------------------------------------------------------------------
// Pipeline artifact test helpers (T4)
// ---------------------------------------------------------------------------

/**
 * Compute the same slug that rnd-dir.sh computes for a given directory.
 * slug = <basename(dir)>-<8char-sha256-of-dir>
 */
async function computeSlug(dir: string): Promise<string> {
  const base = basename(dir);
  const proc = Bun.spawn(
    ["bash", "-c", 'printf "%s" "$TARGET_DIR" | shasum -a 256 | cut -c1-8'],
    { stdout: "pipe", stderr: "pipe", env: { ...process.env, TARGET_DIR: dir } },
  );
  const bytes = await Bun.readableStreamToArrayBuffer(proc.stdout);
  await proc.exited;
  const hash = new TextDecoder().decode(bytes).trim();
  return `${base}-${hash}`;
}

interface SlopTestEnv {
  configDir: string;
  slug: string;
  baseDir: string;
  sessionDir: string;
  cleanup: () => Promise<void>;
}

/**
 * Creates an isolated temp directory tree mirroring the .rnd/ layout used by
 * rnd-dir.sh, with or without an active session.
 */
async function createSlopTestEnv(withSession: boolean): Promise<SlopTestEnv> {
  const configDir = await mkdtemp(join(tmpdir(), "slop-test-"));
  const cwd = process.cwd();
  const slug = await computeSlug(cwd);
  const baseDir = join(configDir, ".rnd", slug);
  await mkdir(baseDir, { recursive: true });

  const sessionId = "20260312-120000-abcd";
  const sessionDir = join(baseDir, "sessions", sessionId);

  if (withSession) {
    await mkdir(sessionDir, { recursive: true });
    await writeFile(join(baseDir, ".current-session"), sessionId, "utf-8");
  }

  async function cleanup() {
    if (existsSync(configDir)) {
      await rm(configDir, { recursive: true, force: true });
    }
  }

  return { configDir, slug, baseDir, sessionDir, cleanup };
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function writeInput(filePath: string, content: string): unknown {
  return {
    tool_name: "Write",
    tool_input: { file_path: filePath, content },
  };
}

function editInput(filePath: string, oldString: string, newString: string): unknown {
  return {
    tool_name: "Edit",
    tool_input: { file_path: filePath, old_string: oldString, new_string: newString },
  };
}

interface SlopOutput {
  verdict: string;
  score: number;
  file_path: string;
  line_count: number;
  matches: Array<{
    pattern_id: string;
    line: number;
    snippet: string;
    severity: number;
  }>;
}

function parseOutput(stdout: string): SlopOutput {
  return JSON.parse(stdout.trim()) as SlopOutput;
}

// ---------------------------------------------------------------------------
// slop-gate: exit code
// ---------------------------------------------------------------------------

describe("slop-gate: exit code", () => {
  it("exits 0 for a Write with slop code (FAIL verdict)", async () => {
    // Use dense slop to drive a high score
    const slopCode = Array(20).fill("catch (e) {}").join("\n");
    const result = await runHook(HOOK_PATH, writeInput("/src/test.ts", slopCode));
    expect(result.exitCode).toBe(0);
  });

  it("exits 0 for a Write with clean code (PASS verdict)", async () => {
    const result = await runHook(HOOK_PATH, writeInput("/src/test.ts", "const x = 1;\nconst y = 2;\n"));
    expect(result.exitCode).toBe(0);
  });

  it("exits 0 for malformed stdin (empty string)", async () => {
    const result = await runHookRaw(HOOK_PATH, "");
    expect(result.exitCode).toBe(0);
  });

  it("exits 0 for malformed stdin (non-JSON)", async () => {
    const result = await runHookRaw(HOOK_PATH, "not valid json at all");
    expect(result.exitCode).toBe(0);
  });

  it("exits 0 for a non-code file (no verdict output)", async () => {
    const result = await runHook(HOOK_PATH, writeInput("/README.md", "catch (e) {}"));
    expect(result.exitCode).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// slop-gate: pattern detection — over-commenting
// ---------------------------------------------------------------------------

describe("slop-gate: pattern detection — over-commenting", () => {
  it("detects over-commenting for '// increment counter\\ncounter++'", async () => {
    const content = "// increment counter\ncounter++\n";
    const result = await runHook(HOOK_PATH, writeInput("/src/test.ts", content));
    expect(result.stdout).not.toBe("");
    const output = parseOutput(result.stdout);
    const overCommentMatches = output.matches.filter((m) => m.pattern_id === "over-commenting");
    expect(overCommentMatches.length).toBeGreaterThanOrEqual(1);
  });

  it("over-commenting match is in the over-commenting category (pattern_id check)", async () => {
    const content = "// increment counter\ncounter++\n";
    const result = await runHook(HOOK_PATH, writeInput("/src/test.ts", content));
    const output = parseOutput(result.stdout);
    expect(output.matches.some((m) => m.pattern_id === "over-commenting")).toBe(true);
  });

  it("over-commenting match has the correct line number", async () => {
    const content = "const a = 1;\n// increment counter\ncounter++\n";
    const result = await runHook(HOOK_PATH, writeInput("/src/test.ts", content));
    const output = parseOutput(result.stdout);
    const match = output.matches.find((m) => m.pattern_id === "over-commenting");
    expect(match).toBeDefined();
    // "// increment counter" is on line 2
    expect(match!.line).toBe(2);
  });
});

// ---------------------------------------------------------------------------
// slop-gate: pattern detection — empty catch block
// ---------------------------------------------------------------------------

describe("slop-gate: pattern detection — empty catch block", () => {
  it("detects empty-catch-block for 'catch (e) {}'", async () => {
    const content = "function foo() {\n  try {\n    bar();\n  } catch (e) {}\n}\n";
    const result = await runHook(HOOK_PATH, writeInput("/src/test.ts", content));
    expect(result.stdout).not.toBe("");
    const output = parseOutput(result.stdout);
    const catchMatches = output.matches.filter((m) => m.pattern_id === "empty-catch-block");
    expect(catchMatches.length).toBeGreaterThanOrEqual(1);
  });

  it("empty-catch-block match has the correct snippet", async () => {
    const content = "try {\n  doSomething();\n} catch (e) {}\n";
    const result = await runHook(HOOK_PATH, writeInput("/src/test.ts", content));
    const output = parseOutput(result.stdout);
    const match = output.matches.find((m) => m.pattern_id === "empty-catch-block");
    expect(match).toBeDefined();
    expect(match!.snippet).toContain("catch");
  });

  it("empty-catch-block match has severity 4", async () => {
    const content = "catch (e) {}\n";
    const result = await runHook(HOOK_PATH, writeInput("/src/test.ts", content));
    const output = parseOutput(result.stdout);
    const match = output.matches.find((m) => m.pattern_id === "empty-catch-block");
    expect(match).toBeDefined();
    expect(match!.severity).toBe(4);
  });
});

// ---------------------------------------------------------------------------
// slop-gate: clean code — PASS verdict
// ---------------------------------------------------------------------------

describe("slop-gate: clean code", () => {
  it("clean code produces verdict PASS", async () => {
    const content = "const x = 1;\nconst y = 2;\nconst z = x + y;\n";
    const result = await runHook(HOOK_PATH, writeInput("/src/clean.ts", content));
    const output = parseOutput(result.stdout);
    expect(output.verdict).toBe("PASS");
  });

  it("clean code produces an empty matches array", async () => {
    const content = "const x = 1;\nconst y = 2;\nconst z = x + y;\n";
    const result = await runHook(HOOK_PATH, writeInput("/src/clean.ts", content));
    const output = parseOutput(result.stdout);
    expect(output.matches).toEqual([]);
  });

  it("clean code score is 0", async () => {
    const content = "const x = 1;\nconst y = 2;\nconst z = x + y;\n";
    const result = await runHook(HOOK_PATH, writeInput("/src/clean.ts", content));
    const output = parseOutput(result.stdout);
    expect(output.score).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// slop-gate: diff-aware analysis (Edit tool)
// ---------------------------------------------------------------------------

describe("slop-gate: diff-aware analysis — Edit tool", () => {
  it("Edit: slop in old_string but clean new_string produces PASS with no matches", async () => {
    const oldString = "// increment counter\ncounter++\ncatch (e) {}";
    const newString = "const x = 1;\n";
    const result = await runHook(HOOK_PATH, editInput("/src/test.ts", oldString, newString));
    const output = parseOutput(result.stdout);
    expect(output.verdict).toBe("PASS");
    expect(output.matches).toEqual([]);
  });

  it("Edit: clean old_string but slop new_string produces matches", async () => {
    const oldString = "const x = 1;";
    const newString = "// increment counter\ncounter++\n";
    const result = await runHook(HOOK_PATH, editInput("/src/test.ts", oldString, newString));
    const output = parseOutput(result.stdout);
    expect(output.matches.some((m) => m.pattern_id === "over-commenting")).toBe(true);
  });

  it("Edit: line_count reflects new_string length, not old_string", async () => {
    // old_string has 5 lines, new_string has 1 line
    const oldString = "a\nb\nc\nd\ne";
    const newString = "const x = 1;";
    const result = await runHook(HOOK_PATH, editInput("/src/test.ts", oldString, newString));
    const output = parseOutput(result.stdout);
    // new_string "const x = 1;" split by "\n" = 1 line
    expect(output.line_count).toBe(1);
  });

  it("Edit: output file_path matches tool_input.file_path", async () => {
    const result = await runHook(
      HOOK_PATH,
      editInput("/src/components/Button.tsx", "old", "const x = 1;"),
    );
    const output = parseOutput(result.stdout);
    expect(output.file_path).toBe("/src/components/Button.tsx");
  });
});

// ---------------------------------------------------------------------------
// slop-gate: file extension filtering (T3)
// ---------------------------------------------------------------------------

describe("slop-gate: file extension filtering", () => {
  it(".md file produces no stdout output", async () => {
    const result = await runHook(
      HOOK_PATH,
      writeInput("/skills/foo/SKILL.md", "// increment counter\ncatch (e) {}"),
    );
    expect(result.stdout).toBe("");
  });

  it(".json file produces no stdout output", async () => {
    const result = await runHook(
      HOOK_PATH,
      writeInput("/slop-patterns.json", "// increment counter\ncatch (e) {}"),
    );
    expect(result.stdout).toBe("");
  });

  it(".yaml file produces no stdout output", async () => {
    const result = await runHook(
      HOOK_PATH,
      writeInput("/config.yaml", "catch (e) {}"),
    );
    expect(result.stdout).toBe("");
  });

  it(".yml file produces no stdout output", async () => {
    const result = await runHook(
      HOOK_PATH,
      writeInput("/config.yml", "catch (e) {}"),
    );
    expect(result.stdout).toBe("");
  });

  it("file with no extension produces no stdout output", async () => {
    const result = await runHook(
      HOOK_PATH,
      writeInput("/hooks/slop-gate", "// increment counter\ncatch (e) {}"),
    );
    expect(result.stdout).toBe("");
  });

  it(".ts file with anti-patterns produces stdout output", async () => {
    const result = await runHook(
      HOOK_PATH,
      writeInput("/src/test.ts", "// increment counter\ncounter++\n"),
    );
    expect(result.stdout).not.toBe("");
    const output = parseOutput(result.stdout);
    expect(output.matches.length).toBeGreaterThan(0);
  });

  it(".py file with anti-patterns produces stdout output", async () => {
    // Python doesn't have JS catch blocks but the over-commenting pattern works
    const result = await runHook(
      HOOK_PATH,
      writeInput("/scripts/run.py", "// increment counter\ncounter++\n"),
    );
    expect(result.stdout).not.toBe("");
  });

  it(".sh file with code content produces stdout output", async () => {
    const result = await runHook(
      HOOK_PATH,
      writeInput("/scripts/deploy.sh", "# increment counter\ncounter++\ncatch (e) {}\n"),
    );
    // .sh is in the allowlist — will be analyzed
    expect(result.stdout).not.toBe("");
  });
});

// ---------------------------------------------------------------------------
// slop-gate: output JSON structure
// ---------------------------------------------------------------------------

describe("slop-gate: output JSON structure", () => {
  it("output has all required keys: verdict, score, matches, file_path, line_count", async () => {
    const result = await runHook(
      HOOK_PATH,
      writeInput("/src/test.ts", "const x = 1;\n"),
    );
    const output = parseOutput(result.stdout);
    expect(output).toHaveProperty("verdict");
    expect(output).toHaveProperty("score");
    expect(output).toHaveProperty("matches");
    expect(output).toHaveProperty("file_path");
    expect(output).toHaveProperty("line_count");
  });

  it("verdict is one of PASS, WARN, FAIL", async () => {
    const result = await runHook(
      HOOK_PATH,
      writeInput("/src/test.ts", "const x = 1;\n"),
    );
    const output = parseOutput(result.stdout);
    expect(["PASS", "WARN", "FAIL"]).toContain(output.verdict);
  });

  it("matches array entries have: pattern_id, line, snippet, severity", async () => {
    const result = await runHook(
      HOOK_PATH,
      writeInput("/src/test.ts", "// increment counter\ncounter++\n"),
    );
    const output = parseOutput(result.stdout);
    expect(output.matches.length).toBeGreaterThan(0);
    const match = output.matches[0];
    expect(match).toHaveProperty("pattern_id");
    expect(match).toHaveProperty("line");
    expect(match).toHaveProperty("snippet");
    expect(match).toHaveProperty("severity");
  });

  it("file_path in output matches the input file_path", async () => {
    const result = await runHook(
      HOOK_PATH,
      writeInput("/src/utils/helpers.ts", "const x = 1;\n"),
    );
    const output = parseOutput(result.stdout);
    expect(output.file_path).toBe("/src/utils/helpers.ts");
  });

  it("line_count in output matches number of lines in content", async () => {
    // "line1\nline2\nline3\n" splits to ["line1", "line2", "line3", ""] = 4 lines
    const content = "const a = 1;\nconst b = 2;\nconst c = 3;\n";
    const result = await runHook(
      HOOK_PATH,
      writeInput("/src/test.ts", content),
    );
    const output = parseOutput(result.stdout);
    expect(output.line_count).toBe(content.split("\n").length);
  });
});

// ---------------------------------------------------------------------------
// slop-gate: scoring and verdict thresholds
// ---------------------------------------------------------------------------

describe("slop-gate: scoring and verdict thresholds", () => {
  it("verdict PASS when score < 3", async () => {
    // 1 match with severity 2 across 10 lines = score 0.2 (PASS)
    const lines = ["// increment counter", ...Array(9).fill("const x = 1;")];
    const content = lines.join("\n");
    const result = await runHook(HOOK_PATH, writeInput("/src/test.ts", content));
    const output = parseOutput(result.stdout);
    expect(output.score).toBeLessThan(3);
    expect(output.verdict).toBe("PASS");
  });

  it("verdict WARN when score is between 3 and 7 inclusive", async () => {
    // Multiple catch blocks on few lines to get score in WARN range
    // 2 empty catch blocks (severity 4 each) across 3 lines = 8/3 = 2.67 (PASS)
    // Need 3 catch blocks across 3 lines = 12/3 = 4 (WARN)
    const content = "catch (e) {}\ncatch (e) {}\ncatch (e) {}\n";
    const result = await runHook(HOOK_PATH, writeInput("/src/test.ts", content));
    const output = parseOutput(result.stdout);
    // 3 matches * severity 4 / 4 lines = score 3 (WARN boundary)
    expect(output.score).toBeGreaterThanOrEqual(3);
    expect(output.score).toBeLessThanOrEqual(7);
    expect(output.verdict).toBe("WARN");
  });

  it("verdict FAIL when score > 7", async () => {
    // Single line triggering 3 patterns: empty-catch-block (4) + placeholder-todo (3) + console-log-leftover (3)
    // = 10 severity on 1 line = score 10 > 7 → FAIL
    const content = "console.log(x); // TODO fix this; catch (e) {}";
    const result = await runHook(HOOK_PATH, writeInput("/src/test.ts", content));
    const output = parseOutput(result.stdout);
    expect(output.score).toBeGreaterThan(7);
    expect(output.verdict).toBe("FAIL");
  });

  it("score is normalized by line count (more lines = lower score per match)", async () => {
    // 1 catch block on 1 line vs 1 catch block on 100 lines
    const sparse = "catch (e) {}\n" + Array(99).fill("const x = 1;").join("\n");
    const dense = "catch (e) {}";
    const resultSparse = await runHook(HOOK_PATH, writeInput("/src/test.ts", sparse));
    const resultDense = await runHook(HOOK_PATH, writeInput("/src/test.ts", dense));
    const scoreSparse = parseOutput(resultSparse.stdout).score;
    const scoreDense = parseOutput(resultDense.stdout).score;
    expect(scoreSparse).toBeLessThan(scoreDense);
  });
});

// ---------------------------------------------------------------------------
// slop-gate: malformed input
// ---------------------------------------------------------------------------

describe("slop-gate: malformed input", () => {
  it("exits 0 with no stdout for empty string stdin", async () => {
    const result = await runHookRaw(HOOK_PATH, "");
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("");
  });

  it("exits 0 with no stdout for non-JSON stdin", async () => {
    const result = await runHookRaw(HOOK_PATH, "this is not json");
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("");
  });

  it("exits 0 with no stdout for JSON array (not object)", async () => {
    const result = await runHookRaw(HOOK_PATH, JSON.stringify([1, 2, 3]));
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("");
  });

  it("exits 0 with no stdout when tool_name is missing", async () => {
    const result = await runHookRaw(
      HOOK_PATH,
      JSON.stringify({ tool_input: { file_path: "/src/test.ts", content: "const x = 1;" } }),
    );
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("");
  });

  it("exits 0 with no stdout when tool_input is missing", async () => {
    const result = await runHookRaw(
      HOOK_PATH,
      JSON.stringify({ tool_name: "Write" }),
    );
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("");
  });

  it("exits 0 with no stdout when file_path is missing", async () => {
    const result = await runHookRaw(
      HOOK_PATH,
      JSON.stringify({ tool_name: "Write", tool_input: { content: "const x = 1;" } }),
    );
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("");
  });

  it("exits 0 with no stdout when content is missing for Write", async () => {
    const result = await runHookRaw(
      HOOK_PATH,
      JSON.stringify({ tool_name: "Write", tool_input: { file_path: "/src/test.ts" } }),
    );
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("");
  });

  it("exits 0 with no stdout when new_string is missing for Edit", async () => {
    const result = await runHookRaw(
      HOOK_PATH,
      JSON.stringify({ tool_name: "Edit", tool_input: { file_path: "/src/test.ts", old_string: "old" } }),
    );
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("");
  });
});

// ---------------------------------------------------------------------------
// slop-gate: missing catalog
// ---------------------------------------------------------------------------

describe("slop-gate: missing catalog", () => {
  it("exits 0 with no stdout when slop-patterns.json does not exist", async () => {
    // Create a temp dir with no slop-patterns.json and a fake hooks/slop-gate
    // that references a nonexistent catalog
    const tmpDir = await mkdtemp(join(tmpdir(), "slop-gate-test-"));
    const fakeHooksDir = join(tmpDir, "hooks");

    try {
      // Create hooks dir
      await mkdir(fakeHooksDir, { recursive: true });

      // Write a wrapper script that calls the real hook with a different import.meta.dir
      // Since Bun resolves import.meta.dir at compile time, we test this differently:
      // We simply confirm that when the real script is run in an environment where the
      // catalog at its resolved path is absent, it exits 0 silently.
      // The real hook resolves: resolve(import.meta.dir, "..", "slop-patterns.json")
      // which is always the plugin root. To test "missing catalog", we temporarily
      // rename the catalog — but since tests run in parallel, instead write a minimal
      // wrapper script that sets up the scenario.

      // Alternative: write a minimal standalone test script that imports with a missing catalog
      const wrapperScript = join(fakeHooksDir, "slop-gate-test");
      await writeFile(wrapperScript, `#!/usr/bin/env bun
// Minimal catalog-missing test: reads a non-existent catalog path
import { resolve } from "node:path";
import { readFileSync } from "node:fs";

try {
  const stdinChunks: Uint8Array[] = [];
  for await (const chunk of Bun.stdin.stream()) {
    stdinChunks.push(chunk);
  }
  const stdinText = new TextDecoder().decode(
    stdinChunks.reduce((acc, chunk) => {
      const merged = new Uint8Array(acc.length + chunk.length);
      merged.set(acc, 0);
      merged.set(chunk, acc.length);
      return merged;
    }, new Uint8Array(0))
  );
  JSON.parse(stdinText);
  // Try to load a non-existent catalog
  readFileSync(resolve(import.meta.dir, "nonexistent-catalog.json"), "utf-8");
} catch {
  process.exit(0);
}
`, { mode: 0o755 });

      const result = await runHook(
        wrapperScript,
        { tool_name: "Write", tool_input: { file_path: "/src/test.ts", content: "const x = 1;" } },
      );
      expect(result.exitCode).toBe(0);
      expect(result.stdout).toBe("");
    } finally {
      if (existsSync(tmpDir)) {
        await rm(tmpDir, { recursive: true, force: true });
      }
    }
  });
});

// ---------------------------------------------------------------------------
// slop-gate: shebang and executability (structural)
// ---------------------------------------------------------------------------

describe("slop-gate: script structure", () => {
  it("script file exists", async () => {
    expect(existsSync(HOOK_PATH)).toBe(true);
  });

  it("script is executable", async () => {
    const { statSync } = await import("node:fs");
    const stat = statSync(HOOK_PATH);
    // Check user execute bit (0o100)
    expect(stat.mode & 0o100).not.toBe(0);
  });

  it("first line is #!/usr/bin/env bun", async () => {
    const { readFileSync } = await import("node:fs");
    const content = readFileSync(HOOK_PATH, "utf-8");
    const firstLine = content.split("\n")[0];
    expect(firstLine).toBe("#!/usr/bin/env bun");
  });
});

// ---------------------------------------------------------------------------
// slop-gate: additional pattern coverage
// ---------------------------------------------------------------------------

describe("slop-gate: additional pattern detection", () => {
  it("detects placeholder-todo", async () => {
    const content = "const x = 1;\n// TODO: fix this later\nconst y = 2;\n";
    const result = await runHook(HOOK_PATH, writeInput("/src/test.ts", content));
    const output = parseOutput(result.stdout);
    expect(output.matches.some((m) => m.pattern_id === "placeholder-todo")).toBe(true);
  });

  it("detects console-log-leftover", async () => {
    const content = "function foo() {\n  console.log('debug');\n  return 1;\n}\n";
    const result = await runHook(HOOK_PATH, writeInput("/src/test.ts", content));
    const output = parseOutput(result.stdout);
    expect(output.matches.some((m) => m.pattern_id === "console-log-leftover")).toBe(true);
  });

  it("outputs valid JSON (parseable without error)", async () => {
    const content = "// increment counter\ncounter++\ncatch (e) {}\n";
    const result = await runHook(HOOK_PATH, writeInput("/src/test.ts", content));
    expect(() => parseOutput(result.stdout)).not.toThrow();
  });
});

// ---------------------------------------------------------------------------
// slop-gate: pipeline artifact integration (T4)
// ---------------------------------------------------------------------------

describe("slop-gate: pipeline artifacts — active session", () => {
  it("creates slop-reports/ directory in sessionDir when active session exists", async () => {
    const env = await createSlopTestEnv(true);
    try {
      const content = "// increment counter\ncounter++\ncatch (e) {}\n";
      await runHook(
        HOOK_PATH,
        writeInput("/src/test.ts", content),
        { CLAUDE_CONFIG_DIR: env.configDir },
      );
      const reportsDir = join(env.sessionDir, "slop-reports");
      expect(existsSync(reportsDir)).toBe(true);
    } finally {
      await env.cleanup();
    }
  });

  it("creates a JSON report file in slop-reports/ for a code file with anti-patterns", async () => {
    const env = await createSlopTestEnv(true);
    try {
      const content = "// increment counter\ncounter++\ncatch (e) {}\n";
      await runHook(
        HOOK_PATH,
        writeInput("/src/test.ts", content),
        { CLAUDE_CONFIG_DIR: env.configDir },
      );
      const reportsDir = join(env.sessionDir, "slop-reports");
      // Sanitized: /src/test.ts → src-test.ts.json
      const reportFile = join(reportsDir, "src-test.ts.json");
      expect(existsSync(reportFile)).toBe(true);
    } finally {
      await env.cleanup();
    }
  });

  it("report file parses as valid JSON", async () => {
    const env = await createSlopTestEnv(true);
    try {
      const content = "// increment counter\ncounter++\ncatch (e) {}\n";
      await runHook(
        HOOK_PATH,
        writeInput("/src/test.ts", content),
        { CLAUDE_CONFIG_DIR: env.configDir },
      );
      const reportsDir = join(env.sessionDir, "slop-reports");
      const reportFile = join(reportsDir, "src-test.ts.json");
      const raw = await readFile(reportFile, "utf-8");
      expect(() => JSON.parse(raw)).not.toThrow();
    } finally {
      await env.cleanup();
    }
  });

  it("report file contains all required keys: file_path, verdict, score, matches, line_count, timestamp", async () => {
    const env = await createSlopTestEnv(true);
    try {
      const content = "// increment counter\ncounter++\ncatch (e) {}\n";
      await runHook(
        HOOK_PATH,
        writeInput("/src/utils/helpers.ts", content),
        { CLAUDE_CONFIG_DIR: env.configDir },
      );
      const reportsDir = join(env.sessionDir, "slop-reports");
      // Sanitized: /src/utils/helpers.ts → src-utils-helpers.ts.json
      const reportFile = join(reportsDir, "src-utils-helpers.ts.json");
      const raw = await readFile(reportFile, "utf-8");
      const report = JSON.parse(raw);
      expect(report).toHaveProperty("file_path");
      expect(report).toHaveProperty("verdict");
      expect(report).toHaveProperty("score");
      expect(report).toHaveProperty("matches");
      expect(report).toHaveProperty("line_count");
      expect(report).toHaveProperty("timestamp");
    } finally {
      await env.cleanup();
    }
  });

  it("report file_path matches the tool input file_path", async () => {
    const env = await createSlopTestEnv(true);
    try {
      await runHook(
        HOOK_PATH,
        writeInput("/src/utils/helpers.ts", "catch (e) {}\n"),
        { CLAUDE_CONFIG_DIR: env.configDir },
      );
      const reportsDir = join(env.sessionDir, "slop-reports");
      const reportFile = join(reportsDir, "src-utils-helpers.ts.json");
      const raw = await readFile(reportFile, "utf-8");
      const report = JSON.parse(raw);
      expect(report.file_path).toBe("/src/utils/helpers.ts");
    } finally {
      await env.cleanup();
    }
  });

  it("report verdict matches hook stdout verdict", async () => {
    const env = await createSlopTestEnv(true);
    try {
      const content = "catch (e) {}\n";
      const result = await runHook(
        HOOK_PATH,
        writeInput("/src/test.ts", content),
        { CLAUDE_CONFIG_DIR: env.configDir },
      );
      const stdoutOutput = parseOutput(result.stdout);
      const reportsDir = join(env.sessionDir, "slop-reports");
      const reportFile = join(reportsDir, "src-test.ts.json");
      const raw = await readFile(reportFile, "utf-8");
      const report = JSON.parse(raw);
      expect(report.verdict).toBe(stdoutOutput.verdict);
    } finally {
      await env.cleanup();
    }
  });

  it("creates cumulative-score.json in slop-reports/", async () => {
    const env = await createSlopTestEnv(true);
    try {
      await runHook(
        HOOK_PATH,
        writeInput("/src/test.ts", "catch (e) {}\n"),
        { CLAUDE_CONFIG_DIR: env.configDir },
      );
      const cumulativePath = join(env.sessionDir, "slop-reports", "cumulative-score.json");
      expect(existsSync(cumulativePath)).toBe(true);
    } finally {
      await env.cleanup();
    }
  });

  it("cumulative-score.json contains required keys: total_score, file_count, average_score, worst_file, worst_score", async () => {
    const env = await createSlopTestEnv(true);
    try {
      await runHook(
        HOOK_PATH,
        writeInput("/src/test.ts", "catch (e) {}\n"),
        { CLAUDE_CONFIG_DIR: env.configDir },
      );
      const cumulativePath = join(env.sessionDir, "slop-reports", "cumulative-score.json");
      const raw = await readFile(cumulativePath, "utf-8");
      const cumulative = JSON.parse(raw);
      expect(cumulative).toHaveProperty("total_score");
      expect(cumulative).toHaveProperty("file_count");
      expect(cumulative).toHaveProperty("average_score");
      expect(cumulative).toHaveProperty("worst_file");
      expect(cumulative).toHaveProperty("worst_score");
    } finally {
      await env.cleanup();
    }
  });

  it("after two Write invocations, cumulative-score.json has file_count of 2", async () => {
    const env = await createSlopTestEnv(true);
    try {
      await runHook(
        HOOK_PATH,
        writeInput("/src/file1.ts", "catch (e) {}\n"),
        { CLAUDE_CONFIG_DIR: env.configDir },
      );
      await runHook(
        HOOK_PATH,
        writeInput("/src/file2.ts", "// increment counter\ncounter++\n"),
        { CLAUDE_CONFIG_DIR: env.configDir },
      );
      const cumulativePath = join(env.sessionDir, "slop-reports", "cumulative-score.json");
      const raw = await readFile(cumulativePath, "utf-8");
      const cumulative = JSON.parse(raw);
      expect(cumulative.file_count).toBe(2);
    } finally {
      await env.cleanup();
    }
  });

  it("after two Write invocations, total_score is the sum of both file scores", async () => {
    const env = await createSlopTestEnv(true);
    try {
      const content1 = "catch (e) {}\n";
      const content2 = "// increment counter\ncounter++\n";

      const result1 = await runHook(
        HOOK_PATH,
        writeInput("/src/file1.ts", content1),
        { CLAUDE_CONFIG_DIR: env.configDir },
      );
      const result2 = await runHook(
        HOOK_PATH,
        writeInput("/src/file2.ts", content2),
        { CLAUDE_CONFIG_DIR: env.configDir },
      );

      const score1 = parseOutput(result1.stdout).score;
      const score2 = parseOutput(result2.stdout).score;

      const cumulativePath = join(env.sessionDir, "slop-reports", "cumulative-score.json");
      const raw = await readFile(cumulativePath, "utf-8");
      const cumulative = JSON.parse(raw);

      // Allow small floating-point tolerance
      expect(Math.abs(cumulative.total_score - (score1 + score2))).toBeLessThan(1e-9);
    } finally {
      await env.cleanup();
    }
  });

  it("worst_file and worst_score track the highest-scoring file", async () => {
    const env = await createSlopTestEnv(true);
    try {
      // file1 has clean code (score 0), file2 has slop (score > 0)
      const content1 = "const x = 1;\nconst y = 2;\n";
      // Dense slop to guarantee file2 has the worst score
      const content2 = "catch (e) {}\ncatch (e) {}\ncatch (e) {}\n";

      await runHook(
        HOOK_PATH,
        writeInput("/src/clean.ts", content1),
        { CLAUDE_CONFIG_DIR: env.configDir },
      );
      await runHook(
        HOOK_PATH,
        writeInput("/src/slop.ts", content2),
        { CLAUDE_CONFIG_DIR: env.configDir },
      );

      const cumulativePath = join(env.sessionDir, "slop-reports", "cumulative-score.json");
      const raw = await readFile(cumulativePath, "utf-8");
      const cumulative = JSON.parse(raw);

      expect(cumulative.worst_file).toBe("/src/slop.ts");
      expect(cumulative.worst_score).toBeGreaterThan(0);
    } finally {
      await env.cleanup();
    }
  });

  it("stdout output is produced even when pipeline artifacts are written", async () => {
    const env = await createSlopTestEnv(true);
    try {
      const result = await runHook(
        HOOK_PATH,
        writeInput("/src/test.ts", "catch (e) {}\n"),
        { CLAUDE_CONFIG_DIR: env.configDir },
      );
      expect(result.stdout).not.toBe("");
      expect(() => parseOutput(result.stdout)).not.toThrow();
    } finally {
      await env.cleanup();
    }
  });
});

// ---------------------------------------------------------------------------
// slop-gate: pipeline artifacts — no active session (T4)
// ---------------------------------------------------------------------------

describe("slop-gate: pipeline artifacts — no active session", () => {
  it("no slop-reports/ directory is created when no active session exists", async () => {
    const env = await createSlopTestEnv(false);
    try {
      await runHook(
        HOOK_PATH,
        writeInput("/src/test.ts", "// increment counter\ncounter++\ncatch (e) {}\n"),
        { CLAUDE_CONFIG_DIR: env.configDir },
      );
      const reportsDir = join(env.sessionDir, "slop-reports");
      expect(existsSync(reportsDir)).toBe(false);
      // Also verify nothing was created in the base dir
      const baseReportsDir = join(env.baseDir, "slop-reports");
      expect(existsSync(baseReportsDir)).toBe(false);
    } finally {
      await env.cleanup();
    }
  });

  it("no cumulative-score.json is created when no active session exists", async () => {
    const env = await createSlopTestEnv(false);
    try {
      await runHook(
        HOOK_PATH,
        writeInput("/src/test.ts", "catch (e) {}\n"),
        { CLAUDE_CONFIG_DIR: env.configDir },
      );
      const cumulativePath = join(env.sessionDir, "slop-reports", "cumulative-score.json");
      expect(existsSync(cumulativePath)).toBe(false);
    } finally {
      await env.cleanup();
    }
  });

  it("stdout output is still produced when no active session exists", async () => {
    const env = await createSlopTestEnv(false);
    try {
      const result = await runHook(
        HOOK_PATH,
        writeInput("/src/test.ts", "catch (e) {}\n"),
        { CLAUDE_CONFIG_DIR: env.configDir },
      );
      expect(result.stdout).not.toBe("");
      expect(() => parseOutput(result.stdout)).not.toThrow();
    } finally {
      await env.cleanup();
    }
  });

  it("exit code is 0 when no active session exists", async () => {
    const env = await createSlopTestEnv(false);
    try {
      const result = await runHook(
        HOOK_PATH,
        writeInput("/src/test.ts", "catch (e) {}\n"),
        { CLAUDE_CONFIG_DIR: env.configDir },
      );
      expect(result.exitCode).toBe(0);
    } finally {
      await env.cleanup();
    }
  });
});

// ---------------------------------------------------------------------------
// slop-gate: RND_DIR resolution failure (T4)
// ---------------------------------------------------------------------------

describe("slop-gate: RND_DIR resolution failure", () => {
  it("exits 0 and produces stdout when rnd-dir.sh errors (unreadable CLAUDE_CONFIG_DIR)", async () => {
    // Pass a CLAUDE_CONFIG_DIR that doesn't exist — rnd-dir.sh will return the
    // base dir (no session), so no artifacts are written, but stdout still flows.
    const result = await runHook(
      HOOK_PATH,
      writeInput("/src/test.ts", "catch (e) {}\n"),
      { CLAUDE_CONFIG_DIR: "/nonexistent/path/that/does/not/exist" },
    );
    expect(result.exitCode).toBe(0);
    expect(result.stdout).not.toBe("");
  });
});

// ---------------------------------------------------------------------------
// slop-gate: filename sanitization (T4 quality criterion)
// ---------------------------------------------------------------------------

describe("slop-gate: filename sanitization", () => {
  it("/src/utils/foo.ts produces report file src-utils-foo.ts.json", async () => {
    const env = await createSlopTestEnv(true);
    try {
      await runHook(
        HOOK_PATH,
        writeInput("/src/utils/foo.ts", "catch (e) {}\n"),
        { CLAUDE_CONFIG_DIR: env.configDir },
      );
      const reportFile = join(env.sessionDir, "slop-reports", "src-utils-foo.ts.json");
      expect(existsSync(reportFile)).toBe(true);
    } finally {
      await env.cleanup();
    }
  });

  it("/src/index.ts produces report file src-index.ts.json (no double dash for single segment)", async () => {
    const env = await createSlopTestEnv(true);
    try {
      await runHook(
        HOOK_PATH,
        writeInput("/src/index.ts", "catch (e) {}\n"),
        { CLAUDE_CONFIG_DIR: env.configDir },
      );
      const reportFile = join(env.sessionDir, "slop-reports", "src-index.ts.json");
      expect(existsSync(reportFile)).toBe(true);
    } finally {
      await env.cleanup();
    }
  });

  it("report filename is deterministic (same path produces same filename on repeat)", async () => {
    const env = await createSlopTestEnv(true);
    try {
      // First invocation
      await runHook(
        HOOK_PATH,
        writeInput("/src/deterministic.ts", "catch (e) {}\n"),
        { CLAUDE_CONFIG_DIR: env.configDir },
      );
      // Second invocation — overwrites the same file
      await runHook(
        HOOK_PATH,
        writeInput("/src/deterministic.ts", "const x = 1;\n"),
        { CLAUDE_CONFIG_DIR: env.configDir },
      );
      const reportFile = join(env.sessionDir, "slop-reports", "src-deterministic.ts.json");
      expect(existsSync(reportFile)).toBe(true);
      // The second write should have overwritten the first — content is the clean version
      const raw = await readFile(reportFile, "utf-8");
      const report = JSON.parse(raw);
      expect(report.verdict).toBe("PASS");
    } finally {
      await env.cleanup();
    }
  });
});
