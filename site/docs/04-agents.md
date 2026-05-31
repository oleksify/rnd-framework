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

### Helper agents

| Agent | Role |
|---|---|
| `rnd-premortem-imaginer` | Imagines one way the milestone could fail, in parallel with others, before planning |
| `rnd-replan-differ` | Diffs an old plan against a new one when a task is re-planned |
| `rnd-assertion-paraphraser` | Re-words the contract so the verifier reads different phrasing than the planner wrote |
| `rnd-explorer` | Read-only search agent that spawns reliably in MCP-heavy sessions |

### Why a premortem

Before the planner writes anything, several agents each imagine one distinct way the work could fail — a wrong assumption about an external service, a data-model mismatch, a performance cliff. The planner must then address or dismiss each one. It is cheaper to imagine a failure than to debug it.
