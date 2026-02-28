---
name: bun-scripting
description: Use when writing helper scripts, utility tasks, or automation within the R&D pipeline — prefer Bun (TypeScript) over Python when available
---

# Bun as Preferred Scripting Runtime

When the `bun` binary is available on the system, **prefer Bun (TypeScript) over Python** for helper scripts, utility tasks, and automation. Bun provides faster startup, built-in TypeScript support, and a rich set of zero-dependency APIs that cover most scripting needs.

## Detection

Before writing a helper script, check for Bun availability:

```bash
command -v bun >/dev/null 2>&1
```

If `bun` is present, write the script in TypeScript and run it with `bun run script.ts`. If `bun` is not available, fall back to Python as usual.

## Rules

1. **Single-file `.ts` scripts only.** No project setup, no `package.json`, no `tsconfig.json` needed.
2. **Never run `bun install`, `bun add`, or use any npm packages.** Use only Bun built-in APIs and Node.js compatible standard modules.
3. **Allowed imports are strictly limited to:**
   - `Bun.*` globals (always available, no import needed)
   - `bun:sqlite` — embedded SQLite
   - `bun:ffi` — foreign function interface (only if calling system C libraries)
   - `node:fs`, `node:fs/promises` — file system operations
   - `node:path` — path manipulation
   - `node:child_process` — spawning processes
   - `node:os` — OS information
   - `node:crypto` — hashing and cryptography
   - `node:util` — utilities like `promisify`, `TextDecoder`
   - `node:stream` — stream primitives
   - `node:url` — URL parsing
   - `node:zlib` — compression
   - `node:assert` — assertions
   - `node:buffer` — binary data handling
   - `node:events` — event emitters
4. **Never import from bare specifiers** (e.g., `import express from "express"` is forbidden).
5. Use `Bun.$` for shell commands instead of `node:child_process` when possible — it is safer and more ergonomic.

## API Quick Reference

Use these built-in APIs instead of reaching for external packages:

### Files

```typescript
// Read
const text = await Bun.file("path/to/file.txt").text();
const json = await Bun.file("data.json").json();
const bytes = await Bun.file("image.png").arrayBuffer();

// Write
await Bun.write("output.txt", "hello");
await Bun.write("data.json", JSON.stringify(obj, null, 2));

// Check existence
import { existsSync } from "node:fs";
```

### HTTP Requests

```typescript
// GET
const res = await fetch("https://api.example.com/data");
const data = await res.json();

// POST
const res = await fetch("https://api.example.com/submit", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ key: "value" }),
});
```

### Shell Commands

```typescript
// Simple execution
const result = await Bun.$`ls -la /tmp`.text();

// With variables (auto-escaped, safe from injection)
const dir = "/some/path";
const output = await Bun.$`find ${dir} -name "*.ts"`.text();

// Check exit code
const proc = await Bun.$`grep -r "pattern" ./src`.nothrow();
if (proc.exitCode !== 0) {
  console.error("not found");
}
```

### JSON

```typescript
// JSON is native — no imports needed
const parsed = JSON.parse(rawString);
const serialized = JSON.stringify(obj, null, 2);
```

### SQLite

```typescript
import { Database } from "bun:sqlite";

const db = new Database("mydb.sqlite");
db.run("CREATE TABLE IF NOT EXISTS kv (key TEXT PRIMARY KEY, value TEXT)");
db.run("INSERT INTO kv VALUES (?, ?)", ["name", "agent"]);
const row = db.query("SELECT value FROM kv WHERE key = ?").get("name");
```

### Hashing

```typescript
const hash = Bun.hash("some content");
// Or use crypto hashes:
const sha = new Bun.CryptoHasher("sha256").update("content").digest("hex");
```

### Glob

```typescript
const glob = new Bun.Glob("**/*.ts");
for await (const path of glob.scan({ cwd: "./src" })) {
  console.log(path);
}
```

### Paths

```typescript
import { join, resolve, basename, dirname, extname } from "node:path";
```

### Sleep / Timing

```typescript
await Bun.sleep(1000); // ms
```

## When to Still Use Python

Fall back to Python when the task specifically requires:

- Libraries with no Bun built-in equivalent (e.g., image processing with Pillow, scientific computing with NumPy/pandas, ML inference)
- Interacting with a Python-specific ecosystem (e.g., pip packages the user explicitly requested)
- The user explicitly asks for Python

## Example

Instead of:

```python
#!/usr/bin/env python3
import json, subprocess, sys

data = json.loads(open("config.json").read())
result = subprocess.run(["grep", "-r", data["pattern"], "./src"], capture_output=True, text=True)
with open("results.txt", "w") as f:
    f.write(result.stdout)
print(f"Found {len(result.stdout.splitlines())} matches")
```

Write:

```typescript
const data = await Bun.file("config.json").json();
const result = await Bun.$`grep -r ${data.pattern} ./src`.nothrow().text();
await Bun.write("results.txt", result);
console.log(`Found ${result.split("\n").filter(Boolean).length} matches`);
```
