/**
 * Tests for hooks/session-end
 *
 * The hook calls rnd-dir.sh --finish to clear
 * .current-session. Always exits 0.
 */
import { describe, expect, test } from "bun:test";
import { existsSync } from "node:fs";
import { join } from "node:path";
import { runHook, createTestEnv } from "./helpers";

const HOOK = join(
  import.meta.dir, "..", "hooks", "session-end.ts",
);

describe("session-end: always exits 0", () => {
  test("with active session", async () => {
    const e = await createTestEnv({ withSession: true });
    try {
      const r = await runHook(HOOK, undefined, e.env);
      expect(r.exitCode).toBe(0);
    } finally { await e.cleanup(); }
  });

  test("without active session", async () => {
    const e = await createTestEnv({ withSession: false });
    try {
      const r = await runHook(HOOK, undefined, e.env);
      expect(r.exitCode).toBe(0);
    } finally { await e.cleanup(); }
  });
});

describe("session-end: clears .current-session", () => {
  test("removes marker when active", async () => {
    const e = await createTestEnv({ withSession: true });
    try {
      const f = join(e.baseDir, ".current-session");
      expect(existsSync(f)).toBe(true);
      await runHook(HOOK, undefined, e.env);
      expect(existsSync(f)).toBe(false);
    } finally { await e.cleanup(); }
  });

  test("idempotent — twice is fine", async () => {
    const e = await createTestEnv({ withSession: true });
    try {
      await runHook(HOOK, undefined, e.env);
      const r2 = await runHook(HOOK, undefined, e.env);
      expect(r2.exitCode).toBe(0);
    } finally { await e.cleanup(); }
  });
});
