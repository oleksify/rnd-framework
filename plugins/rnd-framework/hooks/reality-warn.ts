// hooks/reality-warn.ts — Pure library module for external service reference detection.
//
// Exported functions: scanExternalRefs, buildRealityWarning
// Exported constants: MCP_PATTERNS, HTTP_PATTERNS, DB_PATTERNS, ENV_PATTERNS
//
// This module has no main(), no shebang, no stdin reading.
// The executable entry point is hooks/post-tool-use.ts.

export const MCP_PATTERNS: Array<RegExp> = [
  /mcp_\w+/g,
  /useMcpTool\s*\(/g,
  /use_mcp_tool\s*\(/g,
  /CallTool\s*\(/g,
  /mcp__\w+/g,
];

export const HTTP_PATTERNS: Array<RegExp> = [
  /fetch\s*\(/g,
  /axios\.\w+\s*\(/g,
  /\bgot\s*\(/g,
  /\bky\.\w+\s*\(/g,
  /http\.get\s*\(/g,
  /http\.post\s*\(/g,
];

export const DB_PATTERNS: Array<RegExp> = [
  /['"]better-sqlite3['"]/g,
  /['"]pg['"]/g,
  /['"]mysql2['"]/g,
  /['"]prisma['"]/g,
  /['"]drizzle['"]/g,
  /['"]knex['"]/g,
  /['"]sequelize['"]/g,
  /['"]typeorm['"]/g,
  /['"]sqlite3['"]/g,
  /['"]@libsql\/\w+['"]/g,
  /from\s+['"]@prisma\/client['"]/g,
];

export const ENV_PATTERNS: Array<RegExp> = [
  /process\.env\./g,
  /Bun\.env\./g,
  /import\.meta\.env\./g,
];

export interface CategoryMatch {
  category: string;
  matches: string[];
}

export function scanExternalRefs(content: string): CategoryMatch[] {
  const results: CategoryMatch[] = [];

  const categories: Array<{ name: string; patterns: Array<RegExp> }> = [
    { name: "MCP tool calls", patterns: MCP_PATTERNS },
    { name: "HTTP clients", patterns: HTTP_PATTERNS },
    { name: "Database drivers", patterns: DB_PATTERNS },
    { name: "Environment variables", patterns: ENV_PATTERNS },
  ];

  for (const { name, patterns } of categories) {
    const found = new Set<string>();
    for (const pattern of patterns) {
      pattern.lastIndex = 0;
      let match: RegExpExecArray | null;
      while ((match = pattern.exec(content)) !== null) {
        found.add(match[0].trim());
      }
    }
    if (found.size > 0) {
      results.push({ category: name, matches: Array.from(found) });
    }
  }

  return results;
}

export function buildRealityWarning(matches: CategoryMatch[]): string | null {
  if (matches.length === 0) return null;
  const categories = matches.map((m) => m.category).join(", ");
  return (
    `\u26a0 Reality Auditor: This code references external services (${categories}). ` +
    `The Reality Auditor will verify all service assumptions against live services in Phase 2.5.`
  );
}
