---
name: rnd-slop-detection
description: "Use when interpreting slop gate findings, remediating flagged anti-patterns in code, or understanding how the structural quality signal integrates with the verification pipeline"
user-invocable: false
---

# R&D Slop Detection

## Overview

The slop gate is a PostToolUse hook that runs after every `Write` or `Edit` tool call on a code file. It scans the written content against a catalog of structural LLM anti-patterns — patterns that frequently appear in AI-generated code but rarely in thoughtfully hand-written code. The gate is advisory: it never blocks tool calls, always exits 0, and surfaces findings as inline advisory context so agents see violations immediately.

**Core principle:** Slop detection is a structural quality signal, not a correctness check. Findings don't mean the code is wrong — they mean the code contains patterns that suggest mechanical generation rather than careful thought. Remediation is usually fast and always improves readability.

## When to Use

- When slop gate advisory messages appear after your Write/Edit calls and you want to understand what triggered them
- When you see findings listed and need to remediate your code before the Verifier runs
- When reading a `$RND_DIR/slop-reports/` artifact and need to interpret its contents
- When the Verifier flags a slop report as part of quality criteria evidence
- Before submitting a build, to proactively scan your own output for structural anti-patterns

---

## Pattern Catalog

Each pattern has a severity from 1 (minor style issue) to 5 (serious structural problem). Severity drives the scoring algorithm.

### Category: over-commenting

#### over-commenting — Comment restates code (severity 2)

Comments that describe the mechanics of the next line rather than explaining why the code exists. The worst kind: adding noise without information.

**Before (flagged):**
```typescript
// increment the counter
counter++;

// return the result
return result;

// initialize the array
const items = [];
```

**After (remediated):**
```typescript
counter++;
return result;
const items = [];
```

Keep comments that explain intent, constraints, or non-obvious decisions. Remove comments that just describe what the code already says.

---

### Category: hygiene

#### placeholder-todo — TODO/FIXME left in code (severity 3)

Inline TODO, FIXME, HACK, or XXX markers indicate unresolved work. Leaving them in submitted code signals the implementation is incomplete.

**Before (flagged):**
```typescript
// TODO: handle the error case
// FIXME: this doesn't work for empty arrays
// HACK: temporary workaround
```

**After (remediated):**
```typescript
// Either resolve the issue inline:
if (items.length === 0) return [];

// Or track it externally and remove the marker entirely.
```

#### commented-out-code — Dead code left behind (severity 3)

Code that has been commented out instead of deleted. Version control preserves history; commented-out code is noise.

**Before (flagged):**
```typescript
// const oldResult = computeLegacy(input);
// if (oldResult !== null) {
//   return oldResult;
// }
return computeNew(input);
```

**After (remediated):**
```typescript
return computeNew(input);
```

#### console-log-leftover — Debug logging left behind (severity 3)

`console.log`, `console.debug`, `console.warn`, etc. left in production code after development. Replace with a structured logger that can be toggled, or remove entirely.

**Before (flagged):**
```typescript
console.log("Processing item:", item);
const result = transform(item);
console.debug("result:", result);
return result;
```

**After (remediated):**
```typescript
const result = transform(item);
return result;
```

---

### Category: error-handling

#### empty-catch-block — Silent exception swallowing (severity 4)

A catch block with no body silently hides errors. This is the highest-severity pattern in the catalog because it turns runtime failures invisible.

**Before (flagged):**
```typescript
try {
  await writeFile(path, content);
} catch (e) {
  // silently swallowed
}
```

**After (remediated):**
```typescript
try {
  await writeFile(path, content);
} catch (e) {
  logger.error("Failed to write file", { path, error: e });
  throw e;
}
```

At minimum, log the error. If silent handling is genuinely intentional, add a comment explaining why.

#### cargo-cult-try-catch — Try-catch around infallible code (severity 3)

Wrapping synchronous literal assignments or obviously infallible operations in try-catch adds defensive ceremony without benefit.

**Before (flagged):**
```typescript
try {
  const limit = 100;
} catch (e) {
  handleError(e);
}
```

**After (remediated):**
```typescript
const limit = 100;
```

#### over-defensive-null-check — Null check on non-null value (severity 1)

Guarding against null on a value the type system or prior logic guarantees is non-null. Minor, but signals the author didn't trust their own code.

**Before (flagged):**
```typescript
// config was constructed 3 lines earlier and cannot be null
if (config === null) {
  throw new Error("config is null");
}
```

**After (remediated):**
```typescript
// Trust the type. If you genuinely need a guard, use TypeScript's non-null assertion:
const value = config!.timeout;
```

---

### Category: control-flow

#### unnecessary-else-after-return — Redundant else branch (severity 2)

When an if block ends with `return`, the else branch is unreachable within the if, making the `else` keyword redundant. It adds indentation without adding logic.

**Before (flagged):**
```typescript
if (items.length === 0) {
  return [];
} else {
  return items.map(transform);
}
```

**After (remediated):**
```typescript
if (items.length === 0) {
  return [];
}
return items.map(transform);
```

---

### Category: abstraction

#### unnecessary-wrapper-function — Pass-through wrapper (severity 2)

A function whose body does nothing but call another function with the same arguments. This adds indirection without adding behavior.

**Before (flagged):**
```typescript
function processItem(item: Item): Result {
  return doProcessItem(item);
}
```

**After (remediated):**
```typescript
// Use the function directly, or alias it:
const processItem = doProcessItem;
```

#### empty-function-body — Unimplemented function (severity 3)

A function body that is empty or contains only a comment. This is a placeholder that was not filled in.

**Before (flagged):**
```typescript
function validateInput(input: unknown): boolean {
  // TODO: implement
}
```

**After (remediated):**
```typescript
function validateInput(input: unknown): boolean {
  if (typeof input !== "object" || input === null) return false;
  return "id" in input && "name" in input;
}
```

#### verbose-object-spread-copy — Manual property copying (severity 2)

Constructing an object by manually copying three or more properties from another object, when `{ ...source }` would be clearer.

**Before (flagged):**
```typescript
const copy = {
  id: original.id,
  name: original.name,
  email: original.email,
  role: original.role,
};
```

**After (remediated):**
```typescript
const copy = { ...original };
// or, if only some fields are needed:
const { id, name, email, role } = original;
```

#### re-export-barrel — Unnecessary barrel file (severity 1)

An index file that only re-exports from other modules. Barrel files add indirection and slow TypeScript compilation.

**Before (flagged):**
```typescript
export { UserService } from "./user-service";
export { AuthService } from "./auth-service";
export { DataService } from "./data-service";
```

**After (remediated):**
```typescript
// Import directly from the source module:
import { UserService } from "./services/user-service";
```

---

### Category: typing

#### excessive-type-annotation — Obvious type on literal (severity 1)

Explicitly annotating a variable whose type is already obvious from the literal value assigned. TypeScript infers these automatically.

**Before (flagged):**
```typescript
const maxRetries: number = 3;
const isEnabled: boolean = true;
const greeting: string = "hello";
```

**After (remediated):**
```typescript
const maxRetries = 3;
const isEnabled = true;
const greeting = "hello";
```

#### unnecessary-async — Async function with no await (severity 2)

Declaring a function `async` when it contains no `await` expression wraps the return value in a Promise unnecessarily.

**Before (flagged):**
```typescript
async function getDefaultConfig(): Promise<Config> {
  return { timeout: 30, retries: 3 };
}
```

**After (remediated):**
```typescript
function getDefaultConfig(): Config {
  return { timeout: 30, retries: 3 };
}
```

#### redundant-return-type — Inferred return type annotation (severity 1)

An explicit return type that TypeScript would infer automatically from the function body.

**Before (flagged):**
```typescript
function isValid(input: string): boolean {
  return input.length > 0;
}
```

**After (remediated):**
```typescript
function isValid(input: string) {
  return input.length > 0;
}
```

---

## Advisory Output

When the slop gate finds matches, it outputs an advisory message visible to the agent. The message format:

```
Slop gate: 2 findings in src/auth.ts
  L12: Over-commenting: comment restates code — "// increment counter" — Remove comments that merely describe the mechanics
  L45: Empty catch block — "} catch (e) { }" — At minimum, log or rethrow the error
```

Each line includes:
- **Line number** (`L12`) — where the violation was found
- **Pattern name** — which anti-pattern was detected
- **Snippet** — the matching code fragment (truncated to 120 chars)
- **Remediation** — what to do about it

When no matches are found (clean code), the gate produces no output — agents only see messages when there are findings to address.

### Diff-Aware Analysis

For `Edit` tool calls, only `new_string` is analyzed — not `old_string` and not the full file. This avoids penalizing pre-existing patterns that the current edit did not introduce. For `Write` tool calls, the full content is analyzed.

### File Filtering

The gate only analyzes code files. These extensions are analyzed: `.ts`, `.tsx`, `.js`, `.jsx`, `.mjs`, `.cjs`, `.py`, `.rb`, `.go`, `.rs`, `.java`, `.c`, `.cpp`, `.h`, `.hpp`, `.cs`, `.swift`, `.kt`, `.scala`, `.sh`, `.bash`, `.zsh`, `.fish`, `.lua`, `.php`, `.vue`, `.svelte`.

Files with no extension, or with extensions outside this list (`.md`, `.json`, `.yaml`, `.yml`, `.toml`, `.txt`, etc.), produce no output and exit 0.

---

## Reading Slop Reports

When an active pipeline session exists, the gate writes structured artifacts to `$RND_DIR/slop-reports/`.

### Per-file reports

Each analyzed file produces a JSON report at `$RND_DIR/slop-reports/<sanitized-path>.json`. The report structure:

```json
{
  "file_path": "src/utils/transform.ts",
  "verdict": "WARN",
  "score": 4.2,
  "line_count": 45,
  "timestamp": "2026-03-12T18:22:00.000Z",
  "matches": [
    {
      "pattern_id": "over-commenting",
      "line": 12,
      "snippet": "// increment the counter"
    },
    {
      "pattern_id": "console-log-leftover",
      "line": 31,
      "snippet": "console.log(\"Processing:\", item)"
    }
  ]
}
```

The filename is derived by replacing path separators with dashes and keeping the file extension: `src/utils/transform.ts` becomes `src-utils-transform.ts.json`.

### Cumulative session score

`$RND_DIR/slop-reports/cumulative-score.json` accumulates across the entire session:

```json
{
  "total_score": 12.6,
  "file_count": 4,
  "average_score": 3.15,
  "worst_file": "src/api/handler.ts",
  "worst_score": 5.8
}
```

Use this to identify which file to remediate first (highest `worst_score`) and to gauge session-wide structural quality trends.

### When no session is active

If no active pipeline session exists (no `.current-session` file), the gate does not create any slop-reports directory. Feedback is still written to stdout for immediate visibility, but no persistent artifact is produced.

---

## Remediation Workflow

When you see slop gate findings after a Write or Edit:

1. **Read the advisory message.** Each line includes the pattern name, line number, snippet, and remediation hint.
2. **Apply the pattern-specific remediation** from the Pattern Catalog above.
3. **Re-run the `Write` or `Edit` tool** with the cleaned-up content. The gate will re-analyze and only show findings that remain.
4. **Address all findings before submitting.** Intentional patterns (e.g., a `console.log` in a CLI tool) can be left, but unintentional slop should be fixed.

### Remediation by Category

| Category | Primary remediation |
|----------|---------------------|
| over-commenting | Delete comments that describe mechanics; keep comments that explain why |
| hygiene | Delete console.log, resolve TODOs, remove commented-out code |
| error-handling | Add logging or rethrow in catch blocks; remove guards on provably non-null values |
| control-flow | Remove else after return; flatten nested conditionals |
| abstraction | Delete wrapper functions; implement empty bodies; use spread for object copies |
| typing | Remove redundant annotations TypeScript can infer; remove unnecessary async |

---

## Relationship to Other Quality Gates

The slop gate is a **structural quality signal**, not a correctness gate. It is distinct from the other quality checks in the pipeline:

| Gate | What it checks | Blocks pipeline? |
|------|----------------|------------------|
| Unit tests | Functional correctness — does the code do what the spec says? | Yes (FAIL blocks) |
| Slop gate | Structural quality — does the code look thoughtfully written? | No (advisory only) |
| Verifier | Independent criterion evidence — does the artifact meet pre-registered success criteria? | Yes (FAIL blocks) |

Slop findings do not block the pipeline. However, a Verifier may treat persistent slop findings as evidence against a Quality tier criterion if the pre-registration includes structural quality requirements. Conversely, clean slop output does not guarantee correctness — the code can be well-structured and still wrong.

**The slop gate answers:** "Does this code look like it was written with care?"

**The Verifier answers:** "Does this code meet the pre-registered success criteria?"

Both questions matter. Neither substitutes for the other.

---

## Related Skills

- `rnd-framework:rnd-verification` — Independent verification process; Verifiers may reference slop reports as quality tier evidence
- `rnd-framework:rnd-failure-modes` — Catalog of reasoning failures in verification; structural quality findings from slop reports can inform failure mode analysis
- `rnd-framework:rnd-building` — Building discipline; the slop gate runs during building and findings should be remediated before the build manifest is submitted
