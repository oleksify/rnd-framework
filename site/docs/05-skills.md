## Skills

A **skill** is a short instruction sheet the framework hands to an agent at the moment it's needed — how to run a phase, the rules for a particular language, or guidance for a kind of work. It's how the pipeline gives each agent just the discipline it needs, without stuffing every prompt with everything.

### Phase methodology

| Skill | Purpose |
|---|---|
| `rnd-orchestration` | How the pipeline fits together — roles and checkpoints |
| `rnd-decomposition` | Splitting work into pieces and writing the checks up front |
| `rnd-building` | How to build, test-first |
| `rnd-verification` | Independent checking, one pass per wave |
| `rnd-integration` | Combine the pieces and confirm they work together |
| `rnd-iteration` | Handling failed checks, and when to stop retrying |
| `rnd-scheduling` | Grouping independent work into waves |
| `rnd-scaling` | How much process a task actually needs |
| `rnd-completion` | Wrapping up — branches and pull requests after shipping |

### Reasoning aids

| Skill | Purpose |
|---|---|
| `premortem` | Imagining ways the work could fail, before planning |
| `outside-view` | Checks the plan against how often this kind of work has failed before |
| `rnd-design` | Weighing design options before planning |
| `rnd-failure-modes` | A checklist of the ways reviews go wrong |
| `rnd-calibration` | Tracks how often its own verdicts turn out wrong |
| `rnd-reality-auditing` | Double-checks the outside things the code relies on really exist |

A related decorrelation step, the **assertion paraphraser**, re-words each requirement before the reviewer reads it — see [the wording channel](#the-wording-channel) under Information barrier.

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
| `rnd-language-design` | Explicit syntax/semantics/diagnostics specs before building a DSL, parser, or compiler |
| `rnd-explain` | Turns a shipped change into a self-contained interactive HTML explainer |

A handful more cover working on the plugin itself (`hook-authoring`, `lib-sh-patterns`, `plugin-architecture`, `plugin-versioning`, `bash-hook-testing`).

<details>
<summary><code>rnd-explain</code> — an interactive walkthrough of a change</summary>

Run `/rnd-framework:rnd-explain [ref]` and the framework writes one self-contained HTML file explaining a diff, branch, or PR to someone who wasn't there when it was written. Every page carries four sections in order — **Background**, **Intuition**, **Code**, and a five-question interactive **Quiz** with click-to-reveal feedback.

It fills a fixed template — an inline CSS design system plus a data-driven quiz engine — rather than authoring the document from scratch each run, so the visual design is deterministic and the quiz wiring is never re-invented. The output is strictly self-contained: inline-only CSS and JS, zero external URLs, and a blocking pre-save scan that rejects external links, duplicate ids, or malformed quiz JSON. When a pipeline session exists, the Code section is enriched with short excerpts from the verifier's Case for PASS and Coverage Gaps.

</details>

### In depth

<details>
<summary>How a skill reaches an agent — per-run guidance</summary>

When the framework starts an agent, it reads the run's `AGENTS.md` and any `SKILL.md` files dropped into the run's `skills/` directory, and pastes their content into the agent's prompt under `## Session Context` and `## Session Skills`. Each one is noted in the log as a `skill_injected` event.

The effect: a single run can carry its own custom guidance — project-specific patterns, a domain glossary, a one-off agent — without anyone touching the global plugin files. Skills in your own `.claude/skills/` take priority over the framework's unless you prefix the name with `rnd-framework:`.

</details>

<details>
<summary><code>premortem</code> — imagine the failure before it happens</summary>

Before the planner writes anything, the framework spins up a handful of small agents at once. Each gets **one** way the work could go wrong — a wrong guess about an outside service, a data model that doesn't fit, a part that turns out too slow — and writes a short story of how that failure would play out. The results collect into `premortem.md`, one entry per imagined failure.

The planner then has to **answer each one** in its plan: either guard against it or explain why it won't happen. Imagining a failure up front is far cheaper than debugging it later, and doing it *before* the plan exists stops it from being quietly explained away once there's a plan to defend.

</details>

<details>
<summary><code>outside-view</code> — anchoring the plan in past failure rates</summary>

Just after the premortem and just before the planner starts, the framework hands the planner a quick look at this project's own track record: for each kind of work, how often it has failed review in the past.

It's there to balance the usual optimism of "this particular task will be fine." If changes of this kind have failed, say, 30% of the time before, the planner sees that number while it's deciding how to split the work. And when there isn't enough history to mean anything yet — fewer than five comparable runs — it says so instead of making up a rate.

</details>

<details>
<summary>Calibration and the earned fast path</summary>

The framework keeps a running ledger of how often its own verdicts turn out wrong — a `PASS` that a later review or reality-check contradicts is recorded as a false pass. That history drives two behaviours.

**Auto-escalation:** when a kind of task starts racking up false passes, the framework gives it heavier scrutiny.

**The earned fast path:** the mirror image. After the final ship, a review runs and its results — problems found, or a clean bill of health — are recorded per kind of work. Once a kind has a run of clean reviews in a row, it's treated as well-understood, and tasks of that kind (at `LOW` or `NORMAL` importance) take a lighter, faster route. The speed is *earned*, never assumed: a check always runs, the most important tasks never skip it, and a single new problem found after shipping drops that kind straight back to full scrutiny. Shortcuts are only safe once there's a real track record to back them up.

</details>

<details>
<summary>Re-measurement — has the framework drifted?</summary>

Outside-view and calibration both lean on the project's own history. Re-measurement asks a sharper question about that history: is the framework itself getting *better or worse over time*?

Run `/rnd-framework:rnd-remeasure`. It takes a baseline recorded at an earlier point and compares today's numbers against it — how often each kind of work fails review, how often the builder's own doubts line up with the final verdict, and how many build-check rounds tasks take. The result is a short memo: the baseline, the current snapshot, the difference, and an honest note about what *else* changed in between that could be muddying the comparison.

It won't read tea leaves from a handful of runs. Below ten comparable runs since the baseline it writes a "not enough yet (N=…)" stub instead of a noisy delta. And it only ever reads existing logs — it changes nothing.

</details>
