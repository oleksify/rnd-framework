// hooks/evidence-warn.ts — Pure library module for SQL and API evidence detection.
//
// Exported functions: scanSQL, scanAPI, buildEvidenceWarning
//
// This module has no main(), no shebang, no stdin reading.
// The executable entry point is hooks/post-tool-use.ts.

export const SQL_PATTERNS: Array<RegExp> = [
  /SELECT\s+.*\s+FROM\s+(\w+)/gi,
  /INSERT\s+INTO\s+(\w+)/gi,
  /CREATE\s+TABLE\s+(\w+)/gi,
  /UPDATE\s+(\w+)\s+SET/gi,
  /DELETE\s+FROM\s+(\w+)/gi,
  /ALTER\s+TABLE\s+(\w+)/gi,
  /DROP\s+TABLE\s+(\w+)/gi,
];

export const API_PATTERNS: Array<RegExp> = [
  /fetch\s*\(\s*["'](\/?[^"']+)/gi,
  /axios\.\w+\s*\(\s*["'](\/?[^"']+)/gi,
];

export function scanSQL(content: string): string[] {
  const tables = new Set<string>();
  for (const pattern of SQL_PATTERNS) {
    pattern.lastIndex = 0;
    let match: RegExpExecArray | null;
    while ((match = pattern.exec(content)) !== null) {
      if (match[1]) tables.add(match[1]);
    }
  }
  return Array.from(tables);
}

export function scanAPI(content: string): string[] {
  const endpoints = new Set<string>();
  for (const pattern of API_PATTERNS) {
    pattern.lastIndex = 0;
    let match: RegExpExecArray | null;
    while ((match = pattern.exec(content)) !== null) {
      if (match[1]) endpoints.add(match[1].split("?")[0]);
    }
  }
  return Array.from(endpoints);
}

/**
 * Formats SQL tables and API endpoints into an advisory message string.
 * Returns null when both lists are empty.
 * Pure.
 */
export function buildEvidenceWarning(tables: string[], endpoints: string[]): string | null {
  if (tables.length === 0 && endpoints.length === 0) return null;
  const parts: string[] = [];
  if (tables.length > 0) parts.push(`tables [${tables.join(", ")}]`);
  if (endpoints.length > 0) parts.push(`endpoints [${endpoints.join(", ")}]`);
  return (
    `Evidence check: This code references ${parts.join(" and ")}. ` +
    `Verify you have read the relevant schema/migration files and API specifications before proceeding.`
  );
}
