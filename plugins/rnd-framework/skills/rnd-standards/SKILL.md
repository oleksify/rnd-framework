---
name: rnd-standards
description: "Use when extracting project-specific coding rules from CLAUDE.md files and converting them into regex-based slop patterns saved to $RND_DIR/project-patterns.json"
user-invocable: false
---

# R&D Standards Extraction

## Overview

Projects encode their coding standards as natural-language imperatives and prohibitions in CLAUDE.md files. This skill converts those rules into machine-checkable regex patterns that the slop gate enforces automatically during builds. The output — `$RND_DIR/project-patterns.json` — extends the built-in slop catalog with rules that are specific to the project being worked on.

**Core principle:** Every extractable rule becomes a pattern. Vague rules get skipped with a note. Concrete rules get a regex that catches violations.

## When to Use

- At the start of a pipeline run, before any building begins
- When the project's CLAUDE.md has been updated and patterns may be stale
- When invoked explicitly by `commands/start.md` or `commands/quick.md` during setup

---

## Process

### Step 1: Read All CLAUDE.md Files

Collect every CLAUDE.md in the project using Glob:

```
Glob pattern: **/CLAUDE.md
```

Read each file found. In addition to the project root, also look for `.claude/CLAUDE.md` and `.claude/*/CLAUDE.md` subdirectories, which may contain role-specific overrides.

Read each file in full. Record the source path for each rule you extract (useful for debugging).

### Step 2: Identify Extractable Rules

Scan each file for these rule types:

| Rule type | Examples |
|-----------|---------|
| **Prohibitions** | "NEVER use X", "do not call Y", "avoid Z" |
| **Requirements** | "ALWAYS use X", "must call Y", "all functions must..." |
| **Naming conventions** | "use snake_case", "prefix with `get`", "suffix with `Service`" |
| **Structural requirements** | "no early returns", "no nested ternaries", "functions must not exceed N lines" |
| **Hygiene rules** | "no console.log", "no commented-out code", "no TODO markers" |

Skip rules that are:
- Process-only (e.g., "ask before committing" — no code artifact to match)
- Already covered by the built-in slop catalog (e.g., console.log, empty catch blocks)
- Too vague to write a reliable regex for (e.g., "write clean code")

For each skipped rule, note *why* it was skipped in your self-assessment.

### Step 3: Convert Each Rule to a Pattern Entry

For each extractable rule, produce one JSON object with these fields:

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Kebab-case identifier unique within the file, e.g., `no-early-return` |
| `name` | string | Human-readable name, e.g., `"Early return in function body"` |
| `regex` | string | ECMAScript regex string matching a violation. Must be valid in `new RegExp(pattern)`. |
| `severity` | number | Integer 3 or 4. Use 4 for rules the project marks as critical; 3 for standard rules. |
| `category` | string | Always `"project-standard"` |
| `description` | string | One sentence describing what the pattern detects. |
| `remediation` | string | One sentence describing how to fix it. |

**Severity guidance:**
- `4` — Rules the project marks with NEVER, CRITICAL, or ALWAYS in emphasis (e.g., caps, bold)
- `3` — All other project coding standards

**Regex guidance:**
- Write regexes that match the violation, not the correct pattern
- Test mentally: does this regex match bad code? Does it match good code? Good code should not match.
- Prefer simple, readable patterns over clever ones
- Anchoring with `\b` reduces false positives for word-boundary rules
- For naming convention violations, match the incorrect form (e.g., camelCase identifiers in a snake_case project)

### Step 4: Write project-patterns.json

Save the patterns to `$RND_DIR/project-patterns.json` using the same JSON schema as `slop-patterns.json`:

```json
{
  "patterns": [
    {
      "id": "example-rule",
      "name": "Human readable rule name",
      "regex": "pattern matching violation",
      "severity": 3,
      "category": "project-standard",
      "description": "What this pattern detects.",
      "remediation": "How to fix it."
    }
  ]
}
```

Use the Write tool to create this file. Compute `$RND_DIR` via:

```bash
RND_DIR="$("/path/to/rnd-dir.sh")"
```

The file path is `$RND_DIR/project-patterns.json`.

If no extractable rules are found, write an empty patterns array:

```json
{
  "patterns": []
}
```

---

## Concrete Conversion Examples

### Example 1: Prohibition on early returns

**Rule found in CLAUDE.md:**
> "NEVER use early returns in functions — always use a single exit point"

**Extracted pattern:**

```json
{
  "id": "no-early-return",
  "name": "Early return in function body",
  "regex": "\\breturn\\b.+;(?=[\\s\\S]*?\\breturn\\b)",
  "severity": 4,
  "category": "project-standard",
  "description": "Function contains an early return before the final return statement, violating the single-exit-point rule.",
  "remediation": "Refactor to use a single return at the end of the function; accumulate the result in a variable."
}
```

**Reasoning:** The rule is marked NEVER (caps emphasis) → severity 4. The regex matches a `return` statement that is followed by another `return` elsewhere in the same context, flagging functions with multiple exits.

---

### Example 2: Naming convention (snake_case variables)

**Rule found in CLAUDE.md:**
> "Use snake_case for all variable and function names — never camelCase"

**Extracted pattern:**

```json
{
  "id": "no-camel-case-identifier",
  "name": "camelCase identifier where snake_case is required",
  "regex": "(?:const|let|var|function)\\s+[a-z][a-zA-Z0-9]*[A-Z][a-zA-Z0-9]*\\b",
  "severity": 3,
  "category": "project-standard",
  "description": "Variable or function name uses camelCase, which is prohibited by project naming conventions.",
  "remediation": "Rename the identifier to snake_case (e.g., myVariable → my_variable)."
}
```

**Reasoning:** Standard naming convention (not marked critical) → severity 3. The regex matches `const`/`let`/`var`/`function` declarations where the identifier contains an uppercase letter after a lowercase start.

---

### Example 3: Prohibition on a specific function call

**Rule found in CLAUDE.md:**
> "Do not use `process.exit()` directly — always throw an Error instead"

**Extracted pattern:**

```json
{
  "id": "no-process-exit",
  "name": "Direct process.exit() call",
  "regex": "\\bprocess\\.exit\\s*\\(",
  "severity": 3,
  "category": "project-standard",
  "description": "Direct call to process.exit() bypasses error handling and cleanup; the project requires throwing an Error instead.",
  "remediation": "Replace process.exit(1) with throw new Error('reason') to allow proper cleanup and error propagation."
}
```

**Reasoning:** Standard prohibition (no emphasis marker) → severity 3. The regex matches `process.exit(` with any whitespace between the name and parenthesis.

---

### Example 4: Structural requirement (max function length)

**Rule found in CLAUDE.md:**
> "Functions must not exceed 30 lines — split longer functions into smaller helpers"

**Extracted pattern:**

This rule cannot be reliably expressed as a single-line regex. **Skip it** and note in the self-assessment: "max-function-length rule requires multi-line analysis, not expressible as a single regex — skipped."

---

## Output Checklist

Before saving `project-patterns.json`, verify:

- [ ] Every pattern `id` is unique within the file
- [ ] Every `regex` is a valid ECMAScript regex (mentally test `new RegExp(pattern)`)
- [ ] Every `severity` is 3 or 4
- [ ] Every `category` is `"project-standard"`
- [ ] No pattern duplicates a built-in slop-patterns.json pattern (same behavior, even if different id)
- [ ] Skipped rules are noted in the session log or self-assessment

---

## Related Skills

- `rnd-framework:rnd-slop-detection` — Explains how the slop gate uses patterns and interprets verdicts; project patterns integrate into the same pipeline
- `rnd-framework:rnd-building` — Builders receive slop gate verdicts in real time; project patterns extend what the gate checks
