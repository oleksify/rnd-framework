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

## Related Skills

- `rnd-framework:rnd-verification` — Full verification process; reality reports are supplementary evidence for the Verifier
- `rnd-framework:rnd-building` — Builder methodology; reality auditing checks what the Builder assumed
- `rnd-framework:rnd-experiments` — Verifier experiment design; reality experiments follow the same adversarial framing
