// Tests for hooks/reality-warn
// The module detects external service references and emits advisory warnings.

import { describe, expect, test } from "bun:test";
import {
  scanExternalRefs,
  buildRealityWarning,
  MCP_PATTERNS,
  HTTP_PATTERNS,
  DB_PATTERNS,
  ENV_PATTERNS,
} from "../hooks/reality-warn.ts";

// ---------------------------------------------------------------------------
// Category: MCP tool calls
// ---------------------------------------------------------------------------

describe("reality-warn: MCP tool call detection", () => {
  test("detects mcp_ prefix in function calls", () => {
    const result = scanExternalRefs('const result = mcp_tool_call("args");');
    expect(result.some((r) => r.category === "MCP tool calls")).toBe(true);
  });

  test("detects useMcpTool pattern", () => {
    const result = scanExternalRefs("const r = useMcpTool({ name: 'search' });");
    expect(result.some((r) => r.category === "MCP tool calls")).toBe(true);
  });

  test("detects use_mcp_tool pattern", () => {
    const result = scanExternalRefs("await use_mcp_tool('search', params);");
    expect(result.some((r) => r.category === "MCP tool calls")).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// Category: HTTP clients
// ---------------------------------------------------------------------------

describe("reality-warn: HTTP client detection", () => {
  test("detects fetch( calls", () => {
    const result = scanExternalRefs('const data = await fetch("https://api.example.com");');
    expect(result.some((r) => r.category === "HTTP clients")).toBe(true);
  });

  test("detects axios. usage", () => {
    const result = scanExternalRefs("const res = await axios.get('/api/users');");
    expect(result.some((r) => r.category === "HTTP clients")).toBe(true);
  });

  test("detects got( calls", () => {
    const result = scanExternalRefs("const body = await got('https://example.com').json();");
    expect(result.some((r) => r.category === "HTTP clients")).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// Category: Database drivers
// ---------------------------------------------------------------------------

describe("reality-warn: database driver detection", () => {
  test("detects better-sqlite3 import", () => {
    const result = scanExternalRefs("import Database from 'better-sqlite3';");
    expect(result.some((r) => r.category === "Database drivers")).toBe(true);
  });

  test("detects pg import", () => {
    const result = scanExternalRefs("import { Pool } from 'pg';");
    expect(result.some((r) => r.category === "Database drivers")).toBe(true);
  });

  test("detects prisma import", () => {
    const result = scanExternalRefs("import { PrismaClient } from '@prisma/client';");
    expect(result.some((r) => r.category === "Database drivers")).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// Category: Environment variable reads
// ---------------------------------------------------------------------------

describe("reality-warn: env var detection", () => {
  test("detects process.env. reads", () => {
    const result = scanExternalRefs("const apiKey = process.env.API_KEY;");
    expect(result.some((r) => r.category === "Environment variables")).toBe(true);
  });

  test("detects Bun.env. reads", () => {
    const result = scanExternalRefs("const secret = Bun.env.SECRET;");
    expect(result.some((r) => r.category === "Environment variables")).toBe(true);
  });

  test("detects import.meta.env. reads", () => {
    const result = scanExternalRefs("const url = import.meta.env.VITE_API_URL;");
    expect(result.some((r) => r.category === "Environment variables")).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// No output for clean code
// ---------------------------------------------------------------------------

describe("reality-warn: no output for clean code", () => {
  test("pure math code returns empty array", () => {
    const result = scanExternalRefs("const x = 1 + 2;\nconst y = x * 3;\n");
    expect(result).toEqual([]);
  });

  test("type declarations return empty array", () => {
    const result = scanExternalRefs("interface User { id: string; name: string; }");
    expect(result).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// Advisory message content
// ---------------------------------------------------------------------------

describe("reality-warn: advisory message", () => {
  test("returns null when no matches", () => {
    const msg = buildRealityWarning([]);
    expect(msg).toBeNull();
  });

  test("mentions Reality Auditor by name", () => {
    const matches = [{ category: "HTTP clients", matches: ["fetch"] }];
    const msg = buildRealityWarning(matches);
    expect(msg).not.toBeNull();
    expect(msg).toContain("Reality Auditor");
  });

  test("includes detected categories in message", () => {
    const matches = [
      { category: "HTTP clients", matches: ["fetch"] },
      { category: "Database drivers", matches: ["better-sqlite3"] },
    ];
    const msg = buildRealityWarning(matches);
    expect(msg).toContain("HTTP clients");
    expect(msg).toContain("Database drivers");
  });

  test("includes all four categories when all match", () => {
    const matches = [
      { category: "MCP tool calls", matches: ["mcp_"] },
      { category: "HTTP clients", matches: ["fetch"] },
      { category: "Database drivers", matches: ["pg"] },
      { category: "Environment variables", matches: ["process.env."] },
    ];
    const msg = buildRealityWarning(matches);
    expect(msg).toContain("MCP tool calls");
    expect(msg).toContain("HTTP clients");
    expect(msg).toContain("Database drivers");
    expect(msg).toContain("Environment variables");
  });
});

// ---------------------------------------------------------------------------
// Exported pattern arrays
// ---------------------------------------------------------------------------

describe("reality-warn: exported pattern arrays", () => {
  test("MCP_PATTERNS is a non-empty array of RegExp", () => {
    expect(Array.isArray(MCP_PATTERNS)).toBe(true);
    expect(MCP_PATTERNS.length).toBeGreaterThan(0);
    expect(MCP_PATTERNS[0]).toBeInstanceOf(RegExp);
  });

  test("HTTP_PATTERNS is a non-empty array of RegExp", () => {
    expect(Array.isArray(HTTP_PATTERNS)).toBe(true);
    expect(HTTP_PATTERNS.length).toBeGreaterThan(0);
  });

  test("DB_PATTERNS is a non-empty array of RegExp", () => {
    expect(Array.isArray(DB_PATTERNS)).toBe(true);
    expect(DB_PATTERNS.length).toBeGreaterThan(0);
  });

  test("ENV_PATTERNS is a non-empty array of RegExp", () => {
    expect(Array.isArray(ENV_PATTERNS)).toBe(true);
    expect(ENV_PATTERNS.length).toBeGreaterThan(0);
  });
});
