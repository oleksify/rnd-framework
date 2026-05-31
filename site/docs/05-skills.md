## Skills

A **skill** is a focused instruction document the framework loads into an agent at the right moment — methodology for a phase, language-specific rules, or guidance for a particular kind of work. Skills are how the pipeline carries its discipline into each agent without bloating every prompt.

### Phase methodology

| Skill | Purpose |
|---|---|
| `rnd-orchestration` | Pipeline overview, agent roles, gate criteria |
| `rnd-decomposition` | Hierarchical decomposition and pre-registration |
| `rnd-building` | Builder methodology with test-first discipline |
| `rnd-verification` | Wave-batched independent verification |
| `rnd-integration` | Merge and system validation |
| `rnd-iteration` | Build-verify feedback loops and budgets |
| `rnd-scheduling` | Dependency-based wave scheduling |
| `rnd-scaling` | How much ceremony a task needs |
| `rnd-completion` | Post-ship branch management and PRs |

### Reasoning aids

| Skill | Purpose |
|---|---|
| `premortem` | Pre-planning failure imagination |
| `outside-view` | Injects historical failure rates as a calibration anchor |
| `rnd-design` | Architectural exploration before planning |
| `rnd-failure-modes` | Catalogue of verification anti-patterns |
| `rnd-calibration` | Tracks verdict accuracy over time |
| `rnd-reality-auditing` | Adversarial external-contract verification |

### Craft

| Skill | Purpose |
|---|---|
| `kiss-practices` | Language-specific rules against over-engineering |
| `fp-practices` | Functional-programming patterns per language |
| `code-review` | Review categories, severities, report format |
| `rnd-formatting` | Detect and run the project formatter |
| `rnd-doc-polish` | Update docs and stale comments after ship |
| `committing` | Commit message style and confirmation |
| `prefer-system-tools` · `bun-scripting` | Tooling discipline |

A handful more cover working on the plugin itself (`hook-authoring`, `lib-sh-patterns`, `plugin-architecture`, `plugin-versioning`, `bash-hook-testing`).
