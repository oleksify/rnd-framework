## Agents

The pipeline runs as separate **agents**, each in its own context window. An agent is an isolated Claude instance with a narrow set of tools and a single job. Running them separately is what makes the [information barrier](#information-barrier) structural rather than a polite request — the verifier literally cannot see the builder's context.

There are 14 agents: 10 that handle pipeline phases and 4 helpers.

### Pipeline agents

| Agent | Default model | Role |
|---|---|---|
| `rnd-scoper` | opus / high | Freezes the deliverable boundary you ratify *before* planning |
| `rnd-planner` | opus / high | Splits the frozen scope into pieces; writes the plan files |
| `rnd-builder` | sonnet / high | Builds one task with tests; writes a manifest |
| `rnd-reality-auditor` | sonnet / low | Checks that declared external references actually exist |
| `rnd-verifier` | opus / high | Independent check, with no view of the build |
| `rnd-cleanup` | sonnet / medium | Removes dead code after a pass; rolls back if it breaks |
| `rnd-polisher` | opus / high | Fixes the joins between tasks (duplication, naming drift) |
| `rnd-integrator` | haiku / low | Combines the results, runs integration tests, decides SHIP |
| `rnd-debugger` | sonnet / high | Root-cause analysis for failing tasks |
| `rnd-data-scientist` | sonnet / medium | On-demand numerical work (Julia, DuckDB) |

The model shown is the *default*. The orchestrator overrides it per task based on how critical the task is — a low-stakes config change runs on a lighter model than a security-sensitive migration.

#### In depth

<details>
<summary><code>rnd-scoper</code> — freezes what "in scope" means, before planning</summary>

The scoper runs first, before the planner. It turns your raw task description into a short list of user-visible, acceptance-level **deliverables**, each with a stable id, and presents them as `scope.md` for you to ratify. Once you approve, the boundary is frozen into `scope.json` and becomes the planner's single source of truth.

That frozen boundary is enforced in both directions. A gate blocks the planner if it invents a task with no matching deliverable (**scope creep**) or leaves a ratified deliverable with no task (**scope miss**). The goalposts for *what gets built* are locked before decomposition starts — the same discipline pre-registration applies to *what "done" means*.

</details>

<details>
<summary><code>rnd-planner</code> — turns a task into a contract</summary>

The planner runs first and is the only agent that decides *what* gets built. It writes four files:

- **`protocol.md`** — scope and goals. Line 2 carries a *size cap*: a number limiting how large the plan can grow, so the breakdown can't sprawl without bound.
- **`validation-contract.md`** — one heading per testable assertion. Each one is tagged with a **Shape** (what kind of claim it is) and a **Confidence** (`high` / `medium` / `stretch`). A gate blocks the planner if any assertion is missing either label.
- **`features.json`** — the machine-readable task list: ids, `dependsOn[]`, `assertionIds[]`, criticality, status.
- **`AGENTS.md`** — the per-agent work assignments the orchestrator reads when it starts each agent.

Two rules keep it in check. Waves are capped at **four tasks**, each at least ~1 hour of work, so tiny fragments get grouped rather than multiplied. And every plan carries an **Assumptions** section — if an assumption names a check meant to disprove it and that check never runs, the verifier knocks the verdict down a level.

</details>

<details>
<summary><code>rnd-builder</code> — implements one task, test-first</summary>

The builder takes a single task and writes it with tests first. It produces two records:

- a **build manifest** — a short, structured log of exactly what changed (later phases trace their findings back through it), and
- a **self-assessment** — its own honest list of where it's unsure.

The self-assessment is **barrier-protected**: the verifier never sees it (see [Information barrier](#information-barrier)). The builder also can't quietly wave a problem away — anything it spots but doesn't fix has to go into a found-issues ledger with an explicit decision of *fixed* or *escalated*. "Pre-existing, out of scope" is not an allowed brush-off.

</details>

<details>
<summary><code>rnd-verifier</code> — independent check behind the barrier</summary>

One verifier runs per wave and reviews every task's plan. Before it reads a line of the builder's code, it writes its own tests from the contract alone — so it checks against what was promised, not against what happened to get built.

It produces a **verdict map** with one entry per assertion; each entry carries a verdict, the evidence it cites, and feedback. Those combine into a per-task verdict by a simple rule: any `FAIL` → needs another round; otherwise any "passes but needs polish" → that; else `PASS`.

Two sections are required in every report. **Coverage Gaps** forces it to state what it checked *and* what it couldn't. **Case for PASS** / **Case for FAIL** forces it to argue both sides before landing a verdict — which keeps it from rubber-stamping.

</details>

<details>
<summary><code>rnd-reality-auditor</code> — does the outside world actually look like that?</summary>

This one runs only when a task **declares external dependencies** — URLs, APIs, schemas, env vars. Its first move (Step 0) is an *existence check*: a quick, mechanical pass confirming that every imported module, third-party method call, cited RFC or error code, and named environment variable really exists in the form the code claims.

If any cited reference is missing, it stops right there with an `INVALID` — and if the builder had already recorded a `PASS` for that task, it flags it as a likely false pass. Catching a made-up API or a wrong schema field here is far cheaper than catching it during integration.

</details>

<details>
<summary><code>rnd-cleanup</code> and <code>rnd-polisher</code> — tidy without breaking</summary>

**Cleanup** runs per task, right after it passes verification. It sweeps for dead functions, orphan files, duplicate code, and stale comments left behind by the build, applies the fixes, then re-checks — and rolls the whole sweep back if the re-check breaks.

**Polish** runs once per wave, after every per-task cleanup is done. It works on the joins *between* tasks: duplication that crept in across tasks, naming and API drift, helpers that should be moved to a shared place. Same safety rule — if a re-check breaks, the polish is rolled back.

</details>

<details>
<summary>Criticality-driven dispatch — why the model isn't fixed</summary>

The model in the table above is only a default. Each task in `features.json` carries a **Criticality** of `LOW`, `NORMAL`, or `HIGH`, and the orchestrator picks the spawned agent's model from a *per-agent* mapping — the verifier and planner step up to `opus` at `HIGH`, the builder steps up from `sonnet` to `opus`, and so on. If a task has no criticality, nothing is overridden and the agent's own default stands.

Layered on top is the **earned fast path**: once a kind of work has a proven track record of clean post-ship reviews, the framework runs a lighter profile for it at `LOW`/`NORMAL` criticality. The floors never bend — a check always runs (lighter, never skipped), and `HIGH` criticality never takes the fast path. See [the earned fast path](#skills) under Skills.

</details>

### Helper agents

| Agent | Role |
|---|---|
| `rnd-premortem-imaginer` | Imagines one way the milestone could fail, in parallel with others, before planning |
| `rnd-replan-differ` | Diffs an old plan against a new one when a task is re-planned |
| `rnd-assertion-paraphraser` | Re-words the contract so the verifier reads different phrasing than the planner wrote |
| `rnd-explorer` | Read-only search agent that starts reliably in MCP-heavy sessions |

### Why a premortem

Before the planner writes anything, several agents each imagine one distinct way the work could go wrong — a wrong guess about an outside service, a data model that doesn't fit, a part that's too slow. The planner then has to answer each one. Imagining a failure up front is far cheaper than debugging it later.
