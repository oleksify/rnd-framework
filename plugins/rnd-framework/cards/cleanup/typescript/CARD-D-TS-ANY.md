---
id: D-TS-ANY
role: cleanup
language: typescript
tags: [dead-code, type-safety]
applicable_task_types: [refactor]
scope: Replace any-typed shims left from a migration with proper types now that the surrounding code is typed.
specializes: [P-IMPOSSIBLE-01]
---

**Before:**
```typescript
// Added during JS→TS migration; TODO: type properly
function parseConfig(raw: any): any {
  return {
    host: raw.host as any,
    port: Number(raw.port),
    flags: (raw.flags ?? []) as any[],
  }
}

const cfg = parseConfig(JSON.parse(fs.readFileSync('config.json', 'utf8')))
```

**After:**
```typescript
interface Config {
  host: string
  port: number
  flags: string[]
}

function parseConfig(raw: Record<string, unknown>): Config {
  return {
    host: String(raw['host']),
    port: Number(raw['port']),
    flags: Array.isArray(raw['flags']) ? raw['flags'].map(String) : [],
  }
}

const cfg = parseConfig(JSON.parse(fs.readFileSync('config.json', 'utf8')))
```

**Why after is better:** `any` disables the type checker for every expression it touches — assignments to `any` fields never produce errors even when the shape is wrong. Migration-era shims annotated with `any` are placeholders, not permanent design. Once surrounding code is typed, the compiler has enough information to derive the correct type. Replace `any` with a concrete interface and let the type checker catch shape mismatches at compile time rather than at runtime.
