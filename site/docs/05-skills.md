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

### In depth

<details>
<summary>How a skill reaches an agent — session-local injection</summary>

When the orchestrator spawns an agent, it reads the session's `AGENTS.md` and any `SKILL.md` files dropped into the session's `skills/` directory, and injects their content into the spawn prompt under `## Session Context` and `## Session Skills`. Each injection is logged as a `skill_injected` audit event.

The effect: a single run can carry its own custom guidance — project-specific patterns, a domain glossary, a one-off agent — without anyone editing the global plugin files. Personal skills in your own `.claude/skills/` shadow the framework's unless you prefix the name with `rnd-framework:`.

</details>

<details>
<summary><code>premortem</code> — imagine the failure before it happens</summary>

Before the planner writes anything, the orchestrator fans out several lightweight agents in parallel. Each is handed **one** failure framing — a wrong assumption about an external service, a data-model mismatch, a performance cliff — and writes a short narrative of how that failure would unfold. The results are aggregated into `premortem.md`, one entry per imagined failure mode.

The planner then has to **address or dismiss each one** in `protocol.md`. It is cheaper to imagine a failure than to debug it, and forcing the imagination *before* the plan exists keeps it from being rationalised away afterward.

</details>

<details>
<summary><code>outside-view</code> — anchoring the plan in past failure rates</summary>

Right after the premortem and just before the planner spawns, the framework injects a *reference-class* block into the planner's context: for each shape of assertion, how often work of that shape has historically failed verification, drawn from this project's own session log.

It's a deliberate counterweight to the *inside view* — the natural optimism of "this particular task will go fine". If contract-style assertions have failed 30% of the time before, the planner sees that number while it decomposes. When the corpus is too thin to be meaningful (fewer than five comparable sessions), the block says so rather than inventing a rate.

</details>

<details>
<summary>Calibration and the earned fast path</summary>

The framework keeps a running ledger of how often its own verdicts turn out wrong — a `PASS` that a later review or a reality audit contradicts is recorded as a false pass. That history drives two behaviours.

**Auto-escalation:** when a kind of task accumulates false passes, the framework promotes it to heavier scrutiny.

**The earned fast path:** the mirror image. After the final ship, a post-ship review runs and its findings (and clean bills of health) are recorded per assertion-shape. Once a shape has a streak of consecutive clean reviews, it's treated as *expert* — and tasks of that shape, at `LOW` or `NORMAL` criticality, run a lighter profile. The speed is *earned*, never assumed: verification still always runs, `HIGH` criticality never qualifies, and a single new post-ship finding drops the shape back to novice automatically. It follows Kahneman and Klein's rule that fast intuition is only trustworthy in a regular environment with real feedback.

</details>
