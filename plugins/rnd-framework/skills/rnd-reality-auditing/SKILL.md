---
name: rnd-reality-auditing
description: "Adversarial methodology for verifying external service contracts — identifies SQL, API, MCP, SDK, and env-var assumptions in Builder code, designs disproving experiments, and produces reality reports with VALID/INVALID/UNCHECKED verdicts backed by raw evidence"
effort: medium
---

# Reality Auditing

## Overview

Builders hallucinate. They write code that assumes a table column exists, an API returns a certain shape, or an environment variable is set — and none of those assumptions have been checked against the real system. Reality auditing exists to catch this before it reaches production.

**Core principle:** Assume the Builder hallucinated everything. For every external service interaction in the code, construct an experiment designed to disprove the assumption. If the assumption survives the experiment, mark it VALID. If it doesn't, mark it INVALID. If the experiment cannot be run, mark it UNCHECKED.

This is adversarial by design. You are not confirming what the Builder said — you are trying to prove them wrong.

## When to Use

Run on every pipeline task — the audit is mandatory, not conditional on the presence of external dependencies. Even tasks that appear purely internal may reference external data (URLs, package names, service endpoints) in generated content, configuration, or seed data.

- After the Builder produces a build manifest and before the Verifier writes its verdict
- When the Builder's self-assessment lists unverified external assumptions
- Whenever the post-tool-use hook emits a Reality Auditor advisory

## The Iron Laws

```
1. NEVER MARK A CLAIM VALID WITHOUT RUNNING THE EXPERIMENT — if you can't run it, it's UNCHECKED
2. EVERY VERDICT MUST INCLUDE THE EXPERIMENT COMMAND AND RAW OUTPUT
3. INVALID VERDICTS MUST INCLUDE BOTH EXPECTED AND ACTUAL VALUES
4. UNCHECKED IS ONLY ACCEPTABLE WHEN THE SERVICE IS UNREACHABLE OR THE EXPERIMENT CANNOT BE RUN
5. NEVER MODIFY PROJECT SOURCE FILES — all writes go to $RND_DIR/reality/
6. DO NOT READ $RND_DIR/builds/T<id>-self-assessment.md — information barrier
```

## Identifying External Service Interactions

Scan the Builder's code and changed files for these six categories. Each one is a candidate for an adversarial experiment.

### 1. SQL / Database

Patterns to look for:
- Raw SQL strings: `SELECT`, `INSERT`, `UPDATE`, `DELETE`, `CREATE TABLE`, `ALTER TABLE`
- ORM model definitions: `@Entity`, `model User`, `createTable`, schema files
- Migration files: anything in `migrations/`, `db/schema.*`, `prisma/schema.prisma`
- Column references: `users.email`, `orders.status`, schema assertions

For each: identify the exact table name, column name, and assumed type. Those are your hypotheses.

### 2. HTTP APIs

Patterns to look for:
- `fetch(`, `axios.`, `got.`, `ky.`, `request(`, `http.get(`, `https.get(`
- URL strings: `https://api.example.com/v2/users`
- Expected response shapes in destructuring: `const { data, total } = await res.json()`
- Status code checks: `if (res.status === 201)`

For each: identify the endpoint, method, and expected response shape.

### 3. MCP Tools

Patterns to look for:
- `mcp__`, `use_mcp_tool`, `useMcpTool`
- Tool invocation patterns: `mcp__serverName__toolName`
- Any reference to external MCP servers by name

For each: identify the server name, tool name, and expected return shape.

### 4. SDK / Library Calls

Patterns to look for:
- Imported external service clients: `Stripe`, `S3`, `SendGrid`, `Twilio`, `OpenAI`
- Method calls: `stripe.charges.create(`, `s3.putObject(`, `openai.chat.completions.create(`
- Library-specific patterns: `prisma.user.findUnique(`, `drizzle.select().from(`

For each: identify the method, the expected arguments, and the expected return shape.

### 5. Environment Variables

Patterns to look for:
- `process.env.DATABASE_URL`, `Bun.env.API_KEY`, `process.env.STRIPE_SECRET_KEY`
- Config reads: `config.get('database.url')`, `dotenv.parse`
- Any variable whose value comes from outside the process

For each: identify the variable name and what the code assumes about its value (non-empty, valid URL, valid key format).

### 6. External Data References

Patterns to look for:
- URLs embedded in data: `https://example.com`, `http://`, `ftp://`
- Email addresses: `user@domain.com` patterns in seed data, config files, or generated content
- Phone numbers: formatted phone strings in data files
- Physical addresses: street/city/postal code strings in seed data or content
- API endpoints referenced as string literals in data (not code): `"endpoint": "https://api.service.com/v1"`
- Package or library names embedded in content: `"dependency": "some-package@2.3.0"`, documentation references

For each: identify the referenced entity and what the code or data assumes about its existence, reachability, or format.

## Reading Builder's Manifest

Before scanning code, read `$RND_DIR/builds/T<id>-manifest.md` and extract the `## External References` section if present. This section lists external dependencies the Builder declared explicitly.

Use declared references as your starting hypothesis list. Do not trust them — treat each declared reference as a claim that must survive adversarial testing. The Builder may have declared correct references or may have missed some.

After extracting declared references, proceed to Diff-Based Reference Discovery to catch references the Builder did not declare.

## Diff-Based Reference Discovery

Scan all files created or modified by the Builder (listed under `## Files Created/Modified` in the build manifest) for undeclared external references. This catches what the Builder missed.

For each changed file:
1. Read the file and scan for all six categories above (SQL, HTTP APIs, MCP Tools, SDK/Library, Environment Variables, External Data References)
2. Cross-reference against the declared references from the manifest
3. Any reference found in scanning but absent from the manifest is an undeclared assumption — add it to your experiment list and flag it as undeclared in the reality report

Record every discovered reference, whether declared or undeclared. Undeclared references are higher-priority audit targets — the Builder may not have considered whether they are correct.

## Existence Pre-Pass

Before writing adversarial experiments, run a mechanical existence check on every reference the Builder claims. LLM fabrication — invented module names, nonexistent methods, made-up RFC numbers, phantom env vars — is a worse failure than a contract mismatch. Catch it first.

**When to run:** Always, as Step 0, before the Adversarial Experiment Design phase. A single MISSING verdict short-circuits the entire audit: return status `INVALID_FOUND` immediately without running adversarial experiments.

**Probe execution constraint:** Write each probe as a file to `$RND_DIR/reality/T<id>-experiments/existence-probe-<n>.{py,js,sh}` and execute it by path. Prefer `python file.py` over `python -c '…'` — file execution is reviewable and produces a durable artifact at `$RND_DIR`.

### Reference Categories

Check four categories of references declared in the Builder's manifest and source files:

#### 1. Imports

Module imports that the Builder claims resolve at runtime.

Patterns: `import x`, `require('x')`, `from x import y`, `use x::y`

Probe: write a minimal import-and-exit file, execute it, confirm exit 0.

Example Python probe (`existence-probe-1.py`):
```python
import json  # replace with the claimed module name
```

Example Node probe (`existence-probe-1.js`):
```javascript
require('fs')  // replace with the claimed package name
```

#### 2. Third-Party Method Calls

Methods or attributes the Builder accesses on external libraries, SDKs, or APIs — where the module exists but the specific symbol might not.

Patterns: `library.method(`, `obj.attribute`, `SomeClass.staticMethod(`

Probe: write a file that imports the module and accesses the symbol, confirm no `AttributeError` / `TypeError`.

Example (`existence-probe-2.py`):
```python
import boto3
getattr(boto3, 'client')  # replace with the claimed attribute
```

#### 3. RFC / Error-Code Citations

RFC numbers, HTTP status codes, error code constants, or specification references the Builder cites as authoritative.

Patterns: `RFC 7234`, `HTTP 418`, `errno.ENOENT`, `POSIX.1-2017`

Probe: for stdlib constants, write a file that imports the module and reads the constant; for RFC numbers and external specs, mark UNCHECKED (unreachable citation — note the claimed text in the report).

Example (`existence-probe-3.py`):
```python
import errno
val = errno.ENOENT  # replace with the claimed constant
print(val)
```

#### 4. Environment Variable Names

Env var names the Builder reads that must exist in the execution environment or be declared in the project's documented config.

Patterns: `os.environ['VAR']`, `process.env.VAR`, `Bun.env.VAR`, `${VAR}`

Probe: write a shell file that checks the var is documented (grep the project's `.env.example`, `README`, or config file) OR confirm the var is set in the current environment.

Example (`existence-probe-4.sh`):
```bash
#!/usr/bin/env bash
set -euo pipefail
# Check that the claimed env var is declared in the project's documented config.
grep -r "MY_VAR" . --include="*.env.example" --include="*.md" | head -1
```

### Probe Execution

Execute each probe by file path using Bash:

```bash
python3 "$RND_DIR/reality/T<id>-experiments/existence-probe-1.py"
node "$RND_DIR/reality/T<id>-experiments/existence-probe-1.js"
bash "$RND_DIR/reality/T<id>-experiments/existence-probe-4.sh"
```

### Verdicts

| Verdict | Meaning |
|---------|---------|
| `EXISTS` | Probe ran and exited 0; the reference resolves |
| `MISSING` | Probe ran and exited non-zero; the reference does not exist |
| `UNCHECKED` | Probe could not be constructed or run (e.g., unreachable spec, missing runtime) |

A single `MISSING` verdict halts the audit. Return status `INVALID_FOUND` and do not proceed to adversarial experiments.

### Calibration Hook

When the pre-pass finds a MISSING reference AND the task has a prior Builder PASS record for the same `taskId` in the same session, the orchestrator must append a `FALSE_PASS_PROXY` calibration record to `calibration.jsonl` linking to the original PASS via `proxyFor`. This surfaces the earlier incorrect PASS in closed-loop calibration metrics.

See `rnd-framework:rnd-calibration` for the `FALSE_PASS_PROXY` record schema and the `proxyFor` field specification.

## Adversarial Experiment Design

For each interaction found, frame the experiment as a falsification attempt:

> "If this assumption is wrong, this command will fail or show X."

Never design experiments to confirm — design them to disprove. If the assumption survives, that's your evidence.

### Experiment Structure

```
Hypothesis: [Precise claim the code makes — table column, endpoint shape, env var]
Experiment: [Exact command or query to run]
Expected output: [What the raw output must contain for the hypothesis to hold]
Disproving condition: [What in the output would falsify the hypothesis]
```

### Concrete Example — SQL

```
Hypothesis: Table `users` has columns `id` (INTEGER), `email` (TEXT), `name` (TEXT)
Experiment: sqlite3 ./dev.db "PRAGMA table_info(users);"
             (PostgreSQL: psql $DATABASE_URL -c "\d users")
             (MySQL: mysql -u root mydb -e "DESCRIBE users;")
Expected output: Rows for id, email, name appear with matching type labels
Disproving condition: Any column is missing, has a different type, or the table does not exist

If disproved: INVALID — record expected schema vs actual schema from the raw output
```

### Concrete Example — HTTP API

```
Hypothesis: GET /api/v2/users returns JSON with shape { data: User[], total: number }
Experiment: curl -s https://api.example.com/api/v2/users \
              -H "Authorization: Bearer $API_TOKEN" | head -c 500
Expected output: JSON object containing a "data" key (array) and a "total" key (number)
Disproving condition: Response is not JSON, missing "data" or "total" keys, or error status

If disproved: INVALID — record expected shape vs actual response from the raw output
```

### Experiment Execution Rules

- Run the experiment exactly as written — do not interpret or summarize before recording raw output
- Capture raw stdout, including error messages and unexpected fields
- If a command requires credentials, use environment variables already set in the shell — do not hardcode secrets
- For database experiments, prefer read-only queries (`PRAGMA`, `\d`, `DESCRIBE`, `SELECT 1 FROM`)
- For API experiments, use `curl -s` with `head -c 500` to limit output size while preserving shape evidence

## Verdicts

### VALID

The experiment ran and the raw output confirms the hypothesis. The assumption survived adversarial testing.

Requirements:
- Experiment command must be recorded
- Raw output must be pasted
- No additional fields required beyond the standard report structure

### INVALID

The experiment ran and the raw output disproves the hypothesis. The assumption is wrong.

Requirements:
- Experiment command must be recorded
- Raw output must be pasted
- **Expected** field must state what the code assumed (derived from the code, not the experiment)
- **Actual** field must state what the experiment found (derived from the raw output, not expectation)

Both fields are mandatory. An INVALID verdict without Expected and Actual is incomplete.

### UNCHECKED

The experiment could not be run. This verdict is only acceptable when:
- The service is unreachable (network not available, sandbox environment, credentials missing)
- The experiment tool is not installed and cannot be installed in this environment
- The service requires a resource that does not exist in this environment (e.g., a production database)

Requirements:
- **Reason** field must explain exactly why the experiment could not be run
- Must not be used as a shortcut when the experiment would be inconvenient to run

## Reality Report Template

Save to `$RND_DIR/reality/T<id>-reality-report.md`.

```markdown
# Reality Report: T<id>

## Summary
- External interactions found: N
- VALID: X
- INVALID: Y
- UNCHECKED: Z

## Existence Pre-Pass

| Reference | Category | Verdict |
|-----------|----------|---------|
| `module_name` | import | EXISTS \| MISSING \| UNCHECKED |
| `library.method` | third-party method | EXISTS \| MISSING \| UNCHECKED |
| `RFC 7234` | RFC/error-code citation | EXISTS \| MISSING \| UNCHECKED |
| `MY_ENV_VAR` | env-var name | EXISTS \| MISSING \| UNCHECKED |

**Pre-pass status:** EXISTS (all resolved) | MISSING (short-circuited to INVALID_FOUND) | UNCHECKED (runtime unavailable)

_If any reference is MISSING, stop here. Overall status: `INVALID_FOUND`. Do not proceed to adversarial experiments._

## Interactions

### 1. [Short description of the interaction]
**Source:** [file:line — exact code snippet showing the assumption]
**Hypothesis:** [Precise claim the code makes]
**Experiment:** [Exact command run]
**Raw output:**
\`\`\`
[paste actual output here — do not paraphrase]
\`\`\`
**Verdict:** VALID | INVALID | UNCHECKED
**Expected:** [what the code assumed — required for INVALID]
**Actual:** [what the experiment found — required for INVALID]
**Reason:** [why the experiment could not run — required for UNCHECKED]

### 2. ...
```

## Required Report Sections

Every `T<id>-reality-report.md` MUST include EITHER a `## Anomalies` section with at least one bullet entry containing a `Source: <file/line/URL>` subfield, OR a `## No-Finding Rationale` section with ≥200 characters of substantive prose explaining why no anomalies were found. The anomaly-gate.sh hook enforces this on SubagentStop.

## Evidence Chain Requirements

Every reality report is an evidence chain. Each link must hold:

1. **Source** — pinpoints the code making the assumption (file and line)
2. **Hypothesis** — makes the assumption explicit and falsifiable
3. **Experiment** — is a real command that can be re-run by anyone
4. **Raw output** — is the unedited output from running the experiment
5. **Verdict** — follows necessarily from the raw output

A verdict that cannot be traced back through all five links is not a verdict — it is an opinion.

Never infer a verdict from reading the code alone. The experiment must run. If it cannot, the verdict is UNCHECKED.

## Artifact Location

All reality auditing artifacts go to `$RND_DIR/reality/`:

```
$RND_DIR/reality/
├── T<id>-reality-report.md      # Report with all verdicts
└── T<id>-experiments/           # Optional: raw experiment output for long outputs
```

Never write to the project source tree.

## Schema-as-Property Checks

When an `External dependencies` entry in the pre-registration carries a `schema:` sub-field, the declared JSON Schema acts as a degenerate property: "for all response samples, required fields match this schema." This check runs inside the existing Reality-Auditor flow — no new agent is spawned.

### Dispatch

Detect the `schema:` sub-field in the `External dependencies` block → invoke `lib/run-properties.sh` in schema mode → record the verdict in the reality report.

```
bash "${CLAUDE_PLUGIN_ROOT}/lib/run-properties.sh" schema <schema-fixture-path> <project-dir>
```

### Schema Fixture Format

The schema fixture is a JSON file with two top-level keys:

```json
{
  "required": ["field1", "field2"],
  "sample":   { "field1": "value", "field2": "value" }
}
```

- `required` — list of top-level field names that must be present in the sample.
- `sample` — the captured response or data object to validate.

**v1 scope: presence-of-keys only.** The runner checks whether every field in `required` exists as a key in `sample`. Type checking, nested schemas, and full JSON Schema semantics are deferred to v2.

### Outcomes

| Runner output | Meaning | Reality-report verdict |
|---|---|---|
| `PROPERTY_PASS` | All required keys present | VALID |
| `PROPERTY_COUNTER_EXAMPLE` | At least one required key absent; missing key in stderr JSON `shrunk_input` | INVALID |

On `PROPERTY_COUNTER_EXAMPLE`, stderr carries a JSON object with `property`, `shrunk_input` (the first missing field name), and `seed: 0`. Embed this JSON in the `## Interactions` entry for the failing dependency.

## Related Skills

- `rnd-framework:rnd-verification` — Full verification process; reality reports are supplementary evidence for the Verifier
- `rnd-framework:rnd-building` — Builder methodology; reality auditing checks what the Builder assumed
- `rnd-framework:rnd-experiments` — Verifier experiment design; reality experiments follow the same adversarial framing
