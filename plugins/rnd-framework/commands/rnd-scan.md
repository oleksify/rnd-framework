---
description: "Scan the project and build a persistent fact sheet (environment, dependencies, services, conventions) for grounding future pipeline runs."
argument-hint: "[--force to rescan even if facts are fresh]"
effort: medium
---

# R&D Framework: Project Scan

Gather project facts once, use them in every pipeline run. Results are saved to a persistent `project-facts.md` at the project's `.rnd/` base directory — surviving across sessions and pipeline runs.

## Setup

```bash
FACTS_PATH=$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh" --facts)
BASE_DIR=$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh" --base)
```

## Step 1: Check Existing Facts

If `$FACTS_PATH` exists and `$ARGUMENTS` does not contain `--force`:
1. Read the `Scan commit:` line from the file
2. Compare against `git rev-parse HEAD`
3. If they match, report: "Project facts are fresh (scanned at commit `<hash>`). Use `--force` to rescan." Then stop.

If the file does not exist or `--force` is set, proceed to Step 2.

## Step 2: Environment & Runtime

Gather the project's runtime environment:

1. **Language and version:**
   - Glob for `.tool-versions`, `.node-version`, `.python-version`, `.ruby-version`, `.elixir-version`, `rust-toolchain.toml`
   - If found, read and record exact version
   - If not found, infer from config files (e.g., `engines` in package.json, `python_requires` in pyproject.toml)

2. **Package manager:**
   - Glob for: `package-lock.json` (npm), `yarn.lock` (yarn), `pnpm-lock.yaml` (pnpm), `bun.lockb` (bun), `mix.lock` (mix), `Cargo.lock` (cargo), `poetry.lock` / `uv.lock` (python), `go.sum` (go)
   - Record which lockfile(s) exist

3. **OS and platform:**
   - Record `uname -s` and `uname -m` output

4. **CLI tools:**
   - Check availability of common tools: `node`, `python`, `elixir`, `go`, `cargo`, `bun`, `deno`, `docker`, `git`
   - For each found, record version (`<tool> --version`)

## Step 3: Dependencies

Scan lockfiles for dependency details:

1. **Identify the primary lockfile** from Step 2
2. **Extract key dependencies:**
   - For `package.json`: read `dependencies` and `devDependencies` keys, list names and version ranges
   - For `mix.exs`: read `deps` function, list dependency names and version constraints
   - For `Cargo.toml`: read `[dependencies]` section
   - For `pyproject.toml`: read `[project.dependencies]` or `[tool.poetry.dependencies]`
   - For `go.mod`: read `require` block
3. **Lockfile hash:** compute `sha256sum <lockfile> | cut -c1-16` for change detection
4. **Count:** total number of direct dependencies

## Step 4: External Services & Contracts

Scan for external service usage:

1. **Database:**
   - Grep for database drivers/adapters: `pg`, `mysql`, `sqlite`, `mongo`, `redis`, `ecto`, `prisma`, `drizzle`, `knex`, `sequelize`, `sqlalchemy`, `diesel`
   - If found, identify: DB type, connection config location, schema/migration files

2. **API endpoints:**
   - Grep for `https://` URLs in source files (excluding tests, node_modules, vendor, .git)
   - Group by domain, note which files reference each
   - Flag any that appear to be third-party APIs (not localhost or the project's own domain)

3. **Environment variables:**
   - Read `.env.example`, `.env.template`, `.env.sample` if any exist
   - Grep for `process.env`, `System.get_env`, `os.environ`, `os.Getenv`, `env::var` in source
   - List each env var name found, noting which are likely secrets (keys, tokens, passwords)

4. **Message queues / async:**
   - Grep for: `amqp`, `rabbitmq`, `kafka`, `bullmq`, `sidekiq`, `oban`, `celery`, `pubsub`

## Step 5: Conventions & Boundaries

Extract project-specific rules:

1. **CLAUDE.md:**
   - Read `CLAUDE.md` if it exists at the project root
   - Extract: coding conventions, off-limits paths, commit message format, test commands, architecture notes
   - Summarize in 10-20 bullet points

2. **Test framework:**
   - Grep for test runner configs: `vitest.config`, `jest.config`, `pytest.ini`, `pyproject.toml [tool.pytest]`, `.rspec`, `mix.exs` (ExUnit)
   - Count existing test files (Glob for `*.test.*`, `*_test.*`, `test_*.py`, `*_spec.*`)
   - Record the exact test run command

3. **CI/CD:**
   - Read `.github/workflows/*.yml`, `.gitlab-ci.yml`, `Jenkinsfile`, `Makefile`
   - Extract: build commands, test commands, deploy targets

4. **Linters and formatters:**
   - Glob for: `.eslintrc*`, `biome.json`, `.prettierrc*`, `.rubocop.yml`, `ruff.toml`, `.clang-format`, `mix.exs` (mix format)
   - Record which are present

5. **Off-limits:**
   - Read `.gitignore` — infer sensitive paths
   - Note any credentials, secrets, or config files that should not be modified

## Step 6: Write project-facts.md

Write all gathered facts to `$FACTS_PATH` using the Write tool. Use this structure:

```markdown
# Project Facts

Scan commit: <git rev-parse HEAD output>
Scanned at: <ISO 8601 timestamp>

## Environment & Runtime

- **Language:** <name> <version>
- **Package manager:** <name> (lockfile: <path>)
- **Platform:** <uname -s> <uname -m>
- **CLI tools:** <list of tool: version>

## Dependencies

- **Direct dependencies:** <count>
- **Lockfile hash:** <first 16 chars of sha256>
- **Key dependencies:**
  - <name> <version> — <purpose if inferrable>
  - ...

## External Services

### Database
- **Type:** <sqlite/postgres/mysql/none>
- **Config:** <path to config file>
- **Schema:** <path to schema/migrations>

### APIs
- <domain> — referenced in <files> (<purpose if inferrable>)
- ...

### Environment Variables
- `VAR_NAME` — <purpose> [secret: yes/no]
- ...

## Conventions & Boundaries

### Coding
- <extracted convention 1>
- <extracted convention 2>
- ...

### Testing
- **Framework:** <name>
- **Test count:** <number> files
- **Run command:** <exact command>

### CI/CD
- **Platform:** <GitHub Actions/GitLab CI/etc>
- **Build:** <command>
- **Test:** <command>

### Off-Limits
- <path or resource that should not be modified>
- ...
```

## Step 7: Report

After writing, summarize:

> "Project facts saved to `<path>`. Scanned: <language> project with <dep count> dependencies, <db type> database, <test count> test files. Facts will be reused in future `/rnd-start` runs until the code changes."

Use `AskUserQuestion` to offer:
- "Start a pipeline with /rnd-start (Recommended)"
- "Review project facts"
- "Done"
