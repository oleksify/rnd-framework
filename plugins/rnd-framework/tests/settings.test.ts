/** Tests for rnd-framework/settings.json (T14) */
import { describe, test, expect } from "bun:test";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { existsSync } from "node:fs";

const PLUGIN_ROOT = join(import.meta.dir, "..");
const SETTINGS_PATH = join(PLUGIN_ROOT, "settings.json");
const REQUIRED_VERBS = ["Planning", "Building", "Verifying", "Integrating"];

describe("T14: settings.json exists at plugin root", () => {
  test("settings.json file exists", () => {
    expect(existsSync(SETTINGS_PATH)).toBe(true);
  });
});

describe("T14: settings.json is valid JSON", () => {
  test("file parses as valid JSON without throwing", async () => {
    const content = await readFile(SETTINGS_PATH, "utf-8");
    expect(() => JSON.parse(content)).not.toThrow();
  });
});

describe("T14: spinnerVerbs key is present", () => {
  test("parsed JSON contains a spinnerVerbs key", async () => {
    const content = await readFile(SETTINGS_PATH, "utf-8");
    const parsed = JSON.parse(content);
    expect(parsed).toHaveProperty("spinnerVerbs");
  });
});

describe("T14: spinnerVerbs contains required pipeline phase verbs", () => {
  test.each(REQUIRED_VERBS)("spinnerVerbs includes '%s'", async (verb) => {
    const content = await readFile(SETTINGS_PATH, "utf-8");
    const parsed = JSON.parse(content);
    expect(Array.isArray(parsed.spinnerVerbs)).toBe(true);
    expect(parsed.spinnerVerbs).toContain(verb);
  });
});

describe("T14: spinner verbs are present participles (quality)", () => {
  test("all spinner verbs end in -ing", async () => {
    const content = await readFile(SETTINGS_PATH, "utf-8");
    const parsed = JSON.parse(content);
    const nonIng = (parsed.spinnerVerbs as string[]).filter(
      (v: string) => !v.endsWith("ing"),
    );
    expect(nonIng).toHaveLength(0);
  });
});
