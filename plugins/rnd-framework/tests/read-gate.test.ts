/**
 * Tests for hooks/read-gate
 *
 * Covers all 5 success criteria from the T5 pre-registration:
 *   1. Path containing "self-assessment" → exit 2 + stderr "INFORMATION BARRIER"
 *   2. Path containing ".rnd/" but NOT "self-assessment" → exit 0 + permissionDecision "allow"
 *   3. Path containing both ".rnd/" and "self-assessment" → exit 2 (block takes priority)
 *   4. Path not containing ".rnd/" → exit 0 + empty stdout (no opinion)
 *   5. Filename "self-assessment.md" in a non-.rnd/ path → still blocked (substring match)
 *
 * Also covers T3 hardening criteria:
 *   6. Case-insensitive self-assessment matching (capital variants blocked)
 *   7. Malformed stdin (empty, non-JSON, missing keys) → exits 0, no opinion
 *   8. Empty file_path → exits 0, no opinion
 *   9. ".rnd" without trailing slash → no opinion
 *  10. "self-assessment" as substring in unrelated path → blocked
 *  11. Symlink paths: hook checks path string, not resolved target (documented behavior)
 */

import { describe, test, expect } from "bun:test";
import { join } from "node:path";
import { runHook, runHookRaw } from "./helpers";

const HOOK = join(import.meta.dir, "..", "hooks", "read-gate");

/** Build the stdin JSON that read-gate expects */
function input(filePath: string): unknown {
  return { tool_input: { file_path: filePath } };
}

/** Build stdin JSON including agent_type (Claude Code 2.1.69+) */
function inputWithAgent(filePath: string, agentType: string): unknown {
  return { tool_input: { file_path: filePath }, agent_type: agentType };
}

// ---------------------------------------------------------------------------
// Criterion 1: self-assessment path → INFORMATION BARRIER block
// ---------------------------------------------------------------------------
describe("read-gate: self-assessment paths are blocked", () => {
  test("plain self-assessment filename returns exit 2", async () => {
    const result = await runHook(HOOK, input("T1-self-assessment.md"));
    expect(result.exitCode).toBe(2);
  });

  test("stderr contains INFORMATION BARRIER for self-assessment path", async () => {
    const result = await runHook(HOOK, input("T1-self-assessment.md"));
    expect(result.stderr).toContain("INFORMATION BARRIER");
  });

  test("self-assessment inside a nested directory is blocked", async () => {
    const result = await runHook(
      HOOK,
      input("/home/user/project/builds/T3-self-assessment.md"),
    );
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("INFORMATION BARRIER");
  });
});

// ---------------------------------------------------------------------------
// Criterion 2: .rnd/ path (no self-assessment) → auto-allow
// ---------------------------------------------------------------------------
describe("read-gate: .rnd/ paths without self-assessment are auto-allowed", () => {
  test("plain .rnd/ path returns exit 0", async () => {
    const result = await runHook(
      HOOK,
      input("/home/user/.rnd/project-abc/sessions/20260305-120000-1a2b/plan.md"),
    );
    expect(result.exitCode).toBe(0);
  });

  test(".rnd/ path stdout contains permissionDecision allow", async () => {
    const result = await runHook(
      HOOK,
      input("/home/user/.rnd/project-abc/sessions/20260305-120000-1a2b/plan.md"),
    );
    const parsed = JSON.parse(result.stdout);
    expect(parsed.hookSpecificOutput.permissionDecision).toBe("allow");
  });

  test("deeply nested .rnd/ path is auto-allowed", async () => {
    const result = await runHook(
      HOOK,
      input("/foo/bar/.rnd/baz/qux/deep/file.md"),
    );
    expect(result.exitCode).toBe(0);
    const parsed = JSON.parse(result.stdout);
    expect(parsed.hookSpecificOutput.permissionDecision).toBe("allow");
  });

  test(".rnd/ build manifest is auto-allowed", async () => {
    const result = await runHook(
      HOOK,
      input("/Users/me/.rnd/myproject-abc12345/sessions/20260305-120000-1a2b/builds/T2-manifest.md"),
    );
    expect(result.exitCode).toBe(0);
    const parsed = JSON.parse(result.stdout);
    expect(parsed.hookSpecificOutput.permissionDecision).toBe("allow");
  });
});

// ---------------------------------------------------------------------------
// Criterion 3: path with both ".rnd/" and "self-assessment" → block (priority)
// ---------------------------------------------------------------------------
describe("read-gate: .rnd/ + self-assessment → block takes priority", () => {
  test("path with both .rnd/ and self-assessment returns exit 2", async () => {
    const result = await runHook(
      HOOK,
      input("/home/user/.rnd/project/sessions/20260305-120000-1a2b/builds/T1-self-assessment.md"),
    );
    expect(result.exitCode).toBe(2);
  });

  test("path with both .rnd/ and self-assessment has INFORMATION BARRIER on stderr", async () => {
    const result = await runHook(
      HOOK,
      input("/home/user/.rnd/project/sessions/20260305-120000-1a2b/builds/T1-self-assessment.md"),
    );
    expect(result.stderr).toContain("INFORMATION BARRIER");
  });

  test("path with both .rnd/ and self-assessment produces no allow output", async () => {
    const result = await runHook(
      HOOK,
      input("/home/user/.rnd/project/sessions/20260305-120000-1a2b/builds/T1-self-assessment.md"),
    );
    // stdout must NOT contain a permissionDecision allow
    expect(result.stdout).not.toContain("allow");
  });
});

// ---------------------------------------------------------------------------
// Criterion 4: non-.rnd/ path → no opinion (exit 0, empty stdout)
// ---------------------------------------------------------------------------
describe("read-gate: non-.rnd/ paths produce no opinion", () => {
  test("regular source file returns exit 0", async () => {
    const result = await runHook(
      HOOK,
      input("/Users/me/project/src/index.ts"),
    );
    expect(result.exitCode).toBe(0);
  });

  test("regular source file stdout is empty", async () => {
    const result = await runHook(
      HOOK,
      input("/Users/me/project/src/index.ts"),
    );
    expect(result.stdout.trim()).toBe("");
  });

  test("a README.md produces no opinion", async () => {
    const result = await runHook(HOOK, input("/home/user/project/README.md"));
    expect(result.exitCode).toBe(0);
    expect(result.stdout.trim()).toBe("");
  });

  test("home directory config file produces no opinion", async () => {
    const result = await runHook(HOOK, input("/home/user/.bashrc"));
    expect(result.exitCode).toBe(0);
    expect(result.stdout.trim()).toBe("");
  });
});

// ---------------------------------------------------------------------------
// Criterion 5: "self-assessment.md" in a non-.rnd/ path is still blocked
// ---------------------------------------------------------------------------
describe("read-gate: self-assessment substring match applies to full path", () => {
  test("self-assessment.md in project root is blocked even without .rnd/", async () => {
    const result = await runHook(
      HOOK,
      input("/Users/me/project/self-assessment.md"),
    );
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("INFORMATION BARRIER");
  });

  test("self-assessment in path segment is blocked even without .rnd/", async () => {
    const result = await runHook(
      HOOK,
      input("/Users/me/docs/self-assessment/notes.txt"),
    );
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("INFORMATION BARRIER");
  });

  test("self-assessment.md on its own (relative path) is blocked", async () => {
    const result = await runHook(HOOK, input("self-assessment.md"));
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("INFORMATION BARRIER");
  });
});

// ---------------------------------------------------------------------------
// T3 Criterion: case-insensitive self-assessment matching
// ---------------------------------------------------------------------------
describe("read-gate: case-insensitive self-assessment blocking", () => {
  test("Self-Assessment.md (capital S and A) is blocked with exit 2", async () => {
    const result = await runHook(HOOK, input("/rnd/builds/T1-Self-Assessment.md"));
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("INFORMATION BARRIER");
  });

  test("SELF-ASSESSMENT.md (all caps) is blocked with exit 2", async () => {
    const result = await runHook(HOOK, input("/rnd/builds/T1-SELF-ASSESSMENT.md"));
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("INFORMATION BARRIER");
  });

  test("self-ASSESSMENT.md (mixed case) is blocked with exit 2", async () => {
    const result = await runHook(HOOK, input("/rnd/builds/T1-self-ASSESSMENT.md"));
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("INFORMATION BARRIER");
  });
});

// ---------------------------------------------------------------------------
// T3 Criterion: malformed or missing stdin input → no opinion
// ---------------------------------------------------------------------------
describe("read-gate: malformed stdin produces no opinion", () => {
  test("empty string stdin exits 0 with empty stdout", async () => {
    const result = await runHookRaw(HOOK, "");
    expect(result.exitCode).toBe(0);
    expect(result.stdout.trim()).toBe("");
  });

  test("non-JSON text stdin exits 0 with empty stdout", async () => {
    const result = await runHookRaw(HOOK, "this is not json at all");
    expect(result.exitCode).toBe(0);
    expect(result.stdout.trim()).toBe("");
  });

  test("JSON with no tool_input key exits 0 with empty stdout", async () => {
    const result = await runHookRaw(HOOK, '{"other_key": "value"}');
    expect(result.exitCode).toBe(0);
    expect(result.stdout.trim()).toBe("");
  });
});

// ---------------------------------------------------------------------------
// T3 Criterion: empty file_path extracted from JSON → no opinion
// ---------------------------------------------------------------------------
describe("read-gate: empty file_path produces no opinion", () => {
  test("file_path set to empty string exits 0 with empty stdout", async () => {
    const result = await runHook(HOOK, { tool_input: { file_path: "" } });
    expect(result.exitCode).toBe(0);
    expect(result.stdout.trim()).toBe("");
  });
});

// ---------------------------------------------------------------------------
// T3 Criterion: ".rnd" without trailing slash → no opinion
// ---------------------------------------------------------------------------
describe('read-gate: ".rnd" without trailing slash produces no opinion', () => {
  test('path exactly ".rnd" exits 0 with empty stdout', async () => {
    const result = await runHook(HOOK, input(".rnd"));
    expect(result.exitCode).toBe(0);
    expect(result.stdout.trim()).toBe("");
  });

  test('path "/some/dir/.rnd" (no trailing slash) exits 0 with empty stdout', async () => {
    const result = await runHook(HOOK, input("/some/dir/.rnd"));
    expect(result.exitCode).toBe(0);
    expect(result.stdout.trim()).toBe("");
  });
});

// ---------------------------------------------------------------------------
// T3 Criterion: "self-assessment" as substring in documentation path → blocked
// ---------------------------------------------------------------------------
describe("read-gate: self-assessment substring in documentation path is blocked", () => {
  test("/docs/my-self-assessment-guide/chapter1.txt is blocked", async () => {
    const result = await runHook(
      HOOK,
      input("/docs/my-self-assessment-guide/chapter1.txt"),
    );
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("INFORMATION BARRIER");
  });
});

// ---------------------------------------------------------------------------
// T3 Criterion: symlink behavior documented — hook checks path string only
// ---------------------------------------------------------------------------
describe("read-gate: symlink paths are checked as path strings, not resolved targets", () => {
  test("path 'link-to-sa' that does not contain 'self-assessment' produces no opinion", async () => {
    // The hook checks the path string, not the resolved symlink target.
    // A symlink named "link-to-sa" pointing to a self-assessment file would
    // NOT be blocked because the path string "link-to-sa" does not contain
    // "self-assessment". This is documented behavior — the hook cannot resolve
    // symlinks without filesystem access.
    const result = await runHook(HOOK, input("/project/builds/link-to-sa"));
    expect(result.exitCode).toBe(0);
    expect(result.stdout.trim()).toBe("");
  });
});

// ---------------------------------------------------------------------------
// T5 Criterion 1: verifier + self-assessment → blocked
// ---------------------------------------------------------------------------
describe("read-gate: verifier agent cannot read self-assessment files", () => {
  test("rnd-framework:rnd-verifier is blocked from self-assessment", async () => {
    const result = await runHook(
      HOOK,
      inputWithAgent("/builds/T1-self-assessment.md", "rnd-framework:rnd-verifier"),
    );
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("INFORMATION BARRIER");
  });

  test("agent_type containing 'verifier' substring is blocked", async () => {
    const result = await runHook(
      HOOK,
      inputWithAgent("/builds/T1-self-assessment.md", "custom-verifier"),
    );
    expect(result.exitCode).toBe(2);
  });
});

// ---------------------------------------------------------------------------
// T5 Criterion 2: non-verifier + self-assessment → allowed
// ---------------------------------------------------------------------------
describe("read-gate: non-verifier agents can read self-assessment files", () => {
  test("builder agent is allowed to read self-assessment", async () => {
    const result = await runHook(
      HOOK,
      inputWithAgent("/builds/T1-self-assessment.md", "rnd-framework:rnd-builder"),
    );
    expect(result.exitCode).toBe(0);
  });

  test("planner agent is allowed to read self-assessment", async () => {
    const result = await runHook(
      HOOK,
      inputWithAgent("/builds/T1-self-assessment.md", "rnd-framework:rnd-planner"),
    );
    expect(result.exitCode).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// T5 Criterion 3: absent/empty agent_type → block (backward compat)
// ---------------------------------------------------------------------------
describe("read-gate: absent agent_type defaults to blocking self-assessment", () => {
  test("no agent_type field → self-assessment blocked", async () => {
    const result = await runHook(HOOK, input("/builds/T1-self-assessment.md"));
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("INFORMATION BARRIER");
  });

  test("empty string agent_type → self-assessment blocked", async () => {
    const result = await runHook(
      HOOK,
      inputWithAgent("/builds/T1-self-assessment.md", ""),
    );
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("INFORMATION BARRIER");
  });
});

// ---------------------------------------------------------------------------
// T5 Criterion 4: .rnd/ auto-allow unaffected by agent_type
// ---------------------------------------------------------------------------
describe("read-gate: .rnd/ auto-allow works for all agent types", () => {
  const rndPath = "/home/user/.rnd/project/sessions/20260305-120000-1a2b/plan.md";

  test("verifier gets .rnd/ auto-allow for non-self-assessment path", async () => {
    const result = await runHook(
      HOOK,
      inputWithAgent(rndPath, "rnd-framework:rnd-verifier"),
    );
    expect(result.exitCode).toBe(0);
    const parsed = JSON.parse(result.stdout);
    expect(parsed.hookSpecificOutput.permissionDecision).toBe("allow");
  });
});
