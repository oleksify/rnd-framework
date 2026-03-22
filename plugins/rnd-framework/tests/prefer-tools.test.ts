/**
 * Tests for hooks/prefer-tools
 *
 * The hook reads JSON from stdin: { "tool_input": { "command": "..." } }
 * Exit codes:
 *   0 + hookSpecificOutput JSON  → auto-allow
 *   0 + no stdout               → no opinion (pass-through)
 *   2 + stderr message          → blocked
 */

import { describe, expect, test } from "bun:test";
import { join } from "node:path";
import { runHook, runHookRaw } from "./helpers";

const HOOK = join(import.meta.dir, "../hooks/prefer-tools.ts");

/** Build the stdin payload the hook expects. */
function payload(command: string) {
  return { tool_input: { command } };
}

// ---------------------------------------------------------------------------
// sed / awk → Edit tool
// ---------------------------------------------------------------------------

describe("sed/awk blocking", () => {
  test("blocks 'sed s/foo/bar/ file.txt' with exit 2 and Edit tool mention", async () => {
    const result = await runHook(HOOK, payload("sed s/foo/bar/ file.txt"));
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("Edit tool");
  });

  test("blocks 'awk {print $1} file' with exit 2 and Edit tool mention", async () => {
    const result = await runHook(HOOK, payload("awk '{print $1}' file"));
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("Edit tool");
  });
});

// ---------------------------------------------------------------------------
// cat / head / tail → Read tool
// ---------------------------------------------------------------------------

describe("cat/head/tail blocking", () => {
  test("blocks 'cat somefile' with exit 2 and Read tool mention", async () => {
    const result = await runHook(HOOK, payload("cat somefile"));
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("Read tool");
  });

  test("blocks 'head -n 10 file' with exit 2 and Read tool mention", async () => {
    const result = await runHook(HOOK, payload("head -n 10 file"));
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("Read tool");
  });

  test("blocks 'tail -f file' with exit 2 and Read tool mention", async () => {
    const result = await runHook(HOOK, payload("tail -f file"));
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("Read tool");
  });
});

// ---------------------------------------------------------------------------
// grep / rg → Grep tool
// ---------------------------------------------------------------------------

describe("grep/rg blocking", () => {
  test("blocks 'grep pattern file' with exit 2 and Grep tool mention", async () => {
    const result = await runHook(HOOK, payload("grep pattern file"));
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("Grep tool");
  });

  test("blocks 'rg pattern' with exit 2 and Grep tool mention", async () => {
    const result = await runHook(HOOK, payload("rg pattern"));
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("Grep tool");
  });
});

// ---------------------------------------------------------------------------
// find → Glob tool
// ---------------------------------------------------------------------------

describe("find blocking", () => {
  test("blocks 'find . -name *.ts' with exit 2 and Glob tool mention", async () => {
    const result = await runHook(HOOK, payload("find . -name '*.ts'"));
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("Glob tool");
  });
});

// ---------------------------------------------------------------------------
// echo/printf with file redirects → Write tool
// ---------------------------------------------------------------------------

describe("echo/printf file redirect blocking", () => {
  test("blocks 'echo foo > output.txt' with exit 2 and Write tool mention", async () => {
    const result = await runHook(HOOK, payload("echo foo > output.txt"));
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("Write tool");
  });

  test("blocks 'printf '%s' data > file.txt' with exit 2 and Write tool mention", async () => {
    const result = await runHook(HOOK, payload("printf '%s' data > file.txt"));
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("Write tool");
  });
});

// ---------------------------------------------------------------------------
// echo/printf redirects to .rnd/ paths → exempt (auto-allow)
// ---------------------------------------------------------------------------

describe("echo/printf redirects to .rnd/ paths — auto-allow", () => {
  test("'echo content > /path/.rnd/builds/file.md' returns exit 0 with allow", async () => {
    const result = await runHook(HOOK, payload('echo "DONE" > /home/user/.rnd/sessions/20260314/builds/T1-self-assessment.md'));
    expect(result.exitCode).toBe(0);
    const parsed = JSON.parse(result.stdout);
    expect(parsed.hookSpecificOutput.permissionDecision).toBe("allow");
  });

  test("'printf content > /path/.rnd/builds/file.md' returns exit 0 with allow", async () => {
    const result = await runHook(HOOK, payload("printf 'DONE' > /home/user/.rnd/sessions/20260314/builds/T1-self-assessment.md"));
    expect(result.exitCode).toBe(0);
    const parsed = JSON.parse(result.stdout);
    expect(parsed.hookSpecificOutput.permissionDecision).toBe("allow");
  });

  test("'echo content > /tmp/regular.txt' is still blocked", async () => {
    const result = await runHook(HOOK, payload("echo content > /tmp/regular.txt"));
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("Write tool");
  });
});

// ---------------------------------------------------------------------------
// echo to /dev/ paths → exempt (exit 0)
// ---------------------------------------------------------------------------

describe("echo to /dev/ paths — exempted", () => {
  test("allows 'echo foo > /dev/stderr' (exit 0)", async () => {
    const result = await runHook(HOOK, payload("echo foo > /dev/stderr"));
    expect(result.exitCode).toBe(0);
  });

  test("allows 'echo foo > /dev/null' (exit 0)", async () => {
    const result = await runHook(HOOK, payload("echo foo > /dev/null"));
    expect(result.exitCode).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// echo without redirect → auto-allow
// ---------------------------------------------------------------------------

describe("echo without redirect — auto-allow", () => {
  test("'echo hello' returns exit 0 with permissionDecision allow", async () => {
    const result = await runHook(HOOK, payload("echo hello"));
    expect(result.exitCode).toBe(0);
    const parsed = JSON.parse(result.stdout);
    expect(parsed.hookSpecificOutput.permissionDecision).toBe("allow");
  });
});

// ---------------------------------------------------------------------------
// ls → no opinion
// ---------------------------------------------------------------------------

describe("ls — no opinion", () => {
  test("'ls -la' returns exit 0 with empty stdout (no opinion)", async () => {
    const result = await runHook(HOOK, payload("ls -la"));
    expect(result.exitCode).toBe(0);
    expect(result.stdout.trim()).toBe("");
  });
});

// ---------------------------------------------------------------------------
// git add .rnd → blocked
// ---------------------------------------------------------------------------

describe("git add .rnd — blocked", () => {
  test("'git add .rnd/something' returns exit 2 and stderr contains BLOCKED", async () => {
    const result = await runHook(HOOK, payload("git add .rnd/something"));
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("BLOCKED");
  });
});

// ---------------------------------------------------------------------------
// git push to main/master/production → blocked
// ---------------------------------------------------------------------------

describe("git push to protected branches — blocked", () => {
  test("'git push origin main' returns exit 2 and stderr contains BLOCKED", async () => {
    const result = await runHook(HOOK, payload("git push origin main"));
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("BLOCKED");
  });

  test("'git push origin master' returns exit 2", async () => {
    const result = await runHook(HOOK, payload("git push origin master"));
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("BLOCKED");
  });

  test("'git push origin production' returns exit 2", async () => {
    const result = await runHook(HOOK, payload("git push origin production"));
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("BLOCKED");
  });

  test("'git push origin feature-branch' is not blocked", async () => {
    const result = await runHook(HOOK, payload("git push origin feature-branch"));
    expect(result.exitCode).toBe(0);
    expect(result.stderr.trim()).toBe("");
  });

  test("'git push --tags' is not blocked", async () => {
    const result = await runHook(HOOK, payload("git push --tags"));
    expect(result.exitCode).toBe(0);
    expect(result.stderr.trim()).toBe("");
  });
});

// ---------------------------------------------------------------------------
// rnd-dir.sh in command → auto-allow
// ---------------------------------------------------------------------------

describe("rnd-dir.sh in command — auto-allow", () => {
  test("command containing 'rnd-dir.sh' returns exit 0 with permissionDecision allow", async () => {
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
  test("command containing '.rnd' (not git add) returns exit 0 with permissionDecision allow", async () => {
    const result = await runHook(HOOK, payload("ls /some/.rnd/builds"));
    // ls hits the ls branch first and returns allow
    expect(result.exitCode).toBe(0);
    const parsed = JSON.parse(result.stdout);
    expect(parsed.hookSpecificOutput.permissionDecision).toBe("allow");
  });

  test("non-ls command containing '.rnd' returns exit 0 with permissionDecision allow", async () => {
    const result = await runHook(HOOK, payload("bun run /tmp/.rnd/builds/check.ts"));
    expect(result.exitCode).toBe(0);
    const parsed = JSON.parse(result.stdout);
    expect(parsed.hookSpecificOutput.permissionDecision).toBe("allow");
  });

  test("cat .rnd/file is blocked (tool discipline overrides .rnd/ auto-allow)", async () => {
    const result = await runHook(HOOK, payload("cat /path/.rnd/builds/manifest.md"));
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("Read tool");
  });

  test("sed on .rnd/ file is blocked (tool discipline overrides .rnd/ auto-allow)", async () => {
    const result = await runHook(HOOK, payload("sed s/foo/bar/ /path/.rnd/plan.md"));
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("Edit tool");
  });
});

// ---------------------------------------------------------------------------
// cd prefix stripping
// ---------------------------------------------------------------------------

describe("cd prefix stripping", () => {
  test("'cd /some/path && sed s/a/b/ f' returns exit 2 (cd prefix stripped, sed still blocked)", async () => {
    const result = await runHook(HOOK, payload("cd /some/path && sed s/a/b/ f"));
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("Edit tool");
  });

  test("'cd /path && cd /other && ls' returns exit 0 with empty stdout (no opinion)", async () => {
    const result = await runHook(HOOK, payload("cd /path && cd /other && ls"));
    expect(result.exitCode).toBe(0);
    expect(result.stdout.trim()).toBe("");
  });
});

// ---------------------------------------------------------------------------
// Unmatched commands → no opinion
// ---------------------------------------------------------------------------

describe("unmatched commands — no opinion", () => {
  test("'npm install' returns exit 0 with empty stdout (no opinion)", async () => {
    const result = await runHook(HOOK, payload("npm install"));
    expect(result.exitCode).toBe(0);
    expect(result.stdout.trim()).toBe("");
  });
});

// ---------------------------------------------------------------------------
// cd semicolon stripping (FIX 1)
// ---------------------------------------------------------------------------

describe("cd semicolon stripping", () => {
  test("'cd /path ; sed s/a/b/ f' returns exit 2 with Edit tool mention", async () => {
    const result = await runHook(HOOK, payload("cd /path ; sed s/a/b/ f"));
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("Edit tool");
  });

  test("'cd /path; sed s/a/b/ f' (no space before ;) returns exit 2 with Edit tool mention", async () => {
    const result = await runHook(HOOK, payload("cd /path; sed s/a/b/ f"));
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("Edit tool");
  });

  test("'cd /a ; cd /b ; cat file' returns exit 2 with Read tool mention", async () => {
    const result = await runHook(HOOK, payload("cd /a ; cd /b ; cat file"));
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("Read tool");
  });

  test("'cd /path ;; cat file' (double semicolon) returns exit 2 with Read tool mention", async () => {
    const result = await runHook(HOOK, payload("cd /path ;; cat file"));
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("Read tool");
  });
});

// ---------------------------------------------------------------------------
// git add edge cases (FIX 2)
// ---------------------------------------------------------------------------

describe("git add .rnd edge cases", () => {
  test("'git add .rnd.backup' returns exit 0 with empty stdout (no opinion, not blocked)", async () => {
    const result = await runHook(HOOK, payload("git add .rnd.backup"));
    expect(result.exitCode).toBe(0);
    expect(result.stdout.trim()).toBe("");
  });

  test("'git add .rnd/' returns exit 2 with BLOCKED in stderr", async () => {
    const result = await runHook(HOOK, payload("git add .rnd/"));
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("BLOCKED");
  });

  test("'git add some/path/.rnd/file' returns exit 2 with BLOCKED in stderr", async () => {
    const result = await runHook(HOOK, payload("git add some/path/.rnd/file"));
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("BLOCKED");
  });

  test("'cd /path && git add .rnd/file' returns exit 2 with BLOCKED (cd prefix bypass)", async () => {
    const result = await runHook(HOOK, payload("cd /some/path && git add .rnd/file"));
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("BLOCKED");
  });

  test("'cd /path && git add .rnd.backup' returns exit 0 with empty stdout (no opinion, not a false positive)", async () => {
    const result = await runHook(HOOK, payload("cd /some/path && git add .rnd.backup"));
    expect(result.exitCode).toBe(0);
    expect(result.stdout.trim()).toBe("");
  });
});

// ---------------------------------------------------------------------------
// echo/printf with multiple redirects (FIX 3)
// ---------------------------------------------------------------------------

describe("echo/printf multiple redirect blocking", () => {
  test("'echo foo > /dev/stderr > /tmp/out' returns exit 2 with Write tool mention", async () => {
    const result = await runHook(HOOK, payload("echo foo > /dev/stderr > /tmp/out"));
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("Write tool");
  });

  test("'printf data > /dev/null > file.txt' returns exit 2 with Write tool mention", async () => {
    const result = await runHook(HOOK, payload("printf data > /dev/null > file.txt"));
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("Write tool");
  });
});

// ---------------------------------------------------------------------------
// Malformed stdin — graceful exit 0
// ---------------------------------------------------------------------------

describe("malformed stdin — graceful handling", () => {
  test("empty stdin returns exit 0 without crashing", async () => {
    const result = await runHookRaw(HOOK, "");
    expect(result.exitCode).toBe(0);
  });

  test("non-JSON text on stdin returns exit 0 without crashing", async () => {
    const result = await runHookRaw(HOOK, "not valid json at all");
    expect(result.exitCode).toBe(0);
  });

  test("JSON missing tool_input key returns exit 0 without crashing", async () => {
    const result = await runHookRaw(HOOK, '{"no_tool_input":"here"}');
    expect(result.exitCode).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// Large command — no crash
// ---------------------------------------------------------------------------

describe("large command — no crash", () => {
  test("10000-character command string does not crash the hook (exits 0)", async () => {
    const bigCommand = "x".repeat(10000);
    const result = await runHook(HOOK, payload(bigCommand));
    expect(result.exitCode).toBe(0);
  });
});
