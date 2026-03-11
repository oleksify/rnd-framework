/**
 * Tests for hooks/prefer-tools
 *
 * The hook reads JSON from stdin: { "tool_input": { "command": "..." } }
 * Exit codes:
 *   0 + hookSpecificOutput JSON  → auto-allow
 *   0 + no stdout               → no opinion (pass-through)
 *   2 + stderr message          → blocked
 */

import { describe, expect, it } from "bun:test";
import { join } from "node:path";
import { runHook, runHookRaw } from "./helpers";

const HOOK = join(import.meta.dir, "../hooks/prefer-tools");

/** Build the stdin payload the hook expects. */
function payload(command: string) {
  return { tool_input: { command } };
}

// ---------------------------------------------------------------------------
// sed / awk → Edit tool
// ---------------------------------------------------------------------------

describe("sed/awk blocking", () => {
  it("blocks 'sed s/foo/bar/ file.txt' with exit 2 and Edit tool mention", async () => {
    const result = await runHook(HOOK, payload("sed s/foo/bar/ file.txt"));
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("Edit tool");
  });

  it("blocks 'awk {print $1} file' with exit 2 and Edit tool mention", async () => {
    const result = await runHook(HOOK, payload("awk '{print $1}' file"));
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("Edit tool");
  });
});

// ---------------------------------------------------------------------------
// cat / head / tail → Read tool
// ---------------------------------------------------------------------------

describe("cat/head/tail blocking", () => {
  it("blocks 'cat somefile' with exit 2 and Read tool mention", async () => {
    const result = await runHook(HOOK, payload("cat somefile"));
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("Read tool");
  });

  it("blocks 'head -n 10 file' with exit 2 and Read tool mention", async () => {
    const result = await runHook(HOOK, payload("head -n 10 file"));
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("Read tool");
  });

  it("blocks 'tail -f file' with exit 2 and Read tool mention", async () => {
    const result = await runHook(HOOK, payload("tail -f file"));
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("Read tool");
  });
});

// ---------------------------------------------------------------------------
// grep / rg → Grep tool
// ---------------------------------------------------------------------------

describe("grep/rg blocking", () => {
  it("blocks 'grep pattern file' with exit 2 and Grep tool mention", async () => {
    const result = await runHook(HOOK, payload("grep pattern file"));
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("Grep tool");
  });

  it("blocks 'rg pattern' with exit 2 and Grep tool mention", async () => {
    const result = await runHook(HOOK, payload("rg pattern"));
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("Grep tool");
  });
});

// ---------------------------------------------------------------------------
// find → Glob tool
// ---------------------------------------------------------------------------

describe("find blocking", () => {
  it("blocks 'find . -name *.ts' with exit 2 and Glob tool mention", async () => {
    const result = await runHook(HOOK, payload("find . -name '*.ts'"));
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("Glob tool");
  });
});

// ---------------------------------------------------------------------------
// echo/printf with file redirects → Write tool
// ---------------------------------------------------------------------------

describe("echo/printf file redirect blocking", () => {
  it("blocks 'echo foo > output.txt' with exit 2 and Write tool mention", async () => {
    const result = await runHook(HOOK, payload("echo foo > output.txt"));
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("Write tool");
  });

  it("blocks 'printf '%s' data > file.txt' with exit 2 and Write tool mention", async () => {
    const result = await runHook(HOOK, payload("printf '%s' data > file.txt"));
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("Write tool");
  });
});

// ---------------------------------------------------------------------------
// echo to /dev/ paths → exempt (exit 0)
// ---------------------------------------------------------------------------

describe("echo to /dev/ paths — exempted", () => {
  it("allows 'echo foo > /dev/stderr' (exit 0)", async () => {
    const result = await runHook(HOOK, payload("echo foo > /dev/stderr"));
    expect(result.exitCode).toBe(0);
  });

  it("allows 'echo foo > /dev/null' (exit 0)", async () => {
    const result = await runHook(HOOK, payload("echo foo > /dev/null"));
    expect(result.exitCode).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// echo without redirect → no opinion
// ---------------------------------------------------------------------------

describe("echo without redirect — no opinion", () => {
  it("'echo hello' returns exit 0 and empty stdout", async () => {
    const result = await runHook(HOOK, payload("echo hello"));
    expect(result.exitCode).toBe(0);
    expect(result.stdout.trim()).toBe("");
  });
});

// ---------------------------------------------------------------------------
// ls → auto-allow
// ---------------------------------------------------------------------------

describe("ls — auto-allow", () => {
  it("'ls -la' returns exit 0 and stdout contains permissionDecision allow", async () => {
    const result = await runHook(HOOK, payload("ls -la"));
    expect(result.exitCode).toBe(0);
    const parsed = JSON.parse(result.stdout);
    expect(parsed.hookSpecificOutput.permissionDecision).toBe("allow");
  });
});

// ---------------------------------------------------------------------------
// git add .rnd → blocked
// ---------------------------------------------------------------------------

describe("git add .rnd — blocked", () => {
  it("'git add .rnd/something' returns exit 2 and stderr contains BLOCKED", async () => {
    const result = await runHook(HOOK, payload("git add .rnd/something"));
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("BLOCKED");
  });
});

// ---------------------------------------------------------------------------
// rnd-dir.sh in command → auto-allow
// ---------------------------------------------------------------------------

describe("rnd-dir.sh in command — auto-allow", () => {
  it("command containing 'rnd-dir.sh' returns exit 0 with permissionDecision allow", async () => {
    const result = await runHook(HOOK, payload('RND_DIR="$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh")"'));
    expect(result.exitCode).toBe(0);
    const parsed = JSON.parse(result.stdout);
    expect(parsed.hookSpecificOutput.permissionDecision).toBe("allow");
  });
});

// ---------------------------------------------------------------------------
// .rnd in command (non-git-add) → auto-allow
// ---------------------------------------------------------------------------

describe(".rnd in command (not git add) — auto-allow", () => {
  it("command containing '.rnd' (not git add) returns exit 0 with permissionDecision allow", async () => {
    const result = await runHook(HOOK, payload("ls /some/.rnd/builds"));
    // ls hits the ls branch first and returns allow
    expect(result.exitCode).toBe(0);
    const parsed = JSON.parse(result.stdout);
    expect(parsed.hookSpecificOutput.permissionDecision).toBe("allow");
  });

  it("non-ls command containing '.rnd' returns exit 0 with permissionDecision allow", async () => {
    const result = await runHook(HOOK, payload("bun run /tmp/.rnd/builds/check.ts"));
    expect(result.exitCode).toBe(0);
    const parsed = JSON.parse(result.stdout);
    expect(parsed.hookSpecificOutput.permissionDecision).toBe("allow");
  });
});

// ---------------------------------------------------------------------------
// cd prefix stripping
// ---------------------------------------------------------------------------

describe("cd prefix stripping", () => {
  it("'cd /some/path && sed s/a/b/ f' returns exit 2 (cd prefix stripped, sed still blocked)", async () => {
    const result = await runHook(HOOK, payload("cd /some/path && sed s/a/b/ f"));
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("Edit tool");
  });

  it("'cd /path && cd /other && ls' returns exit 0 with allow (chained cd stripped)", async () => {
    const result = await runHook(HOOK, payload("cd /path && cd /other && ls"));
    expect(result.exitCode).toBe(0);
    const parsed = JSON.parse(result.stdout);
    expect(parsed.hookSpecificOutput.permissionDecision).toBe("allow");
  });
});

// ---------------------------------------------------------------------------
// Unmatched commands → no opinion
// ---------------------------------------------------------------------------

describe("unmatched commands — no opinion", () => {
  it("'npm install' returns exit 0 and empty stdout", async () => {
    const result = await runHook(HOOK, payload("npm install"));
    expect(result.exitCode).toBe(0);
    expect(result.stdout.trim()).toBe("");
  });
});

// ---------------------------------------------------------------------------
// cd semicolon stripping (FIX 1)
// ---------------------------------------------------------------------------

describe("cd semicolon stripping", () => {
  it("'cd /path ; sed s/a/b/ f' returns exit 2 with Edit tool mention", async () => {
    const result = await runHook(HOOK, payload("cd /path ; sed s/a/b/ f"));
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("Edit tool");
  });

  it("'cd /path; sed s/a/b/ f' (no space before ;) returns exit 2 with Edit tool mention", async () => {
    const result = await runHook(HOOK, payload("cd /path; sed s/a/b/ f"));
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("Edit tool");
  });

  it("'cd /a ; cd /b ; cat file' returns exit 2 with Read tool mention", async () => {
    const result = await runHook(HOOK, payload("cd /a ; cd /b ; cat file"));
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("Read tool");
  });

  it("'cd /path ;; cat file' (double semicolon) returns exit 2 with Read tool mention", async () => {
    const result = await runHook(HOOK, payload("cd /path ;; cat file"));
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("Read tool");
  });
});

// ---------------------------------------------------------------------------
// git add edge cases (FIX 2)
// ---------------------------------------------------------------------------

describe("git add .rnd edge cases", () => {
  it("'git add .rnd.backup' returns exit 0 with empty stdout (not blocked)", async () => {
    const result = await runHook(HOOK, payload("git add .rnd.backup"));
    expect(result.exitCode).toBe(0);
    expect(result.stdout.trim()).toBe("");
  });

  it("'git add .rnd/' returns exit 2 with BLOCKED in stderr", async () => {
    const result = await runHook(HOOK, payload("git add .rnd/"));
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("BLOCKED");
  });

  it("'git add some/path/.rnd/file' returns exit 2 with BLOCKED in stderr", async () => {
    const result = await runHook(HOOK, payload("git add some/path/.rnd/file"));
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("BLOCKED");
  });
});

// ---------------------------------------------------------------------------
// echo/printf with multiple redirects (FIX 3)
// ---------------------------------------------------------------------------

describe("echo/printf multiple redirect blocking", () => {
  it("'echo foo > /dev/stderr > /tmp/out' returns exit 2 with Write tool mention", async () => {
    const result = await runHook(HOOK, payload("echo foo > /dev/stderr > /tmp/out"));
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("Write tool");
  });

  it("'printf data > /dev/null > file.txt' returns exit 2 with Write tool mention", async () => {
    const result = await runHook(HOOK, payload("printf data > /dev/null > file.txt"));
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("Write tool");
  });
});

// ---------------------------------------------------------------------------
// Malformed stdin — graceful exit 0
// ---------------------------------------------------------------------------

describe("malformed stdin — graceful handling", () => {
  it("empty stdin returns exit 0 without crashing", async () => {
    const result = await runHookRaw(HOOK, "");
    expect(result.exitCode).toBe(0);
  });

  it("non-JSON text on stdin returns exit 0 without crashing", async () => {
    const result = await runHookRaw(HOOK, "not valid json at all");
    expect(result.exitCode).toBe(0);
  });

  it("JSON missing tool_input key returns exit 0 without crashing", async () => {
    const result = await runHookRaw(HOOK, '{"no_tool_input":"here"}');
    expect(result.exitCode).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// Large command — no crash
// ---------------------------------------------------------------------------

describe("large command — no crash", () => {
  it("10000-character command string does not crash the hook (exits 0)", async () => {
    const bigCommand = "x".repeat(10000);
    const result = await runHook(HOOK, payload(bigCommand));
    expect(result.exitCode).toBe(0);
  });
});
