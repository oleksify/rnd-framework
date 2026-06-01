## Agents

The pipeline runs as separate **agents**, each in its own context window. An agent is an isolated Claude instance with a narrow tool grant and a specific job. Running them separately is what makes the [information barrier](#information-barrier) structural rather than a polite request — the verifier literally cannot see the builder's context.

There are 13 agents: 9 that handle pipeline phases and 4 helpers.

### Pipeline agents

| Agent | Default model | Role |
|---|---|---|
| `rnd-planner` | opus / high | Decomposes the task; writes the plan artifacts |
| `rnd-builder` | sonnet / high | Implements one task with tests; writes a manifest |
| `rnd-reality-auditor` | sonnet / low | Checks declared external references actually exist |
| `rnd-verifier` | sonnet / high | Independent verification behind the barrier |
| `rnd-cleanup` | sonnet / medium | Removes dead code after a pass; rolls back if it breaks |
| `rnd-polisher` | opus / high | Fixes cross-task seams (duplication, naming drift) |
| `rnd-integrator` | haiku / low | Merges outputs, runs integration tests, decides SHIP |
| `rnd-debugger` | sonnet / high | Root-cause analysis for failing tasks |
| `rnd-data-scientist` | sonnet / medium | On-demand numerical work (Julia, DuckDB) |

The model shown is the *default*. The orchestrator overrides it per task based on the task's **criticality** — a low-stakes config change runs on a lighter model than a security-sensitive migration.

#### In depth

<details>
<summary><code>rnd-planner</code> — turns a task into a contract</summary>

The planner runs first and is the only agent that decides *what* gets built. It emits four artifacts:

- **`protocol.md`** — scope and goals. Line 2 carries a *heuristic ceiling*: an integer cap on how large the plan is allowed to grow, so decomposition can't sprawl unbounded.
- **`validation-contract.md`** — one heading per testable assertion. Each assertion is tagged with a **Shape** (what kind of claim it is) and a **Confidence** (`high` / `medium` / `stretch`). A gate blocks the planner if any assertion is missing either label.
- **`features.json`** — the machine-readable task manifest: ids, `dependsOn[]`, `assertionIds[]`, criticality, status.
- **`AGENTS.md`** — per-agent work assignments the orchestrator reads when it spawns each agent.

Two disciplines constrain it. Waves are capped at **four tasks**, each with a minimum ~1-hour scope, so tiny fragments get coalesced rather than multiplied. And every pre-registration carries an **Assumptions** section — if an assumption names a "refuted by" check that never actually runs, the verifier downgrades the verdict one tier.

</details>

<details>
<summary><code>rnd-builder</code> — implements one task, test-first</summary>

The builder takes a single task and writes it with tests first. It produces two records:

- a **build manifest** — a terse, structured log of exactly what changed (the verifier and later phases attribute findings through it), and
- a **self-assessment** — its own honest uncertainties about the work.

The self-assessment is **barrier-protected**: the verifier never sees it (see [Information barrier](#information-barrier)). The builder also can't quietly wave a problem away — anything it notices but doesn't fix must land in a found-issues ledger with an explicit decision of *fixed* or *escalated*. "Pre-existing, out of scope" is not an allowed dismissal.

</details>

<details>
<summary><code>rnd-verifier</code> — independent check behind the barrier</summary>

One verifier spawns per wave and reviews every task's pre-registration. Before it reads a line of the builder's code, it writes its own experiments from the contract alone — so it tests against what was promised, not against what happened to be built.

It emits a **per-assertion verdict map** keyed by assertion id; each entry carries a verdict, the evidence it cites, and feedback. Per-task verdicts then aggregate by a simple rule: any `FAIL` → needs iteration; otherwise any quality-needs-iteration → that; else `PASS`.

Two sections are mandatory in every report. **Coverage Gaps** forces it to state what it checked *and* what it couldn't. **Case for PASS** / **Case for FAIL** forces it to argue both sides before landing a verdict — symmetry against rubber-stamping.

</details>

<details>
<summary><code>rnd-reality-auditor</code> — does the outside world actually look like that?</summary>

This one runs only when a task **declares external dependencies** — URLs, APIs, schemas, env vars. Its first move (Step 0) is an *existence pre-pass*: a mechanical probe that every imported module, third-party method call, cited RFC or error code, and named environment variable actually exists in the form the code claims.

If any cited reference is missing, it short-circuits to `INVALID` — and if the builder had already recorded a `PASS` for that task, it flags it as a likely false pass. Catching a hallucinated API or a wrong schema field here is far cheaper than catching it in integration.

</details>

<details>
<summary><code>rnd-cleanup</code> and <code>rnd-polisher</code> — tidy without breaking</summary>

**Cleanup** runs per task, right after it passes verification. It sweeps for dead functions, orphan files, duplicate implementations, and stale comments left behind by the build, applies the fixes, then re-verifies — and rolls the whole sweep back if re-verification breaks.

**Polish** runs once per wave, after every per-task cleanup is done. It works at the seams *between* tasks: duplication that crept in across tasks, naming and API drift, helpers that should be lifted to a shared location. Same safety rule — if a re-verification breaks, the polish is rolled back.

</details>

<details>
<summary>Criticality-driven dispatch — why the model isn't fixed</summary>

The model in the table above is only a default. Each task in `features.json` carries a **Criticality** of `LOW`, `NORMAL`, or `HIGH`, and the orchestrator overrides the spawned agent's model from a *per-agent* mapping — the verifier and planner climb to `opus` at `HIGH`, the builder climbs from `sonnet` to `opus`, and so on. If a task has no criticality, no override happens and the agent's own default stands.

Layered on top is the **earned fast path**: once a kind of work has a feedback-confirmed track record of clean post-ship reviews, the framework runs a lighter profile for it at `LOW`/`NORMAL` criticality. The floors are inviolable — verification always runs (lighter, never absent), and `HIGH` criticality never fast-paths. See [the earned fast path](#skills) under Skills.

</details>

### Helper agents

| Agent | Role |
|---|---|
| `rnd-premortem-imaginer` | Imagines one way the milestone could fail, in parallel with others, before planning |
| `rnd-replan-differ` | Diffs an old plan against a new one when a task is re-planned |
| `rnd-assertion-paraphraser` | Re-words the contract so the verifier reads different phrasing than the planner wrote |
| `rnd-explorer` | Read-only search agent that spawns reliably in MCP-heavy sessions |

### Why a premortem

Before the planner writes anything, several agents each imagine one distinct way the work could fail — a wrong assumption about an external service, a data-model mismatch, a performance cliff. The planner must then address or dismiss each one. It is cheaper to imagine a failure than to debug it.
